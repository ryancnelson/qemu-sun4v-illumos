# OpenIndiana RC build Aug 29

Date: 2026-08-29

Status: design record for the first portable VM-bundle build trial.

## Product

The product is a portable, versioned OpenIndiana VM bundle for QEMU's Niagara
sun4v machine. The bundle owns the guest configuration, disk images, artifact
manifest, launch contract, and boot acceptance tests. It does not distribute or
build QEMU for every destination host. The initial GitHub repository description
called the target sun4u; the active `-M niagara` machine and hSIMD device model
are sun4v.

The initial bundle is assembled on `ec2trib`. A Tribblix host can work directly
with UFS filesystems and ZFS pools used by the guest. A completed bundle must be
usable on `teddeck` or `ec2cicd` with a compatible QEMU binary supplied on that
host.

The private product repository is:

```text
https://github.com/ryancnelson/openindiana-rc-build-aug29
```

These trial notes remain in the Niagara investigation repository while the
build method is being recovered and proved. Product-owned scripts and the
accepted bundle specification should move to the product repository once its
local working copy is established.

## Documents

- [Disk topology](disk-topology.md) records the historical single-disk layout,
  the current eight-disk hSIMD model, and the intended separation of roles.
- [Boot archive and UFS root selection](boot-archive-root-selection.md) records
  the verified SPARC root-selection behavior and the archive-editing work that
  remains.
- [QEMU source and CI boundary](qemu-source-and-ci.md) records which repository
  produces `qemu-system-sparc64` and how Biggie Woodpecker drives the build.
- [Build and acceptance contract](build-and-acceptance.md) defines the first
  reproducible assembly and boot trial.
- [Development notebook](development-notebook.md) records the 2026-08-29 design
  discussion, live QCOW2 chain inspection, and planned image round trip.

## Current decisions

- QEMU's eight hSIMD units are separate resources. A multi-purpose monolithic
  disk is no longer required.
- QEMU unit 100 is a 32 MiB RAM-backed disk used only by the
  guest-sockets-over-storage driver.
- Boot files and `boot_archive` will live on a persistent UFS disk.
- The real UFS root will live on another persistent disk.
- A third persistent disk will hold a ZFS pool.
- The exact QEMU units for boot UFS, root UFS, and the ZFS disk remain to be
  assigned by the bundle manifest.
- The boot archive must contain the hSIMD driver and registration data for the
  selected root disk.
- Root selection must follow the already verified `swapgeneric` behavior. It
  must not rely on an unverified `/etc/system` `rootdev:` override.
- Archive modification must account for compression, filesystem format, and
  any companion `boot_archive.hash` used by the selected image and loader.

## Related evidence

- [`notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md`](../../../notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md)
  documents the verified `swapgeneric` patch used to select a UFS root while
  loading the archive from HSFS.
- [`notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md`](../../../notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md)
  documents units 100 through 107, their OpenBoot paths, and the current unit-100
  activation requirement.
- [`notes/BIGGIE-TERM4CODE-02-PREPARATION.md`](../../../notes/BIGGIE-TERM4CODE-02-PREPARATION.md)
  documents an OpenIndiana archive rebuilt with hSIMD registration for unit
  104 and a successful installed-root handoff.
- [`notes/PORTABLE-QCOW2-CI-CD-CONVEYOR.md`](../../../notes/PORTABLE-QCOW2-CI-CD-CONVEYOR.md)
  contains the existing artifact, promotion, and cross-host transport rules.
