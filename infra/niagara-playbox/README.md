# Niagara playbox build host

`niagara-playbox` is the native arm64 build host used by Woodpecker. Its root
filesystem is intentionally small. Docker data and Woodpecker build state must
live on `/mnt/disk-images`, the separate XFS filesystem.

The installed Docker daemon uses the checked-in `docker-daemon.json` as
`/etc/docker/daemon.json`. Its data root is `/mnt/disk-images/docker`.
`/var/lib/docker` is also a symlink to that directory so a future daemon start
without the override cannot silently return large state to the root LV.
Docker 29 also uses containerd's image store, independently of Docker's
`data-root`; the checked-in `containerd-config.toml` therefore places that
store at `/mnt/disk-images/containerd`. Both settings are required before
pulling the 1.3 GiB appliance layer.

Woodpecker connects as `root` over Tailscale to `100.112.174.2`. The local
Woodpecker runner does not inherit Biggie's Tailscale DNS resolver, so CI uses
the stable tailnet address explicitly.

The host-side OpenSPARC firmware rebuild requires Ubuntu's `flex` package in
addition to the already installed compiler, patch, tar, and Docker tools. QEMU
itself is compiled inside the pinned Ubuntu Docker build stage, natively on
arm64.
