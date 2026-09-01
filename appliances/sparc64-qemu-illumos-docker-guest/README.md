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

The OpenBoot command remains:

```text
boot /virtual-devices@100/disk@5:a -k -v
```

## Use the self-contained image on an x86-64 Docker host

The public image contains the pinned QEMU runtime and a compressed copy of the
accepted assets. A new anonymous Docker volume receives a sparse writable root
on first start; no asset bind mount or preexisting volume is required.

```sh
docker run -d \
  --name openindiana-sparc64 \
  --hostname oi-basecamp \
  --memory 6g \
  --cpus 2 \
  --tmpfs /run/unit100:rw,size=1200m,mode=0700 \
  ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest
```

Connect to OpenBoot through the container-owned Unix socket:

```sh
docker exec -it openindiana-sparc64 \
  socat -,rawer,escape=0x1d UNIX-CONNECT:/state/console.sock
```

At the `ok` prompt, boot the accepted unit105 identity:

```text
boot /virtual-devices@100/disk@5:a -k -v
```

Press `Ctrl-]` to detach the console client. Removing the container with
`docker rm -v` also removes its writable anonymous root volume.

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
