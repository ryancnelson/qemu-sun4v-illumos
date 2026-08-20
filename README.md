# niagra-qemu-solaris-project

Running Solaris 10 on emulated UltraSPARC T1 (Niagara / sun4v) hardware under
QEMU on a modern x86 Linux host. The immediate goal is a working, writable
Solaris 10 environment. The medium-term goal is a patch to QEMU's Niagara
machine that fixes the storage write bug and gets submitted upstream.

**New agents:** start with
[`THE-TRIBBLIX-HSIMD-STORY.md`](THE-TRIBBLIX-HSIMD-STORY.md) for the narrative
of the August 19–20, 2026 investigation: how Tribblix first booted from RAM,
how the Solaris 10 `hsimd` driver became a durable boot-archive addition, what
the first ZFS experiment proved, which apparent proofs were retracted, and why
the next experiment puts a ZFS file vdev on UFS. Then use `CURRENT-STATE.md`
and `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` for exact operational state.

## Repository layout

```
patches/        QEMU source patches
qemu/           QEMU v8.2.2 source (shallow clone, sparc64 target)
tests/          Automated test harness (see below)
```

Operational scripts and disk images live outside the repo at
`~/vms/opensparc/` and `datapool/niagara/` (see Storage and Running sections).

## Current state

Solaris 10 boots to a login prompt in about 40 seconds. Root login works with
no password. The serial console is the only I/O path — no networking, no
graphics. Disk writes issued inside the guest are silently discarded and lost
on exit; see **Known bugs** below.

## Storage — ZFS on datapool

All VM storage lives on `datapool`, a 6.5T ZFS pool on this host. Raw files
on a regular filesystem are not used for active VMs — they cannot be
snapshotted atomically, cannot be safely opened by two processes, and give no
rollback primitive.

### Dataset layout

```
datapool/niagara/              ZFS filesystem — project root
datapool/niagara/base          ZFS filesystem — read-only Oracle assets
                                 (disk.s10hw2, firmware ROMs)
                                 Never opened by QEMU directly.
datapool/niagara/vms/          ZFS filesystem — container for VM zvols
datapool/niagara/vms/primary   zvol — the persistent daily-driver instance
                               snapshot: primary@clean (taken once after seeding,
                               used as the clone source for all test runs)
datapool/niagara/vms/test-*    zvols — ephemeral test instances, one per run,
                               cloned from primary@clean, destroyed after
```

### Why zvols

A zvol is a block device (`/dev/zvol/datapool/niagara/vms/primary`). QEMU
opens it like any other block device. Snapshots are instant and
space-efficient (copy-on-write). Cloning a snapshot to spin up a test
instance takes milliseconds and uses no extra space until the test writes
something. Destroying the clone after the test is equally instant.

This replaces the previous `cp disk.s10hw2 disk-rw.s10hw2` approach, which
was slow, wasted 512MB per copy, and had no isolation guarantees.

### Provisioning (one-time)

```bash
sudo bash zfs-setup.sh
```

This script creates the dataset hierarchy, imports the Oracle disk image into
the primary zvol, and takes the `@clean` snapshot. It is idempotent.

## Test harness

### Design principles

The test suite follows the Gilfoyle debugging methodology: every PASS or FAIL
must trace to directly observed data. No inference, no assumption. If the
claim is "writes persist", the test writes a unique canary string, exits QEMU,
and searches the raw block device for the canary with `strings`. Either it is
there or it is not.

### Storage isolation

The single most dangerous failure mode is two QEMU processes opening the same
block device simultaneously. On a zvol this causes immediate filesystem
corruption. The harness prevents it with a mandatory locking protocol:

1. Before opening any zvol, a lockfile is written to
   `/run/niagara-<zvol-name>.lock` containing the current PID.
2. Any script that wants to open a zvol checks for the lock first, verifies
   the recorded PID is still alive, and aborts if so.
3. QEMU is always launched through `lib/vm.sh`, which holds the lock for the
   duration of the process and removes it via a `trap` on exit — including on
   SIGTERM and SIGKILL-induced exits via the monitor.
4. Tests never open the primary zvol. They clone from `primary@clean`, open
   the clone, and destroy it on exit.

No test can run if any lock for its target zvol is held. No two tests share a
zvol. The primary VM and the test suite cannot run simultaneously on the same
zvol by construction.

### Test lifecycle

```
test start
  └─ assert: no lock for test zvol
  └─ zfs clone primary@clean → vms/test-<name>-<pid>
  └─ acquire lock on test zvol
  └─ boot QEMU against /dev/zvol/datapool/niagara/vms/test-<name>-<pid>
  └─ run interactions via expect
  └─ exit QEMU via monitor (quit command — ensures clean flush)
  └─ release lock
  └─ run host-side assertions against zvol (e.g. strings, md5)
  └─ destroy clone

test failure or signal
  └─ trap → release lock → destroy clone
```

### Library structure

```
tests/
  lib/
    lock.sh      acquire/release/check lock primitives
    zvol.sh      clone-from-snapshot, destroy, path resolution
    vm.sh        boot QEMU with lock held; expect interaction helpers
  test-boot-to-login.sh        PASSES on stock QEMU (baseline)
  test-disk-writes-persist.sh  FAILS on stock QEMU; target for patch #1
  test-reboot-obp-intact.sh    FAILS on stock QEMU; target for patch #2
  run-all.sh                   runs all tests, reports pass/fail with evidence
  zfs-setup.sh                 one-time provisioning
```

### Running tests

```bash
# Against system QEMU (establishes failing baseline)
sudo bash tests/run-all.sh

# Against a patched build
QEMU_BIN=./qemu/build/qemu-system-sparc64 sudo bash tests/run-all.sh
```

Tests require `sudo` because zvol operations (`zfs clone`, `zfs destroy`) need
root, and opening a block device needs read access to `/dev/zvol/...`.

### Current baseline (stock QEMU 8.2.2)

| Test | Expected | Evidence |
|------|----------|----------|
| test-boot-to-login | PASS | Login prompt observed at ~40s |
| test-disk-writes-persist | FAIL | Canary string not found in block device after exit |
| test-reboot-obp-intact | FAIL | OBP traps with "Fast Data Access MMU Miss" after reboot |

## Setup

### Prerequisites

```bash
sudo apt-get install -y qemu-system-sparc   # provides qemu-system-sparc64
```

### Disk image

Download the OpenSPARC T1 Architecture 1.5 package from Oracle:

```bash
mkdir -p ~/vms/opensparc && cd ~/vms/opensparc
wget "https://download.oracle.com/technetwork/systems/opensparc/OpenSPARCT1_Arch.1.5.tar.bz2"
tar -xjf OpenSPARCT1_Arch.1.5.tar.bz2
```

The archive extracts flat into the current directory. `S10image/` contains the
disk image (`disk.s10hw2`, 512 MB raw) and the firmware ROMs that QEMU loads
via `-L`.

### Running

Copy `run-solaris.sh` to `~/vms/opensparc/` and run it:

```bash
~/vms/opensparc/run-solaris.sh
```

At the `ok` prompt, type `boot disk`. Login as `root` with no password.

To exit QEMU: `Ctrl-A x`. To reach the QEMU monitor: `Ctrl-A c`.

The script makes a writable raw copy of the base image on first run
(`disk-rw.s10hw2`) so the original stays intact. Reset with
`run-solaris.sh reset`.

## Known bugs

### 1. Disk writes are silently discarded (BLOCKING)

**Symptom:** Any file written inside the guest is gone after the next boot.
`sync` inside the guest does nothing useful.

**Root cause:** Traced to `hw/sparc64/niagara.c` in QEMU. The virtual disk
is set up as anonymous RAM via `memory_region_init_ram`, then the image file
is copied into it once at boot via `rom_add_file_fixed`. There is no write-back
path. Every guest write lands in anonymous heap memory and evaporates when QEMU
exits. The comment in the source even calls it "kind of initrd." `cache=writethrough`
on the drive does not help — the block layer is not involved in the write path
at all.

**Fix:** Replace `memory_region_init_ram` + `rom_add_file_fixed` with
`memory_region_init_ram_from_file(..., RAM_SHARED, ...)`. This mmaps the
backing file with `MAP_SHARED`, so guest writes go directly to the host file.
See `patches/0001-niagara-vdisk-ram-shared.patch`.

**Status:** Patch written, not yet built or tested.

### 2. OBP traps after guest reboot

**Symptom:** After `init 6` or `reboot` inside the guest, control returns to
the OpenBoot `ok` prompt, but any subsequent command (`boot disk`, `devalias`,
etc.) immediately traps:

```
ERROR: Last Trap: Fast Data Access MMU Miss
[Exception handlers interrupted, please file a bug]
```

The session is unrecoverable. QEMU must be restarted.

**Root cause:** QEMU's Niagara machine does not reset CPU or MMU state when
the guest calls `prom_reboot`. The kernel's MMU context (TLBs, trap base
register) remains active when control transfers back to OBP, so OBP's first
memory access faults. The machine was designed as a one-shot boot environment
for the OpenSPARC simulators, not a fully operational VM.

**Workaround:** Exit QEMU (`Ctrl-A x`) and restart `run-solaris.sh` instead
of rebooting inside the guest.

**Status:** No fix yet. Needs a proper reset sequence in `niagara_init` or a
`machine_reset` handler.

### 3. No networking

**Symptom:** The Niagara machine exposes no PCI bus and no virtio bus. Every
attempt to attach a NIC fails:

```
qemu-system-sparc64: No 'PCI' bus found for device 'sunhme'
qemu-system-sparc64: No 'virtio-bus' bus found for device 'virtio-net-device'
```

OBP does show a `net` alias (`/virtual-devices/network@0`) in `devalias`, but
QEMU does not back it with anything.

**Status:** Blocked on the machine architecture. Fixing this likely requires
adding a virtual network device to the Niagara machine in QEMU, wired to the
same hypervisor interface that `q.bin` expects.

## Patches

### `patches/0001-niagara-vdisk-ram-shared.patch`

Fixes bug #1. Replaces the anonymous RAM + file copy approach with a
`MAP_SHARED` mmap of the backing file. One call instead of two, and writes
actually persist.

To build, apply this patch to QEMU 8.2.2 source and build the sparc64 target:

```bash
# Get source
apt-get source qemu   # or clone https://github.com/qemu/qemu -b v8.2.2

# Apply patch
patch -p1 < patches/0001-niagara-vdisk-ram-shared.patch

# Build (sparc64 target only)
./configure --target-list=sparc64-softmmu
make -j$(nproc)
```

## Sources

**Starting point — AI-generated overview (Gemini):**
Provided the basic invocation (`-M niagara -L . -drive if=pflash,...`) and
background on the OpenSPARC T1 image. Accurate on the boot procedure.
Inaccurate on networking: claimed `sunhme` works; it does not — the Niagara
machine has no PCI bus. Also suggested a qcow2 overlay for the disk; pflash
does not accept qcow2, and the write problem runs deeper than format selection.

**Oracle OpenSPARC T1 Architecture 1.5 package:**
`https://download.oracle.com/technetwork/systems/opensparc/OpenSPARCT1_Arch.1.5.tar.bz2`
The source of `disk.s10hw2` (Solaris 10 `Generic_118822-23` for sun4v), the
firmware ROMs (`q.bin`, `openboot.bin`, `reset.bin`, `1up-hv.bin`, etc.), and
the `README` files describing the original SAM/Legion simulator environment.
The SAM and Legion binaries in the package are SPARC ELF — they only ran on
Solaris/SPARC hosts and are not usable here.

**QEMU source — `hw/sparc64/niagara.c` (v8.2.2):**
`https://github.com/qemu/qemu/blob/v8.2.2/hw/sparc64/niagara.c`
Primary reference for understanding the machine implementation, locating the
vdisk bug, and writing the patch. Written by Artyom Tarasenko (2016).

**QEMU source — `include/exec/memory.h` (v8.2.2):**
`https://raw.githubusercontent.com/qemu/qemu/v8.2.2/include/exec/memory.h`
Used to verify the `memory_region_init_ram_from_file` signature and the
`RAM_SHARED` flag semantics before writing the patch.

**Artyom Tarasenko's SPARC emulation work — `https://tyom.blogspot.com/`**
Author of the QEMU Niagara machine target; the copyright header in `niagara.c`
confirms authorship. This project stands on his work, and several of our choices
trace directly to his posts.

- `2016/01/sun4v-in-qemu.html` — he began sun4v emulation in **2012**, "instead
  of pain killers to get some distraction from a broken leg".
- `2016/03/hello-solaris-10-under-qemusun4v.html` — first Solaris 10 boot.
- `2016/10/qemu-sun4vniagara-target-went-public.html` — public release; firmware
  (hypervisor, machine description, OpenBOOT) comes from OpenSPARC T1.
- `2016/11/sun4v-emulation-update.html` — improved memory flushes; machine
  renamed to lowercase `niagara`.
- `2017/01/sun4v-emulation-is-in-qemu-master.html` — merged upstream 19 Jan 2017.
- **`2025/01/self-hosting-opensolaris-under-qemu.html` (25 Jan 2025)** — he
  returned to Niagara after eight years. Source of the 1GiB MD files. Three
  things in it bear directly on this repo:
    * **`10.0.5.15`, the address our PPP link uses, comes from this post.**
    * He states he no longer remembers how he produced the MD files, and names
      the real specification: **FWARC 2005/115** (below). We reached
      byte-identical MD regeneration without it.
    * Performance: Tribblix takes **~1 hour** to boot on his laptop, and he
      judges sun4v emulation "can definitely be significantly optimized" —
      independent confirmation that there is headroom.
  His method is `slirp` compiled **inside** the guest plus `pppd` over a `socat`
  pty, with `pmemsave 0x1f40000000` for persistence. We diverged: Solaris 10
  ships its own PPP, and `patches/0001` gives real writeback instead of
  `pmemsave`.

**Machine Description specification — FWARC 2005/115:**
`https://sun4v.github.io/ARChive/FWARC/2005/115`
The authoritative MD format document, named by Tarasenko in the 2025 post. Our
`md/*.pdesc` plus `tools/build-mdgen.sh` regenerate `1up-md.bin` / `1up-hv.bin`
byte-identically (guarded by `tests/test-md-roundtrip.sh`), but that was reached
by reverse-engineering the binaries. Read this before changing MD *structure*
rather than field values.

**`github.com/artyom-tarasenko/qemu-sun4v-md`:**
Branch `1GiB-experimental` (dir `1GiB-snv_77`) lifts guest RAM from 256 MB to
1 GiB. Purely an MD change: `openboot.bin`, `q.bin`, `nvram1` and `reset.bin` are
byte-identical to ours; only `1up-md.bin` / `1up-hv.bin` differ. Branch
`snv77_slirp` carries his prepared, **redistributable** OpenSolaris image.

**`github.com/artyom-tarasenko/hsimd` — the guest's disk driver, GPLv2:**
The OpenSPARC RAM-disk driver, imported from Legion. **This is the driver our
guest uses for every disk access** (`hsimd_ioctl`, the `0xf0`/`0xf1` hypercalls).
Worth flagging loudly because this repo previously recorded that modifying the
guest driver was unavailable, which is why the `ttyb`/`qcn` route was declared a
dead end and why P2-018 (mapping the shared region directly, avoiding a hypercall
per 512-byte block) looked blocked. It is published and buildable. Tarasenko also
notes other illumos distributions lack `hsimd` entirely, which is why the
OpenSPARC snv_77 image in particular boots well here.

**`github.com/artyom-tarasenko/openfirmware`** (fork of Mitch Bradley's):
IEEE-1275 Open Firmware by its inventor. Relevant to a defect we hit and merely
documented: after a Solaris `init 6`, OBP reports `panic - kernel: prom_reboot:
reboot call returned!` and a subsequent `boot disk` fails with `ERROR: Last Trap:
Level 14 Interrupt`, so restarting requires killing QEMU.

**`github.com/artyom-tarasenko/opensparc-hypervisor`:**
Hypervisor source imported from the kenai Mercurial repo — the provenance of
`q.bin`, whose behaviour (direct `0xf0`/`0xf1` hypercalls, no LDC) this project
established empirically.

**Checked and found empty — a useful negative result:** his QEMU fork has
`sun4v-v0`, `sun4v-v1`, `sun4v-v2` and `sun4v-for-upstream` branches, and all
carry the *same single* `hw/sparc64/niagara.c` commit from 2016-09-29. There is no
unmerged niagara work to adopt, so `patches/0001` is not duplicating his. The
fork's March 2026 activity is a PReP/AIX branch, unrelated to sun4v.

**Empirical findings (this session):**
- Boot-to-login confirmed at ~40 seconds on a Xeon E5-2690 v3.
- Write bug confirmed by canary test: wrote `CANARY_XYZ123` to `/etc/hostname.test`
  inside the guest, ran `sync; sync`, then searched the raw image file on the host
  with `strings`. No match — the write never reached the file.
- `cache=writethrough` confirmed ineffective (the block layer is bypassed entirely).
- qcow2 overlay confirmed broken for pflash: OBP reports "Bad magic number in
  disk label" because it reads the qcow2 header as raw disk data.
- Networking confirmed non-functional: both `sunhme` (PCI) and
  `virtio-net-device` (virtio-bus) rejected by the Niagara machine at startup.
