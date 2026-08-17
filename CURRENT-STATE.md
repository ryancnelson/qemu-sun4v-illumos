# Current State

## What works

- Solaris 10 (SunOS 5.10 Generic_118822-23, sun4v) boots to login prompt in ~40s
- Root login, no password
- Serial console via `-nographic`
- QEMU 8.2.2, `qemu-system-sparc64 -M niagara`
- Firmware ROMs and disk image from Oracle OpenSPARC T1 Arch 1.5 package

## What is broken

1. **Disk writes are lost** — vdisk is anonymous RAM in QEMU, no write-back.
   Root cause isolated to `hw/sparc64/niagara.c`. Fix identified (RAM_SHARED patch).
   Not yet built or tested.

2. **OBP traps after guest reboot** — CPU/MMU state not reset on `prom_reboot`.
   No fix yet.

3. **No networking** — Niagara machine has no PCI or virtio bus.
   No fix yet.

## What exists in this repo

- `README.md` — full documentation, bugs, sources, ZFS design, test harness design
- `patches/` — patch file for bug #1 (written, not yet applied or tested)
- `qemu/` — QEMU v8.2.2 shallow clone (gitignored, for local patching and building)
- `tests/` — three test scripts + runner (written against flat files, not yet
  wired to ZFS/zvol layer which does not exist yet)
- `BACKLOG.md` — prioritized work items
- `CURRENT-STATE.md` — this file

## How to run a loop (iterate-bot / ralph-loop)

The project has two codebases in play: QEMU (host) and the guest OS source.
Both are open. A bug at the QEMU/driver interface can be fixed from either
side or both simultaneously. Each loop iteration produces a passing test as
its artifact — not just "it seemed to work."

1. Read `BACKLOG.md`, pick the top P1 item
2. Write the failing test that covers it (observable output, not inference)
3. Fix it — in QEMU source, in OS source, or both
4. Verify: `sudo QEMU_BIN=./qemu/build/qemu-system-sparc64 bash tests/run-all.sh`
5. Commit both repos with test output pasted into the commit message as evidence
6. Update `BACKLOG.md` (mark done, add friction log entry if anything bit you)
7. Repeat

## Environment

- Host: biggie (Linux, x86, Xeon E5-2690 v3)
- ZFS pool: `datapool` (6.5T, mounted at `/datapool`)
- Base image: `~/vms/opensparc/S10image/disk.s10hw2` (512MB raw, Solaris 10)
- Firmware ROMs: `~/vms/opensparc/S10image/`
- ZFS datasets: `datapool/niagara/` — **not yet provisioned** (next P1)
- QEMU source: `./qemu/` (shallow clone v8.2.2, build deps installed)
- Guest OS source: **not yet cloned** — target is illumos-gate (see P2-004)

## Source repos

| Repo | What it contains | Status |
|------|-----------------|--------|
| This repo | Tests, patches, docs, coordination | Active |
| `./qemu/` | QEMU v8.2.2 source, sparc64 target | Cloned, not yet built |
| illumos-gate | Guest OS — sun4v kernel, vnet, vdisk | **Not yet cloned** |

The guest OS source (illumos-gate) is the CDDL continuation of the OpenSolaris
Nevada (onnv) gate. The vnet and vdisk drivers in disk.s10hw2 descend directly
from this source. Reading it now tells us what the code running in our VM
expects from the hypervisor — even before we can rebuild the OS.

## Next action

Implement `tests/zfs-setup.sh` and `tests/lib/` (lock, zvol, vm).
See BACKLOG P1-001.
