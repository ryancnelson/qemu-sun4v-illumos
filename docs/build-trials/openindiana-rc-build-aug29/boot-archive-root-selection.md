# Boot archive and UFS root selection

## Required boot sequence

The split layout requires this sequence:

```text
OpenBoot
  -> boot UFS disk and slice
  -> secondary booter
  -> kernel and boot_archive from the boot UFS filesystem
  -> boot_archive mounted as the temporary root
  -> hSIMD driver attaches the selected root disk
  -> kernel mounts the separate UFS root
  -> normal startup imports the separate ZFS pool
```

The OpenBoot command selects the filesystem used to load the secondary booter,
kernel, and archive. The selected real root is a separate decision made during
early kernel boot.

## Verified SPARC behavior

The prior Tribblix trial established that `/etc/system` is not sufficient for
this root selection path:

- `modsysfile.c:setparams()` ignores `MOD_ROOTDEV`;
- `swapgeneric.c:loadrootmodules()` clears the root filesystem name and type,
  then obtains both from standalone boot properties;
- the SPARC standalone exports `boot-path` from the PROM boot device and
  `fstype` from the filesystem that supplied the archive; and
- the tested SPARC booter does not support the suggested
  `-B rootdev=...` override.

An archive containing these lines therefore does not by itself redirect the
initial root mount:

```text
rootdev:/virtual-devices@100/disk@4:a
rootfs:ufs
```

The verified workaround patched the archive's
`kernel/misc/sparcv9/swapgeneric` module. Its private property readers returned
the required physical root path and `ufs` filesystem type. The existing
implementation and evidence are in:

```text
patches/swapgeneric-rootprops.s
patches/patch-swapgeneric-root.py
notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md
```

The OpenIndiana trial must verify the equivalent module and code path before
modifying it. A successful Tribblix patch is evidence for the method, not proof
that the OpenIndiana module has the same ELF layout or instruction ranges.

## NVRAM alternatives

Newer Oracle OpenBoot implementations define `os-root-device`, and OpenBoot's
`boot-file` variable can provide persistent arguments to the secondary booter.
Neither mechanism is accepted for this bundle until the QEMU firmware and the
selected OpenIndiana SPARC booter demonstrate it.

An arbitrary NVRAM variable has no effect unless the booter or kernel reads it.
The current persisted-NVRAM QEMU work preserves firmware state; it does not add
an OpenIndiana root-selection consumer.

## Fixed-width patching

The eight-slot mapping makes a fixed-width root-path substitution possible:

```text
/virtual-devices@100/disk@4:a
/virtual-devices@100/disk@6:d
```

Both paths have the same byte length. This can avoid changing the size or
layout of the patched file. The target is the verified root-path literal in the
decompressed boot archive's `swapgeneric` module, not an assumed `/etc/system`
line and not arbitrary bytes in the compressed outer archive.

A patcher must:

- identify the expected archive format and compression;
- verify the original module hash or audited ELF structure;
- require exactly one intended old path in the expected module;
- require equal-length replacement text;
- derive `disk@N` from the declared QEMU unit using `N = unit - 100`;
- validate the slice letter;
- preserve or correctly update the module's ELF relocations when required;
- reopen the archive and verify the new path and `ufs` marker; and
- leave the source artifact unchanged.

Blind whole-image search and replacement is not an accepted build method.

## Archive format and hash

`bootadm` can create cpio, HSFS, UFS, or UFS-with-compressed-files archives.
The archive may also have an outer gzip layer. The actual OpenIndiana artifact
must be inspected before choosing extraction and repackaging commands.

Some illumos loaders use a companion file:

```text
boot_archive
boot_archive.hash
```

Changing the archive without updating a loaded companion hash can fail with an
invalid-hash error. The first trial must determine:

- whether the SPARC media contains `boot_archive.hash`;
- whether this SPARC booter loads or validates it;
- the digest or signature format;
- whether an unkeyed digest can be regenerated; and
- whether the distribution's `bootadm` must produce it.

Disabling hash loading is a diagnostic control, not a release procedure.

## Offline modification workflow

The reproducible workflow is:

1. Copy the source disk image into a trial-specific work area.
2. Record the source image hash, size, format, and VTOC.
3. Attach the image read-only and identify the boot UFS slice.
4. Mount the boot slice read-only and inventory `boot_archive*`, kernel, and
   boot blocks.
5. Identify archive compression and filesystem format.
6. Extract or mount a disposable copy of the archive.
7. Inspect the OpenIndiana `swapgeneric` module and prove the root-selection
   code path.
8. Apply the audited root-path and filesystem patch.
9. Rebuild the archive in its original format.
10. Regenerate and verify any required companion hash.
11. Insert both files into a writable copy of the boot UFS disk.
12. Sync, unmount, detach, and run the applicable filesystem checks.
13. Reopen the completed disk read-only and verify every expected byte-level
    marker and hash.
14. Boot a disposable run copy and confirm the real UFS root path printed by
    the kernel.

Commands remain unspecified until the source disk and archive formats are
measured on `ec2trib`.
