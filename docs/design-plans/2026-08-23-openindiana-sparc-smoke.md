# OpenIndiana SPARC on QEMU Niagara: first smoke-test design

Status: direct boot executed; OpenIndiana reaches a maintenance shell with a
working hsimd disk.  Manual media discovery and lofi mounting succeed.  The
next boot-path change is a narrow `media-fs-root` fallback for an HSFS disk
slice; a live PPP-over-channel experiment is also in progress.

## Immutable input

The two local downloads named `OpenIndiana_Text_SPARC_12_2025.iso` are
byte-identical.  The unsuffixed copy is canonical:

```
size     644198400 bytes
SHA-256  173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04
label    OpenIndiana_Text_SPARC_12_2025
```

The ISO has a valid Sun disk label (`0xDABE`, XOR checksum zero), with slice 2
covering 1,257,600 sectors.  It contains a native `platform/sun4v` tree.
`platform/sun4v/boot_archive` is a symlink to the common 192,595,968-byte UFS
boot archive at `platform/sun4u/boot_archive` (SHA-256
`5c78bd894c12fb2b1caad2b289605655ce8971da38edba7d410b425a362b85ab`).

## Isolation rule

Never give the imported source ISO to QEMU.  The patched Niagara vdisk is a
`MAP_SHARED` regular-file mapping, so each run must open a disposable XFS
reflink child.  A failed or killed run is rolled back by deleting that child
and making a new reflink from the hash-pinned parent.

`tools/openindiana-playbox-run.sh` enforces the source size and hash, refuses a
second Niagara QEMU, constrains the replaceable filename to `*.test.iso`, and
compares the new child with its parent before launch.

## First experiment

Boot the unmodified ISO before transplanting any Tribblix artifact:

```
boot disk -v
```

If OBP cannot resolve the archive through the default slice, repeat from a
fresh reflink with `boot disk:d -v`.  Do not introduce the Tribblix
`swapgeneric` or Solaris 10 `hsimd` changes until an observed failure requires
one of them.

## Pre-registered observations

1. **OBP gate:** the ISO label is accepted and OBP opens the boot archive.
2. **Kernel gate:** an OpenIndiana/illumos kernel banner appears and the kernel
   advances beyond early CPU initialization.
3. **Disk gate:** a virtual disk driver attaches to QEMU's `disk@0` and the
   intended live root is selected.
4. **Userland gate:** SMF or the text installer begins, with a usable console.

Classify the first failure by its direct console evidence:

- a trap in CPU performance-counter initialization is evidence for auditing
  the Tribblix `cu_flags` workaround against this archive;
- failure to attach `disk@0` is evidence for auditing/injecting `hsimd`;
- successful archive load followed by the wrong root selection is evidence for
  auditing `swapgeneric` and boot properties;
- missing-file or archive-path errors at OBP are media-layout failures and must
  be solved before changing the kernel.

Record the exact last console line and elapsed time.  An attempt, QEMU CPU
usage, or silence alone is not a PASS or a diagnosis.

## Measured result: 2026-08-24

The unmodified archive reached the OpenIndiana kernel but exposed two independent
failures.  Niagara PCBE initialization needed the already-understood
`set cu_flags=0` workaround, and the stock image had no kernel driver for the
firmware node `SUNW,legion-disk`.  A derivative archive was therefore built with
exactly those two required changes: `cu_flags=0` and the known-good Solaris 10
`hsimd` driver, updated to return `ENOTTY` for unsupported ioctls.

Final pre-channel artifacts on `niagara-playbox`:

```
OpenIndiana_Text_SPARC_12_2025.boot_archive.hsimd
size     192595968
SHA-256  f334e542c0ba0ac35fea8bf8f6270f813e984727a6d5c77a3c6fda0906cee376

OpenIndiana_Text_SPARC_12_2025.hsimd.test.iso
size     644198400
SHA-256  5b73fa5d8b5c5500218273a6ab3b25bec8583553806b0f15bac1c488d43cf9c3
```

The archive occupies ISO byte offset `449744896`, length `192595968` (ISO9660
LBA 219602, 94041 2048-byte sectors).  Prefix and suffix digests matched the
pristine ISO after the splice, and the Sun VTOC checksum remained valid.

Observed boot results:

- no PCBE panic;
- `virtual-device: hsimd0` and
  `hsimd0 is /virtual-devices@100/disk@0`;
- real `/dev/dsk/c4d0s0` through `c4d0s7` nodes;
- `/usr/lib/fs/hsfs/fstyp /dev/rdsk/c4d0s2` reports `hsfs`;
- a read-only mount of `c4d0s2` on `/.cdrom` succeeds;
- `/.cdrom/solaris.zlib` attaches as `/dev/lofi/1`;
- mounting `/dev/lofi/1` read-only on `/usr` succeeds; and
- `/usr/bin/pppd` exists in the mounted live userland.

The warning `hsimd_ioctl: cmd 4a4 not implemented` is non-fatal; it is the
`CDROMREADOFFSET` probe and the HSFS mount proceeds successfully.

## Automatic-media failure: corrected diagnosis

The boot stopped at `Preparing text install image for use` with
`lofiadm of /usr FAILED!`.  This is not a failed hsimd read and not evidence for
a second missing CD transport.  `/lib/svc/method/media-fs-root` asks `listusb`,
then `listcd`, then tries network media.  `listcd` finds no kernel CD device, so
the method never tests the ordinary hsimd block disk even though its slice 2 is
valid HSFS media.  Manual HSFS + lofi + `/usr` mounting proves the remainder of
the storage path.

The next remaster should add one narrowly scoped fallback: scan candidate
`/dev/dsk/*s2` devices, confirm HSFS with the corresponding raw device, mount a
candidate on `/.cdrom`, and require the media and archive `.volsetid` values to
match.  Do not invent CD hardware for this step.

## Machine/storage model established

This Niagara machine definition presents one file-backed virtual storage device.
OpenBoot reads that device and interprets its HSFS contents as boot media.  The
kernel accesses the same bytes through `hsimd`; both firmware and kernel paths
ultimately use the q.bin virtual-disk contract (FAST_TRAP `0xf0`/`0xf1`) backed
at guest physical `0x1f40000000`.  There is no second QEMU CD device or hidden
CD MMIO contract to recover from OpenBoot.

All eight slices in the current OpenIndiana ISO are aliases of the same extent
(start block 0, 1,257,600 blocks).  A future installer/target image must use
non-overlapping VTOC regions: immutable OpenIndiana media plus a distinct
writable region for a ZFS target.  After this bootstrap works, extending q.bin
with purpose-built paravirtual block and character devices is an intentional
next phase; emulating real Fire/PCI hardware is not a prerequisite.

The same arrangement can become a native OpenIndiana development basecamp.
Durable ZFS plus channel networking can hold a toolchain, sources, packages,
build products, and test evidence outside the ephemeral boot archive. The
Solaris 10 donor should remain a bootstrap and regression oracle, not an
assumed permanent compiler host. This is initially a userland hypothesis:
compiler/ABI probes and a native rebuild of a channel utility must pass before
treating the guest as suitable for illumos kernel or driver builds.

The first live inventory corrected an assumption from the Tribblix checkpoint:
this OpenIndiana environment has a 64-bit SPARC V9 kernel and illumos linker
5.11-1.1790, but no `/usr/bin/gcc`, no `/usr/versions/gcc-7/bin/gcc`, and no
other regular file named `gcc` below `/usr`. `pkg list '*gcc*'` did not return
in the maintenance environment and was safely interrupted on channel 1. Thus
toolchain installation or import onto durable storage is an explicit bootstrap
step; GCC 7 must not be described as already present on this media.

## Live channel/PPP result: PASS

The running guest remains in the maintenance root shell with `/.cdrom` and
`/usr` mounted read-only.  QEMU uses monitor socket
`/tmp/oi-hsimd-monitor.sock`; do not send console Ctrl-C, because that previously
killed QEMU rather than merely cancelling guest input.

`guest-chand` is project payload, not a stock OpenIndiana file.  The first
binary recovered from `primary.img:/opt/niag/bin/guest-chand` had SHA-256
`dfb07cc6f6aee2ac704317b173762d8cd67485287eea6caed8dac2fcd5c1cceb`,
but direct execution proved it ignored the placement overrides and tried its
compiled `/dev/rdsk/c0t0d0s3` default.  The actual runtime-override build was
recovered read-only from the installed root in `tribblix-m34-batch-final.iso`:

```
SHA-256  baa7bd2798a414cf7f774f83588fdb132b857f86f5a189ade65f7e1440baffc9
```

Its `NIAG_CHAN_DEV` override works.  Its numeric
`NIAG_CHAN_GUEST_BLK` parser rejects every tested value, including `1000`, on
this OpenIndiana userland.  The live test therefore uses the binary's compiled
block default while overriding only the raw device.  Host and guest identity:

```
channel base byte     520093696
channel base block    1015808
guest device          /dev/rdsk/c4d0s2
NIAG_CHAN_GUEST_BLK   unset (compiled default 1015808)
NIAG_CHAN_HOST_BYTE   520093696
```

This deliberately makes the test ISO non-rebootable but does not overlap
`solaris.zlib`; the running root archive is already resident in RAM.  Payloads
were staged in unused channel-15 data space at absolute block `1252526`.  The
final 60-block tar contained the correct `guest-chand`, `guest-echocli`, and
`guest-ppp-chan.pl` and was verified independently after guest readback:

```
SHA-256  339f4f9dbfb496e8e1ed46c183ad1ba9fe9bd39b75e08ebc793f0e6032bae84d
```

The deliberately mutated test ISO has no stable post-test digest: channel
initialization and traffic modify its scratch blocks.  The pristine and
pre-channel derivative hashes above remain the reproducible inputs.

Channel-0 echo passed before PPP.  The host sent the exact 22-byte marker
`OI-CHAN-ECHO-20260824\n`; sequence state reached `h2g seq=1 ack=1` and
`g2h seq=1 ack=1`, and the returned marker SHA-256 was
`05978be00400eddaeffc521a6513683be6b670a24a8a2dd5ef90bfd1c3f74e72`.

The first pppd start exited because only `/devices/pseudo/clone@0:sppp`
existed.  Both majors were already registered (`sppp 270`, `sppptun 271`), and
targeted `/usr/sbin/devfsadm -i sppp -i sppptun` created the missing
`sppptun` clone.  The shipped SPARC V9 `sppp`, `sppptun`, `spppasyn`, and
`spppcomp` modules are present.

`guest-ppp-chan.pl` now passes `logfile /tmp/gpppd-chan0.log` to pppd because
the maintenance environment has no `/var/adm/messages`.  After a clean
stop/init/start cycle, OpenIndiana pppd 2.4.0b1 and Linux pppd 2.4.9 completed
LCP and IPCP:

```
guest sppp0 local     10.0.5.15
guest sppp0 remote    10.0.5.1
host ppp0 local       10.0.5.1
host ppp0 peer        10.0.5.15
```

Measured network acceptance:

- host to guest: 3/3 ICMP replies, 0% loss, 73.9–129.4 ms;
- guest to host: `10.0.5.1 is alive`;
- guest through playbox forwarding/NAT: `1.1.1.1 is alive`;
- direct DNS through `8.8.8.8`: `example.com` returned `NOERROR` over UDP in
  61 ms; and
- bounded guest statistics ping through `/usr/bin/timeout 6`: six replies from
  `1.1.1.1`, 64.0–153.7 ms.

`dladm show-link` returns no rows because `sppp0` is not a normal dladm
datalink.  `ifconfig -a` currently fails while probing an unsupported address
family, but this does not contradict the independently measured PPP interface,
routes, packet counters, pings, or DNS result.

## Safe console, NFS, iSCSI, and ZFS checkpoint: PASS

Channel 1 now carries a separate root PTY through `socat`. The playbox tmux
session is `oi-safe-console`. A controlled `sleep 30` test proved that Ctrl-C
interrupts only the guest process and leaves QEMU alive; this is the console to
use for all further interactive work. It is an emergency root PTY, not yet the
final authenticated `ttymon`/getty service.

OpenIndiana mounted the playbox NFSv3 export at `/mnt/host`, and a guest copy of
the 125,440-byte rescue tar was byte-identical to the raw-disk mailbox copy
(SHA-256 `f5535d9b5cba23862afc31d4c29014b5521e58c216ad2567958174757d609cbb`).

The guest's loaded `iscsi` v1.55 and `idm` modules discovered a Linux LIO LUN
through PPP. The first ZFS write falsified the default target configuration:
LIO's three-second `dataout_timeout` expired and faulted that WWID. PPP itself
remained healthy. A fresh LUN identity configured with the Linux 6.8 maximum
timeout of 60 seconds passed. OpenIndiana created a whole-disk pool with all
optional features disabled:

```text
zpool create -d -f oi_iscsi_test c0t600140544D6BE8EE5BD4D559AFA788DCd0
```

`zpool status` reported `ONLINE` and zero errors. The file
`/oi_iscsi_test/CHECKPOINT.txt` read back with illumos cksum `3367977479 22`.
The pool was then cleanly exported and the iSCSI session logged out before an
XFS reflink checkpoint was made. Exact assets, hashes, and tomorrow's ordered
boot-to-checkpoint procedure are in
`docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md`.

## Primary next storage path: appended 2 GiB hsimd slice

The iSCSI result remains an important portable rescue and Linux/illumos
interchange mechanism, but it should not be the normal high-volume data path.
The preferred next image grows Niagara's one supported file-backed disk and
replaces the CD-alias `s7` with a non-overlapping 2 GiB ZFS slice.

Measured clean-image geometry is 640 sectors/cylinder. The source file ends at
byte 644,198,400; the safe next cylinder is 1966, byte 644,218,880, leaving a
20 KiB gap. Exact proposed values are `s7=(1966, 4194304)`,
`s2=(0, 5452544)`, `ncyl=8520`, and final file size 2,791,702,528 bytes.

A sparse reflink geometry test passed `tools/vtoc.py verify`; all original
bytes after the edited label remained byte-identical and the 20 KiB gap was
zero. This proves the host-side layout only. Guest slice boundary behavior and
`zpool create` remain explicit TDD gates because the prior Tribblix experiment
showed that label writes can occur before a pool is actually usable.

## Next-session compatibility work

The next session also includes source-level illumos compatibility work. Storage
tools must stop rejecting the measured `hsimd` disk solely because its
controller string is `SUNW,sun4v-virtual`; `format` and `iostat` will be traced
and fixed independently, with `prtvtoc`, HSFS, lofi, raw I/O, and ZFS as
non-regression controls.

Networking gets a separate trace-first lane. `ifconfig -a` currently aborts at
`socket()` with `EAFNOSUPPORT`, despite proven IPv4 PPP, DNS, NFS, and routing.
The investigation must separate missing IPv6/provider/SMF state from the prior
32-bit ABI failure. An empty `dladm show-link` for legacy `sppp0` is not itself
a defect; `dladm` will be validated against a temporary GLDv3 etherstub/VNIC.
The complete hypothesis matrix and pass criteria are in the next-session
runbook.
