# Tribblix installed-root and network bootstrap design

Status: designed from live audit; build not yet executed.

## Problem

The current Tribblix guest boots from a real persistent UFS root, but the root
was populated from the live boot archive and then augmented with selected
packages. It was not finalized as an installed Tribblix system.

Live evidence:

- `/` is UFS on `/devices/virtual-devices@100/disk@0:a` and has about 507 MiB
  free.
- `TRIBsys-install-media-internal` is still installed.
- `/etc/rc2.d/S99auto_install` still exists.
- only `core-tribblix` and `base-iso` are recorded as installed overlays;
  `base` is absent.
- `svc:/system/filesystem/usr:live-media` and
  `svc:/system/filesystem/root:media` are online.
- `/etc/svc/repository.db` is the 4,575,232-byte live repository, SHA-256
  `08b089c73a748b6816d6037eb6f5781742549b7cad0e6a15bdbad0f291055fc9`.
- `/usr/lib/zap/repository-installed.db.bz2` expands to a distinct
  3,551,232-byte installed repository, SHA-256
  `c0cc74a29fdfbefc522ba68b8ed93e6066f2dbb3a586c253912cc5f37bb441b9`.
- 48 of the 52 packages in `base.pkgs` are missing. Their `.zap` files total
  51,884,974 compressed bytes and are present in the embedded HSFS package
  repository.

This hybrid service repository may be the root cause of the current
`ifconfig`/`ipadm` failure. Native networking must therefore be retested only
after completing the install state.

## Decision

Finalize a disposable copy of the populated persistent UFS root offline. Do
not run `/root/ufs_install.sh` against the running `c1d0s0`: it begins by
running `newfs` on its target and would destroy the mounted root.

The offline finalizer will reproduce the material post-copy actions from the
audited installer while preserving the toolchain and channel work already in
the root:

1. install the missing `base` packages from the embedded M34 media in declared
   overlay order and record the `base` overlay;
2. install `TRIBsys-lib-c-runtime`, which was added after the original batch;
3. remove `TRIBsys-install-media-internal` with package accounting, not a blind
   path deletion;
4. remove `S99auto_install`;
5. replace `repository.db` with the installed-system seed while configd is not
   using it;
6. preserve the persistent-root `/etc/system` and `/etc/vfstab` changes;
7. put the known plain-ENOTTY `hsimd` at the sun4v path actually loaded by the
   kernel, `/platform/sun4v/kernel/drv/sparcv9/hsimd`;
8. install the channel tools under `/opt/niag/bin` and add a respawning channel
   0 login service;
9. regenerate the boot archive, unmount, run `fsck -F ufs -m`, and splice the
   closed root back into a new full disk image.

The immutable input is
`/export/solaris/tribblix-batch/tribblix-batch-final.iso` on `biggie`. The live
playbox image is not an input: its images filesystem has only about 378 MiB
free, so a write-heavy copy-on-write rebuild there risks host ENOSPC.

## Boot acceptance gates

The next image is accepted only if one normal boot proves all of the following:

1. `/` is the persistent UFS slice and the filesystem is clean.
2. `pkginfo -q TRIBsys-install-media-internal` fails.
3. `/var/sadm/overlays/installed/base` exists and all 52 `base.pkgs` packages are
   registered.
4. `S99auto_install` is absent.
5. `repository.db` initially matches the installed seed, then remains a valid
   writable SMF repository after boot.
6. the live-media filesystem service instances are absent, disabled, or not
   selected by the installed repository.
7. the first HSFS mount succeeds; a second-mount workaround is no longer
   required.
8. GCC compile/link/run still passes.
9. channel 0 produces a fresh login prompt and respawns after logout while
   channel 1 remains available for the BBS.
10. `ifconfig lo0`, `ipadm`, `dladm`, and the physical/network milestone are
    retested from this installed state before any native-network patches.

## Network sequence after acceptance

First recover a dependable management plane: channel 0 login, channel 1 BBS,
and separate channel transports for HTTP and NFSv4-over-TCP. Then test native
illumos IP management. If the installed repository repairs it, proceed with
the designed DLPI/VNIC Ethernet-over-channel relay. If it does not, debug the
installed system rather than the live-media hybrid.
