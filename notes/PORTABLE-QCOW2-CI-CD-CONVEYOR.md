# Portable QCOW2 CI/CD conveyor

Date: 2026-08-26

Status: design agreed during the first EC2 installed-OpenIndiana recovery.  The
existing Exabyt conveyor remains the operational baseline; this note records
the portable artifact and transport rules needed to extend it to EC2 without
re-inventing them.

## Goal

Turn Biggie, Exabyt, and EC2 into a reproducible build-and-boot conveyor:

1. publish immutable, hash-pinned Niagara releases;
2. move only changed blocks whenever sender and receiver share a base;
3. create disposable writable state for every QEMU run;
4. cold-boot each candidate through semantic acceptance gates;
5. retain the prior green candidate until the new one passes; and
6. preserve enough provenance and timing evidence to reproduce every result.

The portable contract is QCOW2.  ZFS replication and sparse-aware rsync are
transport/cache optimizations, not the artifact identity.

## Lessons from the Exabyt conveyor

The established Exabyt flow provides the safety model:

- validate every source hash before publication;
- assemble a private partial bundle;
- publish `READY` last;
- update `current` atomically only after the bundle is complete;
- boot per-run writable clones, never immutable release images;
- collect console and launch evidence in a fresh run directory;
- promote `green` only after the smoke guest passes; and
- retire only the prior CI-owned QEMU identified by its recorded PID and run
  directory.

EC2 should implement those rules, not become a second collection of manual
launch commands.

## Portable QCOW2 artifact contract

Each installed-root release has these layers:

```text
immutable standalone base QCOW2, addressed by SHA-256
  -> disposable per-run QCOW2 overlay
     -> optional promoted standalone QCOW2
```

The standalone base:

- has no backing file;
- passes `qemu-img check`;
- records virtual size, actual size, format, compatibility level, cluster
  size, SHA-256, source snapshot/run, and creation tool version;
- is made read-only before publication; and
- is never attached writable to QEMU.

A run overlay:

- names one exact base SHA-256 in its run manifest;
- is the only writable installed-root object attached to that run;
- is disposable unless explicitly promoted; and
- must not be considered portable by pathname alone.  The receiver must have
  and verify the exact base content before using it.

An overlay may be transferred by itself only when the receiver has verified
the exact base hash.  Otherwise transfer a flattened standalone QCOW2.

## Promotion

Promotion is explicit.  Never rename an overlay into the release store.

1. Stop the candidate cleanly and prove that QEMU no longer has the overlay
   open.
2. Flatten the overlay and its exact base into a new standalone QCOW2 partial.
3. Confirm that the result has no backing file.
4. Run `qemu-img check` and record the complete image metadata.
5. Cold-boot a writable overlay of the flattened candidate through the normal
   acceptance gates.
6. Hash the standalone result, make it read-only, atomically rename it into a
   content-addressed release directory, and create `READY` last.
7. Update `current`; update `green` only after the smoke run passes.

This flatten-and-recheck step prevents a missing, stale, or silently rebased
backing file from becoming a release.

## Transport choices

Choose the transport independently from the artifact format.

### Shared QCOW2 base: transfer the overlay

This is the preferred cross-provider incremental path.  A small overlay is a
portable description of changed blocks as long as the manifest pins the exact
base hash and the receiver verifies it before launch.

Record wire bytes, elapsed time, and the before/after artifact hashes.  Do not
infer success from rsync exit status alone.

### Filesystem receiver: seeded sparse-aware rsync

When the destination is ext4 or ordinary EBS storage:

1. create a private partial from the nearest verified base;
2. update that partial with rolling checksums rather than modifying the
   immutable base;
3. preserve holes and compress the stream; and
4. validate, make read-only, then atomically promote.

The intended rsync properties are:

```text
--partial --sparse --no-whole-file --inplace --compress-choice=zstd
```

`--inplace` is allowed only against the private seeded partial.  It must never
target `current`, `green`, a read-only release, or a disk open by QEMU.  If a
remote rsync lacks `--compress-choice=zstd`, use ordinary `-z` and record the
negotiated command in the transfer evidence.

Sparse handling matters even for QCOW2.  During the first EC2 recovery, a
4,306,501,632-byte checkpoint had only about 1.5 GiB allocated.  Plain rsync
sent apparent zero regions at about 3.3 MiB/s.  Compressed sparse rsync raised
effective progress into roughly the 9--27 MiB/s range.  The exact numbers are
incident evidence, not a general benchmark.

### ZFS-capable caches: incremental send/receive

Use a project-specific dataset with stable image paths, immutable snapshots,
and an acknowledged common base.  `zfs send -i` can then move changed blocks,
preserve holes and compression, and resume an interrupted receive.

The receive side is cache-only.  QEMU uses a clone or QCOW2 overlay, never the
received canonical dataset directly.  Snapshot GUIDs and artifact hashes must
be recorded and verified before `READY` is published.  ZFS is an efficient
cache transport between capable hosts; consumers must still be able to use the
QCOW2 release without ZFS.

## Host roles

### Biggie

- canonical source/build and long-lived evidence host;
- creates and validates standalone bases;
- retains immutable snapshots and at least the last two acknowledged releases;
- publishes content-addressed bundles; and
- never exposes a live writable guest disk as a release source.

### Exabyt

- independent provider smoke/acceptance worker;
- Solaris/OpenIndiana archive-builder capacity where required;
- validates portability away from Biggie; and
- remains a useful slower or second-provider regression lane.

### EC2

- fast, disposable, single-lane acceptance worker;
- keeps QEMU, firmware, helpers, and recent immutable bases cached;
- creates a fresh overlay and run directory for every candidate;
- can keep the prior green guest available while a new candidate is staged,
  but should run only one CPU-bound Niagara guest at full speed on the current
  2-vCPU instance; and
- publishes evidence back to the controller before it is stopped or replaced.

The EC2 instance currently exposes 2 AMD EPYC 9R05 vCPUs, about 8 GiB RAM, and
NVMe-backed root storage.  That makes a faster single-vCPU TCG lane plausible,
but does not prove it.  Niagara boot is dominated by one TCG vCPU, so more host
vCPUs mainly enable orchestration or concurrency rather than accelerating one
guest.

## Required bundle manifest

Every runnable bundle must pin:

- build/release ID and creation UTC;
- source repository commits;
- exact QEMU SHA-256 and executable build ID;
- all firmware hashes;
- standalone base QCOW2 SHA-256 and image metadata;
- overlay base hash, if an overlay is transported;
- unit 100/101/103/104 roles, hashes, formats, virtual sizes, and read-only
  policy;
- literal expanded QEMU argv;
- expected direct boot command;
- expected acceptance milestones and budgets; and
- transport method, source/destination identities, wire bytes, elapsed time,
  and final verification results.

Launch admission fails closed if any declared artifact is missing, writable
when it should be immutable, has the wrong hash, has an unexpected backing
chain, or differs from the manifest's disk topology.

## Separate acceptance lanes

Do not treat an installer-media smoke boot as proof of an installed-root cold
boot.  Maintain at least two explicit lanes:

1. installer lane: OBP, kernel banner, required hSIMD units, recovery/tooling,
   channel, PPP/NFS, and bounded-I/O gates;
2. installed-root lane: direct unit-104 boot, root mount, expected SMF
   milestone, login/multi-user, and channel/network canaries.

The first EC2 incident passed some media/device observations but used a 15:11
installed-root checkpoint and a different QEMU binary than the later accepted
`@smf191` state.  A stale local manifest did not prevent launch.  The new
admission contract must make that combination impossible.

## Blue/green operation

`current` means the newest fully published artifact.  `green` means a release
whose fresh cold-boot run passed all gates.  They are deliberately different.

1. Resolve `current` once and pin the release directory.
2. Verify the entire manifest before creating run state.
3. Create a fresh run directory, sockets, logs, and QCOW2 overlay.
4. Launch with a persistent-shell-owned tmux session.
5. Classify semantic progress; repeated console output or high CPU alone is
   not progress.
6. On pass, atomically promote `green` and retain all evidence.
7. On failure, preserve the failed run and prior green; never probe a failed
   guest with improvised storage commands.

## EC2 versus Exabyt benchmark

Benchmark before assigning EC2 the primary fast lane.  Run at least three
cold-cache and three warm-cache boots on each worker with identical:

- QEMU and firmware hashes;
- standalone base and fresh overlay;
- `-smp 1`, guest memory, disk topology, and boot command;
- host-side classifier and milestone patterns; and
- no competing Niagara QEMU.

Record wall time and QEMU CPU seconds to:

- OpenBoot prompt;
- kernel banner;
- installed root mounted;
- target SMF milestone;
- login/multi-user prompt; and
- channel/network canaries.

Also record host CPU model/frequency, steal time, disk-read bytes, cache state,
and wire/staging time.  Promote EC2 to the fast lane only from these results,
not from instance naming or an interactive impression.

## Implementation order

1. Extend the release manifest to include the installed-root standalone QCOW2
   and complete backing-chain metadata.
2. Generalize the Exabyt publisher and smoke consumer into provider profiles;
   remove hard-coded hostnames, QEMU paths, and stale timeout messages.
3. Add a fail-closed EC2 admission/preflight command.
4. Implement base-cache lookup, overlay creation, flatten/promotion, and
   `READY`/`current`/`green` atomics.
5. Add seeded sparse-rsync and optional ZFS incremental transports with common
   evidence output.
6. Run the controlled EC2/Exabyt benchmark.
7. Only then enable automatic candidate dispatch and warm-spare maintenance.

