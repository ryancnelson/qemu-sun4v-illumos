# Backlog

Priority: P1 (blocking) → P2 (important) → P3 (nice to have)
Status: [ ] todo, [~] in progress, [x] done

---

## P1 — Blocking

### P1-001: Implement ZFS storage layer and test isolation [ ]

The test suite currently assumes flat raw files. It must be rewritten around
zvols before any test can run safely on a live host.

Deliverables:
- `tests/zfs-setup.sh` — idempotent provisioning script
  - creates `datapool/niagara/`, `datapool/niagara/base`,
    `datapool/niagara/vms/`
  - imports `disk.s10hw2` into `datapool/niagara/vms/primary` zvol
  - takes `primary@clean` snapshot
- `tests/lib/lock.sh` — acquire, release, check primitives
  - lockfile at `/run/niagara-<zvol-name>.lock` containing PID
  - check verifies PID is still alive before refusing
- `tests/lib/zvol.sh` — clone, destroy, path resolution
  - clone: `zfs clone primary@clean → vms/test-<name>-<pid>`
  - path: `/dev/zvol/datapool/niagara/vms/<name>`
  - destroy: `zfs destroy` after lock released
- `tests/lib/vm.sh` — boot QEMU with lock held; expect helpers
  - wraps QEMU invocation, holds lock for process lifetime
  - exits QEMU via monitor `quit` command (not SIGKILL) to ensure flush
- Rewrite `tests/test-*.sh` on top of new lib
- Rewrite `run-solaris.sh` to use lock + primary zvol

Acceptance: `sudo bash tests/run-all.sh` completes without corrupting any zvol,
even if interrupted mid-run (trap cleanup verified).

### P1-002: Build patched QEMU and verify disk write fix [ ]

Depends on: P1-001 (need test-disk-writes-persist to run against a zvol)

- Apply `patches/0001-niagara-vdisk-ram-shared.patch` to `./qemu/`
- Build sparc64-softmmu target
- Run `test-disk-writes-persist` against patched binary
- Expected: PASS (canary found in zvol after QEMU exits via monitor quit)
- Commit patch as proper `git format-patch` output

Acceptance: `QEMU_BIN=./qemu/build/qemu-system-sparc64 sudo bash tests/run-all.sh`
shows test-disk-writes-persist PASS with canary evidence in output.

---

## P2 — Important

### P2-001: Fix OBP trap after guest reboot [ ]

Depends on: P1-001

Root cause: QEMU Niagara machine has no `machine_reset` handler. The kernel's
MMU context (TLB, TBA register) is still live when `prom_reboot` returns
control to OBP, causing an immediate MMU miss trap on OBP's first memory
access.

Investigation needed:
- Read `hw/sparc64/niagara.c` reset path (or absence of one)
- Check what sun4u machine does in its reset handler for comparison
- Determine minimum CPU state that must be restored for OBP to run cleanly

Test: `test-reboot-obp-intact.sh` currently FAILS. Must PASS.

### P2-002: Networking [ ]

Depends on: P1-001

The Niagara machine has no PCI or virtio bus. OBP lists
`/virtual-devices/network@0` in `devalias` but QEMU does not back it.

Investigation needed:
- Determine what hypercall interface `q.bin` uses for the virtual NIC
- Determine what Solaris's `vnet` driver expects from the hypervisor
- Assess feasibility of wiring a SLIRP backend to the virtual-devices bus

This may require significant QEMU machine-level changes. Scope unknown.

---

## P3 — Nice to have

### P3-001: Submit disk write patch upstream [ ]

Depends on: P1-002 passing

- Format patch per QEMU contribution guidelines
- Write commit message with full explanation of the bug
- Open mailing list thread on qemu-devel

### P3-002: Larger disk image [ ]

The stock `disk.s10hw2` is 512MB with a minimal Solaris install. Adding
packages fills it quickly. Investigate whether the UFS filesystem can be
grown inside a larger zvol, or if a fresh install is required.

### P3-003: Snapshot workflow for daily driver [ ]

Once writes persist (P1-002), define a snapshot discipline for the primary
zvol: pre-experiment snapshots, named restore points, pruning policy.

---

## Friction log

- `cache=writethrough` on the QEMU drive did nothing — the block layer is
  not involved in the vdisk write path at all. Misleading QEMU option.
- qcow2 overlay silently fails for pflash — OBP reads qcow2 magic bytes as
  raw disk label and panics. No error from QEMU at startup.
- OBP `boot disk` fails after any guest reboot — session must be restarted.
  Makes iterating on the guest tedious until P2-001 is fixed.
- `sync` inside the guest is meaningless until P1-002 is done. Builds false
  confidence that writes are landing.
