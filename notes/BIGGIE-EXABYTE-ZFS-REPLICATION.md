# Biggie to Exabyt ZFS artifact replication

Status: proposed; do not provision or migrate the current artifact cache yet.

## Why this is worth doing

Biggie already stores the working tree under the ZFS dataset `datapool/home`,
while Exabyt's `/var/lib/niagara-ci` is currently an ext4 filesystem on
`/dev/vdb`.  The current rsync publisher is correct for immutable releases,
but multi-gigabyte raw disk images make repeated publication expensive even
when most blocks are unchanged.

A dedicated ZFS dataset at each end would give the artifact conveyor:

- atomic, named versions through snapshots;
- block-level incremental replication with `zfs send -i`;
- preservation of holes and ZFS compression without teaching the publisher
  about raw-image allocation;
- cheap local clones for writable QEMU smoke runs; and
- resumable receives for interrupted WAN transfers.

The unit of replication must be a project-specific dataset.  Sending
`datapool/home` would couple artifact publication to unrelated home-directory
changes and expose unrelated data.

## Safety boundary

Do **not** reformat Exabyt's live `/dev/vdb`: it is the ext4 artifact cache and
currently has ample free space.  Attach a new volume, identify it by a stable
`/dev/disk/by-id/...` path, and make that device the Exabyt ZFS pool.  Do not
use the small `/dev/vdc`; it is cloud-provider metadata/configuration media.

Do not build the destination pool in a loopback file on `/dev/vdb` except as
a disposable proof of concept.  A file-backed pool adds a second filesystem
and failure domain without providing the operational properties wanted here.

## Proposed layout

On Biggie:

```text
datapool/niagara-transfer
  releases/<build-id>/...
```

On Exabyt, on a newly attached volume:

```text
exbpool/replicas/niagara-transfer
  releases/<build-id>/...
```

Suggested source properties are `recordsize=1M`, `compression=zstd`, and
`atime=off`.  The large record size suits raw images and immutable artifacts;
small logs and manifests can remain in the existing ext4 bundle tree or move
to a child dataset with the default record size if that distinction matters.

The canonical image name should be stable and updated with `rsync --inplace`
or an equivalent block-aware builder before taking the next snapshot.  If
each build is written to a brand-new pathname, ZFS may be unable to express
the similarity as a small incremental stream even when the file contents are
mostly identical.

## Provisioning outline

These commands are a design, not commands to run against an unidentified
device.  Substitute the verified, newly attached Exabyt disk's by-id path.

```sh
# Biggie
sudo zfs create -o mountpoint=/home/ryan/devel/niagara-transfer \
  -o recordsize=1M -o compression=zstd -o atime=off \
  datapool/niagara-transfer

# Exabyt (Ubuntu), only after attaching and identifying a new blank volume
sudo apt-get install zfsutils-linux
sudo zpool create -o ashift=12 exbpool /dev/disk/by-id/VERIFIED-NEW-DISK
sudo zfs create -o recordsize=1M -o compression=zstd -o atime=off \
  exbpool/replicas
```

Leave `exbpool/replicas/niagara-transfer` absent before the first receive; the
receive creates it as a child of the property-bearing container.  Creating the
target dataset first complicates the initial receive because the destination
name already exists.

The receive target should be treated as receive-only.  QEMU should use a ZFS
clone or a copied/reflinked smoke-run image, never the received canonical
dataset directly.

## First and incremental sends

Take snapshots only after the artifact's size, sparse shape, manifest, and
SHA-256 have passed the existing validation gates.

```sh
# Initial snapshot and transfer from Biggie
sudo zfs snapshot datapool/niagara-transfer@BUILD_0
sudo zfs send -c datapool/niagara-transfer@BUILD_0 |
  mbuffer -q -m 1G |
  ssh EXABYT 'sudo zfs receive -s -u exbpool/replicas/niagara-transfer'

# Next validated build
sudo zfs snapshot datapool/niagara-transfer@BUILD_1
sudo zfs send -c -i datapool/niagara-transfer@BUILD_0 \
  datapool/niagara-transfer@BUILD_1 |
  mbuffer -q -m 1G |
  ssh EXABYT 'sudo zfs receive -s -u exbpool/replicas/niagara-transfer'
```

`-c` sends compressed blocks when supported.  `receive -s` records a resume
token after interruption; inspect `receive_resume_token` on the destination
and resume with `zfs send -t TOKEN`.  Avoid an unconditional `receive -F`
until automation has verified that the destination is the dedicated
receive-only dataset and that discarding its newer snapshots is intended.

## Publication protocol

1. Update the stable source files in `datapool/niagara-transfer`.
2. Run the existing host-side size, sparse-shape, and SHA-256 checks.
3. Take a uniquely named snapshot and record its dataset GUID, snapshot GUID,
   build ID, and artifact hashes in the release manifest.
4. Hold the last acknowledged common snapshot so pruning cannot destroy the
   incremental base.
5. Send the incremental stream and preserve a receive resume token on failure.
6. On Exabyt, verify the received snapshot GUID and artifact hashes.
7. Only then update `bundles/current`/`READY` or the equivalent pointer.
8. Acknowledge the snapshot back to Biggie; retain at least the last two
   acknowledged common snapshots before pruning older versions.

The first experiment should compare `zfs send -nPv` estimated stream size and
wall-clock transfer against the seeded rolling-checksum rsync used for the
Tribblix `big-disk-unit103-v5.img`.  That gives a measured basis for deciding
whether ZFS becomes the primary publisher or remains a bulk checkpoint path.

## Seeded-rsync baseline: Tribblix unit 103 (2026-08-25)

The live `trib104` QEMU used this source on Biggie:

```text
/home/ryan/devel/masa-sun4v/ci/candidates/tribblix-installed-unit104-now/images/big-disk-unit103-v5.img
```

It was copied to Exabyt as:

```text
/var/lib/niagara-ci/incoming/tribblix-installed-unit104-now/big-disk-unit103-v5.img
```

The transfer pre-seeded rsync's destination with Exabyt's nearby canonical
`20260825T170500Z-hsimd-v1` big disk, then used `rsync --inplace
--no-whole-file --compress-choice=zstd`.  Rsync reported:

```text
logical file size:  2,158,034,944 bytes
literal data:       1.61 GB
matched data:       550.72 MB
wire bytes sent:    678.05 MB
wire bytes received: 422.80 KB
reported speedup:   3.18
```

The source's size, allocation, and mtime were unchanged across its final hash.
The destination was hashed, hole-punched with `fallocate -d`, hashed again,
atomically renamed from its partial name, and made read-only.  All three final
hash checks agreed:

```text
SHA-256  96caa933432abcc909a6760a654d0dde89e70ccd954a4a1159d8d856f124433c
```

## Open decisions

- Size and provider class of the new Exabyt volume.
- Whether the dataset should use native ZFS encryption.  If so, decide whether
  Exabyt receives raw encrypted streams (`zfs send -w`) or holds the key.
- Root-over-SSH versus narrowly delegated `zfs receive` permissions.
- Snapshot retention, holds/bookmarks, and alerting on stalled resume tokens.
- Whether manifests remain in the ext4 release tree or travel in the ZFS
  snapshot as the authoritative atomic bundle.
