# Backlog

Priority: P1 (blocking) → P2 (important) → P3 (nice to have)
Status: [ ] todo, [~] in progress, [x] done

---

## P1 — Blocking

### P1-001: Implement ZFS storage layer and test isolation [x] DONE

The test suite currently assumes flat raw files. It must be rewritten around
zvols before any test can run safely on a live host.

Deliverables:
- `tests/zfs-setup.sh` — idempotent provisioning script
  - creates `datapool/niagara/`, `datapool/niagara/base`,
    `datapool/niagara/vms/`
  - imports `disk.s10hw2` into `datapool/niagara/vms/primary` zvol (512MB)
  - takes `primary@clean` snapshot
- `tests/lib/lock.sh` — acquire, release, check primitives
  - lockfile at `/run/niagara-<zvol-name>.lock` containing PID
  - check verifies PID is still alive before refusing
  - acquired before any QEMU open, released via trap on exit
- `tests/lib/zvol.sh` — clone, destroy, path resolution
  - clone: `zfs clone primary@clean → vms/test-<name>-<pid>`
  - path: `/dev/zvol/datapool/niagara/vms/<name>`
  - destroy: `zfs destroy` after lock released
- `tests/lib/vm.sh` — boot QEMU with lock held; expect interaction helpers
  - wraps QEMU invocation, holds lock for process lifetime
  - exits QEMU via monitor `quit` command (not SIGKILL) to ensure flush
- Rewrite `tests/test-*.sh` on top of new lib
- Rewrite `run-solaris.sh` to use lock + primary zvol

Acceptance: `sudo bash tests/run-all.sh` completes without corrupting any zvol,
even if interrupted mid-run (trap cleanup verified by killing the test process
mid-flight and confirming no lock file remains and the clone is destroyed).

### P1-002: Build patched QEMU and verify disk write fix [x] DONE

**RESOLVED.** `test-disk-writes-persist` passes: write to /etc, clean exit,
canary found in raw zvol, second boot reads it back. Storage is trustworthy.


Depends on: P1-001 (need test-disk-writes-persist running against a zvol)

- Apply `patches/0001-niagara-vdisk-ram-shared.patch` to `./qemu/`
- Build sparc64-softmmu target only: `./configure --target-list=sparc64-softmmu && make -j$(nproc)`
- Run `test-disk-writes-persist` against patched binary
- Expected: PASS (canary found in zvol via `strings /dev/zvol/...` after QEMU
  exits cleanly via monitor `quit`)
- Commit patch as proper `git format-patch` output with full explanation

Acceptance: `QEMU_BIN=./qemu/build/qemu-system-sparc64 sudo bash tests/run-all.sh`
shows test-disk-writes-persist PASS with observed canary string in output.

---

## P2 — Important

### P2-001: Fix OBP trap after guest reboot [ ]

Depends on: P1-001

Root cause: QEMU Niagara machine has no `machine_reset` handler. When the
guest calls `prom_reboot`, control returns to OBP firmware but the CPU's
MMU context (TLBs, trap base register) from the running kernel is still live.
OBP's first memory access takes an MMU miss trap, which OBP cannot handle.

Investigation plan:
- Read `hw/sparc64/niagara.c` for the reset code path (or absence of one)
- Compare with `hw/sparc64/sun4m.c` or `hw/sparc64/sun4u.c` reset handlers
  for the minimum CPU state that must be restored
- At minimum: TBA (trap base address register) must be reset to OBP's value;
  TLBs must be flushed

Test: `test-reboot-obp-intact.sh` must PASS.

### P2-002: Networking via PPP over serial [ ]

Depends on: P1-001, ideally P1-002 (persistent disk for pppd config)

The Niagara machine has no PCI or virtio bus, so standard NIC attachment
doesn't work. The serial port is the only available channel.

Plan:
- QEMU exposes the guest's serial device via `-serial` — can be a pipe,
  PTY, or socket on the host
- Guest: configure Solaris `pppd` over `/dev/ttya`
- Host: run Linux `pppd` against the other end of the pipe/PTY
- Result: a point-to-point IP link; full TCP/IP connectivity via `ppp0`

This is the fastest path to any networking. No QEMU machine changes required.

Test: from inside guest, `ping <host-side ppp IP>` succeeds.

### P2-003: Investigate vnet/vnex for native hypervisor networking [ ]

Depends on: P2-002 (networking exists before attempting this)

illumos-gate has a `sun4v/vnet` driver that implements the Oracle hypervisor's
virtual network interface. It talks to the hypervisor via Machine Description
(MD) table entries and the `vnex` nexus device. QEMU's Niagara machine does
not implement the MD networking entries or `vnex`.

This is a QEMU implementation task — the guest-side driver already exists in
Solaris/illumos. The work is on the QEMU side: implement the MD table network
device entries and a corresponding `vnex` QEMU device that backs them with
SLIRP or a tap interface.

Source: `usr/src/uts/sun4v/io/vnet.c` and `vnet_gen.c` in illumos-gate show
the expected hypercall interface.

Scope: significant QEMU work. Needs a spike to assess feasibility.

---

## P2 — Important (continued)

### P2-004: Clone illumos-gate and establish open-source guest OS [ ]

**Why this matters:** With illumos-gate in play, bugs at the QEMU/driver
interface can be fixed from either side. The ralph-loop produces test-verified
fixes to both QEMU and the guest OS simultaneously. Without open OS source,
every iteration is limited to QEMU-side changes only.

**Source lineage:** illumos-gate is the direct CDDL continuation of the
OpenSolaris Nevada (onnv) gate. The vnet, vdisk, ldc, mdeg drivers in
disk.s10hw2 descend directly from this source. We can read the exact code
running in our VM today — we just can't yet rebuild it.

**Why illumos over pre-2010 OpenSolaris:**
- Pre-2010 onnv required Sun Studio to build; illumos fixed gcc support
- The CDDL source is identical in substance; illumos is the living version
- Building from source is straightforward with gcc and standard Linux tooling
- Binary images for sun4v (Tribblix SPARC m34) exist if we need a pre-built OS

**Deliverables:**
- Clone illumos-gate: `git clone https://github.com/illumos/illumos-gate`
- Read `usr/src/uts/sun4v/` — this is the relevant platform directory
  Key files: `io/vnet.c`, `io/vnet_gen.c`, `io/ldc.c`, `io/mdeg.c`,
  `io/vdsk_common.c`, `sys/ldc.h`, `sys/mach_descrip.h`
- Document the LDC/MD protocol from source — this is the spec we implement
  in QEMU for P2-003
- Establish a build environment for sun4v kernel modules (needed before
  we can patch the guest side of any driver)

**Acceptance:** `usr/src/uts/sun4v/io/vnet.c` is readable and annotated
with our understanding of what QEMU must provide. Build environment
documented in this repo.


## P3 — Nice to have

### P3-001: illumos test suite on guest [ ]

Depends on: P1-002 (writable disk), P2-002 (networking to transfer files)

illumos-gate has a comprehensive test suite at `usr/src/test/`:
- `os-tests` — syscall, proc, signal, zone tests
- `zfs-tests` — ZFS correctness
- `net-tests` — networking stack
- `libc-tests`, `crypto-tests`, `elf-tests`, etc.

These run on any illumos derivative including OpenSolaris/Solaris 10 (with
some caveats — ZFS tests require a pool, net-tests require a working NIC).

The `test-runner` framework at `usr/src/test/test-runner` is a Python-based
runner. Transfer to guest via PPP/ftp or by embedding in a larger zvol.

Source: https://github.com/illumos/illumos-gate/tree/master/usr/src/test

### P3-002: Tribblix SPARC investigation [ ]

Depends on: P1-002, P2-002

Tribblix (by Peter Tribble) is an actively maintained illumos distribution
with a SPARC port (latest: m34 ISO). It runs on real Sun hardware
(T-series, Netra). Whether it can boot on QEMU Niagara is unknown.

Their SPARC overlays are at: https://github.com/tribblix/overlays.sparc
Their SPARC build environment is documented in:
https://github.com/tribblix/tribblix-build/tree/main/illumos

The claim that "Tribblix has SPARC64 virtio working" is ⚠️ UNVERIFIED.
No evidence found in their blog, repos, or build scripts. Needs direct
inquiry or source review once their actual gate location is found.

Contact: Peter Tribble (ptribble on GitHub, illumos discuss mailing list)
is responsive and would likely know the state of QEMU Niagara support.

### P3-003: virtio-net on Niagara [ ]

Depends on: P2-003 (understand vnet/vnex first)

Two paths, either requires QEMU machine changes:

**Path A — PCI bus:** Add a PCI bus to the Niagara machine. The guest's
existing `pci-hme` or `pcn` drivers would then attach to a `pcnet` or
`e1000` QEMU device. Risk: OBP may not enumerate a PCI bus correctly on
the Niagara machine type; extensive firmware work may be needed.

**Path B — sun4v native:** Implement the MD/vnex virtual network interface
that Solaris's `vnet` driver expects. This is the architecturally correct
path but requires understanding the full MD schema and hypercall ABI.

### P3-004: virtio framebuffer [ ]

Depends on: P3-003 (get virtio working first)

QEMU has `virtio-vga` and `virtio-gpu` devices. Whether the Niagara machine
can be extended to include a framebuffer path via `virtio-gpu` is unknown.
The sun4v platform has no framebuffer device in its original hardware spec
(Sun Fire T1000/T2000 are headless servers), so OBP has no framebuffer
initialization. A framebuffer would need to be self-identifying to the guest
via a different mechanism (e.g. a PCI VGA device if a PCI bus is added).

### P3-005: Submit disk write patch upstream [ ]

Depends on: P1-002 passing

Format patch per QEMU contribution guidelines, open thread on qemu-devel.
CC: Artyom Tarasenko (original niagara.c author).

### P3-006: Larger disk image / package installation [ ]

Depends on: P1-002

The stock `disk.s10hw2` is 512MB with a minimal Solaris install. Grow the
zvol and resize the UFS filesystem, or investigate adding a second zvol as
`/export` for packages and user data.

---

## Friction log

- `cache=writethrough` on the QEMU drive did nothing — the block layer is
  not involved in the vdisk write path at all. Misleading QEMU option.
- qcow2 overlay silently fails for pflash — OBP reads qcow2 magic bytes as
  raw disk label and panics. No error from QEMU at startup.
- OBP `boot disk` fails after any guest reboot — session must be restarted.
  Makes iterating on the guest tedious until P2-001 is fixed.
- `sync` inside the guest is meaningless until P1-002 is done.
- SAM simulator binaries in the OpenSPARC package are SPARC ELF — they only
  ran on Solaris/SPARC hosts and are useless on this x86 Linux host.
- Tribblix SPARC illumos gate location not found publicly. `tribblix/illumos-tribblix`
  on GitHub returns 404. May be a private or unlisted repo.

### P1-004: Investigate flatblk panic — adding RAM region corrupts UFS mount [~] SUPERSEDED

No longer blocking: storage works without flatblk. Left here as a record of
the failure mode in case a second RAM region is ever needed again.


**Symptom:** Adding ANY new RAM region to the Niagara guest physical address
space via `memory_region_add_subregion` causes a deterministic kernel panic:

```
BAD TRAP: type=10 (illegal instruction)
pc=0x300005e7840  ← data buffer address, not code
ufs:fetchbuf+74 → ufs:readlog → ufs:lufs_read_strategy → vfs_mountroot
```

Same virtual address every time, regardless of the new region's physical
address (tested: 0x1f50000000, 0x400000000), size, or timing of the
`memory_region_add_subregion` call within `niagara_init`.

**Secondary finding:** atexit fires on abnormal QEMU exit (after kernel panic
→ OBP restart → process exit). The vdisk writeback saves corrupted RAM state
to the zvol. Always `zfs rollback primary@clean` after a panicking run.

**Hypothesis:** QEMU's host mmap for existing RAM regions (vdisk_ram,
partition RAM) is moved when a new large allocation is added, staling the
TCG software TLB's host-address pointers. Next vdisk read via the stale
pointer returns garbage → UFS function pointer corruption → illegal
instruction jump.

**Investigation needed:**
- Read QEMU's `physmem.c` / `exec.c` RAM allocation path
- Check if `qemu_ram_alloc` uses a slab allocator that can move existing blocks
- Try: allocate flatblk RAM before all other regions (make it index 0) — if
  it can't be moved, subsequent regions are added to a different pool
- Try: `memory_region_init_ram` with a pre-allocated host buffer
  (`memory_region_init_ram_ptr`) to bypass QEMU's allocator entirely
- Try: use a `/dev/shm`-backed anonymous shared region instead of file mmap

**Additional findings (overnight loop):**

All four approaches tried, all panic the same way:
- New RAM region at 0x1f50000000 (device space adjacent to vdisk)
- New RAM region at 0x400000000 (16GB, "safe" zone)
- New RAM region via `memory_region_init_ram_ptr` (user-supplied buffer)
- Extended vdisk_ram to include flatblk tail (0x1f60000000)

Instrumentation confirmed vdisk_ram host ptr does NOT move (mmap-moves
hypothesis eliminated). The panic is NOT from QEMU moving allocations.

**Current hypothesis:** extending any allocation at NIAGARA_VDISK_BASE or
adding RAM anywhere in the physical address space changes q.bin's internal
DMA behavior. q.bin targets a DMA write to the wrong kernel virtual address,
corrupting a SPARC64 register window (%i7 / return address), causing the
kernel to return into a data buffer (0x300005e7840) and fault on illegal
instruction.

**Blocked on:** q.bin source code or binary instrumentation to trace DMA
target computation. q.bin is a closed binary from the OpenSPARC T1 package.

**Next steps for P1-004:**
- Disassemble q.bin to find vdisk DMA read/write routines
- Instrument QEMU to intercept all writes to partition RAM during vdisk I/O
  and log the target physical addresses — look for writes near the kernel
  stack at the time of panic
- Consider patching q.bin binary if the DMA offset calculation can be found

---

## P1-005: Determine disk write path (vdc: direct hypercall vs LDC) [x] DONE

**ANSWER: direct hypercalls (0xf0/0xf1), not LDC.** q.bin has no LDC
implementation at all. Writes reach vdisk_ram; the atexit writeback
persists them. Measured directly via /proc/<pid>/mem: the canary is present
in the vdisk_ram mapping while the guest is running.


**Why this matters:** Everything else depends on this. If the kernel uses direct
hypercalls (0xf0/0xf1), writes reach vdisk_ram and atexit saves them — we have
working storage already. If it uses LDC, writes are silently dropped by q.bin's
unimplemented LDC handler and we need a different fix.

**Investigation plan:**

1. Read `usr/src/uts/sun4v/io/vdc.c` in illumos-gate (we have the source).
   Look for: does vdc use `hv_disk_read`/`hv_disk_write` (direct hypercalls)
   or `ldc_write` (LDC channel)? The answer is in the I/O submission path.

2. If direct hypercalls: re-run the hostname write test with a CLEAN zvol,
   clean QEMU exit (monitor `quit`), and inspect the zvol with `strings`.
   If the canary appears, writes already work and atexit just wasn't firing.

3. If LDC: implement the minimal LDC vdisk server in QEMU's niagara machine.
   Protocol is documented in `usr/src/uts/sun4v/io/vdc.c` (client side).

4. Alternative — patch disk.s10hw2 kernel to use direct hypercalls:
   The `hcall_disk_read`/`hcall_disk_write` interface (0xf0/0xf1) is simpler
   than LDC. If we can patch or rebuild the vdc driver to use direct hypercalls,
   writes work immediately with no QEMU changes.

**Acceptance:** `test-disk-writes-persist.sh` PASSES.

---

## P2-005: Cross-compile q.bin on Linux / patch binary for debug output [ ]

**Context:** q.bin source is in `~/vms/opensparc/hypervisor/src/`. The build
requires `qas` (custom Sun SPARC assembler) and Sun Studio. Standard Linux
tools may work as a substitute.

**Investigation:**
- `binutils` includes `sparc64-linux-gnu-as` — check if this is compatible with
  the hypervisor assembly syntax (Sun SPARC vs GNU SPARC differences)
- The Makefile uses `qas` and `sas` for assembly. Try substituting with:
  `sparc64-linux-gnu-as -xarch=v9 -64` and `sparc64-linux-gnu-ld`
- If assembly compiles: add `printf`-equivalent debug output to `hcall_disk_write`
  (write a pattern to a known physical address readable via QEMU pmemsave)
- If not: binary patch the working q.bin to add NOPs + MMIO writes at the
  `hcall_disk_write` entry point

**Value:** Definitive proof of whether writes reach q.bin, independent of
the Solaris kernel source analysis in P1-005.

---

## P2-006: q.bin source study — full hypervisor behavior map [ ]

Source location: `~/vms/opensparc/hypervisor/src/greatlakes/`

Key files to read and annotate:
- `common/src/vdev_simdisk.s` — disk hypercall implementation (READ, done)
- `common/src/hcall.s` — full hypercall dispatch table
- `common/src/svc.s` — service channel handling (possible LDC routing)
- `ontario/src/setup.s` — guest initialization, DISK_PA/DISK_SIZE setup
- `ontario/src/main.s` — hypervisor entry, trap table
- `common/src/vdev_console.s` — console (for comparison with disk path)
- `common/include/vdev_simdisk.h` — disk constants (DISK_S2NBLK_OFFSET=0x1d0, etc.)

**Goal:** Build a complete picture of what the working q.bin can and cannot do,
without needing to rebuild it. Specifically: does it have any path from an LDC
channel message to a disk read/write? (Look for LDC-related symbols via `nm` or
`strings` on the working binary.)

**Quick start:**
```bash
nm /datapool/niagara/base/q.bin 2>/dev/null || \
  objdump -t /datapool/niagara/base/q.bin 2>/dev/null
strings /datapool/niagara/base/q.bin | sort
```

---

## P1-006: Add console@4 (ttyb) — second serial data channel [ ]

Now tractable: the MD is editable as text with a verified round-trip
(`tests/test-md-roundtrip.sh`), so this is a source edit, not binary surgery.

`console@1`'s unit address comes from `cfg-handle = 0x1` in the MD's
`virtual-device console` node (`common.pdesc`). `nvram1` already aliases
`ttyb -> /virtual-devices/console@4`, so OBP expects a node that has never
existed.

Steps:
1. Copy `~/vms/opensparc/legion/src/config/niagara/{1up,common}.pdesc` into
   `md/` in this repo (so our MD source is version-controlled).
2. Add a second `virtual-device console` node: `cfg-handle = 0x4`,
   `channel# = 1`, `compatible = "qcn"`, distinct `ino`.
3. Regenerate: `tools/gen-md.sh md/1up.pdesc /datapool/niagara/base/1up-md.bin`
4. Add the matching UART in `hw/sparc64/niagara.c`, wire to `serial_hd(1)`.
5. Expose host-side: `-serial pty` (or a unix socket), attach with `screen`.
6. Verify: `show-devs` lists `console@4`; Solaris has `/dev/term/b`.

Acceptance: a new test that writes a canary out the second serial from the
guest and reads it on the host, with no console interference.

Value: a real bidirectional data channel — enough to move a compiler in with
`sz`/`rz`, without needing networking or a second block device.

---

## P1-007: Install a C compiler in the guest [ ]

Depends on: P1-006 (or any working data channel).

1.6GB free on the 1.9GB UFS is enough for gcc4core.

- Source: `http://mirror.opencsw.org/opencsw/stable/sparc/5.10/`
  `gcc4core-4.9.0,REV=2014.04.27-SunOS5.10-sparc-CSW.pkg.gz` (~137MB gz)
- Dependencies per the OpenCSW catalog: libgcc_s1, libgmp10, libmpfr4,
  libmpc3, libiconv2, libz1, binutils, coreutils, ggrep, gsed
- Transfer via the P1-006 serial channel, then `pkgadd -d`

Acceptance: `gcc hello.c -o hello && ./hello` works in the guest.

First target once it works: build a `format(1M)` that does not reject the
`SUNW,sun4v-virtual` controller name (see CURRENT-STATE "Known gaps" #2).

---

## Harness bugs found and fixed (2026-08-17 review)

Recorded because each one silently produced wrong results:

1. `test-disk-writes-persist` wrote its canary to `/tmp` — which is tmpfs
   (`swap - /tmp tmpfs`). It never touched the disk, so the test could only
   ever fail. Now writes to `/etc`.
2. No test ran `lockfs -f /` before exit, so every run persisted a dirty LUFS
   journal. Added `$vm_clean_shutdown_fragment`.
3. **expect matched the terminal echo of the command it had just typed.**
   `send "... && echo WROTE_OK"` + `expect "WROTE_OK"` matches the echo, so
   expect continued before the shell ran anything — QEMU was quit before the
   write happened. Match the shell prompt `"# "` instead; never an echo-able
   marker.
4. **`strings "$DEV" | grep -qF ...` under `set -o pipefail`.** `grep -q`
   exits on first match, `strings` dies of SIGPIPE (141), and pipefail reports
   the pipeline as FAILED even though the match succeeded. This masked a fully
   working writeback as a failing test. Use `grep -a -q -F` on the device
   directly.
5. **`lock_acquire` installed `trap ... EXIT`, clobbering the caller's cleanup
   trap.** Bash has one EXIT trap. Tests set `trap cleanup EXIT` then called
   `lock_acquire`, which replaced it — so no test ever destroyed its clone.
   15 orphans (~3.3GB) had accumulated. `lock_acquire` no longer sets traps;
   callers own cleanup.
6. `zfs destroy` on a test clone fails permanently with "volume has children"
   because the atexit writeback snapshots the clone itself. Needs `-r`.
7. `$HOME` under `sudo` is `/root`, so `$HOME/vms/opensparc` did not resolve.
   Use the invoking user's home via `SUDO_USER`.
8. `run-solaris.sh reset` rolled back to `@clean` — the 512MB original —
   silently downgrading the disk, despite its comment claiming `@clean-2gb`.
9. `run-solaris.sh` ran `sudo exec "$QEMU"`, which asks sudo to find a binary
   named `exec`. Also took no lock, so it could race the test suite on
   `primary`.
