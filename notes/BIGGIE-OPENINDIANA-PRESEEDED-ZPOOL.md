# Preseed an OpenIndiana hSIMD disk with a host-created ZFS pool

## Proven result

On 2026-08-26, Biggie preseeded the additional 60 GiB unit-104 disk for
`oi-warm-60g-biggie-01` with a pool named `tink`.  The procedure preserved a
valid Sun VTOC for QEMU/OpenBoot, created the pool inside slice 0, exported it
cleanly, detached the Linux loop device, and resumed the paused QEMU.

The resulting pool was created with all ZFS feature flags disabled and these
compatibility/performance-debug settings:

```text
ashift=9
recordsize=8K
compression=off
atime=off
sync=always
```

## Safety rule

Never modify a disk image underneath an actively executing QEMU.  If the image
is already attached, pause the guest through its monitor and verify `VM status:
paused` before changing the label or attaching a loop device.  Cleanly export
the pool and detach the loop device before sending `cont`.

Published release artifacts are intentionally mode `0444`.  A warm-builder
run that requires writable installer media must make a run-local copy and
explicitly `chmod 0644` that copy before launch.  `readonly=off` in QEMU's
argument list is not proof that the backend opened writable.  Before sending
the OBP boot command, require all of the following in `qemu.log`:

```text
unit:0 slice2 size:1073741824
unit:3 slice2 size:<exact installer bytes>
unit:4 slice2 size:64424509440
```

Also fail immediately if the log contains `blk_set_perm failed`.  This gate
would have prevented the abandoned `oi-warm-60g-biggie-02` boot, where the
immutable unit-103 copy remained read-only and QEMU opened both units 103 and
104 with read-only file descriptors.

## Disk layout

The 60 GiB file has 125,829,120 512-byte sectors.  Use geometry that fits in
the 16-bit Sun label fields:

```text
ncyl=7831 acyl=2 nhead=255 nsect=63
sectors_per_cylinder=16065
```

The proven VTOC map is:

```text
s0: start cylinder 1, start sector 16065, length 125788950 sectors
s2: start cylinder 0, length 125829120 sectors (whole-disk backup slice)
```

Slice 2 must remain the exact whole-file size because QEMU's Niagara vdisk
firmware reads `s2.nblk` to decide how many bytes to serve.  Do not create ZFS
on the whole raw file: doing so would overwrite the Sun label.  The ZFS vdev
begins at the slice-0 offset instead.

## Procedure

Set explicit paths for the run; never discover the newest image:

```sh
run=/home/ryan/devel/masa-sun4v/ci/runs/oi-warm-60g-biggie-01
disk=$run/images/extra-unit104-60g.img
monitor=$run/monitor.sock
vtoc=/home/ryan/devel/qemu-sun4v-illumos/tools/vtoc.py
```

Pause and verify QEMU:

```sh
printf 'stop\ninfo status\n' | socat - UNIX-CONNECT:"$monitor"
```

Create and verify the Sun label:

```sh
python3 "$vtoc" set-geometry "$disk" 7831 2 255 63
python3 "$vtoc" set "$disk" 0 1 125788950
python3 "$vtoc" set "$disk" 2 0 125829120
python3 "$vtoc" verify "$disk"
python3 "$vtoc" show "$disk"
```

Attach only slice 0 as a loop device and create the compatibility pool:

```sh
offset=$((16065 * 512))
sizelimit=$((125788950 * 512))
loop=$(sudo losetup --find --show \
  --offset "$offset" --sizelimit "$sizelimit" --sector-size 512 "$disk")

sudo zpool create -d -f -m none -o ashift=9 \
  -O mountpoint=none -O canmount=off \
  -O recordsize=8K -O compression=off -O atime=off -O sync=always \
  tink "$loop"
```

Capture evidence before release:

```sh
sudo zpool status tink
sudo zpool get all tink
sudo zfs get recordsize,compression,atime,sync tink
```

Export, detach, and only then resume QEMU:

```sh
sudo zpool export tink
sudo losetup -d "$loop"
printf 'cont\ninfo status\n' | socat - UNIX-CONNECT:"$monitor"
```

## Acceptance gates

- `tools/vtoc.py verify` reports `OK: label valid`.
- Slice 2 is exactly 125,829,120 sectors.
- `zpool status tink` is `ONLINE` with zero errors.
- Representative feature properties report `disabled`.
- `zpool export tink` succeeds.
- `losetup -j "$disk"` returns no mapping.
- The monitor reports `VM status: running` after `cont`.
- In OpenIndiana, identify unit 104 from independent hSIMD/device evidence and
  import `tink` without upgrading it.  Never run `zpool upgrade tink`.

## Fast Biggie-to-Exabyt artifact reconciliation

### First gate: prove a transfer is necessary

Before copying any multi-gigabyte image, resolve its build/release provenance
and search the destination host's published releases.  On 2026-08-26 this gate
would have prevented wasted transfer attempts: Exabyt's
`oi-archive-builder-exa-01/installer-unit103-rw.img` was byte-identical to the
published `ppp-injected-v2-20260825` bundle, and Biggie already had that exact
release locally:

```text
/home/ryan/devel/niagara-ci/artifacts/releases/
  ppp-injected-v2-20260825/big-disk.img
```

The correct preference order is:

1. Reuse the exact immutable published artifact already on the target host.
2. Regenerate it locally from its pinned source ISO and 192 MiB boot archive.
3. Reconcile from a related local seed with rsync.
4. Stream physical extents with sparse tar.
5. Transfer the whole logical image only as a last resort.

Record the release ID and manifest identity in the new run manifest.  File
size alone is not artifact identity.

### When a transfer is actually required

Plain `scp` through the MBP is a poor choice for multi-gigabyte sparse images:
it can stream logical zero regions and make the laptop an unnecessary relay.
Biggie initially could not authenticate to Exabyt with its own key, but the
MBP's forwarded SSH agent made a direct Biggie-to-Exabyt connection work.  Use
the site-local SSH aliases; do not record private addresses in this public
repository:

```sh
ssh -A biggie \
  'ssh -o BatchMode=yes exabyt hostname'
```

When Biggie already has a closely related image, use it as the destination
seed and let rsync send only changed blocks.  The destination must be a new
staging artifact, never a shared baseline or a file open by QEMU:

```sh
dest=/home/ryan/devel/masa-sun4v/images/\
OpenIndiana_Text_SPARC_12_2025.exabyt-builder-exact.img

cp --reflink=auto --sparse=always \
  /home/ryan/devel/masa-sun4v/images/\
OpenIndiana_Text_SPARC_12_2025.masa-cdlabel.iso \
  "$dest"

rsync -a --inplace --no-whole-file --partial --info=progress2 \
  -e ssh \
  exabyt:/var/lib/niagara-ci/builders/\
oi-archive-builder-exa-01/installer-unit103-rw.img \
  "$dest"
```

Run the rsync from inside `ssh -A biggie '...'` so the data flows directly
between Biggie and Exabyt while authentication uses the forwarded agent.  Do
not perform an additional whole-file checksum pass immediately afterward;
rsync has already reconciled the destination against the source.  Record the
source path, destination path, final byte size, and rsync completion instead.
