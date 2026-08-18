# Spec: Fire PCIe host bridge for QEMU's `niagara` machine

Goal: make Solaris 10's `px` PCIe nexus attach inside the emulated Niagara guest,
so PCI devices — and specifically a NIC — become usable without writing any new
guest driver.

Status: **design only, nothing implemented.** Written 2026-08-18.

---

## 0. The blocker that reorders everything

**Our hypervisor has no Fire support compiled in.** Established by controlled
experiment (see P2-015 in `BACKLOG.md` for the full method and numbers):

| build | `CONFIG_FIRE` | size | Fire addrs present |
|---|---|---|---|
| `ontario/debug/q.bin` | `-D` | 246024 | 7 |
| `ontario/release/q.bin` | `-D` | 205144 | 7 |
| `ontario/legion/q.bin` | `-U` | 190656 | 0 |
| `ontario/t1_fpga/q.bin` | `-U` | 189224 | 0 |
| **`S10image/q.bin` (what we boot)** | absent | 163216 | **0** |

So no amount of QEMU work can make PCI appear while we boot the S10image
hypervisor. `px` calls hypervisor API group #3; in our binary there is nothing
initialised behind those entry points.

**This is cheaper than it sounds.** `ontario/release/q.bin` already exists,
prebuilt, with Fire compiled in. Nothing needs to be built. The prerequisite is
to make a Fire-enabled hypervisor boot under QEMU — filed as **P2-016** — which
is a bounded diagnosis against a known-good reference (our S10image build boots,
so the delta is observable) rather than a toolchain project.

Everything below is the design to implement *after* P2-016 succeeds. It is
written now because the research is done and would otherwise be lost.

---

## 1. Address map

Fire's register and window addresses are **hardcoded in the hypervisor**, not
taken from the Machine Description. This was the single most important correction
to the original plan: the MD's `cfgbase`/`membase`/`pciregs` properties describe
*guest virtual* devices, while Fire itself is placed by the `AID2*` macros in
`greatlakes/ontario/include/fire.h:67-92`.

Constants: `FIRE_A_AID = 0x1e`, `FIRE_B_AID = 0x1f` (`fire/fire.h:59-60`),
`NFIRES = 1`, `NFIRELEAVES = 2` (`fire.h:64-65`). One Fire ASIC, two leaves.

```
AID2JBUS(aid)    = (0x080 << 32) | (aid << 23)
AID2PCI(aid)     = (aid & 0xf) << 36
AID2PCIE(aid)    = AID2JBUS(aid) | ((aid & 1) << 20) | 0x600000
AID2PCIECFG(aid) = AID2PCI(aid) | ((((aid & 1) ^ 1)) << 35)
AID2PCIEIO(aid)  = AID2PCIECFG(aid) | CFG_SIZE
```

Derived physical addresses — **these are where QEMU regions must be mapped**:

| region | leaf A | leaf B | size |
|---|---|---|---|
| JBus (JBC) registers | `0x800f000000` | `0x800f800000` | see §2 |
| PCIe/DLC registers | `0x800f600000` | `0x800ff00000` | see §2 |
| config space | `0xe800000000` | `0xf000000000` | 256 MB |
| IO space | `0xe810000000` | `0xf010000000` | 256 MB |
| MEM32 window | `0xea00000000` | `0xf200000000` | 2 GB |
| MEM64 window | `0xec00000000` | `0xf400000000` | 16 GB |
| EBus | `0xf820000000` | — | — |

The `CFGIO_A 0xe800`, `MEM32_A 0xea00`, `MEM64_A 0xec00`, `CFGIO_B 0xf000`,
`MEM32_B 0xf200`, `MEM64_B 0xf400`, `EBUS 0xf820` constants at `fire.h:79-86`
are these addresses `>> 24`. Sizes from `fire.h:90-95`: `IO_SIZE = CFG_SIZE =
256 MB`, `MEM32_SIZE = 2 GB`, `MEM64_SIZE = 16 GB`.

**None of these collide with the machine's existing regions** (`HV_RAM 0x100000`,
guest RAM `0x80000000`, UART `0x1f10000000`, NVRAM `0x1f11000000`, MD_ROM
`0x1f12000000`, HV_ROM `0x1f12080000`, VDISK `0x1f40000000`, IOB `0x9800000000`).

### Config space addressing

`addr = cfgbase | (bus << 16) | (dev << 11) | (func << 8) | reg`

i.e. bus:8, device:5, function:3, register:8 — standard PCI type-1 layout inside
the 256MB window. Accesses arrive as ordinary loads/stores from the hypervisor
servicing `VPCI_CONFIG_GET`/`VPCI_CONFIG_PUT`; QEMU sees MMIO to the window and
must decode the address back into a `(bus, dev, func, reg)` tuple.

---

## 2. What must actually be emulated

Register definitions: `greatlakes/ontario/include/fire/fire_regs.h` (621 lines,
covering JBC/DLC/PLC/TLU/LPU blocks) and `fire/fire.h` (MSI/EQ structures,
interrupt mappings, IOMMU).

**`setup_fire` touches no hardware.** Read `setup.s:683-792`: it only relocates
hypervisor-internal pointers — IOTSB base, MSI EQ bases, virtual interrupt map,
error and MSI cookies — by subtracting the relocation offset, then branches to
`fire_init`. So boot-time Fire register access happens in `fire_init`
(`vpci_fire.s`), which is where the real emulation requirement lives and which
**still needs reading in detail** — see §6.

Two facts that shrink the work substantially:

- **The IOMMU translation table lives in hypervisor RAM (BSS), not in Fire
  registers.** So DMA from an emulated device does not require emulating IOMMU
  hardware; the hypervisor manages the IOTSB itself, and bypass mode exists.
- **`FIRE_JBUS_DEVICE_ID` (offset 0, reset value `0xfc00000000390000`) is
  referenced nowhere outside its own definition.** A subagent claimed `fire_init`
  version-checks it and required bits[3:0]==0x3; that claim is **false** — grep
  finds no use, and the reset value's low nibble is 0x0. Do not build to it.

---

## 3. QEMU implementation

QEMU version: check `qemu/VERSION` (8.2.2 per earlier session notes).

`hw/sparc64/niagara.c` currently defines **zero `MemoryRegionOps`** — this would
be the machine's first true MMIO device. Existing regions are all plain RAM or
`ram_from_file`. The vdisk at `NIAGARA_VDISK_BASE` is anonymous RAM plus a manual
copy-back, not a device model.

Shape of the work:

1. **New file `hw/pci-host/fire.c`** implementing a `PCIHostState` subclass, with
   `MemoryRegionOps` for the JBC and DLC register blocks and a config-space
   region whose `read`/`write` decode the address per §1 and forward to
   `pci_data_read`/`pci_data_write`.
2. **Register a `PCIBus`** with the MEM32/MEM64/IO windows as its address spaces.
3. **Instantiate from `niagara.c`** in the machine init, mapping each region at
   its §1 address.
4. **Build glue:** add the file to `hw/pci-host/meson.build`, add a `config FIRE`
   to `hw/pci-host/Kconfig`, and `select` it (plus `PCI` and the NIC) from the
   sparc64 machine config.

**Reusability of existing QEMU code is limited, and this matters.** `hw/pci-host/`
has sun4u-era bridges (`sabre.c`) which look superficially close, but their whole
design assumes *the guest* performs config-space accesses through PIO/MMIO
apertures. Our case is inverted: the guest never touches config space — the
*hypervisor* does, and QEMU is servicing q.bin. So the `PCIBus` creation and
config-space plumbing transfer; the guest-facing aperture logic and interrupt
routing do not. Copy selectively, do not fork `sabre.c`.

---

## 4. Interrupts

Fire delivers via sun4v mondo interrupts, which q.bin mediates through
`INTR_DEVINO2SYSINO 0xa0` and friends, plus the MSI/MSI-EQ machinery
(`MSIQ_* 0xc0-0xc8`, `MSI_* 0xc9-0xce`, `MSI_MSG_* 0xd0-0xd3`) whose queues live
in hypervisor memory. The MD properties `ign`, `ino`, and `intrtgt` carry the
interrupt-group/number/target used to build that mapping.

**This is the least-understood part of the design and the most likely place to
get stuck.** Legacy INTx via the interrupt-mapping registers
(`FIRE_DLC_IMU_ISS_INTERRUPT_MAPPING`, `FIRE_DLC_IMU_ISS_CLR_INT_REG`) is the
simpler target; MSI can wait. Polled operation with no interrupts at all is worth
trying first as a smoke test — many drivers will at least attach.

---

## 5. The NIC — verified, and it does *not* come free

Cross-matched every PCI NIC model in this QEMU tree against the guest's
`/etc/driver_aliases` (218 lines). **Zero matches:**

| QEMU model | PCI ID | guest driver |
|---|---|---|
| `sunhme.c` | `108e,1001` | none (guest's `eri` is `108e,1101`, a different chip) |
| `sungem.c` | `106b,21` (Apple) | none |
| `pcnet-pci.c` | `1022,2000` | none |
| `rtl8139.c` | `10ec,8139` | none |
| `tulip.c` | `1011,19` | none |

What the guest *does* have drivers for (binaries confirmed present):

```
ge   pci108e,2bad                  (216296 bytes)  <- Sun GEM
eri  pci108e,1101                  (118280 bytes)
ce   pci108e,abba, pci100b,35      (580480 bytes)  <- Cassini
bge  pci14e4,{1645,1647,1648,1649,16a7,16a8,16c7}, pci108e,{1647,1648,16a7,16a8}
                                   (152800 bytes)  <- Broadcom BCM57xx
```

**Recommended path: re-ID `sungem`.** QEMU's `sungem.c` models the Sun GEM
controller — it is only given Apple UniNorth GMAC IDs (`hw/net/sungem.c:1465-1466`)
because QEMU uses it for PowerMac. Solaris `ge` binds Sun GEM at `108e,2bad`.
Overriding `vendor_id`/`device_id` to `0x108e`/`0x2bad` is a two-line change, and
`ge` should then attach to the same register model.

Risk, stated plainly: same MAC family is not the same card. Apple's GMAC and
Sun's GEM may differ in PHY addressing, MAC-address sourcing, or VPD/ROM layout,
and `ge` may care. Untested. The fallback is `bge`, but QEMU has no BCM57xx model
at all, so that means writing one.

`sungem` is `config SUNGEM: bool, depends on PCI` (`hw/net/Kconfig:113-115`) and
is not currently selected by any sparc64 config — one line to add.

---

## 6. Open questions, in the order they should be answered

1. **P2-016: why do in-tree hypervisor builds hang under QEMU?** Everything else
   is blocked on this. `release/q.bin` (Fire enabled) is the target; our
   S10image build boots, so there is a working reference to diff against.
2. **What does `fire_init` actually do to hardware?** `vpci_fire.s` is 2133 lines
   and reportedly table-driven, which would port cleanly. Needs a direct read:
   every register written, in order, and every register read *and branched on*.
   Any spin-wait loop is a potential boot hang and must be identified before
   writing the model.
3. **Is a failed bridge fatal?** A subagent reported that a zero JBus/PCIe base
   causes a clean skip and boot continues, which would make iteration safe. That
   is plausible but **unverified** — confirm it in source, because it determines
   whether a wrong register value costs a reboot or a debugging session.
4. **Does `ge` bind to a re-IDed `sungem`?** Cheap once PCI exists.
5. **Does `flatblk` bite?** Adding regions has panicked this guest before, though
   the vdisk region at `0x1f40000000` proves device-space regions can work.

## 7. What does NOT need doing

- **No `vpcidevice` MD node is needed for Fire itself.** The original plan had
  this backwards. Fire is placed by hardcoded `AID2*` addresses; the MD node
  describes guest *virtual* PCI devices. Confirmed separately that no reference
  `vpcidevice` node exists anywhere in the OpenSPARC tree or in legion's prebuilt
  MD binaries — it was never shipped in any Niagara configuration.
- **No guest driver work.** `px`, `bge`, `ce`, `ge`, `eri` and the PCI framework
  modules (`busra`, `pcicfg`, `pcie`, `pcihp`) are all already installed.
- **No IOMMU hardware emulation**, per §2.
- **No Fire model to port from legion** — `legion/src/config/niagara/1up.conf`
  declares only memory, serial, and TOD. There is no PCI device model in legion
  to crib from.
