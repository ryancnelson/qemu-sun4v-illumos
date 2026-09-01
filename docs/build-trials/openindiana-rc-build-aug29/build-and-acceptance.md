# Build and acceptance contract

## First trial objective

Assemble a portable OpenIndiana bundle on `ec2trib` with:

- a 32 MiB RAM-backed unit-100 channel disk created at launch;
- a persistent UFS boot disk containing the boot block, kernel, and modified
  `boot_archive`;
- a separate persistent UFS root disk;
- a separate persistent ZFS disk;
- a literal QEMU launch description; and
- enough evidence to reproduce the boot on another host.

The first trial ends at a verified login or maintenance prompt with the intended
UFS device mounted as `/` and the separate ZFS disk visible. Pool creation or
import is a later gate unless the selected source artifacts already define it.

## Test-first implementation

Before modifying an archive, tests must fail for the unmodified input and pass
for the intended output:

- QEMU unit-to-firmware-slot mapping covers units 100 through 107.
- Unit 100 is exactly 32 MiB, RAM-backed, and assigned only to the channel
  transport.
- The boot, UFS root, and ZFS roles use distinct declared units.
- The source archive format and compression are recognized.
- The expected OpenIndiana `swapgeneric` module matches an accepted hash or
  audited structure.
- The old root path occurs exactly once in the expected module.
- The replacement path has the same length and names the declared root unit and
  slice.
- Any companion archive hash matches the rebuilt archive.
- Reopening the completed boot disk yields the expected module, root path,
  filesystem marker, and file hashes.
- No output disk has an undeclared backing file.

## Input qualification checklist

No boot or root disk is admitted by filename or recollection alone. Inspection
must answer and record:

- Which QEMU unit, Sun VTOC slice, filesystem type, and path contain the
  `boot_archive`?
- What exact root device path and root filesystem type does that archive ask
  the kernel to mount?
- Does the archive contain the current hSIMD driver, and does its recorded
  identity correspond to the implementation that exposes eight disks?
- Does the archive contain `/usr/bin/awk` and every other executable, library,
  device node, configuration file, and script needed before the real root is
  mounted?
- Does the effective `/etc/system` contain the temporary hSIMD safety bound
  `set zfs:zfs_vdev_aggregation_limit=0x20000`? The authoritative root
  filesystem copy must contain it too, so a later boot-archive rebuild does not
  remove the protection.
- What is the root disk's logical size?
- What Sun VTOC does the root disk contain, including geometry, tags, flags,
  starts, and lengths for every slice?
- What does `fstyp` report for the declared root slice?
- Can the root filesystem be checked and mounted read-only with native
  Tribblix tools?

The boot archive's origin is part of its identity. Record the source product,
release, architecture, source-media hash, source path, extraction or copy
procedure, local modifications, output hash, and the root disk it is expected
to mount.

The same provenance requirements apply to every root filesystem and installer
medium. A matching product label is insufficient; the manifest must identify
how the exact bytes were produced.

## Launch admission

A run is rejected before QEMU starts if:

- any persistent disk is missing or has the wrong hash;
- two roles claim the same unit;
- unit 100 is absent or is backed by a persistent product disk;
- a firmware slot does not match `unit - 100`;
- the root path embedded in the archive disagrees with the manifest;
- the boot archive and its companion hash disagree;
- the effective `/etc/system` or the root filesystem's authoritative copy
  lacks `set zfs:zfs_vdev_aggregation_limit=0x20000` while the current hSIMD
  driver still asserts on requests larger than 128 KiB;
- the QEMU binary lacks the required hSIMD and NVRAM capabilities; or
- a release image would be opened writable instead of through declared run
  state.

## Boot acceptance

The first accepted boot records:

- expanded QEMU command line and process identity;
- QEMU source commit, executable SHA-256, and build ID;
- firmware and NVRAM hashes;
- disk image hashes, sizes, formats, units, and slices;
- exact OpenBoot boot command;
- successful loading of the kernel and `boot_archive` from the boot UFS disk;
- attachment of the intended hSIMD root unit;
- the kernel's printed root device and `fstype ufs`;
- mounted `/` device as reported inside the guest;
- visibility of the separate ZFS disk without destructive pool operations; and
- console transcript and elapsed time for each milestone.

Acceptance must distinguish OpenBoot visibility from an operational backing
disk. `show-devs` lists firmware-described slots even when a slot has no image.
A successful label, filesystem, or bounded read proves that a selected slot is
backed.

## Artifact manifest

The bundle manifest pins:

- build-trial ID and creation time;
- source repositories and commits;
- QEMU capability set and executable identity;
- firmware and persistent-NVRAM identity;
- every disk role, unit, firmware path, image hash, format, and size;
- VTOC and slice assignments;
- boot-archive source, format, compression, patch inputs, and output hash;
- boot-archive inventory, including hSIMD identity and early-userland tool and
  library closure;
- companion hash method and value when present;
- exact root path and filesystem type;
- root-disk source, logical size, complete VTOC, root slice, and `fstyp`
  result;
- expanded QEMU arguments;
- expected boot milestones and time budgets; and
- the evidence directory produced by the run.

Generated images and run evidence remain outside Git. The repository contains
the manifest, assembly code, patch inputs, tests, and hashes needed to recreate
them.
