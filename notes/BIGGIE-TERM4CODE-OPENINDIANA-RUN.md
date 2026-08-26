# Biggie OpenIndiana run `term4code`

## Run contract

`term4code` is the Biggie OpenIndiana trial launched on 2026-08-26 from
repository commit `6ca75df872c618ec8559d5a1a9601bf04d758d2b`.  Its hypothesis is that
the published `ppp-injected-v2-20260825` installer can boot with a private
writable carrier and a separately labelled, host-preseeded 60 GiB hSIMD disk.

The run directory is:

```text
/home/ryan/devel/masa-sun4v/ci/runs/term4code
```

It contains the expanded QEMU argv, run manifest, timestamps, console log,
QEMU log, initial live-QEMU inventory, NVRAM readback, and boot-stage captures.
The tmux session has persistent `shell`, `owner`, `console`, and `monitor`
windows.  QEMU has no controlling terminal; serial and monitor access use
run-local Unix sockets.  The `console` window is the visible window.

## Completed launch gates

- The canonical checkout was clean at commit `6ca75df` before run creation.
- Every pre-existing Biggie QEMU was recorded and used disjoint artifacts.
  No existing VM was stopped, paused, modified, or reused.
- The published installer source is exactly 2,791,702,528 bytes with SHA-256
  `d131bc48bfa267511347ab7a2bc9c6b1d554b0356f6c6705a4ceacd19135ed17`.
- Unit 100 is a private writable 1 GiB carrier copy.
- Unit 103 is a private writable copy of that published installer.
- Unit 104 is a private 60 GiB Sun-labelled disk.  VTOC verification passed;
  slice 0 starts at sector 16,065 for 125,788,950 sectors and slice 2 covers
  exactly 125,829,120 sectors.
- Before QEMU owned unit 104, the host created pool `tink` with all reported
  features disabled, `ashift=9`, `recordsize=8K`, `compression=off`,
  `atime=off`, and `sync=always`.  The pool was ONLINE with zero errors, then
  cleanly exported and its loop mapping detached.
- The intentionally terminated whole-file SHA-256 of the new sparse 60 GiB
  disk is not an acceptance gate and was not repeated.
- QEMU's log reported unit 0 as 1,073,741,824 bytes, unit 3 as 2,791,702,528
  bytes, and unit 4 as 64,424,509,440 bytes.  It contained no
  `blk_set_perm failed` message.
- The run-local NVRAM is 8 KiB.  Fresh-OBP readback showed
  `auto-boot?=false`, an empty `boot-file`, `use-nvramrc?=false`, an empty
  `nvramrc`, and `diag-switch?=false`.
- The exact boot command was
  `boot /virtual-devices@100/disk@3:d -k -v`; KMDB loaded before the kernel
  banner.

## Initial failure boundary

The kernel mounted `/ramdisk-root:a`.  hSIMD units 0, 3, and 4 attached.  Unit
4 reported the expected 60 GiB size and exact slice-0/slice-2 map.  Unit 3
reported the already-known installer-label geometry mismatch: its label says
5,452,800 blocks while the drive supplies 5,452,544 blocks.

Boot then reached:

```text
Preparing text install image for use
lofiadm of /usr FAILED!
Requesting System Maintenance Mode
Enter user name for system maintenance (control-d to bypass):
```

This was a failed media-lofi gate, not an installer-menu pass.  Ryan explicitly
handed console input to the operator for in-place recovery; the VM was not
restarted or paused.

## In-place media recovery

Hypothesis 1 was that the RAM root was usable and the failure was media
discovery or mount ordering rather than hSIMD attachment.  The documented
maintenance login (`root`, then `root`) reached `root@openindiana:~#`.
`touch` and `find` initially reported `command not found` because `/usr` was
not mounted; those tool failures were not treated as writability evidence.
Shell redirection created, listed, and removed exact canaries in `/` and
`/etc/dev`.  `mount` independently reported `/`, `/devices`, and `/dev`
read-write.

Hypothesis 2 was that `/.cdrom` was simply absent from the startup mount
topology.  It existed as an empty, unmounted directory.  Fresh device links
mapped unit 103 slice zero to `/dev/dsk/c4d3s0`, backed by
`/devices/virtual-devices@100/disk@3:a`.  The smallest discriminating mount was:

```text
mount -F hsfs -o ro /dev/dsk/c4d3s0 /.cdrom
```

It returned status zero.  `mount` then reported `/.cdrom` on that exact device,
and the media exposed `solaris.zlib` (419,822,080 bytes) and
`solarismisc.zlib` (29,211,648 bytes).

Hypothesis 3 was that the stock `media-fs-root` lofi operations would succeed
once the correct media root existed.  Rather than repeat its unrelated
USB/CD/network discovery and DHCP wait, the recovery used its documented
smallest equivalent:

```text
/usr/sbin/lofiadm -a /.cdrom/solaris.zlib
mount -F hsfs -o ro /dev/lofi/1 /usr
/usr/sbin/lofiadm -a /.cdrom/solarismisc.zlib
mount -F hsfs -o ro /dev/lofi/2 /mnt/misc
```

Both mounts returned status zero.  The acceptance gate passed: `/usr` is a
read-only HSFS mount on `/dev/lofi/1`, `/mnt/misc` is a read-only HSFS mount on
`/dev/lofi/2`, and `lofiadm` maps those devices to the two expected files.

The exact stock `/lib/svc/method/media-fs-root` was then invoked once in the
recovered state.  Shell-builtin tests for `/.cdrom/.volsetid` and
`/.cdrom/solaris.zlib` had both returned zero, and all three required mounts
were present before the invocation.  The method nevertheless traversed its
network fallback, printed a line-130 shell-expression error, waited through
eleven failed `dhcpinfo` calls, and finally reported:

```text
lofiadm: could not map file /.cdrom/solaris.zlib: Device busy
lofiadm of /usr FAILED!
```

This is a non-idempotent rerun failure: `/dev/lofi/1` already mapped that exact
file.  After the method returned, `/.cdrom`, `/usr`, and `/mnt/misc` remained
mounted; both `lofiadm` mappings remained exact; builtin tests for
`/usr/bin/touch` and `/mnt/misc/opt` returned zero.  A bash `read`/`case` audit
of the method confirmed `SOLARIS_ZLIB="/.cdrom/solaris.zlib"` and direct
`/usr/sbin/lofiadm` calls without depending on `grep` or `find`.

The archive patcher currently scans candidate paths matching `*s2`.  This run
proves that the installation medium is unit 103 **slice zero** (`c4d3s0`,
`disk@3:a`).  Missing that mapping explains why startup left `/.cdrom`
unmounted even though hSIMD, HSFS, and both compressed payloads worked.  Future
archive validation must test the proven slice-zero mapping rather than infer
that the existing `*s2` fallback covers it.

## Unit-104 import and first mutation panic

The fortification lane independently identified unit 104 before writing it:

- `/dev/dsk/c4d4s0` maps to `/virtual-devices@100/disk@4:a`;
- `prtvtoc /dev/rdsk/c4d4s2` reported 512-byte sectors, slice 0 starting at
  sector 16,065 for 125,788,950 sectors, and slice 2 covering exactly
  125,829,120 sectors (60 GiB);
- read-only `zpool import` found `tink`, GUID
  `10910206772798469634`, ONLINE on `c4d4s0`.

`zpool import -N tink` returned zero without an upgrade.  The imported pool was
ONLINE with zero errors, `ashift=9`, every reported feature disabled,
`recordsize=8K`, `compression=off`, `atime=off`, and `sync=always`.
`zfs snapshot tink@empty-imported` succeeded and the snapshot appeared in
`zfs list -t snapshot` with zero used bytes.

The first dataset mutation, intended to create `tink/source`, caused the
current hSIMD driver to panic on a 147,456-byte (`0x24000`) request:

```text
panic[cpu0]: assertion failed: sz <= 128*1024
hsimd:hsimd_diskio ... 24000
hsimd:hsimd_strategy ... 24000
```

The console entered KMDB at `[0]>`.  Commands for the remaining datasets,
listing, and a recursive snapshot had already been queued by the host-side
driver loop; they were mistakenly delivered to KMDB, which rejected them as
unknown symbols.  They had no ZFS effect and must not be described as dataset
creation attempts or successes.  Whether `tink/source` committed before the
panic is unknown and must be inspected only after an explicitly authorized
recovery.

The run is preserved at KMDB with all panic evidence.  It is **not closed**.
No reboot, QEMU stop/pause, or further console input has been issued.  Import
PASS and `tink@empty-imported` PASS remain the last accepted handholds; the
first dataset-mutation sequence is PANIC.
