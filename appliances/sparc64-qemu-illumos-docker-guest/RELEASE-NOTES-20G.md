# 20 GiB OpenIndiana SPARC64 beta appliance

This bundle boots the accepted OpenIndiana Hipster 2025.12 sun4v guest on an
x86-64 Linux Docker host. It builds the pinned Niagara/hsimd QEMU fork locally,
verifies every runtime asset, and waits for a console login prompt.

Requirements: x86-64 Linux, Docker, about 25 GiB of free disk space after
extraction, and at least 6 GiB of available RAM. The root image is sparse;
extract it onto a filesystem and with tools that preserve sparse files.

```sh
./appliance build
./appliance verify20
./appliance smoke20
./appliance console
```

The smoke test boots `/virtual-devices@100/disk@5:a -k -v`. The root login used
by the automated inventory is `root` with password `root`. The normal user
`jack` is present; the development user `ryan` was removed before release.

The accepted root image is logically 20 GiB, occupied 2.91 GiB on the assembly
host, passed a complete ZFS scrub with zero errors, and has SHA-256:

```text
24306fcf52c9d05c6dd49115f5e2833a3b8563e59d88b923f7022a214308e722
```

Known constraint: the root is intentionally attached as Niagara unit105. Its
ZFS labels record that path. Moving it to unit104 makes pre-root ZFS discovery
fall back to a full disk scan, which currently triggers the known hsimd
large-I/O assertion. The experiment notebook contains the preserved failure
and successful acceptance evidence.
