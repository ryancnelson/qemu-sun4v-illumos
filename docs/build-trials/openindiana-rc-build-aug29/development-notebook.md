# Development notebook

## 2026-08-29: bundle storage and boot design

### Product boundary

`openindiana-rc-build-aug29` will produce a portable, versioned OpenIndiana VM
bundle. The bundle contains guest configuration, disk artifacts, manifests,
assembly tools, and boot tests. Destination hosts such as `teddeck` and
`ec2cicd` may supply their own compatible QEMU binaries.

The QEMU binary is produced separately from `ryancnelson/qemu`, branch
`niagara-persistent-nvram`. The observed branch contains Masayuki Murayama's
sun4v and hSIMD work, Ryan's persistent Niagara NVRAM change, and Ryan's SPARC
TTE range-flush change. The current native `ec2trib` checkout also contains the
unpublished illumos-host portability commit `9573242`.

Biggie Woodpecker is the CI controller. QEMU builds may run on `ec2trib` over
SSH. The OpenIndiana bundle pipeline is separate from the Solaris 9 sun4m
workflow currently stored in `ryancnelson/tribblix-woodpecker`.

### Historical disk100

The original hSIMD driver exposed one disk. Historical `disk100` images used
VTOC slices to combine several roles:

- installation HSFS images;
- UFS filesystems;
- a PCFS file-transfer slice;
- channels-for-sockets guest-driver payloads;
- recovery and development material; and
- sometimes ZFS pool vdevs.

That layout was required by the one-disk implementation. It is source material
for recovery, not the intended bundle layout.

### Current eight-disk model

Masa's hSIMD implementation exposes QEMU drive units 100 through 107. The
firmware and kernel paths use child slots 0 through 7:

| QEMU unit | Firmware path |
| ---: | --- |
| 100 | `/virtual-devices@100/disk@0` |
| 101 | `/virtual-devices@100/disk@1` |
| 102 | `/virtual-devices@100/disk@2` |
| 103 | `/virtual-devices@100/disk@3` |
| 104 | `/virtual-devices@100/disk@4` |
| 105 | `/virtual-devices@100/disk@5` |
| 106 | `/virtual-devices@100/disk@6` |
| 107 | `/virtual-devices@100/disk@7` |

The intended bundle separates these persistent roles:

- one UFS disk containing the boot block, secondary booter, kernel, and
  `boot_archive`;
- one UFS disk containing the real root filesystem; and
- one disk containing a guest ZFS pool.

Unit 100 is reserved for the guest-sockets-over-storage transport. Its intended
form is a 32 MiB RAM-backed disk with no filesystem or product-storage role.
The current QEMU backend also uses unit 100, or unit 102 as a fallback, to
activate its scan of all eight hSIMD slots.

Exact units for boot UFS, root UFS, and ZFS remain manifest decisions.

### OpenBoot and real-root selection

The required boot sequence is:

```text
OpenBoot selects the boot UFS disk and slice
  -> secondary booter loads the kernel and boot_archive
  -> kernel mounts boot_archive as its temporary root
  -> hSIMD attaches the separate root disk
  -> kernel mounts the declared UFS slice as /
  -> normal startup imports the separate ZFS pool
```

The verified Tribblix behavior rules out a simple `/etc/system` edit as the
normal root selector on this SPARC path:

- `modsysfile.c:setparams()` ignores `MOD_ROOTDEV`;
- `swapgeneric.c:loadrootmodules()` obtains the root path and filesystem type
  from standalone boot properties; and
- the tested SPARC booter does not support `-B rootdev=...`.

The earlier successful implementation patched
`kernel/misc/sparcv9/swapgeneric` so its private property readers returned the
real UFS root path and `ufs`. The OpenIndiana module must be inspected and
accepted independently before applying an equivalent patch.

The eight-slot paths allow equal-length substitutions such as:

```text
/virtual-devices@100/disk@4:a
/virtual-devices@100/disk@6:d
```

The patch target is the audited path literal in the decompressed
`swapgeneric` module. It is not `disk@104`, an arbitrary whole-image string, or
an assumed `/etc/system` line.

Newer OpenBoot implementations define `os-root-device`, and `boot-file` can
carry persistent arguments. Neither mechanism is accepted until the selected
QEMU firmware and OpenIndiana booter demonstrate it. Persistent QEMU NVRAM
preserves variables; it does not make OpenIndiana consume a new variable.

### Boot-archive modification

The build pipeline must determine the actual archive format before editing.
Possible formats include cpio, HSFS, UFS, UFS with compressed files, and an
outer gzip layer.

Some illumos loaders use a companion `boot_archive.hash`. Changing the archive
without updating a loaded hash can cause an invalid-hash failure. The SPARC
trial must record whether the file exists, whether the booter loads it, and
whether it is an unkeyed digest or a signature. Disabling hash loading is only
a diagnostic control.

The current candidate's reported origin is the OpenIndiana SPARC installation
ISO. The ISO files were copied onto hSIMD `disk@4`. That history is a lead for
inspection, not accepted provenance yet. The trial must identify the exact ISO
and its hash, map `disk@4` to its QEMU unit, find the slice and filesystem that
hold the copied files and `boot_archive`, and record any changes made after the
copy.

A boot archive is qualified together with the root filesystem it requests.
Inspection must establish:

- the boot disk unit, VTOC slice, filesystem type, and archive path;
- the real-root device path and filesystem type requested by the archive;
- the hSIMD driver identity and whether it exposes all eight disks;
- the presence of `/usr/bin/awk`; and
- the full set of commands, libraries, configuration files, and device support
  required before the real root is mounted.

Until hSIMD accepts or segments strategy requests larger than 128 KiB, the
effective `/etc/system` must contain:

```text
set zfs:zfs_vdev_aggregation_limit=0x20000
```

The root filesystem's authoritative `/etc/system` must contain the same line.
Any boot archive built from that root must be reopened to prove that the
effective copy retains it. This is a temporary panic guard, not the driver
fix.

The root disk inspection must record its logical size, complete Sun VTOC,
declared root slice, and the `fstyp` result for that slice. Successful
read-only `fsck` and mount checks on Tribblix are separate evidence.

Future bundle trials may select different, internally consistent source sets:

- a Tribblix boot archive with a Tribblix root filesystem;
- an Oracle Solaris 11.4 boot archive with a prepared Solaris 11.4 root disk;
  or
- an Oracle Solaris 11.4 boot archive and HSFS installer medium, plus a
  separate installation target disk.

Each source set gets its own manifest and acceptance evidence. Boot archives,
root disks, and installer media are not interchangeable merely because they
boot on SPARC.

The accepted editing path will:

1. preserve the source disk;
2. work on a private materialized disk;
3. identify and extract the boot slice;
4. extract or mount the boot archive;
5. validate the OpenIndiana `swapgeneric` input;
6. apply the audited root-path patch;
7. rebuild the original archive format;
8. regenerate any required companion hash;
9. replace the archive in the private boot disk; and
10. reopen and verify the result before booting it.

### Live run disk inventory

The running trial inspected on 2026-08-29 is:

```text
/tink/runs/oi-basecamp-20260829T005549Z-91568
```

Its run-local disk directory contains:

```text
carrier-unit100.qcow2  file size 196,624 bytes
root-unit104.qcow2     file size 197,568 bytes
```

Tribblix `file` reports these as `data`, but both begin with QCOW2 magic
`51 46 49 fb` (`QFI` followed by `0xfb`) and declare QCOW2 version 3.

`qemu-img info --force-share --backing-chain --output=json` reported the
following unit-100 chain:

```text
/tink/runs/oi-basecamp-20260829T005549Z-91568/disks/carrier-unit100.qcow2
  qcow2, 64 KiB clusters, virtual size 1 GiB
  -> /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img
     raw, virtual size 1 GiB, actual allocation 657,920 bytes
```

The top carrier overlay had an actual allocation of 264,704 bytes. This run
therefore advertises a 1 GiB unit-100 disk. That conflicts with the intended
32 MiB RAM-backed design. The discrepancy must be resolved before its topology
is used as a bundle manifest. The 32 MiB value may describe the active channel
region, or this run may predate the smaller carrier.

The unit-104 chain is:

```text
/tink/runs/oi-basecamp-20260829T005549Z-91568/disks/root-unit104.qcow2
  qcow2, 64 KiB clusters, virtual size 60 GiB
  -> /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/root-unit104.qcow2
     qcow2, 64 KiB clusters, virtual size 60 GiB
     actual allocation 629,942,784 bytes
     -> /tink/disk-images/runs/workstation-playbox-known-good-20260827T165948Z/images/known-good-state.qcow2
        qcow2, 2 MiB clusters, virtual size 60 GiB
        actual allocation 32,790,016 bytes
        -> /mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
           raw, virtual size 60 GiB
           actual allocation 5,224,185,344 bytes
```

The run-local root overlay had an actual allocation of 264,704 bytes. QEMU
resolves each virtual sector from the first layer that allocates it. The merged
60 GiB block-device view contains the Sun disklabel and its filesystems. A
complete Sun disk image is not stored inside the 197 KiB top file.

Absolute backing paths make this chain unsuitable as a portable artifact.
Copying either run-local overlay without its complete chain does not copy the
disk.

### QCOW2 and Tribblix tooling boundary

`/usr/bin/qemu-img` is installed on `ec2trib`. `guestfish` and
`virt-filesystems` are not installed there.

QEMU's block layer is responsible for QCOW2 metadata and backing-chain
resolution. Tribblix native tools are responsible for the Sun VTOC and guest
storage formats:

```text
qemu-img
  -> inspect and materialize the merged virtual block device

lofiadm, prtvtoc, mount, fsck, bootadm, and zpool
  -> inspect and modify the Sun disk and its slices
```

Libguestfs can open QCOW2 and may enumerate a Sun disklabel on a Linux worker.
Its Linux appliance is not the filesystem authority for illumos UFS or ZFS.
The first native pipeline does not require libguestfs.

The relevant illumos facility is lofi through `lofiadm`. lofs is the loopback
filesystem used to mount one directory tree at another location.

### Editable raw baseline

The first editable bundle artifact should be a standalone sparse raw disk
materialized from the complete unit-104 chain. The original chain remains
unchanged.

Do not convert while QEMU is writing to the chain. Stop the guest and QEMU
cleanly, or use an independently frozen source. `--force-share` is acceptable
for metadata inspection and can return inconsistent information during writes;
it is not an acceptance mechanism for conversion.

The planned conversion is:

```sh
qemu-img convert -p \
  -f qcow2 \
  -O raw \
  -S 4k \
  root-unit104.qcow2 \
  root-unit104.work.raw.partial
```

After conversion, the pipeline will verify the resolved source and raw output,
rename the partial within the trial filesystem, inspect the SPARC VTOC with
`tools/vtoc.py`, attach it with `lofiadm` where useful, and inspect every slice
read-only. The working raw disk will remain sparse on ZFS. Copy and transport
operations must preserve holes.

`prtvtoc` on the x86 Tribblix host is not authoritative for a big-endian SPARC
disk label. It can report a host-side or synthesized partition map that bears
no resemblance to the valid VTOC8 stored in sector zero. The bundle pipeline
must parse and validate the on-disk SPARC label directly: magic `0xDABE`, XOR
checksum zero, big-endian geometry, and all eight partition-map entries.

### 2026-08-29 interactive unit-104 inspection

Before disk inspection, the source dataset was protected by:

```text
tink@oi-rc-aug29-pre-disk104-inspect
```

The stopped run's complete unit-104 chain was flattened to the sparse raw
working image:

```text
/tink/builds/openindiana-rc-build-aug29/interactive/raw/root-unit104.work.raw
```

`qemu-img compare` reported `Images are identical` for the resolved QCOW2
source and the raw result. The raw image is 60 GiB logical and approximately
5.5 GiB allocated. The source QCOW2 chain remains unchanged.

An initial host `prtvtoc` probe incorrectly appeared to show only slices 2 and
8. That result led briefly to the false hypothesis that slice 0 had been lost.
The same host probe also claimed that immutable unit 103 had only slices 2 and
8, even though that exact image had previously booted through slice 3. Unit
103's SHA-256 still matched its recorded identity exactly:

```text
e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c
```

The project big-endian parser, `tools/vtoc.py show`, recovered the actual
labels. Unit 103 has valid magic and checksum; slices 0, 1, and 3 through 6
alias its 1,257,600-sector boot region, slice 2 covers 5,452,544 sectors, and
slice 7 is the appended 4,194,304-sector region.

Flattened unit 104 also has valid magic and checksum:

```text
geometry: 7831 data cylinders, 2 alternate cylinders,
          255 heads, 63 sectors/track, 16065 sectors/cylinder
s0: start cylinder 1, start sector 16065, 125788950 sectors
s2: start cylinder 0, start sector 0, 125829120 sectors
```

`qemu-img map` showed that guest sector zero is inherited unchanged from depth
3, the raw base image. Bytes at the historical slice-0 start contain repeated
big-endian ZFS uberblock magic. Therefore the observed OpenBoot failure:

```text
lz4 write outside buffer
Can't mount root
The file just loaded does not appear to be executable.
```

is not explained by a missing or invalid VTOC slice. Investigation must move
to the boot blocks, boot archive, and differences between the successfully
booted artifact and the current resolved unit-104 contents. Host `prtvtoc`
output must not be used to repair this image.

### Niagara-playbox donor set copied to ec2trib

The inputs from this historical niagara-playbox command were copied without
starting QEMU:

```text
sudo /home/niagara/niag-proj/qemu/build/qemu-system-sparc64 \
  -M niagara \
  -L /home/niagara/sun4v/firmware/base-1gib \
  -m 1024 \
  -nographic \
  -monitor unix:/tmp/oi-donor-monitor.sock,server,nowait \
  -drive if=pflash,file=/home/niagara/sun4v/images/primary-oi-donor.img,format=raw
```

The verified ec2trib destination is:

```text
/tink/builds/openindiana-rc-build-aug29/interactive/source/niagara-playbox/
  qemu-system-sparc64
  base-1gib/
  primary-oi-donor.img
```

The source image is 2,684,354,560 bytes. Direct playbox-to-ec2trib SSH was not
authorized. The final image transfer therefore used the established Biggie
Woodpecker route: the forwarded operator key authenticated Biggie to
`niagara@niagara-playbox`, while the running Woodpecker agent's mounted SSH
configuration authenticated its inner connection to `ec2trib`. Biggie
streamed the source into a new `.partial` directory on ec2trib. No existing
artifact was overwritten. After independent source and destination hashes
matched, the directory was renamed atomically to `niagara-playbox`.

The primary identities are:

| Artifact | SHA-256 |
| --- | --- |
| `qemu-system-sparc64` | `bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b` |
| `primary-oi-donor.img` | `711619f87b3e2b72e01ffba4954173a509fa556ab98a300c77e72d910c3826d2` |

All twelve firmware files were also hashed independently at both endpoints:

| Firmware file | SHA-256 |
| --- | --- |
| `1g2p-hv.bin` | `3b09a5d17bc829e62e881e9b2bce0dcc33482faf81e23c947c1b2048665f7b50` |
| `1g2p-md.bin` | `97a131f8871c646399ded72417663cc0fca1a3e6a7534a74ac9fa94a48945bdf` |
| `1g32p-hv.bin` | `eaf7acf4e2f92406bf44c86dbec546b9d81897c73107a3e2c014aed18a707000` |
| `1g32p-md.bin` | `2d605310aa831dfe4b44a93d47efa4cb69e661d520ddac64241fc16dc0b264cd` |
| `1up-hv.bin` | `a22506c1ef124e56d20138b52c96360d43dc14ce6096b8ac29bdc3b161c8cc69` |
| `1up-md.bin` | `479377deeca024bf975ba05e676d01536130c83ef8d27207f0198e3db6285ba7` |
| `netcons` | `21118a9088ccc8298133e799331c37e598e221b35b28eaf5ac37889325b126b0` |
| `nvram1` | `6a86841db2b662b5a40dbfe13fc88f334be647984a24cb6a979e9c7717512cf2` |
| `openboot.bin` | `d88c7556b767936c34ad3a4df5774575fc26aa076574deb705c3b9891b1f03b8` |
| `q.bin` | `c32afe0ba5ebc29dd83466226456249b37c1a091d7d4b8a45ac9b039c13cc84b` |
| `q.bin.orig` | `c32afe0ba5ebc29dd83466226456249b37c1a091d7d4b8a45ac9b039c13cc84b` |
| `reset.bin` | `942b5c5b83feb55b6e25c491f570a91c62351abf6c325c5b11e79075e320d7fb` |

The initial modifier will preserve the whole-disk label and boot blocks by
changing contents inside the existing slices. Reconstructing the VTOC is not
part of the first trial.

### Standalone QCOW2 publication

After native modifications:

1. unmount all mounted filesystems;
2. export every imported ZFS pool cleanly;
3. detach the lofi device;
4. confirm that no process has the raw disk open; and
5. convert the raw disk into a new standalone QCOW2 partial.

The planned conversion is:

```sh
qemu-img convert -p \
  -f raw \
  -O qcow2 \
  -o compat=1.1,cluster_size=65536,lazy_refcounts=off \
  -S 4k \
  root-unit104.work.raw \
  root-unit104.release.qcow2.partial
```

Acceptance requires:

```sh
qemu-img check -f qcow2 root-unit104.release.qcow2.partial

qemu-img compare -p \
  -f raw \
  -F qcow2 \
  root-unit104.work.raw \
  root-unit104.release.qcow2.partial

qemu-img info --backing-chain --output=json \
  root-unit104.release.qcow2.partial
```

`qemu-img compare` verifies logical block content across formats. The accepted
`info` output must contain no backing filename. The pipeline then hashes the
QCOW2 file, renames it into the immutable release store, and makes it read-only.

Each boot test uses a fresh writable overlay:

```sh
qemu-img create \
  -f qcow2 \
  -F qcow2 \
  -b /absolute/path/root-unit104.release.qcow2 \
  root-unit104.test-run.qcow2
```

QEMU opens the test overlay writable. The standalone release remains
unchanged. If guest changes are promoted, the stopped test overlay's merged
view is converted into another standalone candidate. The pipeline does not
commit test writes into an immutable release.

### Tooling commands

The build repository should provide commands with these responsibilities:

```text
disk inspect          report the complete image chain and source identities
disk materialize      produce a verified sparse raw working disk
disk list-slices      save and normalize the Sun VTOC
disk extract-slice    copy one declared slice without changing the disk
disk mount-slice      attach a declared slice using native read-only defaults
disk patch-boot       rebuild boot_archive and any required hash
disk verify           check labels, filesystems, paths, hashes, and manifests
disk package          produce a standalone immutable QCOW2
disk test-overlay     create disposable per-run writable state
```

All commands operate on a trial manifest. They fail if a backing file is
missing, a chain changes during inspection, a role claims the wrong unit, a
root path disagrees with the manifest, or an output retains an undeclared
backing file.

### Sources and prior evidence

- [QEMU disk image utility](https://www.qemu.org/docs/master/tools/qemu-img.html)
- [OpenIndiana invalid boot-archive hash report](https://openindiana.org/pipermail/openindiana-discuss/2025-August/027582.html)
- [`notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md`](../../../notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md)
- [`notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md`](../../../notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md)
- [`notes/BIGGIE-TERM4CODE-02-PREPARATION.md`](../../../notes/BIGGIE-TERM4CODE-02-PREPARATION.md)
- [`notes/PORTABLE-QCOW2-CI-CD-CONVEYOR.md`](../../../notes/PORTABLE-QCOW2-CI-CD-CONVEYOR.md)
