# OpenIndiana SPARC: boot-to-checkpoint runbook

This is the recovery plan for the next session. The goal is not to restore a
QEMU machine snapshot; Niagara VMState/migration is known not to work on this
platform. The goal is to reproduce the working guest from immutable media and
saved payloads, create a fast 2 GiB ZFS pool on an appended hsimd slice, and
retain the exported iSCSI pool as a portable recovery/interchange checkpoint.

## Saved checkpoint

The authoritative live-state capture is
`captures/openindiana-live-20260824/`. Its
`OI-ISCSI-CAPTURE-SHA256SUMS` manifest verifies the guest rescue tar, console
transcripts, PPP and iSCSI logs, LIO configuration, pool properties, and
checksum proof.

The exported whole-disk ZFS image is stored on the playbox as:

```text
/home/niagara/sun4v/images/oi-iscsi-zpool-checkpoint-20260824.img
SHA-256 3ebd859053c8da8b1dd27d3e21115978e3716f35ce17d81eb84b23614861a502
```

It is a 1 GiB XFS reflink with about 2.2 MiB allocated. A gzip recovery copy
is on both the playbox and Minnie at `~/sun4v/media/`:

```text
oi-iscsi-zpool-checkpoint-20260824.img.gz
SHA-256 a54d664594c19badfb97ac51d35f2be0a774206bfd34164ab64e6df3dbda2583
```

The pool was cleanly exported before both copies were made. It contains
`/CHECKPOINT.txt`, whose illumos `cksum` is `3367977479 22`.

## Gate 0: preserve rollback inputs

1. Verify the immutable OpenIndiana source using
   `tools/openindiana-playbox-run.sh`; do not boot or modify that source.
2. Verify `captures/openindiana-live-20260824/OI-ISCSI-CAPTURE-SHA256SUMS`.
3. Never write to the checkpoint image. Make an XFS reflink child for a test:

   ```sh
   cp --reflink=always --sparse=auto \
     ~/sun4v/images/oi-iscsi-zpool-checkpoint-20260824.img \
     ~/sun4v/images/oi-iscsi-zpool-work.img
   ```

4. Confirm no process has the checkpoint or work image open before configuring
   LIO.

## Gate 1: build a rebootable OpenIndiana image

The currently running ISO is deliberately non-rebootable: its already-loaded
boot archive was used as channel scratch. Do not mistake it for tomorrow's
boot input.

Build a fresh reflink child of the verified OpenIndiana source. Its boot
archive must contain, before the first boot:

- the working `hsimd` driver and registrations;
- the tested `media-fs-root` fallback that scans hsimd-backed `s2`, checks
  `.volsetid`, mounts `/.cdrom`, attaches `solaris.zlib`, and mounts `/usr`;
- `guest-chand`, `guest-echocli`, and the patched `guest-ppp-chan.pl` from the
  captured rescue tar;
- `socat` and `guest-rootpty.sh` for the safe channel console;
- targeted `devfsadm -i sppp -i sppptun` before PPP starts; and
- startup wiring for channel 0/PPP and channel 1/safe console.

Acceptance is binary: do not launch until the rebuilt archive has been mounted
read-only and every required path and captured SHA-256 has been checked.

After the boot archive is finalized, append the direct ZFS region. The measured
OpenIndiana geometry is 640 sectors/cylinder. The original file ends at sector
1,258,200, so `s7` starts at the next cylinder, sector 1,258,240, leaving the
same 20 KiB safety gap used successfully in the Tribblix work.

```sh
truncate -s 2791702528 "$WORK_IMAGE"
python3 tools/vtoc.py set-ncyl "$WORK_IMAGE" 8520
python3 tools/vtoc.py set "$WORK_IMAGE" 2 0 5452544
python3 tools/vtoc.py set "$WORK_IMAGE" 7 1966 4194304
python3 tools/vtoc.py verify "$WORK_IMAGE"
```

Exact layout:

```text
original file end   byte   644198400
s7 start            byte   644218880  (cyl 1966; 20 KiB gap)
s7 length                  2147483648  (exactly 2 GiB)
s7 end / file size  byte  2791702528
s2 length                  5452544 sectors
ncyl                        8520
```

This was validated on the playbox geometry-test reflink
`OpenIndiana_Text_SPARC_12_2025.direct-zfs.geometry-test.iso`: VTOC magic and
XOR passed, the non-label bytes of the original file were byte-identical, the
20 KiB gap was zero, and the sparse 2.6 GiB image allocated only 615 MiB.

## Gate 2: boot and establish the live userland

1. Launch only the fresh disposable image with
   `tools/openindiana-playbox-run.sh` (or its updated remaster path).
2. At OpenBoot use `boot disk -v`; use `boot disk:d -v` only if archive lookup
   requires the alternate slice.
3. Require all of these before continuing:

   - `/dev/dsk/c4d0s2` exists;
   - `/.cdrom` is HSFS;
   - `/.cdrom/solaris.zlib` is attached as `/dev/lofi/1`;
   - `/usr` is mounted HSFS from `/dev/lofi/1`; and
   - `/usr/bin/pppd`, `/usr/sbin/iscsiadm`, `zpool`, and `zfs` exist.

If automatic media setup fails, use the measured manual mount sequence in
`docs/design-plans/2026-08-23-openindiana-sparc-smoke.md`; do not hypothesize a
second CD device.

## Gate 3: channels, safe console, and PPP

The active channel geometry proved tonight is:

```text
guest raw disk          /dev/rdsk/c4d0s2
guest channel base      block 1015808
host channel base       byte 520093696
channel 1 guest base    block 1017856
```

Leave `NIAG_CHAN_GUEST_BLK` unset; this recovered 32-bit binary rejects the
numeric override and uses the correct compiled default. Set only
`NIAG_CHAN_DEV=/dev/rdsk/c4d0s2` where needed.

1. Initialize/start host bridge 0, guest channel 0, then prove exact echo.
2. Create `sppp`/`sppptun` nodes and start guest and host pppd.
3. Require `10.0.5.15` (guest) to `10.0.5.1` (host), bounded ping in both
   directions, ping to `1.1.1.1`, and DNS through `8.8.8.8`.
4. Start channel 1 and the safe root PTY. On the playbox expose it as:

   ```sh
   tmux new-session -d -s oi-safe-console \
     'socat -,raw,echo=0 UNIX-CONNECT:/run/niag1'
   ```

5. Prove Ctrl-C containment with `sleep 30`: Ctrl-C must return the guest
   prompt while QEMU remains alive. Never send ordinary Ctrl-C through QEMU's
   `console-share` session.

## Gate 4: create and verify the primary hsimd ZFS pool

Do not use `format`; its rejection of controller name `SUNW,sun4v-virtual` is
unrelated to whether ZFS can use an already-defined host-side slice.

1. Require `/dev/dsk/c4d0s7` and `/dev/rdsk/c4d0s7`.
2. Run `prtvtoc` and require exactly 4,194,304 sectors beginning at cylinder
   1966, with `s2` covering the complete served disk.
3. Plant a disposable host canary at `s7` byte zero and require an exact guest
   read from `/dev/rdsk/c4d0s7` block zero.
4. Repeat the prior boundary classifier at the last valid sector, exact end,
   and one sector past end. Record syscall return, errno, and transfer count.
5. Require a dry run before the only write experiment:

   ```sh
   zpool create -n -d -f oi_hsimd /dev/dsk/c4d0s7
   ```

6. Capture a baseline hash/nonzero count of `s7`, then run once:

   ```sh
   zpool create -d -f oi_hsimd /dev/dsk/c4d0s7
   ```

7. While it runs, measure QEMU liveness, backing-file mtime, and writes within
   `s7`; do not infer a hang merely from slow console output. Abort if any byte
   outside `s7` changes.
8. Pass only on `ONLINE`, zero errors, a small file write/read checksum, and a
   clean export/import cycle. Do not run `zpool upgrade`.

This is the primary data path because it avoids PPP and LIO throughput and
timeout constraints. Linux can later expose the same slice with an explicit
loop offset of 644,218,880 and size 2,147,483,648; never expose it concurrently
to a running guest.

## Gate 5: restore LIO and discover the portable checkpoint

The saved target configuration is
`captures/openindiana-live-20260824/targetcli-saveconfig.json`. The target must
listen only on `10.0.5.1:3260` and ACL only this initiator:

```text
iqn.1986-03.com.sun:01:008003dead03.6a8bd87f
```

Back the LUN with `oi-iscsi-zpool-work.img`, not the immutable checkpoint.
Before the guest logs in, set the ACL's LIO `dataout_timeout` to 60 seconds.
The Linux 6.8 target default of 3 seconds caused the first measured ZFS write
to time out; 60 is the kernel's maximum and passed.

In the guest, omit the explicit port on the add command. This OpenIndiana
`iscsiadm` rejected `10.0.5.1:3260` as an invalid port but accepted the
default-port form:

```sh
iscsiadm add discovery-address 10.0.5.1
iscsiadm modify discovery --sendtargets enable
iscsiadm list discovery-address -v 10.0.5.1
iscsiadm list target -S
devfsadm -i iscsi
format </dev/null
devfsadm -i ssd
```

Require a `LIO-ORG` disk under `scsi_vhci` and a full `/dev/dsk/c0t...d0`
devlink. A raw `s2` open can return `EIO` before the disk has a valid label;
the meaningful pre-write gate is successful inquiry plus a successful
whole-disk `zpool import` scan.

## Gate 6: import and verify the portable checkpoint

The pool was created with `zpool create -d`, so all optional feature flags are
disabled for illumos/Linux portability. Import it without upgrading:

```sh
zpool import
zpool import oi_iscsi_test
zpool status -v oi_iscsi_test
zpool get all oi_iscsi_test | egrep 'version|feature@'
cksum /oi_iscsi_test/CHECKPOINT.txt
```

Pass criteria:

- pool state `ONLINE` with zero read/write/checksum errors;
- every `feature@...` remains `disabled`;
- `CHECKPOINT.txt` is `3367977479 22`; and
- LIO records no DataOut timeout.

Do not run `zpool upgrade`.

## Gate 7: repair illumos storage and network administration tools

This is part of the next session's goal, not optional cleanup. Trace the stock
commands first and patch the narrowest correct layer. Do not change `hsimd` or
the IP stack merely to satisfy a userland assumption unless the kernel ABI is
measured to be wrong.

### Storage-tool lane

Baseline failures and controls:

- `format </dev/null` rejects `c4d0` because controller name
  `SUNW,sun4v-virtual` is not in its compiled controller table;
- `iostat -En` does not report the hsimd disk;
- `prtvtoc`, raw `dd`, HSFS, lofi, and direct hsimd reads/writes are controls
  that already work; and
- `CDROMREADOFFSET` (`0x4a4`) is a non-fatal CD probe and must not be confused
  with a required disk ioctl.

Procedure:

1. Capture `truss` for `format`, `iostat -En`, `prtvtoc`, and `zpool create -n`
   against the same `c4d0` image. Record every ioctl, return, errno, and returned
   `dk_cinfo`/geometry field.
2. Locate the exact illumos-gate controller validation and libdiskmgt/iostat
   enumeration code. Add fixture/unit tests for the measured
   `SUNW,sun4v-virtual` response before changing it.
3. Teach `format` to classify the Niagara virtual disk without weakening
   validation for unrelated controllers. Trace `iostat` independently; do not
   assume it shares the same rejection path merely because its symptom is
   similar.
4. Inventory unsupported `hsimd` ioctls. Implement an ioctl in the driver only
   when an illumos consumer genuinely requires that ABI and the return can be
   defined correctly from the one-disk geometry.
5. Build patched 32-bit and 64-bit commands as appropriate, stage them in the
   boot archive under distinct test names first, and run the same pre-registered
   matrix.

Pass criteria: `format` lists `c4d0` with the exact served capacity, `iostat
-En` reports it, `prtvtoc` still reports the exact VTOC, and no working HSFS,
lofi, hsimd, or ZFS behavior regresses.

### Network-tool lane

The measured failure is exact: `ifconfig -a` fails at `socket()` with
`Address family not supported by protocol family`, while IPv4 PPP, routes,
ping, DNS, and NFS all work. Prior Tribblix work also found that 32-bit
`ifconfig`/`soconfig` failed while a 64-bit AF_INET socket probe passed.

Procedure:

1. Record ELF class for `ifconfig`, `soconfig`, `ipadm`, and the working pppd.
2. Use `truss -f -t open,socket,ioctl` to identify the exact address family and
   ABI of the first failing call. Test `ifconfig -a4`, `ifconfig sppp0`, and
   minimal 32-bit/64-bit AF_INET and AF_INET6 socket probes separately.
3. Capture `/etc/sock2path`, `/etc/netconfig`, `soconfig -l`, relevant `modinfo`
   rows, device nodes, `svcs -xv`, and the logs for `network/netmask`,
   `network/ipmp`, `network/ip-interface-management`, and `ipmgmtd`.
4. Repair missing provider/module/SMF state first if that is the cause. If
   AF_INET works and only AF_INET6 is unavailable, make all-family enumeration
   skip `EAFNOSUPPORT` and continue to IPv4 rather than aborting the command.
   If the failure is ABI-specific, build and test a native 64-bit command before
   proposing a broader kernel change.
5. Treat `dladm show-link` on `sppp0` as a classification test, not a presumed
   bug: `sppp0` is a legacy STREAMS interface, not a GLDv3 datalink. Validate
   `dladm` itself by creating a temporary etherstub/VNIC; then test `ipadm` on
   that VNIC after `ipmgmtd` is healthy.

Pass criteria: `ifconfig -a` reports loopback and `sppp0` without aborting,
`ipadm` opens its management handle, `dladm` reports a temporary GLDv3
etherstub/VNIC, and the already-working PPP ping/DNS/NFS matrix still passes.

## Gate 8: replace PPP data traffic with Ethernet over channel 2

Use the existing design in `notes/ETHERNET-OVER-CHANNEL.md`; do not redesign it
from memory. Yesterday's experiment already proved that illumos can create the
etherstub and VNICs. It stopped at IP administration because `ipadm` could not
open its handle and `ifconfig` aborted with `EAFNOSUPPORT`, so Gate 7 is a hard
prerequisite.

Channel assignments for the experiment are:

```text
channel 0   PPP bootstrap/fallback
channel 1   safe console
channel 2   framed Ethernet relay
```

Guest link setup after Gate 7 passes:

```sh
dladm create-etherstub -t estub0
dladm create-vnic -t -l estub0 vnic0
dladm create-vnic -t -l estub0 wire0
ipadm create-ip vnic0
ipadm create-addr -T static -a 10.77.0.2/24 vnic0/v4
```

Then connect `wire0` through a guest `libdlpi` raw-frame relay to
`/tmp/niag2`, the shared-disk channel, the host `/run/niag2` socket, and a Linux
TAP relay. Frame transport is a four-byte network-order length followed by the
complete Ethernet frame, with strict MTU bounds and exact partial-I/O handling.

Validation order is fixed:

1. local switching between `vnic0` and a DLPI probe on `wire0`;
2. one exact frame in each direction through channel 2;
3. Linux `tap0` at `10.77.0.1/24` and successful ARP;
4. bounded ICMP in both directions;
5. TCP, DNS, and NFS; and
6. throughput/reliability comparison against PPP.

Do not remove PPP startup until Ethernet passes every gate from a cold boot.

## Gate 9: turn the checkpoint into a native development basecamp

The working OpenIndiana environment is not merely a rescue target. Once its
writable ZFS storage and Ethernet-over-channel path are reproducible, use it to
move development off the Solaris 10 donor and onto the newer guest toolchain.
Keep the donor as a known-good bootstrap and comparison oracle; do not make it
the permanent build environment.

Inventory the compiler, linker, assembler, headers, make implementation,
runtime libraries, package metadata, and both 32-bit and 64-bit output support.
If the compiler is absent, install or import it onto the durable development
dataset and record its source and package provenance. Record exact versions and
paths. Start with small compile/link/run probes for
ordinary C, SPARC V9, `libsocket`, `libdlpi`, and the interfaces used by
`guest-chand`. Then rebuild `guest-chand` and the Ethernet relay natively and
compare their behavior with the preserved binaries before attempting `hsimd`
or broader illumos components.

Pass criteria:

1. compiler and linker probes run successfully from the reproducible basecamp;
2. resulting binaries have the intended ELF class, ISA, dependencies, and
   runtime behavior;
3. at least one channel utility is rebuilt natively and passes the same channel
   test as its preserved predecessor;
4. source, build commands, compiler versions, hashes, and test output are saved
   outside the ephemeral root; and
5. a cold boot can remount the development dataset and repeat the build without
   the Solaris 10 donor.

Kernel or driver work remains a later, separately gated step: first establish
whether this image has compatible illumos headers and build machinery rather
than assuming that a working userland compiler is a complete ON build host.

## Linux handoff experiment

Never import the same backing image in Linux while it is exposed to a logged-in
guest. Export it in OpenIndiana, disable SendTargets, confirm `targetcli
sessions` reports no open sessions, and make another reflink child. Attach the
child read-only or with an isolated loop device, import without mounting first,
then verify `CHECKPOINT.txt`. This proves the UFS tooling problem is gone; it
is not a license for concurrent dual-host import.
