# SPARC64 QEMU OpenIndiana Docker guest

This project packages the login-proven Niagara QEMU shape as an x86-64 Linux
container appliance. It builds the Niagara-capable QEMU fork from a source
archive of pinned ec2trib commit
`049affb20df67162cf58deeaf74d5ad4b83cbdc3` and attaches the accepted objects
without changing their roles:

- unit100: a per-run RAM-backed raw channel carrier;
- unit103: read-only installer/boot media;
- unit105: the cleaned writable 20 GiB OpenIndiana ZFS root;
- firmware and NVRAM copied from the accepted ec2trib run.

The appliance supplies these OpenBoot environment overrides on every start:

```text
boot-device=/virtual-devices@100/disk@5:a
boot-file=-k -v
auto-boot?=true
```

The Niagara firmware cannot persist `setenv` through its unavailable LDOM
variable service, so QEMU's `-prom-env` interface applies the settings after
loading the accepted NVRAM image.

## Use the self-contained image on an x86-64 Docker host

The public image contains the pinned QEMU runtime and a compressed copy of the
accepted assets. A Docker volume receives a sparse writable root on first
start; no asset bind mount or preexisting volume is required.

For a human first boot, allocate a terminal. The entrypoint detects it and
connects that terminal directly to the guest serial console:

```sh
docker run --rm -it \
  --name openindiana-sparc64 \
  --hostname oi-basecamp \
  --memory 6g \
  --cpus 2 \
  --cap-add NET_ADMIN \
  --device /dev/ppp \
  --sysctl net.ipv4.ip_forward=1 \
  --tmpfs /run/unit100:rw,size=1200m,mode=0700 \
  --mount type=volume,src=openindiana-sparc64,dst=/var/lib/illumos-appliance \
  ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest
```

The first run verifies and materializes the embedded sparse disk into the
named volume, then automatically boots unit105 as OpenBoot `disk@5`. No
OpenBoot command should be required.

Use Docker's `Ctrl-P Ctrl-Q` sequence to detach without stopping the guest,
and reconnect with:

```sh
docker attach openindiana-sparc64
```

For automation or a background guest, omit `-it` (or set
`CONSOLE_MODE=socket`) and attach through the container-owned Unix socket:

```sh
docker run -d \
  --name openindiana-sparc64 \
  --hostname oi-basecamp \
  --memory 6g \
  --cpus 2 \
  --cap-add NET_ADMIN \
  --device /dev/ppp \
  --sysctl net.ipv4.ip_forward=1 \
  --tmpfs /run/unit100:rw,size=1200m,mode=0700 \
  --mount type=volume,src=openindiana-sparc64,dst=/var/lib/illumos-appliance \
  -e CONSOLE_MODE=socket \
  ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest

docker exec -it openindiana-sparc64 \
  socat -,rawer,escape=0x1d UNIX-CONNECT:/state/console.sock
```

Press `Ctrl-]` to detach the socket console client. The named volume preserves
the writable guest across replacement containers; remove it explicitly with
`docker volume rm openindiana-sparc64` only when that state is disposable.

The three networking options grant only the running container what it needs to
create its PPP peer and forward the guest's `10.0.5.15/32` traffic. The
entrypoint starts channel 0 for PPP, channel 1 for the local BBS, and adds only
three address- and interface-scoped firewall rules inside the container's own
network namespace. It never flushes the Docker host's firewall. To run without
these helpers, omit those three options and add `-e NIAGARA_NETWORK=off`.

After the guest reaches a root prompt, bring up its side of the link with:

```sh
/usr/sbin/devfsadm -i sppp -i sppptun
NIAG_CHAN_DEV=/dev/rdsk/c1d0s2; export NIAG_CHAN_DEV
nohup /opt/niag/bin/guest-chand 0 /tmp/niag0 </dev/null >/tmp/niag-chand0.log 2>&1 &
nohup /opt/niag/bin/guest-chand 1 /tmp/niag1 </dev/null >/tmp/niag-chand1.log 2>&1 &
nohup /usr/bin/perl /opt/niag/bin/guest-ppp-chan.pl 0 10.0.5.15:10.0.5.1 </dev/null >/tmp/gppp0.log 2>&1 &
```

The accepted addresses are guest `10.0.5.15` and container `10.0.5.1`; the
guest PPP wrapper installs its default route. Woodpecker proves both directions
of the PPP link and an outbound guest ping before publishing the image. The
container also exposes a DNS forwarder at `10.0.5.1:53` and an HTTP/HTTPS
CONNECT proxy at `http://10.0.5.1:8888`. Both bind only to the PPP endpoint; the
proxy accepts only `10.0.5.15`. Set the guest resolver to `nameserver 10.0.5.1`,
and set `http_proxy`/`https_proxy` when a tool should use the explicit proxy
instead of NAT. Runtime state is recorded in `/state/network/status.env`, and
Docker's health check verifies that the network supervisor remains alive.
The release gate performs a DNS lookup and HTTPS CONNECT handshake from inside
OpenIndiana.

To call the container-local BBS after starting channel 1, run this in the guest
and type `ATDT18005551212`:

```sh
/opt/niag/bin/socat - UNIX-CONNECT:/tmp/niag1
```

Unit100 is intentionally RAM-backed and uses QEMU `cache=writeback`. Using
`cache=none` would request `O_DIRECT`, which is unsupported by tmpfs on some
Linux kernels. The persistent unit103 and unit105 disks retain `cache=none`.

## 20 GiB beta candidate

The accepted small candidate uses only the carrier, installer, firmware,
NVRAM, and `root-unit105-20g.raw`; the 60 GiB source root is not required.

```sh
./appliance build
./appliance verify20
./appliance smoke20
```

The root image is 20 GiB logically and 2.91 GiB allocated on the assembly
host. Preserve sparse files when copying or extracting it. Its accepted digest
is recorded in `assets.release.SHA256SUMS`.

The root disk is intentionally writable and therefore becomes run state. The
held, immutable clean source remains on ec2trib.

## Maintainer workflow

The tracked text inputs live here; large verified assets remain in the
ec2cicd assembly workbench. Pushes to `codex/self-contained-oci` select the
Woodpecker workflow that stages these inputs, builds the OCI image, performs a
fresh-volume boot/login test with zero bind mounts, and only then publishes a
commit-qualified tag plus `latest` to GHCR. Interactive host sessions must not
publish replacement images.
