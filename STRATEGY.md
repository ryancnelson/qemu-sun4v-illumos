# Strategy: illumos/Solaris on QEMU SPARC64 — Full Picture

This document captures the architectural understanding developed through
investigation and debugging. It supersedes earlier assumptions and lays out
the actual paths forward.

---

## What We Know About the Current State

### What works on QEMU Niagara (`-M niagara`)

- Solaris 10 boots to a login prompt in ~40 seconds
- Serial console is fully functional (the `qcn` virtual device)
- Root filesystem is readable — UFS reads go through q.bin's OBP path, which
  accesses the memory-mapped vdisk at `NIAGARA_VDISK_BASE` correctly
- `/tmp` is tmpfs — writable, in RAM, works today

### What is broken

**Disk writes persist. RESOLVED — this section previously said the opposite.**

The old analysis below was wrong in its central claim, and is kept because the
reasoning shows how the wrong conclusion was reached:

> "Solaris's `vdc` driver communicates with q.bin via LDC hypercalls. q.bin was
> designed for the SAM simulator; QEMU has no SAM, so writes are acknowledged
> and discarded. Atexit writeback cannot help because vdisk RAM is never
> updated by runtime writes."

What is actually true, measured:

1. The guest driver is **`hsimd`**, not `vdc`, and it does **not** use LDC.
   It issues **direct hypercalls 0xf0/0xf1**. There is no LDC code anywhere in
   the hypervisor source. (P1-005)
2. Those hypercalls read and write the memory-mapped vdisk at
   `NIAGARA_VDISK_BASE` (0x1f40000000) directly, so vdisk RAM **is** current.
3. Therefore atexit writeback is sufficient, and it works. Verified
   end-to-end: write a file, shut down cleanly, find the canary in the raw
   zvol, boot again, read it back. `tests/test-disk-writes-persist.sh`.
4. The earlier "writes are discarded" reading came from a canary written to
   `/tmp`, which is tmpfs and never touches the disk at all.

Persistence has one hard requirement: **the guest must be shut down with
`init 5`, and QEMU must exit via a signal, never SIGKILL.** Killing a guest
that is sitting at a shell prompt persists a dirty LUFS journal, and the next
boot panics replaying it:
`BAD TRAP type=10 -> ufs:readlog -> fetchbuf -> ldl_read -> lufs_read_strategy
-> vfs_mountroot`. The filesystem itself is fine; Linux mounts it happily,
because the damage is an unreplayed journal rather than corrupt files.
See `$vm_halt_writeback_fragment` in `tests/lib/vm.sh`.

**Networking does not exist.** The Niagara machine has no PCI bus and no
virtio bus. `net /virtual-devices/network@0` appears in OBP devalias (from
nvram1) but QEMU does not back it with any device.

**OBP corrupts after guest reboot.** `prom_reboot` returns control to OBP
firmware with kernel MMU state (TLBs, trap base register) still active.
OBP's first memory access faults. Session must be restarted.

---

## Why Linux/NetBSD Boot on sun4u but Solaris Cannot

QEMU's `sun4u` machine uses **OpenBIOS** — an open-source OBP
reimplementation written in Forth. It is good enough for Linux and NetBSD,
which use firmware to load the kernel and then take over completely. They
treat OBP as a thin bootstrap layer.

Solaris treats OBP as a **runtime dependency**. The kernel continues calling
OBP after boot: console I/O, power management, watchdog, kernel debugger
(`kmdb`), crash dumps. If OBP is not Sun's implementation, these calls fail.

**Observed state**: Solaris 10 on sun4u QEMU boots the kernel but the console
dies. The kernel loads (OpenBIOS gets that far), then tries to initialize its
`su` console driver against an EBUS serial port that OpenBIOS has not
described correctly in the device tree. The driver fails to attach. You are
blind. (Prior research session: 2026-07-23.)

**sun4u devices that work and have Solaris drivers:**
- IDE disk (real block device, writes work in QEMU)
- e1000 / pcnet NIC
- ESP/LSI SCSI
- PCI bus (Simba bridges)

If Solaris could boot on sun4u, all of this works. The console is the
single visible blocker. There may be deeper OBP compatibility issues beneath
it (SMCC checks, specific OBP method signatures Solaris calls at runtime),
but the console is where investigation must start.

---

## Why the Niagara Machine Has Real OBP

The Niagara machine does not use OpenBIOS. It loads the actual Sun firmware
blobs from the OpenSPARC T1 Architecture 1.5 package:
- `openboot.bin` — real Sun OBP firmware
- `q.bin` — real Sun hypervisor
- `1up-hv.bin`, `1up-md.bin` — Machine Description and hypervisor config
- `reset.bin` — reset vector

Solaris boots because it is talking to the firmware it was designed for.

**The Machine Description (MD)** is the key to device enumeration on sun4v.
Unlike sun4u (which probes PCI buses), sun4v devices are declared in the MD
table. OBP reads the MD and builds the device tree from it. The device tree
is not discovered — it is declared. To add a device to a Niagara VM, you
must: (1) add the device to QEMU, and (2) add its entry to the MD binary.

---

## The arm64-gate Template (richlowe/arm64-gate)

Rich Lowe's arm64-gate project (actively maintained as of 2026) shows how to
bootstrap illumos on a completely new architecture without OBP. The approach:

```
QEMU -machine virt (arm64)
  -kernel inetboot.bin              # custom bare-metal bootloader, no firmware
  -append "-D /virtio_mmio@a003c00" # tell inetboot where the disk is
  -device virtio-blk-device         # block storage via VirtIO MMIO
  -device virtio-net-device         # networking via VirtIO MMIO
```

Key facts:
- **No firmware at all.** No OBP, no UEFI, no U-Boot in the final config.
  `inetboot.bin` is loaded directly as `-kernel`.
- **VirtIO MMIO** (not PCI). VirtIO devices are at fixed physical addresses
  described in the Flattened Device Tree (FDT) that QEMU's virt machine
  provides. No PCI bus required.
- **A new illumos platform directory** was written for arm64, replacing all
  sun4u/sun4v OBP calls with DTB-based device enumeration and VirtIO drivers.
- **DTrace is not yet ported** to the arm64 illumos build.

The OBP runtime dependency is not fundamental to illumos. It lives in the
`sun4u` and `sun4v` platform directories. The arm64 port bypassed those
entirely.

---

## Flat Memory Block Device — The Simplest Viable Path

VirtIO has an endianness problem: the spec defines little-endian data
structures throughout. SPARC64 is big-endian. The illumos arm64 VirtIO
drivers work because ARM64 is also little-endian. Porting them to SPARC64
requires auditing and fixing every struct field access.

**We don't need VirtIO.** The simplest possible block device has no protocol:

```
QEMU: map disk image as guest RAM at fixed physical address BASE
      backed by a zvol or file, included in atexit writeback

Driver:
  read:  bcopy(BASE + blkno*512, buf, count)
  write: bcopy(buf, BASE + blkno*512, count)

inetboot:
  disk is at known physical address, read it like memory
  no driver needed in the bootloader
```

This has **zero endianness issues** — it is plain memory in the CPU's native
byte order. It is slower than VirtIO (synchronous memcpy, no queuing, no DMA)
and that is acceptable for a development/research VM. Get it working first,
optimize later.

The driver is ~200 lines of DDI boilerplate plus a bcopy. The QEMU change is
one `memory_region_init_ram_from_file()` call at a new physical address.

---

## Paths Forward — Prioritized

### Path A: Flat Memory Block Device on Niagara (immediate, bounded)

Add a new RAM region to the Niagara machine at a fresh physical address
(e.g., 0x1f50000000), backed by a zvol, captured in atexit writeback.
Write a Solaris/illumos kernel driver that maps this region and exposes it as
a block device. Format UFS, mount, use.

- **Scope**: ~1 day of focused work
- **Risk**: Low — direct memory access always works in QEMU TCG
- **Payoff**: Writable persistent storage on the existing working VM

### Path B: Fix sun4u Console — Solaris on sun4u (medium, high payoff)

Investigate exactly what OpenBIOS puts in the serial console device tree node
vs. what Solaris's `su` driver expects. Fix OpenBIOS to describe the EBUS
serial device correctly. If this unblocks Solaris, we get: IDE disk (writes
work), e1000 networking, SCSI — all already in QEMU with existing Solaris
drivers.

- **Scope**: Unknown — could be surgical (one OBP property), could reveal
  deeper compatibility issues
- **Risk**: Medium — may be one fix or may cascade
- **Payoff**: Enormous if it works — all I/O problems solved for free
- **Tool**: DTrace on a working illumos system to observe which OBP calls
  Solaris makes at console initialization time

### Path C: sparc64-virt Machine (long-term, architecturally clean)

Following the arm64-gate template exactly:
1. New QEMU machine `-M sparc64-virt` with flat memory block at known address
   and FDT
2. `inetboot` for SPARC64: reads FDT, finds block device, loads kernel
3. New `qemu64` platform directory in illumos-gate: no OBP calls, DTB-based
   enumeration, VirtIO (with endian fixes) or flat-memory block driver
4. Contribute back to illumos-gate and arm64-gate lineage

- **Scope**: Weeks of kernel work
- **Risk**: Low — the template exists and works on arm64
- **Payoff**: Clean, sustainable, upstream-able, no dependency on OpenSPARC
  firmware blobs

### Path D: kexec OBP Stub (speculative, clever)

Boot Linux on sun4u QEMU (works). Place a minimal SPARC64 OBP Client
Interface (CIF) stub at TL1 in host RAM before kexec. The stub implements
the ~dozen OBP calls Solaris makes at runtime (write, read, open, close,
getprop, nextprop). kexec into Solaris with device tree pre-built in memory
and CIF handler pointer in the right register.

- **Scope**: ~1500 lines of SPARC64 assembly + CIF dispatch table
- **Risk**: High — SPARC TL1 programming, no prior art for this exact pattern
- **Payoff**: If it works, sun4u devices available with no kernel changes

---

## Device Inventory (Current Niagara VM)

From `prtconf -v` and `show-devs`:

| Device | Status | Notes |
|--------|--------|-------|
| `/virtual-devices/disk@0` | Reads work, writes lost | vdc/LDC path, q.bin SAM API missing |
| `/virtual-devices/console@1` | Works | qcn driver, serial to QEMU stdio |
| `/virtual-devices/nvram@2` | Not attached | 8KB, OBP config only |
| `/virtual-devices/rtc@3` | Not attached | Real-time clock |
| `net /virtual-devices/network@0` | Does not exist | OBP alias only, no QEMU device |
| `scsi_vhci` | Loaded | SCSI multipath layer, ready for iSCSI |
| `iscsi` | Force-attached | iSCSI initiator, waiting for a network |
| `/tmp` | Writable | tmpfs, in-session only |

---

## Sources

- QEMU `hw/sparc64/niagara.c` v8.2.2 — primary reference for machine implementation
- illumos-gate `usr/src/uts/sun4v/io/vnet_gen.c`, `vdsk_common.c` — LDC/vdisk protocol
- `richlowe/arm64-gate` (github) — arm64 illumos bring-up template, actively maintained 2026
- Oracle OpenSPARC T1 Architecture 1.5 package — firmware blobs, disk image
- Prior research session 2026-07-23 (recall: ted-mbp-rnelson-3) — sun4u boot status table
- This session's empirical findings — canary test, atexit writeback, device enumeration

---

## q.bin Source Discovery (Session 2)

The hypervisor source code is in the OpenSPARC T1 Architecture 1.5 package we
already downloaded, at `~/vms/opensparc/hypervisor/src/`. This changes the
investigation significantly.

### What the source reveals

**Disk I/O is direct hypercalls, not LDC:**
```
hcall_disk_read  (0xf0): bcopy vdisk_ram[offset..offset+size] → guest DMA buffer
hcall_disk_write (0xf1): bcopy guest DMA buffer → vdisk_ram[offset..offset+size]
```
No LDC implementation exists in the source. Disk size is read from the disk
image's VTOC at offset 0x1d0 (big-endian) — correctly yields 512MB for disk.s10hw2.

**The working q.bin is unique:**
The pre-built q.bin in S10image (163KB) works under QEMU. The source-tree builds
(debug: 246KB, release: 205KB, legion: 190KB) all hang — they require SAM/Legion
runtime APIs not present in QEMU. The working binary was built for QEMU/SAM
simulation specifically and is not in the source tree.

**Build environment unavailable:**
The source requires `qas` (custom Sun SPARC assembler) and Sun Studio. Rebuilding
on this Linux host is not straightforward. Possible but not yet attempted with
standard binutils SPARC64 tools.

### What this means for storage

If the Solaris kernel's vdc driver calls hcall_disk_write (0xf1) for writes, they
go directly to vdisk_ram — and atexit writeback should capture them. The disk
writes might already be working; we just haven't confirmed because our canary tests
wrote to tmpfs by mistake, and the zvol was repeatedly corrupted by panicked exits
during flatblk experiments.

If vdc uses LDC (which q.bin doesn't implement), writes are silently dropped.

**The critical next test:** Write a file to the ROOT UFS filesystem (not /tmp),
exit QEMU cleanly via monitor `quit`, and use `strings` on the zvol to look for
the canary. This definitively answers whether writes reach vdisk_ram.

### flatblk panic root cause (final assessment)

Adding any RAM region to the Niagara physical address space causes a deterministic
kernel panic in `ufs:fetchbuf` at pc=0x300005e7840. Four approaches confirmed
the panic; vdisk_ram host pointer was confirmed stable (not relocated).

Best current hypothesis: changing the size of any memory region (or adding a new
one) changes q.bin's DMA target computation during a disk write, corrupting a
SPARC64 register window in the kernel. This is consistent with the direct-hypercall
bcopy path in vdev_simdisk.s where the destination address depends on disk_pa
and the guest's real memory offset.

Fixing this without rebuilding q.bin requires understanding exactly which physical
address calculation q.bin performs — achievable via binary disassembly of the
working q.bin or by adding QEMU-side logging around vdisk_ram writes.
