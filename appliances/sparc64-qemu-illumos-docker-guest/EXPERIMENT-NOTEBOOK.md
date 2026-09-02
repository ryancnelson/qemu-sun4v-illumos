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

## EXP-20260901-10: ARM64 staging transfer and persistent XFS cache

Woodpecker pipeline 34 transferred the 1.3 GiB self-contained release archive
directly from biggie to `niagara-playbox` and verified the received bytes as:

```text
fc3b734a110ce4534d3a5f5d61033d91977b3adb21041eb446bd7af58227443c  sparc64-qemu-openindiana-20g-beta-20260901.tar.zst
```

The stage then failed before compilation because it entered `$WORK/release`
and requested `RELEASE-ARCHIVE.SHA256SUMS`, while the repository tree copy had
placed that manifest at `$WORK`. The pipeline now copies the manifest into the
directory where it is consumed. The verified archive is retained in
`/mnt/disk-images/woodpecker/cache` on the XFS volume, checked by SHA-256 on
each run, and reflink-copied into the numbered workspace. A cache miss still
uses biggie's pinned-image extraction and direct host-to-host transfer path.

Pipeline 35 proved that cache and manifest staging passed, then stopped before
compilation with exit 126 because `appliance` is intentionally stored as mode
0644 and the ARM64 workflow invoked it directly. The workflow now invokes both
shell entry points explicitly with `bash` in build, test, and release stages;
it no longer assumes executable permission survives repository checkout or
cross-host staging.

Pipeline 36 then built the native ARM64 patched QEMU successfully, reported
QEMU 10.2.0, found the Niagara machine, and passed all four static appliance
policies. Packaging stopped at a second direct `./appliance self-build` call
inside `ci-self-contained-oci.sh`. Every internal invocation in that CI driver
now uses `bash appliance`, covering build, stop, smoke, network, inspection,
and inventory without changing the repository's established mode 0644 file.

## EXP-20260901-10: native arm64 builder storage preflight

`niagara-playbox`, an Ubuntu 24.04 arm64 VM on teddeck, is reachable directly
from the Biggie Woodpecker runner as root at tailnet address `100.112.174.2`.
It has six CPUs, 5.8 GiB RAM, Docker 29.1.3, and a separate XFS filesystem at
`/mnt/disk-images`. The root LV has less than 1 GiB free and is not a valid
container build workspace.

Setting Docker's `data-root` to `/mnt/disk-images/docker` was necessary but not
sufficient. Docker 29 reports the `io.containerd.snapshotter.v1` driver and
continued downloading image layers into `/var/lib/containerd`; pipeline 31
filled the root LV while pulling the pinned amd64 appliance. The run was
canceled before compilation. The orphaned remote pull was terminated by exact
PID, containerd was stopped, and its 1.1 GiB partial store was moved intact to
`/mnt/disk-images/containerd`. The checked-in Docker and containerd configs now
place both stores on XFS. `/var/lib/docker` points to the XFS Docker directory;
the prior 184 KiB inactive metadata directory is retained at
`/mnt/disk-images/docker-root-before-symlink-20260901` for recovery.

The arm64 workflow stages the 40 MiB pinned QEMU source and small firmware from
ec2cicd. Relaying the 1.3 GiB bundle over SFTP was measured and rejected: the
Biggie relay reached about 63 MiB and the direct 169 ms ec2cicd path about 19
MiB before their superseded runs were canceled. Instead, the arm64 host pulls
the immutable proven amd64 OCI tag from GHCR and extracts the
architecture-neutral `beta.tar.zst` layer locally. It then compiles QEMU
natively and boot-tests the assembled arm64 image before any multi-architecture
tag promotion.

The same inspection confirmed a separate x86 release defect: the host-side
PPP/BBS supervisor exists, but `/root/jack/BRING_UP_NETWORKING.sh` and
`CALL_BBS.sh` were never installed in the embedded guest. CI currently types
their component commands over the console. `P0-OCI-GUEST-NETWORK-UX` records
the requirement to install and test those exact user-facing scripts.

## EXP-20260901-10: automatic boot path and pipeline 26 falsification

The published NVRAM reports `boot-device=vdisk`, `boot-file` empty, and
`auto-boot?=false`. Its aliases do not identify the accepted root: `disk`
points at `/pci@7c0/scsi@1/disk@0`, while `vdisk` points at
`/virtual-devices/disk@0`. `show-devs` proves that QEMU unit105 is presented
to this firmware as `/virtual-devices@100/disk@5`; a manual boot of
`disk@105` fails, while the established successful command is:

```text
boot /virtual-devices@100/disk@5:a -k -v
```

Interactive `setenv` changes the live values but prints `Unable to update LDOM
Variable`; the 8192-byte NVRAM file remains at its original SHA-256
`e1cf2fe5626d9c69b1ef62f90ab035f5f5761b7f7e62c6de744782ac6aebe47a`.
Pipeline 26 then tested QEMU's documented generic `-prom-env` interface. Image
assembly and the interactive-console test passed, but the untouched cold boot
still stopped at `ok` after 55 seconds. The passive gate printed
`APPLIANCE_AUTO_BOOT=FAIL` and correctly skipped GHCR publication. This proves
that Niagara/OpenBoot ignores those generic environment overrides.

Two fresh-QEMU attempts to edit the hashed NVRAM record stream were rejected:
OpenBoot still reported `vdisk` and `false`. The authoritative OpenSPARC OBP
source then explained the result. Niagara's `loadconfig.fth` runs `pdnvupdate`
at stand-init and copies matching properties from the Machine Description's
`variables` node into the options dictionary. The shipped `2c8t_guest.desc`
contains exactly `boot-device = "vdisk"` and `auto-boot? = "false"`, so those
platform-description values supersede the token-store experiment.

QEMU source inspection independently confirmed that `-M
niagara,nvram-file=PATH` maps the requested 8192-byte file directly with
`RAM_SHARED` and skips the firmware-directory `nvram1` loader. The container
flag was therefore correct; the selected policy source was wrong.

The established x86 mdgen path regenerated the accepted `2c8t_guest.pp.bak`
byte-identically as SHA-256
`b5d160f6f55a30d2ed56b5e24f9b1158180bb6a84d71fe222b4476945bd5b823`.
Woodpecker now requires that baseline round trip before deriving a Machine
Description with the disk@5 boot path, `-k -v`, and automatic boot. The
untouched cold-boot gate remains passive and fails if a user-visible `ok`
prompt ever requires manual input.

The derived MD is deterministic at SHA-256
`561859faa18066b8e9b5c408eb7cd7a5f2576d3208c4cfb3c07d77dcf468167c`.
A firmware-only cold QEMU with no disks immediately printed:

```text
Boot device: /virtual-devices@100/disk@5:a  File and args: -k -v
Bad magic number in disk label
ERROR: boot-read fail
```

The deliberate failure is the expected bounded result with no attached disk;
it proves the fresh firmware consumed all three MD policy values and attempted
automatic boot without console input. Full acceptance still belongs to the
Woodpecker login gate with the actual unit105 root attached.

## EXP-20260901-11: pipeline 27 automatic-boot release acceptance

Woodpecker pipeline 27 tested commit
`932bd15d8ea23db8f37f40f897004fb0e6591082` and passed in 8 minutes 11
seconds. The assembly gate rebuilt Sun's mdgen on x86-64, reproduced the
accepted MD baseline byte-for-byte, and emitted:

```text
MD_BASELINE_ROUNDTRIP=PASS
MD_POLICY_EDIT=PASS boot_device=/virtual-devices@100/disk@5:a boot_file=-k,-v auto_boot=true
MD_RELEASE_BUILD=PASS sha256=561859faa18066b8e9b5c408eb7cd7a5f2576d3208c4cfb3c07d77dcf468167c bytes=10139
```

The foreground interactive-console test passed with the explicit manual MD.
The release cold boot received no OpenBoot command and printed:

```text
Boot device: /virtual-devices@100/disk@5:a  File and args: -k -v
hsimd5 is /virtual-devices@100/disk@5
root on distpool/ROOT/openindiana fstype zfs
oi-basecamp console login:
APPLIANCE_AUTO_BOOT=PASS
APPLIANCE_LOGIN_SMOKE=PASS
```

The same image then passed the Sunset BBS exchange, bidirectional PPP, guest
NAT, DNS, HTTP CONNECT proxy, ZFS inventory, no-bind-mount assertion, and
forbidden boot-signature check. `distpool` was ONLINE with zero read, write,
or checksum errors. The gate ended with:

```text
OCI_GUEST_PPP_NAT=PASS host=10.0.5.1 guest=10.0.5.15
OCI_GUEST_SERVICES=PASS dns=10.0.5.1:53 http_proxy=http://10.0.5.1:8888
OCI_BOOT_FAILURE_SIGNATURES=ABSENT
OCI_COLD_BOOT_TEST=PASS
```

Woodpecker published and anonymously verified:

```text
ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:20260901.1-932bd15d8ea2
ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest
digest sha256:bbd96fae308098ded8260506e92e98863c78d6884780bd459142f9ac326c0f5d
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
the declared configuration but not public ingress. A scoped `tailscaled`
restart was also required; afterward the same mapping and the loopback relay
were both reverified. GitHub webhook status, not a manual release bypass, is
the first diagnostic when a pushed commit produces no Woodpecker run.

The same supervisor provides two guest-only rescue services on the PPP endpoint:
a DNS forwarder on `10.0.5.1:53` and an HTTP/HTTPS CONNECT proxy on
`10.0.5.1:8888`. The proxy ACL admits only `10.0.5.15`; neither service binds to
the container's Docker-facing address. `/state/network/status.env` distinguishes
`waiting_for_ppp`, `ready`, and `stopped`, while the OCI health check verifies
that the supervisor remains alive even while it is waiting for the guest.

## EXP-20260901-07: channel launch/readiness race in pipeline 21

Woodpecker pipeline 21 booted commit `220611ce47ae0666fa67ff53c1e429bbe28f1ff4`
to `oi-basecamp console login:`, logged in as root, and printed
`GUEST_CHANNELS_STARTED`. Its immediately following BBS probe failed with
`connect(5, AF=1 "/tmp/niag1", 12): No such file or directory`. The retained
console transcript establishes the ordering: both `guest-chand` processes were
backgrounded, the command-completion marker was printed, and only during the
next command did `hsimd0` attach unit100. The host supervisor had already
printed `NETWORK_HELPERS=PASS ... phase=waiting-for-guest`.

Root cause: the gate treated successful background process creation as channel
socket readiness. That is invalid because opening unit100 can trigger a slow
hsimd attach. The guest launch command now removes stale sockets and logs,
starts both daemons, and waits for both `/tmp/niag0` and `/tmp/niag1` to become
Unix sockets, bounded at 60 seconds. Timeout prints
`GUEST_CHANNELS_NOT_READY` plus both exact daemon logs and fails the gate;
success prints `GUEST_CHANNELS_READY`. The static network policy test requires
both the readiness marker and failure diagnostics.

The push carrying that fix initially produced no Woodpecker pipeline. At that
time biggie still reported the intended Funnel mapping and the local relay port
was accepting connections. A separate request to the public Funnel root then
returned HTTP 404, proving public transport to the relay was available again;
the subsequent notebook push is the deliberate push-event release retrigger.

## EXP-20260901-08: persistent BBS modem timeout in pipeline 22

Pipeline 22 proved the channel-readiness correction: unit100 attached at about
361 seconds, both sockets appeared, and the guest printed
`GUEST_CHANNELS_READY`. The following dial reached an open guest socket but did
not receive `CONNECT 2400`. Retained host evidence showed channel 1 repeatedly
cycling through `client connected` and `client gone`; `bbs.log` likewise showed
three separate `bbs: attached to channel` events during the cold boot.

`host-bbs.py` imposed a 120-second timeout while waiting for the first `ATD`.
That is appropriate for the standalone listening/test mode, but not for channel
mode: unit100 represents a persistent virtual serial cable and this emulated
SPARC guest takes roughly six minutes to reach its first dial. The third
120-second timeout therefore coincided with the first guest call and discarded
it during reconnect. Channel mode now constructs its `Session` with
`modem_timeout=None`; standalone listener mode retains the bounded default. A
unit test proves that the persistent session passes `None` to its modem read.

Pipeline 23 falsified the timeout as the cause of the missing response. It
retained one BBS attachment and one channel-1 client for the entire boot, then
again reached `GUEST_CHANNELS_READY`, but the dial produced no output and no
`CONNECT 2400`. The no-timeout behavior remains correct for a persistent cable,
but it is not the transport repair. The next diagnostic gate prints each guest
daemon's startup line (including its actual raw device and base block), captures
the unfiltered BBS bytes, and enables host bridge `CHAN_TRACE` so each outbound
or inbound sequence transition is visible. No further transport change is made
until that boundary evidence identifies which side failed to publish a frame.

Pipeline 24 supplied the decisive placement evidence. The guest binaries
reported:

```text
guest-chand: ch0 ... dev /dev/rdsk/c1d0s2 base blk 640
guest-chand: ch1 ... dev /dev/rdsk/c1d0s2 base blk 2688
```

The container had inherited Basecamp R0's older host offset `520093696`, equal
to block `1015808`, while this OpenIndiana disk and guest binary use whole-disk
block `640`. The correct host placement is therefore `640 * 512 = 327680`;
channel 1 follows at block `640 + 2048 = 2688`, exactly matching the guest.
The container default and static policy test now use `327680`. This changes
placement only; the shared framing constants remain canonical in `chan.h`.

## EXP-20260901-09: pipeline 25 full release acceptance

Woodpecker pipeline 25 tested commit
`7226255e1a06a3dec2ed86fcf382a5432df939ed` and passed in 8 minutes 19
seconds. The exact self-contained image passed foreground interactive-console
startup, cold boot to `oi-basecamp console login:`, unit100 channel readiness,
the Sunset BBS `CONNECT 2400` exchange, PPP in both directions, guest outbound
NAT to `8.8.8.8`, DNS through `10.0.5.1:53`, and HTTP CONNECT through
`10.0.5.1:8888`. The gate printed:

```text
OCI_GUEST_PPP_NAT=PASS host=10.0.5.1 guest=10.0.5.15
OCI_GUEST_SERVICES=PASS dns=10.0.5.1:53 http_proxy=http://10.0.5.1:8888
OCI_NO_BIND_MOUNTS=PASS
OCI_BOOT_FAILURE_SIGNATURES=ABSENT
OCI_COLD_BOOT_TEST=PASS
```

The guest inventory reported `distpool` ONLINE with zero read, write, or
checksum errors, a 19.5 GiB pool with 17.1 GiB free, user `jack` present, and
user `ryan` absent. Woodpecker published and anonymously verified:

```text
ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:20260901.1-7226255e1a06
ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest
digest sha256:1957edc7706966dcc68b66801623408aeffbe875bc5a9c3208b7214b6077a165
OCI_ANONYMOUS_MANIFEST=PASS
```
