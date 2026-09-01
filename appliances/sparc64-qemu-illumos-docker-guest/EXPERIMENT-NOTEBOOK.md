# Appliance experiment notebook

## EXP-20260901-01: reproduce the cleaned 60 GiB guest in Docker

Host: `ec2cicd`, Ubuntu 24.04, x86-64, two vCPUs, 7.6 GiB RAM.

The image was built from an archive of the exact clean ec2trib QEMU checkout at
commit `049affb20df67162cf58deeaf74d5ad4b83cbdc3`. The build compiled
`hw/sparc64/niagara.c` and rejected the result unless `-machine help`
advertised `niagara`.

The held cleaned root, unit100 carrier, unit103 installer, firmware, and NVRAM
were transferred from ec2trib with sparse extents preserved. The complete
destination set passed `assets.SHA256SUMS`.

Command:

```sh
cd ~/devel/sparc64-qemu-illumos-docker-guest
./appliance smoke
```

Observed gates:

```text
Sun Fire T200, No Keyboard
OpenBoot 4.x.build_122***PROTOTYPE BUILD***
APPLIANCE_OPENBOOT_COMMAND_SENT=PASS
OpenIndiana Hipster 2025.12 Version illumos-31d3d510d0 64-bit
hsimd4 is /virtual-devices@100/disk@4
root on rpool/ROOT/openindiana fstype zfs
oi-basecamp console login:
APPLIANCE_LOGIN_SMOKE=PASS
```

Result: **PASS**. The Docker appliance running on Linux x86-64 reproduced the
accepted ec2trib boot through a real login prompt. Evidence is in
`state/smoke-console.log`, `state/smoke-login.out`, and `state/console.log`.

## Next experiment: migrate to a 20 GiB distribution root

The 60 GiB raw file consumes only about 5.5 GiB on a sparse-aware filesystem,
but its logical size is inconvenient for distribution and unsafe around tools
that inflate holes. ZFS cannot shrink its existing vdev. The next experiment
will attach a new sparse 20 GiB raw disk, create and populate a new pool from
inside the big-endian SPARC guest, install SPARC ZFS boot blocks, and accept the
new image only after independently booting it to the same login prompt.

The first rebuild after adding the 20 GiB disk exposed a packaging hazard:
without `.dockerignore`, Docker's legacy builder staged the nominal sparse disk
files as build context and temporarily drove the host filesystem to 99% use.
The build was interrupted before QEMU launch, its temporary allocation was
released, and `.dockerignore` now excludes `assets/` and `state/`. Disk images
must remain bind-mounted runtime data, never Docker build context.

## EXP-20260901-02: assemble a 20 GiB big-endian distribution root

A blank sparse 20 GiB raw image was attached as Niagara `unit105` while the
accepted 60 GiB image remained the running root on `unit104`. Inside the SPARC
guest, `devfsadm -v` created `c1d5` nodes and reported the expected hsimd size
of `0x500000000` bytes.

The disk was labeled and partitioned with native illumos tools. Slice 0 begins
at sector 16065 and spans 41881455 sectors; slice 2 describes the whole
41897520-sector accessible disk. The exact pool creation command was:

```sh
zpool create -f -d -o ashift=9 -R /mnt/distpool \
    distpool /dev/dsk/c1d5s0
```

`-d` deliberately disables optional ZFS feature flags because OpenBoot's ZFS
reader is known to be fragile. The source boot environment was copied entirely
inside the big-endian SPARC guest:

```sh
zfs create -o mountpoint=legacy distpool/ROOT
zfs snapshot -r rpool/ROOT/openindiana@distribution-20g
zfs send -R rpool/ROOT/openindiana@distribution-20g | \
    zfs receive -u distpool/ROOT/openindiana
zfs create distpool/export
zfs create distpool/export/home
zfs create -V 1G -b 8K -o refreservation=1G distpool/swap
zfs create -V 1G -b 128K -o refreservation=1G distpool/dump
zpool set bootfs=distpool/ROOT/openindiana distpool
```

The resulting pool was online with no errors, used 4.35 GiB, and retained
14.5 GiB available. Its copied root used 2.35 GiB and `var` used 128 MiB.
The copied `/etc/vfstab` swap reference was changed from `rpool` to `distpool`.
The boot archive and SPARC ZFS boot blocks were then installed with:

```sh
bootadm update-archive -R /mnt/distpool
installboot -F zfs /platform/sun4v/lib/fs/zfs/bootblk /dev/rdsk/c1d5s0
```

Both commands completed successfully. The target datasets were unmounted and
`zpool export distpool` completed before the guest performed a clean shutdown.
The first independence test attached this image as `unit104`, omitted the
60 GiB source, and successfully loaded OpenBoot, the kernel, and hsimd. During
pre-root discovery it printed `NOTICE: Performing full ZFS device scan!` and
panicked in `hsimd_diskio()` on the driver's `sz <= 128*1024` assertion. The
complete evidence was preserved as `state/smoke20-panic-console.log` and
`state/smoke20-panic-login.out`.

Native `zdb -l` proved why this differs from the accepted 60 GiB image:

```text
source: path=/dev/dsk/c1d4s0 phys_path=/virtual-devices@100/disk@4:a
target: path=/dev/dsk/c1d5s0 phys_path=/virtual-devices@100/disk@5:a
```

The pool was assembled while the target was `unit105`; moving it to unit104
made the boot-time ZFS lookup fall back to a full device scan, which exercised
the driver's known large-I/O failure. A generated `/etc/zfs/zpool.cache` was
also inspected, but SPARC `bootadm list-archive` showed that this file is not
part of the 64-entry kernel boot archive, so cache editing is not the fix for
pre-root discovery.

The next safe acceptance test therefore preserves the target's truthful ZFS
label identity: attach the 20 GiB root alone as `unit105`, omit the 60 GiB
source entirely, and boot `disk@5:a`. Restoring the conventional unit104 role
requires assembling the pool at unit104 (or fixing hsimd's large-I/O path); it
is not a reason to mutate a viable release candidate's labels.

## EXP-20260901-03: standalone 20 GiB acceptance

The appliance attached `root-unit105-20g.raw` as unit105, did not attach the
60 GiB source root, and submitted:

```text
boot /virtual-devices@100/disk@5:a -k -v
```

Observed gates:

```text
hsimd5: hsimd_attach: size:0x500000000, cap:0x5
hsimd5 is /virtual-devices@100/disk@5
root on distpool/ROOT/openindiana fstype zfs
oi-basecamp console login:
APPLIANCE_LOGIN_SMOKE=PASS
```

Result: **PASS**. There was no full ZFS device scan and no hsimd panic. The
running inventory proved OpenIndiana `illumos-31d3d510d0` on sun4v, an ONLINE
single-vdev `distpool` with zero errors, 14.3 GiB available to the root, user
`jack` present, and user `ryan` absent.

The temporary recursive `@distribution-20g` migration snapshot was removed.
A complete ZFS scrub then finished in 57 seconds, repaired 0 bytes, and found
0 errors. The guest shut down cleanly and returned to OpenBoot before QEMU was
stopped. Final host-side identity:

```text
apparent size: 21474836480 bytes (20 GiB)
allocated size: 2.91 GiB (6104536 512-byte blocks)
sha256: 24306fcf52c9d05c6dd49115f5e2833a3b8563e59d88b923f7022a214308e722
```

This is the accepted small distribution candidate. Its unit105 identity is a
current hsimd/ZFS boot constraint, not an arbitrary appliance preference.

## EXP-20260901-04: beta bundle and extraction verification

The beta staging tree contains no 60 GiB root image. GNU tar sparse-file
encoding plus zstd level 10 produced:

```text
release/sparc64-qemu-openindiana-20g-beta-20260901.tar.zst
size: 1.3 GiB
sha256: fc3b734a110ce4534d3a5f5d61033d91977b3adb21041eb446bd7af58227443c
```

A clean directory extraction reproduced the root image with the exact original
20 GiB apparent size and 6104536 allocated 512-byte blocks. Running
`./appliance verify20` inside that extracted copy passed all five assets. The
disposable extraction was then removed; the archive, staging hardlinks, and
evidence remain on ec2cicd.

## EXP-20260901-05: hp2 tmpfs portability regression and CI correction

The first public `latest` image verified every embedded asset on `hp2`, then
QEMU exited before OpenBoot:

```text
carrier-unit100.raw: filesystem does not support O_DIRECT
```

The published entrypoint attached RAM-backed unit100 with `cache=none`. QEMU
implements that setting with `O_DIRECT`, which is unsupported by tmpfs on
hp2's Linux kernel. This is the same failure already diagnosed and fixed in
the Tribblix login launcher; the container packaging failed to carry the known
rule forward.

The correction is intentionally limited to unit100:

```text
unit100  tmpfs-backed carrier  cache=writeback
unit103  persistent read-only  cache=none
unit105  persistent ZFS root   cache=none
```

`scripts/test-drive-cache-policy.py` enforces that split. Ryan required that
no replacement be assembled, tested, or released by an interactive host
session. The repository Woodpecker workflow now defines the delivery path:
static policy check, stage to the existing ec2cicd workbench, OCI assembly,
fresh anonymous-volume cold boot/login and inventory, then GHCR publication.
The release step receives `ghcr_token` as a Woodpecker secret, passes it to
ec2cicd only over SSH standard input, and logs Docker out even if publication
fails.

## EXP-20260901-06: Woodpecker cold-booted and released the corrected image

Branch `codex/self-contained-oci` was pushed to the private GitHub repository
and exercised through Woodpecker repository 2. The early pipeline iterations
made the local-runner assumptions explicit:

- pipeline 10: rejected the container-style `image: python:3.12-slim` because
  this installation's local backend treats `image` as an executable;
- pipeline 11: proved the local runner has Bash but no Python, so the Python
  policy test remains on the authoritative `ec2cicd` build host;
- pipeline 12: could not resolve the `ec2cicd` MagicDNS name;
- pipeline 13: reached `root@100.71.153.107`, copied the staging tree, and
  exposed a premature runner-side expansion of `$HOME`;
- pipeline 14, commit `58020851d59bab884e6658d575c741be0364b492`:
  **PASS**.

Pipeline 14 used the explicit tailnet endpoint and the remote workbench
`/root/devel/sparc64-qemu-illumos-docker-guest`. Its measured stages were:

```text
static-appliance-policy       PASS  00:00
stage-appliance-on-ec2cicd    PASS  00:06
assemble-self-contained-image PASS  00:23
cold-boot-login-test          PASS  06:09
release-ghcr                  PASS  00:04
pipeline total                PASS  06:45
```

The live boot record showed OpenBoot receiving
`boot /virtual-devices@100/disk@5:a -k -v`, hsimd attaching unit105, and ZFS
selecting `distpool/ROOT/openindiana`. The test then reached the login prompt,
ran the guest inventory, verified exactly one anonymous Docker volume and no
bind mounts, and found none of the known panic, full-device-scan, or
`NIAGARA_DEVFSADM_RW_GATE_FAIL` signatures.

Woodpecker published both names below and then verified `latest` through an
anonymous Docker configuration:

```text
ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:20260901.1-58020851d59b
ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest
registry digest: sha256:cf908d12c8ecb963aaff90d727d9caba1ed9e2fb377f75af4870c9dbc17ddab7
OCI_ANONYMOUS_MANIFEST=PASS
```

## First-boot console UX follow-up

The tested release currently starts detached and exposes the guest console on
`/state/console.sock`; a human uses `docker exec -it ... socat` to attach.
The intended beta-user path is also a single foreground `docker run --rm -it`
command. Add an entrypoint console mode that connects QEMU's guest-console
character device directly to container stdin/stdout for that case, while
retaining socket mode for Woodpecker, the MCP console, and channel helpers.
Docker's normal `Ctrl-P Ctrl-Q` sequence should detach the interactive client.

## Release networking follow-up

The appliance release must include the host side of the already-proven shared
disk channel system, not merely QEMU and the three disk objects. The container
owns channel 0's Linux PPP peer and channel 1's local BBS. Its Linux network
namespace performs source NAT only for guest address `10.0.5.15/32`; no helper
may flush or replace the Docker host's firewall rules.

The release gate is intentionally end to end: boot the exact self-contained
image, start the OpenIndiana `guest-chand` instances on unit100
`/dev/rdsk/c1d0s2`, start `guest-ppp-chan.pl` with symmetric `asyncmap 0`, prove
the Linux `ppp0` peer, ping in both directions, and finally ping an external IP
from the guest through container NAT. A successful build must print
`OCI_GUEST_PPP_NAT=PASS` before GHCR publication.

CI appliance volumes use explicit pipeline-qualified names and the label
`io.niagara.appliance-ci=1`. Normal teardown deletes both container and volume;
the next build also removes any dangling volume with that project-specific
label. This is required because a superseded remote Woodpecker step can kill
the SSH parent before its local `finally` cleanup completes, leaving a sparse
root volume behind until the build host fills.

Woodpecker deliberately rejects a manual run of this release workflow because
the GHCR secret is authorized only for push events. Do not weaken that policy.
On 2026-09-01 two GitHub push deliveries failed with HTTP 502 while biggie's
local webhook relay remained healthy on `127.0.0.1:8112`. Reapplying the
existing Tailscale Funnel mapping (`8443` to that same loopback target) restored
the authorized push path. GitHub webhook status, not a manual release bypass,
is the first diagnostic when a pushed commit produces no Woodpecker run.

The same supervisor provides two guest-only rescue services on the PPP endpoint:
a DNS forwarder on `10.0.5.1:53` and an HTTP/HTTPS CONNECT proxy on
`10.0.5.1:8888`. The proxy ACL admits only `10.0.5.15`; neither service binds to
the container's Docker-facing address. `/state/network/status.env` distinguishes
`waiting_for_ppp`, `ready`, and `stopped`, while the OCI health check verifies
that the supervisor remains alive even while it is waiting for the guest.
