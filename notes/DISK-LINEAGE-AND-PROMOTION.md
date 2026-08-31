# Disk lineage and promotion contract

## Purpose

Run-local qcow2 overlays persist writes, but persistence does not make an
overlay the parent of the next run. This contract prevents saved guest work
from becoming invisible when a later trial branches from an older checkpoint.

## State classes

- **BASELINE** -- immutable and independently cold-boot tested.
- **CANDIDATE** -- contains valuable guest changes but is not yet accepted.
- **DISPOSABLE** -- diagnostic branch; never becomes a parent implicitly.
- **RELEASE** -- standalone, sanitized, hashed, and release-tested.

`known-good` in a filename is not evidence of any state class. The run manifest
and acceptance record control.

## Required run manifest

Every run must record, before launch:

```text
run_id=
purpose=productive|debug|recovery|release
disposition=candidate|disposable
parent_image=
parent_sha256=
parent_run_id=
writable_overlay=
created_utc=
```

The expanded QEMU command, complete backing chain, and hashes belong beside the
manifest. A launcher must fail closed when the selected parent is older than the
newest preserved candidate unless the operator explicitly authorizes an older
debug parent. The launch summary must name the newer work that will be absent.

## End-of-run disposition

Before a run is closed, assign exactly one disposition:

- `PROMOTE`
- `PRESERVE_UNPROMOTED`
- `DISCARDABLE`
- `FAILED_WITH_EVIDENCE`

A run containing operator-created files is never automatically discardable.
Unexpected termination defaults to `PRESERVE_UNPROMOTED`.

## Promotion gate

Promotion is explicit and never mutates the evidence overlay in place:

1. Prove that QEMU has exited and no process has any member of the chain open
   for writing.
2. Record hashes, sizes, backing paths, run purpose, and final disposition.
3. Preserve the original chain and create a new checkpoint using reflink or
   another copy-on-write mechanism.
4. Verify that the checkpoint resolves through the intended candidate overlay,
   not merely its older parent.
5. Boot a disposable child, verify unique files in `/export/home/ryan` and
   `/root`, and shut down cleanly.
6. Cold boot a second disposable child and repeat the persistence checks.
7. Only then update the canonical candidate pointer and project status.

The future `tools/promote-run` command should implement these checks and require
an explicit operator confirmation before changing the canonical pointer.

## Recovery gate

To recover an unpromoted overlay:

1. Preserve or reflink every member of its backing chain.
2. Boot a writable recovery child above the preserved overlay, or import a copy
   read-only. Never mount or rebase the only overlay in place.
3. Copy required files to host staging and record hashes.
4. Inventory all guest changes before deciding whether to promote the overlay.

## Unit-101 rule

RAM backing and initialization are separate gates. A unit-101 file must be in a
run-scoped tmpfs path, but a correctly sized all-zero file is invalid. Before
QEMU starts, require the accepted VTOC, geometry, slices, mailbox offsets, and
clean sequence state. Until deterministic generation is proven, copy the
hash-pinned sparse template into tmpfs. Require guest channel echo before BBS or
PPP acceptance.

## Current lineage correction -- 2026-08-27

- `workstation-playbox-known-good-20260827T165948Z/images/root-unit104.qcow2`
  is **CANDIDATE / PRESERVE_UNPROMOTED**. It is 619,380,736 bytes and was last
  written at the 20:19:17 termination. It likely contains the operator's files
  under `/export/home/ryan` or `/root`.
- `workstation-playbox-debug-20260827T203510Z/images/root-unit104.qcow2` is a
  **DISPOSABLE** sibling created from the older accepted parent. It does not
  include the candidate's writes.
- The GCC 11.5 archive is host-staged only at
  `workstation-playbox-known-good-20260827T165948Z/staging/gcc-11.5.0/` and was
  not installed in the guest before the termination.
- The next recovery boot must place a fresh writable overlay above the preserved
  candidate, seed unit 101 correctly in tmpfs, and verify the operator's files
  before any release cleanup.

