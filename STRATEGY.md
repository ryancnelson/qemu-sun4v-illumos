# Strategy: illumos/Solaris on QEMU SPARC64 — Full Picture

> **READ `CURRENT-STATE.md` FIRST — it is authoritative for anything factual.**
>
> This file is a HISTORICAL record of how the architectural understanding
> developed, kept because the reasoning and the dead ends are useful. Parts are
> known stale and were true only when written. In particular it discusses disk
> writes as unreliable (since root-caused and fixed: direct hypercalls 0xf0/0xf1,
> not LDC) and the guest as lacking a usable compiler (since fixed: gcc 4.3.3
> compiles, links and runs against 262 installed headers). An independent
> reviewer reading this file drew both of those wrong conclusions, which is why
> this warning exists.

This document captures the architectural understanding developed through
investigation and debugging, and the paths considered along the way.

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

The networking design space and current recommendation are consolidated in
[`ETHERNET_MUSINGS.md`](ETHERNET_MUSINGS.md). In particular, PCI compatibility
is optional: a custom driver can register a normal illumos MAC/GLDv3 link while
using the existing channel or a small dedicated paravirtual transport below it.

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
| `/virtual-devices/disk@0` | **Reads AND writes work** | `hsimd` driver, direct hypercalls 0xf0/0xf1, NOT vdc/LDC. Persists via atexit writeback |
| `/virtual-devices/console@1` | Works | qcn driver, serial to QEMU stdio |
| `/virtual-devices/nvram@2` | Not attached | 8KB, OBP config only |
| `/virtual-devices/rtc@3` | Not attached | Real-time clock |
| `net /virtual-devices/network@0` | Does not exist | OBP alias only (from nvram1), no QEMU device, and no `vnet` driver in this kernel anyway |
| `scsi_vhci` | Loaded | SCSI multipath layer, ready for iSCSI |
| `iscsi` | Force-attached | iSCSI initiator, waiting for a network |
| `/tmp` | Writable | tmpfs, in-session only |

### Guest driver inventory — what this kernel can actually bind (2026-08-17)

Read directly off the image with `tools/peek.sh`, not inferred:

```
/platform/sun4v/kernel/drv/sparcv9:
    bge ce dma ebus glvc hsimd mdesc ncp px qcn rootnex su trapstat vnex
/kernel/drv/sparcv9 (network):
    eri qfe ge xge            (NO e1000g, pcn, rtls, dnet)
/kernel/misc/sparcv9 (PCI framework):
    busra pcicfg pcie pcihp
```

**Absent, and decisively so: `vnet` `vsw` `vdc` `vds` `ldc` `vldc` `cnex`.**

This image (`Generic_118822-23`, Solaris 10 3/05) **predates LDoms by roughly
18 months**, so there is no LDC stack in the kernel at all. Two consequences:

1. It retroactively explains why q.bin talks to the guest through raw
   hypercalls `0xf0/0xf1` with `hsimd` rather than LDC: there is no LDC peer to
   talk to. The older claim that the disk path was "vdc over LDC" was wrong.
2. **The LDoms/vnet networking route is permanently closed to this guest**, at
   any price short of replacing the OS. Artyom Tarasenko's OpenSolaris snv_77
   work is not portable here for that reason.

What IS present changes the picture in two interesting ways:

- **`px` is a PCI Express nexus driver, and `bge`/`ce`/`ge` are real NIC
  drivers.** The T1000/T2000 this firmware targets had onboard PCIe. So the
  guest is *capable* of driver-bound real hardware; it simply has no bus.
- **`glvc` is a hypervisor-mediated byte channel already in the image.** Its own
  strings show an MTU, a channel id, and an explicit fallback:
  `glvc, instance %d ddi_add_intr() failed, using polling mode` /
  `intr support not found, err = %d , use polling mode`. On real hardware this
  is the guest↔service-processor channel.

### Can we ever have real device drivers here?

Declaring a device is **solved**: the MD is editable as text and regenerates
byte-identically (`test-md-roundtrip`), and an added `console@4` node was
enumerated by OBP. Devices on sun4v are declared, not probed. Binding a
*driver* is the hard half. Ranked by value per unit of work:

| path | new emulation needed | blocker |
|------|---------------------|---------|
| PPP over the existing console | none | none — needs a PPP/slirp binary, and we now have a compiler |
| 2nd MD-declared RAM region | small | flatblk verdict, but see below — it is STALE |
| `glvc` byte channel | q.bin hypercall handler | cannot rebuild q.bin (only the S10image binary runs) |
| `px` + PCIe + NIC | a Fire/JBus host bridge, from scratch | the largest single piece of work in the project |

On the PCI route specifically: the niagara machine exposes **no PCI bus at all**,
which is the same wall that killed virtio-vsock
(`No 'PCI' bus found for device`). It would need a Fire/JBus PCIe host bridge
emulated well enough for `px` — which does IOMMU, interrupt mapping and MSI —
declared in the MD. And the NIC overlap is currently **empty**: our QEMU offers
`sunhme`, the guest has `bge/ce/eri/qfe/ge/xge`. QEMU's `sungem` against the
Solaris `ge` driver is the plausible pairing, and enabling `sungem` is a build
config flag rather than new code — but the bridge is the real cost.

### The flatblk "no second RAM region" verdict is STALE

P1-004 concluded that adding any RAM region deterministically panics the guest,
having eliminated the mmap-moves hypothesis by instrumentation and landing on
"adding RAM anywhere changes q.bin's DMA behavior".

That investigation predates the MD toolchain (`72c8fa5` is older than
`8ff48d0`). **Memory is MD-declared** — that is precisely how Artyom's files
raise the ceiling to 1GiB. So "q.bin's DMA goes somewhere wrong" is exactly the
symptom you would predict from a physical address space that no longer matches
the `mblock` nodes q.bin read at boot.

Nobody has yet tried adding a RAM region **together with a matching `mblock`
node in the MD**. That is a new experiment, one boot, informative either way.

But note it may not be worth much, because:

**We already have the shared-memory channel.** The vdisk at
`NIAGARA_VDISK_BASE` (0x1f40000000) *is* a memory-mapped region both sides
depend on: QEMU allocates it and writes it back on exit, and the guest reaches
it via `hsimd` → hypercall → q.bin → memcpy. The exchange slice is a mailbox at
an agreed offset within it, and the FAT filesystem (P2-005) is a filesystem
living in shared host RAM. A ring buffer carved out of that same region needs no
new QEMU memory at all; the only thing missing versus a virtio queue is a
doorbell, and polling substitutes for it at the cost of latency, not
correctness. 91MB moved in 8s through it already.

---

## Sources

- QEMU `hw/sparc64/niagara.c` v8.2.2 — primary reference for machine implementation
- illumos-gate `usr/src/uts/sun4v/io/vnet_gen.c`, `vdsk_common.c` — LDC/vdisk protocol
- `richlowe/arm64-gate` (github) — arm64 illumos bring-up template, actively maintained 2026
- Oracle OpenSPARC T1 Architecture 1.5 package — firmware blobs, disk image
- Prior research session 2026-07-23 — sun4u boot status table
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

**Build environment: HARDER THAN STOCK, BUT NOT UNAVAILABLE (revised 2026-08-17).**

An earlier revision of this document called q.bin "a fixed binary we cannot
rebuild". That is wrong and it distorted the whole device strategy, so state it
precisely instead. From `hypervisor/src/Makefile.master`:

```
AS    = $(QBINDIR)/qas        <- custom Sun SPARC assembler
SAS   = $(QBINDIR)/sas
CC    = $(SPRODIR)/bin/cc     <- Sun Studio
CPP   = /usr/ccs/lib/cpp      <- note: SOLARIS paths
LD    = /usr/ccs/bin/ld
MDGEN = $(QBINDIR)/mdgen-v1
```

Two real obstacles, both softer than "unavailable":

1. **The toolchain is Sun's.** But those are *Solaris* paths, and we now have a
   Solaris 10 guest with a working C toolchain and native binutils 2.21.1. **The
   guest is the natural build host for q.bin.** It had no compiler when the
   original assessment was written. We have also already cross-built `mdgen` out
   of this same tree with standard tools
   (`patches/0002-mdgen-x86-crossbuild.patch`), which partly disproves the claim
   by example. `mdgen-v1` above is exactly that tool.
2. **The working binary matches no variant in the tree.** Targets are
   `debug dumbreset fpga_1thread_reset legion release t1_fpga`; there is no
   `sam` target and no Makefile mentions one. The 163KB S10image q.bin was built
   for a QEMU/SAM-like configuration absent from the source drop, so this is not
   "run make" — it needs a configuration that avoids the missing SAM runtime
   APIs that make the in-tree builds hang.

**Crux unknown, and it is cheap to probe:** whether GNU `as` accepts Sun's
assembly syntax and any `qas`-specific directives. Assemble a few `.s` files and
find out before planning anything larger.

**Why this is the highest-leverage unlock in the project.** Rebuilding q.bin
flips the closed half of the device fork (below) open, and in one move enables:

- `glvc` — a real hypervisor-mediated byte channel whose driver is ALREADY in
  the guest
- our own paravirtual devices with custom hypercalls, i.e. a ring buffer **with
  a doorbell**, which is the one thing the shared-memory mailbox cannot express
- very likely flatblk, since q.bin's DMA address computation is the prime
  suspect there and we would then control it
- and it permanently removes the "we can add MD nodes but nothing services
  them" dead end

Risk is real: hyperprivileged SPARC assembly with exact trap-table layout
requirements.

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


---

## The device fork: who services the device?

The single most useful frame for "can we add hardware". A device needs three
things, and we control a different number of them depending on where it lives.

| device lives at | serviced by | can we change it? |
|---|---|---|
| `/virtual-devices@100` (cfg-handle, hypercalls) | **q.bin** | only by rebuilding q.bin (see above) |
| a raw physical address (MMIO) | **QEMU** | **yes** — it is our C code |

Devices under `/virtual-devices` are paravirtual: in `md/common.pdesc` they
carry `cfg-handle`, `my-space`, `intr`, `ino` and **no `reg` property at all**.
They have no registers. Their semantics live entirely in q.bin.

This explains the `console@4`/ttyb outcome properly. Adding the MD node worked —
OBP enumerated it. The node simply had nothing behind it, because only q.bin can
implement a virtual console channel. `qcn` being a singleton driver was the
second problem, not the first.

**Requirements for any new device, all three needed:**

1. A device tree node — **solved**, the MD is ours and round-trips
   byte-identically (`test-md-roundtrip`).
2. Something that services accesses — q.bin (closed for now) or QEMU (open).
3. A guest driver that binds — **the real constraint**, because Solaris 10 3/05
   will ignore any device it has no driver for, and we cannot realistically
   write sun4v kernel modules.

Constraint 3 is why every dead end looks the same:

| attempt | QEMU side | guest driver |
|---|---|---|
| `ttyb` second console | MD node fine, OBP saw it | `qcn` is a singleton -> refused |
| virtio-vsock | device exists in our build | none, and no bus either |
| `px` + NIC | needs a Fire bridge written | **already present** (`bge`/`ce`/`ge`) |

### The cheap experiment nobody has tried: a second UART bound by `su`

QEMU already emulates a 16550 at `NIAGARA_UART_BASE`, and the guest **already
ships `su`, a 16550 driver**. The guest never touches that UART today — q.bin
drives it on the guest's behalf to serve the `qcn` console.

So: add a *second* `serial_mm_init` at a fresh address in `niagara.c` (about two
lines, our code), declare a node for it in the MD with a `reg` property, and see
whether `su` binds. If it does, we get a second serial port **serviced entirely
by QEMU with no q.bin involvement** — the thing we keep concluding we cannot
have. All three requirements are then satisfied with an existing driver.

Caveats: `su` normally attaches beneath `ebus`/ISA (which hangs off PCI on real
T2000), binding depends on the `compatible`/`name` properties Solaris matches,
and it is unclear whether MD->OBP translation will emit a usable `reg` property
for a node type that normally has none. It may simply not bind.

Note this is not an alternative to PPP — it is the *line PPP would run on*.
Today PPP has to consume the console, which is why the install step deliberately
stops short of starting it.

---

## How the emulation actually works, and what you can observe

### TCG

QEMU runs SPARC64 guest code on an x86-64 host via **TCG (Tiny Code
Generator)**, a JIT: it takes a run of guest instructions up to a branch (a
"translation block"), lowers it to an architecture-neutral IR, compiles that to
x86-64, and caches the result. `-enable-kvm` is meaningless here; no hardware
can virtualize SPARC on x86. This is "softmmu" mode (full system, MMU emulated),
as opposed to `linux-user` mode.

TCG costs roughly 5-50x native, which is why boot takes ~40s, why the guest
reports `UltraSPARC-T1 (cpuid 0 clock 5 MHz)`, and why Tribblix reportedly needs
an hour to boot.

### Why the whole machine is six RAM regions and one UART

```
memory_region_init_ram: hv_ram, nvram, md_rom, hv_rom, prom, vdisk_ram
serial_mm_init(sysmem, NIAGARA_UART_BASE, 0, NULL, 115200, serial_hd(0), BIG_ENDIAN)
```

`niagara.c` contains **zero `MemoryRegionOps`** — not one MMIO device model. Every
guest memory access takes TCG's *fast path*: generated host code consults a
software TLB, resolves guest-physical to host-virtual, and issues an ordinary
`mov` against QEMU's own memory. The single exception is the UART, which is the
one address range wired to a device callback.

### Consequence: syscall tracing cannot see guest I/O

If you `strace` QEMU while the guest runs `dd if=bigfile | dd of=/dev/null`, you
see **none of the data**:

| when | syscalls visible |
|---|---|
| startup | the entire disk read in 64MB `blk_pread` chunks |
| during the dd | timers/signals, plus `write()` carrying only dd's *console text* |
| exit | the entire disk written back in 64MB `pwrite` chunks |

The guest's read path is `UFS -> hsimd -> hypercall 0xf0 -> q.bin -> memcpy`
inside QEMU's address space. No syscall, and under TCG not even a vmexit. The
pipe between the two `dd` processes is guest kernel memory, equally invisible.
Two independent confirmations already in this repo: `cache=writethrough` on the
drive changed nothing, and the write canary was found by reading
`/proc/<pid>/mem`, not by intercepting a syscall.

This is also why `SIGKILL` loses all data, why the exchange slice reaches 91MB/8s
(it is a memcpy, not I/O), and why a guest killed at a shell prompt leaves a
dirty journal.

### The right instruments

| goal | tool |
|---|---|
| watch guest instructions / memory accesses | **TCG plugin** — our build has `plugins = True`, API includes `qemu_plugin_register_vcpu_mem_cb`. `contrib/plugins/` has `execlog.c`, `hwprofile.c`, `cache.c`, unbuilt |
| inspect guest RAM live | `/proc/<pid>/mem` against the vdisk region, or monitor `pmemsave 0x1f40000000 <len> out.bin` / `xp` |
| trace QEMU's own C functions | **eBPF uprobes** — binary is not stripped, 48355 symbols; `bpftrace`/`bpftool`/`perf` all installed |
| guest instruction/host code dumps | `-d in_asm,out_asm,exec -D file` |

**TCG plugins are read-only.** They observe emulation; they cannot register
memory regions, answer MMIO, return data, or raise interrupts. A plugin can
watch storage traffic; it cannot *be* storage. The one arguably device-ish trick
is using `qemu_plugin_register_vcpu_mem_cb` to spot a guest write to a magic
address as a one-way doorbell — a notification, not a data path.

Two traps worth noting: USDT/`stapsdt` probes are **absent** from our build
(`trace_backends = ['log']`; a rebuild with the `dtrace` backend would add
them), and `bpf = auto` in our config is QEMU's **virtio-net RSS steering**
feature, nothing to do with tracing.
