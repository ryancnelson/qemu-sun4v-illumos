# Niagara playbox build host

`niagara-playbox` is the native arm64 build host used by Woodpecker. Its root
filesystem is intentionally small. Docker data and Woodpecker build state must
live on `/mnt/disk-images`, the separate XFS filesystem.

The installed Docker daemon uses the checked-in `docker-daemon.json` as
`/etc/docker/daemon.json`. Its data root is `/mnt/disk-images/docker`.

Woodpecker connects as `root` over Tailscale to `100.112.174.2`. The local
Woodpecker runner does not inherit Biggie's Tailscale DNS resolver, so CI uses
the stable tailnet address explicitly.

The host-side OpenSPARC firmware rebuild requires Ubuntu's `flex` package in
addition to the already installed compiler, patch, tar, and Docker tools. QEMU
itself is compiled inside the pinned Ubuntu Docker build stage, natively on
arm64.
