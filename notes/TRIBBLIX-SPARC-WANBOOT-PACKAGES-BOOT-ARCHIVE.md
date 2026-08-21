# Tribblix SPARC: WAN boot, packages, and boot archives

Source material:

- [Installing Tribblix on SPARC](https://www.tribblix.org/install-sparc.html)
- [Tribblix overlays](https://www.tribblix.org/overlays.html)
- [ZAP package administration](https://www.tribblix.org/zap.html)

This is an operational summary of upstream Tribblix documentation, plus notes on
how it applies to the QEMU Niagara work. Commands in the upstream sections have
not necessarily been verified on our virtual machine yet.

## WAN boot

OpenBoot firmware does not provide DNS resolution. Resolve
`pkgs.tribblix.org` elsewhere and pass its numeric address as `server-ip`.

Current OpenBoot implementations can accept all network arguments on the boot
command line:

```text
boot net:host-ip=<guest-ip>,router-ip=<gateway>,subnet-mask=<mask>,hostname=tribblix.local,file=http://<server-ip>/m34.sparc/boot_archive
```

The two-step form is:

```text
setenv network-boot-arguments host-ip=<guest-ip>,router-ip=<gateway>,subnet-mask=<mask>,hostname=tribblix.local,file=http://<server-ip>/m34.sparc/boot_archive
boot net
```

TFTP is also supported by changing the file URL to, for example:

```text
file=tftp://<server-ip>/boot_archive
```

The exact release path changes with the Tribblix milestone; `m34.sparc` is the
example for Milestone 34.

### Why this matters here

WAN boot could eventually remove the ISO/VTOC/boot-alias part of our iteration
loop: publish a newly remastered `boot_archive`, reset QEMU, and boot it directly.
That depends on QEMU's Niagara firmware and emulated network path supporting the
required OpenBoot network operations; we have not demonstrated that yet.

A simpler near-term variant is to host the archive locally, avoiding public DNS
and reducing network variables. Even before WAN boot works, the documented URL
confirms that the SPARC `boot_archive` is a standalone release artifact.

## Extracting the SPARC boot archive from an ISO

Tribblix recommends the `iso-read` program from `TRIBlibcdio`:

```sh
iso-read -e platform/sun4v/boot_archive \
    -o boot_archive tribblix-sparc-0m34.iso
```

Tribblix uses one boot archive for both sun4u and sun4v; the sun4u path on the
media is a symbolic link. For Niagara, extract `platform/sun4v/boot_archive`.

This is cleaner and less error-prone than manually calculating ISO extents. Our
existing extent-level tools remain useful when putting a modified archive back
without rebuilding the whole hybrid image.

## Packages and overlays

Tribblix packages are SVR4 packages in filesystem format, distributed as zip
archives. ZAP is the normal interface and overlays are preferred because they
carry the intended package sets and dependency ordering.

Useful commands:

```sh
zap list-overlays
zap describe-overlay develop
zap install-overlay develop
zap refresh
zap verify-overlay develop
zap update-overlay develop
```

Relevant locations:

- `/var/zap/cache` — downloaded package cache; it can be copied between systems.
- `/var/sadm/overlays` — installed overlay metadata.
- `/etc/zap` — ZAP configuration, including repository definitions under
  `/etc/zap/repositories`.

Relevant overlays include:

- `develop` — development tools and the likely shortest route to self-hosted
  driver/tool work.
- `illumos-build`, `clang`, and `autotools` — more specialized build stacks.
- `networked-system` — network-facing system utilities/services.
- `kitchen-sink` — broad package set when memory and disk space are not tight.

The SPARC installer can request overlays during installation, for example:

```sh
./live_install.sh -G c1t0d0 develop
./live_install.sh -G c1t0d0 kitchen-sink
```

The documented whole-disk forms are `-G` and `-B`, with `-G` preferred. To use
an existing slice instead:

```sh
./live_install.sh -p c1t0d0s0
```

Tribblix warns that systems with less than 1 GiB of memory should install the
base system first and add overlays afterward. Our current 1 GiB QEMU guest is
close enough to that boundary that a base disk-root boot followed by `develop`
is the conservative sequence.

### Practical bootstrap paths for this project

Once persistent UFS root is read/write, we can avoid making guest networking the
first blocker in several ways:

1. Put the `develop` packages on installation media or another readable UFS
   image and install the overlay locally.
2. Preseed `/var/zap/cache` from a donor Tribblix system, host-side extraction,
   NFS, or the exchange channel, then run ZAP in the guest.
3. Build a disk image on another illumos/Tribblix system and attach the populated
   filesystem to Niagara.

This follows the same accelerator ladder that worked for Solaris 10: persistent
storage first, then a native compiler, then fast host communication and NFS.

## Live-media credentials

The documented SPARC live-media login is `jack` / `jack`; the root password is
`tribblix`.

## Current experiment connection

On 2026-08-20 our hybrid M34 image successfully loaded the ISO boot archive from
the `disk:d` alias while selecting hsimd slice 0 as UFS root with `boot -a` and:

```text
/virtual-devices@100/disk@0:a
```

The kernel mounted that root and imported all 95 SMF manifests, but the boot
subsequently reported that the root was still read-only. Establishing a reliable
read/write remount is therefore the immediate blocker before ZAP state, SMF
repository state, packages, and installed overlays can persist across boots.
