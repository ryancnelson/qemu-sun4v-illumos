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

Import PASS and `tink@empty-imported` PASS remain the last accepted handholds;
the first dataset-mutation sequence is PANIC.  After Ryan authorized retirement,
QEMU was stopped through its monitor/owner mechanism, never Control-C.  The run
directory, logs, panic capture, and commit `91a5802` remain preserved.  The
subsequent A/B preparation uses a new `term4code-02` identity and fresh disks.

## Installed-root startup repair trial, 2026-08-26

The isolated `workstation-fix-startup-01` clone was inspected from the
installer rescue environment while the preserved `workstation-reboot-01` QEMU
(PID 2719062) remained alive.  Read-only import proved the exact bootfs was
`rpool/ROOT/openindiana`; `rpool` was ONLINE with no known data errors.  Only
that bootfs was mounted at the rescue altroot `/a`.

Two independent blockers explained the missing channel autostart:

- the preserved normal-boot console showed
  `system/filesystem/root-minimal:default` repeatedly entering maintenance
  because retained live-media `system/filesystem/root:media` completed a
  dependency cycle, so `milestone/multi-user` never ran `/sbin/rc2 start`;
- installed `/dev/rdsk/c1d1s2` pointed to exact unit 101
  `/devices/virtual-devices@100/disk@1:c,raw`, but executable
  `/etc/rc2.d/S99niagara` tested nonexistent `/dev/rdsk/c4d1s2` and silently
  exited zero when it was absent.

Before repair, the host created and verified this recovery snapshot:

```text
datapool/workstation-fix-startup-01@pre-startup-repair-20260826T224159Z
```

Its snapshot view exposed the exact 64,424,509,440-byte unit-104 image.  The
guest then unmounted and exported the read-only pool, reimported it without
force using `readonly=off`, `altroot=/a`, and `-N`, and mounted only
`rpool/ROOT/openindiana`.  These mode-preserving backups were made before
mutation:

```text
/etc/svc/repository.db.pre-startup-repair-20260826T224159Z
/etc/rc2.d/S99niagara.pre-startup-repair-20260826T224159Z
```

The same-version `svccfg` manual documents its offline `repository repfile`
subcommand.  Using that selector against `/a/etc/svc/repository.db`, the trial
read `general/enabled boolean true` for
`svc:/system/filesystem/root:media`, set only that property false, and read
back `general/enabled boolean false`.  The offline helper
`svc.configd -r /a/etc/svc/repository` remained orphaned as PID 213 after
`svccfg` exited; `fuser -c /a` identified it as the sole holder.  Normal TERM
ended only that helper while the rescue system's live configd PID 10 remained.

The second repair changed exactly one line and preserved root:bin mode 0755:

```diff
-DEV=${NIAG_CHAN_DEV:-/dev/rdsk/c4d1s2}
+DEV=${NIAG_CHAN_DEV:-/dev/rdsk/c1d1s2}
```

`sync`, `zpool sync rpool`, and `zpool status -x rpool` passed; the bootfs then
unmounted and `rpool` exported cleanly.  Rescue QEMU PID 2956870 was retired by
one HMP `quit`, never a signal or terminal interrupt.

Fresh run `workstation-fix-verify-01` launched the same isolated units
100/101/103/104 with 8192 MiB and four CPUs as QEMU PID 3063953.  Because the
serial socket uses `wait=off` and its viewer attached three seconds after QEMU,
the initial firmware text was lost; one blank Return proved the already-waiting
literal OBP `ok`.  The sole boot command was:

```text
boot /virtual-devices@100/disk@4:a -k -v
```

Cold-root acceptance passed: unit 104 attached at exact `0xf00000000` and the
kernel reported `root on rpool/ROOT/openindiana fstype zfs`.  Verification then
failed at 16:19:50 PDT: immediately after another
`svccfg apply /etc/svc/profile/generic.xml failed`, the identical
`root-minimal` dependency cycle containing `root:media` reappeared.  Therefore
the offline `general/enabled=false` write was real but not an effective durable
disable across boot/profile processing.  rc2 did not run, and neither
`guest-chand` nor `pppd` could be accepted.  No further guest input was sent;
verification QEMU PID 3063953 and preserved PID 2719062 remain alive.

The next discriminating repair must inspect the offline effective-enable and
override layers, plus the generic-profile import path, before mutation.  Do not
repeat the already-failed `general/enabled=false` write as if it were an
untried fix.  The one-line unit-101 device correction remains independently
valid but cannot be runtime-tested until the SMF cycle is removed.

### Live SMF recovery and isolated PPP acceptance

The preserved verification VM subsequently reached a usable root login without
a reboot.  Live readback showed `root:media` disabled with
`general/enabled=false` and no `general_ovr`, while `root-minimal` remained in
maintenance with the same structural cycle.  `milestone/multi-user:default`
nevertheless transitioned online at 16:36:31 PDT and its log proved that SMF
ran `/sbin/rc2 start`.  `/etc/rc2.d/S99niagara` exited zero.  The corrected
device was present as:

```text
/dev/rdsk/c1d1s2 -> ../../devices/virtual-devices@100/disk@1:c,raw
```

Both `guest-chand` instances started.  The original channel-0 PPP attempt
connected locally, sent ten LCP requests without a host peer, and exited.  No
manual full `S99niagara` or `/sbin/rc2 start` was run.  One follow-up defect was
identified: the S-prefixed backup
`S99niagara.pre-startup-repair-20260826T224159Z` was also treated as an rc2
startup script and executed.  Future backups must not retain an `S*` basename
inside `/etc/rc2.d`.

At 16:52 PDT, the live VTOC of the isolated 33,554,432-byte unit-101 image was
reverified: label magic `0xDABE`, checksum XOR zero, slice 2 at sector 0 for
65,280 blocks, and slice 7 at sector 640 for 32,768 blocks.  The published
channel host base therefore remained exact byte 327,680.  Host admission proved
no `ppp0`, no `10.0.5.1` address/route, and no live host `pppd`.  The existing
scoped NAT rule for `10.0.5.15/32` through `eno51` and IPv4 forwarding were
already active and were not modified.

The run-scoped bridge adopted the live control state rather than reinitializing
it:

```text
ch0 h2g seq=95 len=14 ack=77 | g2h seq=78 len=45 ack=95
host bridge: image byte 327680 my_seq=95 peer_seq=78
bridge PID 3198609
socket /home/ryan/devel/masa-sun4v/ci/runs/workstation-fix-verify-01/host-chan0.sock
log    /home/ryan/devel/masa-sun4v/ci/runs/workstation-fix-verify-01/host-chan0.log
```

An initial unprivileged host-PPP admission attempt exited immediately and was
preserved as a failed run-local PID/log; no guest action had occurred.  The
documented `sudo -n` launch then started the canonical host peer with symmetric
`asyncmap 0` and `10.0.5.1:10.0.5.15`.  Only
`/lib/niag/guest-ppp-chan.pl` channel 0 was restarted in the guest.  Host journal
evidence showed LCP and IPCP acknowledgements followed by:

```text
local  IP address 10.0.5.1
remote IP address 10.0.5.15
```

The guest independently reported `sppp0` UP, POINTOPOINT, and RUNNING at
`10.0.5.15 --> 10.0.5.1`, with default route `10.0.5.1`.  Bounded acceptance
canaries returned literally:

```text
10.0.5.1 is alive
8.8.8.8 is alive
```

`/etc/resolv.conf` contains `nameserver 8.8.8.8`; DNS was not exercised because
the requested acceptance ended at IP reachability.  At final observation the
bridge, host `pppd` ownership chain, guest `pppd`, both QEMUs (PIDs 2719062 and
3063953), and both guest channel daemons remained alive.  No SIGUSR2, NFS, QEMU
lifecycle action, or reboot occurred.

### Live NFSv3/TCP acceptance

The existing Biggie export required no mutation.  Host preflight showed
`/export/solaris` exported to exact `10.0.5.15/32`, rpcbind on TCP/UDP 111,
mountd versions 1 through 3, and NFS versions 3 and 4 on TCP 2049.  The guest
independently reached TCP ports 111 and 2049 through its live PPP route.

The sole mount attempt was guarded by `/usr/bin/timeout -k 2 30` and used:

```text
/sbin/mount -F nfs -o ro,vers=3,proto=tcp,rsize=8192,wsize=8192 10.0.5.1:/export/solaris /mnt/nfs
```

It returned `MOUNT_RC:0`; a subsequent exact-process check returned
`NO_MOUNT_ORPHAN`.  Guest mount-table evidence retained all requested options:

```text
/mnt/nfs on 10.0.5.1:/export/solaris remote/read only/setuid/devices/vers=3/proto=tcp/rsize=8192/wsize=8192
```

The 28-byte canary read literally
`OI_WARM_NET_BIGGIE_20260826`.  A bounded `/dev/null` read of
`chan/xpg4.tar` transferred 1,730,560 bytes in 7.254394 seconds (233 KiB/s) and
returned `READ_RC:0`.  Server NFSv3 read calls increased from 74 to 287, with
zero bad RPC calls, independently confirming the data path.  One guest
`sppp0: bad fcs (len=1504)` diagnostic appeared during that sample; the read
still completed successfully and PPP remained up.  The run-local bounded packet
capture recorded 43 packets with zero kernel drops.

At the final NFS gate, the read-only mount, bridge PID 3198609, host PPP chain,
guest PPP/channel daemons, preserved QEMU PID 2719062, and verification QEMU PID
3063953 all remained alive.  No export, firewall, DNS, iSCSI, SIGUSR2, QEMU
lifecycle, or reboot action occurred.

### Installed developer-tool inventory

The live installed system identifies as `SunOS 5.11 illumos-31d3d510d0 sun4v`
with 64-bit sparcv9 kernel modules.  The root dataset had 45.97 GiB available,
`/tmp` had 4.83 GiB available, and the read-only NFS mount had 32.87 GiB
available.

Existing userland capabilities were:

```text
cc       absent
gcc      absent
clang    absent
git      absent
gmake    absent
make     /usr/bin/make, present but unusable
perl     5.42.0, sun4-solaris-thread-multi-64
python   3.9.25
python3  3.9.25
pkg      /usr/bin/pkg, present but bounded queries time out
```

`/usr/bin/make` is a 32-bit SPARC32PLUS executable.  `ldd` proved both
`libstdc++.so.6` and `libgcc_s.so.1` missing; execution also reported an
unresolved `__register_frame_info` from `/lib/libumem.so.1`.  It is therefore
not an accepted make capability.

The installed IPS image names publisher `openindiana.org` with configured
origin `https://pkg.openindiana.aurora-opencloud.org/oi-sparc/` and sparc/full
variants.  Guest `getent hosts` returned `DNS_RC:2` for that exact hostname.
Both `pkg publisher` and `pkg list -Hv entire` hit their 30-second watchdogs
with return code 124.  The on-disk publisher cache contained an exact
`developer/build/make` manifest and `system/library/gcc-13-runtime`, but no
compiler package manifest; no compiler FMRI was guessed.

The single authorized package operation was:

```text
/usr/bin/timeout -k 5 60 /usr/bin/pkg refresh --full
```

It returned `PKG_REFRESH_RC:124`, produced an empty saved log at
`/var/tmp/devtools-pkg-refresh-20260826.log`, and left `NO_PKG_ORPHAN`.
`/var/pkg/modified`, its lock, and package-history timestamps remained at
12:33 PDT, independently showing that no package transaction completed.  No
install or hello-world compile was attempted because the configured catalog
could not be queried and a compiler package could not be named mechanically.
The typed gate result is `DEVTOOLS_FAIL_DNS_TIMEOUT`.

### Live DNS repair and post-DNS IPS discriminator

Read-only diagnosis separated resolver transport from NSS policy.  The exact
pre-repair state was:

```text
hosts:      files
ipnodes:    files
svc:/network/dns/client:default  disabled
/etc/resolv.conf                 root:root 0644, 19 bytes
nameserver 8.8.8.8\n
```

A bounded direct query to `@8.8.8.8` succeeded and returned the configured
publisher CNAME plus address `65.21.23.2`.  Therefore PPP, routing, the resolver
address, and direct DNS transport were already good; the precise failure was
that NSS never consulted DNS.  Before mutation, the system preserved this
mode-preserving backup outside any rc startup namespace:

```text
/etc/nsswitch.conf.pre-dns-repair-20260827T002229Z
```

The smallest repair changed exactly two lines in installed
`/etc/nsswitch.conf`:

```diff
-hosts:      files
-ipnodes:    files
+hosts:      files dns
+ipnodes:    files dns
```

No DNS SMF service mutation was necessary.  Bounded NSS canaries then resolved
both `pkg.openindiana.aurora-opencloud.org` and `example.com` with return code
zero.  This is `DNS_PASS`.

IPS remained independently blocked after DNS was repaired.  A single bounded
`pkg publisher` retry timed out after 45 seconds with `PUBLISHER2_RC:124`.  The
single post-DNS catalog refresh used a 90-second watchdog and distinct log:

```text
/var/tmp/devtools-pkg-refresh-after-dns.log
```

It returned `REFRESH2_RC:124`, left an empty log, and the exact-process check
reported `NO_PKG_ORPHAN`.  Since the live catalog never became queryable, no
compiler FMRI could be established mechanically; no package was installed or
guessed, and no hello-world compile was attempted.  The terminal results are
`PKG_CATALOG_FAIL_IPS_CLIENT_TIMEOUT` and `DEVTOOLS_FAIL`.  PPP, read-only NFS,
the host bridge and PPP chain, guest channel/PPP processes, and both QEMUs were
preserved throughout.

### Instrumented IPS publisher discriminator

The package image lock and modified markers were both zero-byte files last
modified at 12:33 PDT.  `fuser /var/pkg/lock` reported no holder before or after
the test.  One read-only publisher invocation ran under a hard 35-second
watchdog and `truss -f`, producing these guest artifacts:

```text
/var/tmp/pkgpub.truss
/var/tmp/pkgpub.out
/var/tmp/pkgpub.ps
/var/tmp/pkgpub.ptree
/var/tmp/pkgpub.pstack
/var/tmp/pkgpub.pfiles
/var/tmp/pkgpub.watchdog.pid
```

At the live ten-second inspection boundary the ownership chain was
`timeout(3867) -> truss(3868) -> python3.9 pkg publisher(3869)`.  At 24 seconds,
the Python process was runnable (`R`), had consumed 15 CPU seconds, and was using
41.7 percent CPU.  It was not asleep on a lock or external event.  `pstack` and
`pfiles` were invoked as required but Solaris correctly refused a second
`/proc` controller while `truss` owned the process (`process is traced`); the
empty output files and literal refusals were retained.

The 70.08 KiB trace contained 1,544 syscall records.  Its terminal activity was
continuous successful `stat`, `open`, `fstat`, `read`, and `close` processing of
Python 3.9 standard-library bytecode, ending while opening
`/usr/lib/python3.9/__pycache__/gettext.cpython-39.pyc`.  A targeted scan found
no `connect`, `socket`, `/var/pkg/lock`, `/dev/random`, `/dev/urandom`,
`configd`, `door_call`, or `pollsys` entry.  Thus it never reached publisher
DNS/TLS or the package image lock and was not waiting on configd or entropy.

The watchdog returned 124 and a terminal exact-process check reported
`NO_PKG_ORPHAN`; the package lock remained holder-free.  Evidence therefore
types the boundary as `IPS_STALL_PYTHON_STARTUP_CPU_IO`: extremely slow IPS
Python/client initialization through many completed local filesystem and import
operations, not an opaque network timeout or deadlock.  No safe reversible
local correction was identified, so no retry, refresh, catalog query, package
install, or cache/lock deletion followed.  All live basecamp services and both
QEMUs remained preserved.

### Native GCC13 and extended IPS completion window

The direct OpenIndiana GCC13 convention check found no compiler at
`/usr/gcc/13/bin/gcc`; in fact `/usr/gcc/13/bin` is absent.  The installed
`/usr/gcc/13/lib/sparcv9` contains only the 64-bit SPARCV9 GCC runtime set,
including `libgcc_s.so.1`, `libstdc++.so.6.0.32`, `libatomic`, `libgomp`, and
`libssp`.  Runtime libraries therefore must not be mistaken for a working
native compiler, and no direct hello-world compile was possible.

The truss result justified one longer, non-traced completion window.  This
exact invocation was saved separately from all earlier probes:

```text
/usr/bin/timeout -k 5 600 /usr/bin/pkg publisher \
  >/var/tmp/pkgpub-10m.out 2>/var/tmp/pkgpub-10m.err
```

It completed normally with `PKGPUB10M_RC:0`, empty stderr, and the configured
online origin:

```text
openindiana.org  origin  online  F  https://pkg.openindiana.aurora-opencloud.org/oi-sparc/
```

It returned before the two-minute live sample, so no five-minute sample was
applicable.  The next and only mechanical catalog query was bounded by the
same ten-minute watchdog and retained in
`/var/tmp/pkg-catalog-tools.{out,err}`:

```text
/usr/bin/pkg list -a '*gcc*' 'developer/build/make'
```

This process remained runnable and CPU-active throughout: at 02:35 it had
02:02 CPU and 46.3 percent CPU; at 04:57 it had 04:06 CPU and 91.0 percent
CPU; at 08:50 it had 07:41 CPU and 91.6 percent CPU.  Both output files stayed
empty.  The watchdog ended it with `CATALOG_RC:124`, and the exact-process
postcheck returned `NO_CATALOG_ORPHAN`.  This is
`PKG_CATALOG_TOO_SLOW`: publisher configuration is queryable, but this guest
cannot finish a live compiler/make catalog enumeration inside ten minutes.
Because no exact compiler FMRI was established, no package name was guessed,
no install was attempted, and the final gate remains `DEVTOOLS_FAIL`.

The host-side Tribblix fallback inventory found intact, testable archives in
the existing read-only export:

```text
/export/solaris/tribblix-batch/toolpkgs/TRIBv-gcc7.7.3.0.4.0.zap                 55330615
/export/solaris/tribblix-batch/toolpkgs/TRIBdev-gnu-binutils.2.39.0.zap          10149434
/export/solaris/tribblix-batch/toolpkgs/TRIBsys-header.0.34.zap                   4392590
/export/solaris/tribblix-batch/toolpkgs/TRIBdev-build-gnu-make.4.4.1.0.zap         572390
/export/solaris/tribblix-installed-root-stage-20260821/pkgs/TRIBsys-lib-c-runtime.0.34.zap 13102
```

The four tool/header archives pass `unzip -t`, identify `ARCH=sparc`, and the
GCC archive targets `sparc-sun-solaris2.11`.  Its compiler is ELF32
SPARC32PLUS with SPARCV9 CRT/runtime content; the make binary is ELF64 SPARCV9.
However, the archives retain Tribblix package and C-runtime prerequisites and
have not been proven as an OpenIndiana-compatible transplant.  Nothing was
copied into the guest.  PPP, read-only NFS, host channel/PPP processes, and
both QEMUs remained alive at the final 2026-08-27T00:56:10Z host check.

### Exact-FMRI bounded developer-tool install

Host-side depot catalog and manifest inspection subsequently proved these two
exact SPARC FMRIs without relying on the slow guest catalog query:

```text
pkg://openindiana.org/developer/gcc-13@13.4.0,5.11-2026.0.0.2:20260711T141806Z
pkg://openindiana.org/developer/build/gnu-make@4.4.1,5.11-2025.0.0.0:20250325T072357Z
```

Only those two requested FMRIs were passed to one guest install, with IPS left
to resolve their manifest-declared dependencies:

```text
/usr/bin/timeout -k 10 1200 /usr/bin/pkg install --accept "$G" "$M" \
  >/var/tmp/devtools-install.out 2>/var/tmp/devtools-install.err
```

The real worker remained runnable and CPU-active throughout.  The bounded
samples were:

```text
elapsed  worker state  CPU time  CPU%   output bytes  semantic stage
02:08    R             01:43     77.4   0             startup
04:11    R             03:26     82.3   0             startup
06:15    R             05:07     82.2   86            refresh done; caching catalogs
08:22    R             06:53     79.1   86            caching catalogs
10:26    R             08:36     82.6   86            caching catalogs
12:30    R             10:19     82.4   86            caching catalogs
14:36    R             12:11     88.1   86            caching catalogs
16:41    R             14:04     90.1   118           caching done; solver setup
18:42    R             15:56     91.7   118           solver setup
```

The 20-minute watchdog was allowed to decide and returned
`INSTALL_RC:124`.  Stderr remained empty, stdout ended literally at
`Planning: Solver setup ...`, and the terminal process check returned
`NO_INSTALL_ORPHAN`.  IPS's own history independently records
`rebuild-image-catalogs` as succeeded, `refresh-publishers` as succeeded, and
the parent install as `Canceled, None` from 20260827T011623Z through
20260827T013414Z.  The package lock had no holder afterward.  Neither
`/usr/gcc/13/bin/gcc` nor `/usr/bin/gmake` exists, so no partial tool install
was accepted and no hello-world test was possible.

The typed result is `DEVTOOLS_FAIL_IPS_SOLVER_TIMEOUT`: repository transport,
catalog refresh, and local catalog rebuild passed, but dependency solver setup
did not complete within the authorized 1,200 seconds.  No retry or guessed
package substitution followed.  The preserved QEMU, isolated QEMU, host
channel bridge, PPP chain, and NFS-backed live basecamp were not stopped or
reconfigured.

### Cache-reuse install discriminator

Because the first exact-FMRI attempt durably completed publisher refresh and
local catalog rebuild, one non-refreshing discriminator reused that accepted
state rather than repeating the same experiment:

```text
/usr/bin/timeout -k 10 1200 /usr/bin/pkg install --no-refresh --accept "$G" "$M" \
  >/var/tmp/devtools-install-norefresh.out \
  2>/var/tmp/devtools-install-norefresh.err
```

`G` and `M` remained the exact catalog-and-manifest-proven GCC13 and GNU make
FMRIs recorded above.  Samples confirmed that cache reuse materially changed
the boundary:

```text
elapsed  worker state  CPU time  CPU%   output bytes  semantic stage
02:10    R             01:59     88.8   0             startup
04:19    R             03:57     91.8   0             startup
06:30    R             05:59     91.1   26            solver setup
08:56    R             08:13     90.9   26            solver setup
11:16    R             10:23     91.4   26            solver setup
14:09    R             13:03     91.7   26            solver setup
16:31    R             15:15     91.8   26            solver setup
```

The solver returned before the watchdog with `NOREFRESH_RC:1` and this exact
diagnosis:

```text
No matching version of developer/gcc-13 can be installed:
  Reject: pkg://openindiana.org/developer/gcc-13@13.4.0-2026.0.0.2
  Reason: This version is excluded by installed incorporation
          consolidation/userland/userland-incorporation@0.5.11-2026.0.0.32451
```

IPS history retained the corresponding `PlanCreationException` and solver
trace.  The terminal checks returned `NO_INSTALL_ORPHAN`, showed no package
lock holder, and confirmed that `/usr/gcc/13/bin/gcc` and `/usr/bin/gmake`
remain absent.  Therefore no transaction or partial developer-tool install
was accepted, and compile/runtime/non-regression gates were not applicable.

The typed result is `DEVTOOLS_FAIL_INCORPORATION_VERSION_EXCLUDED`.  This is a
version-policy incompatibility between the installed image incorporation and
the exact current publisher GCC13, not DNS, transport, catalog, lock, CPU
stall, or an arbitrary timeout.  Per the bounded test rule, no retry, image
upgrade, incorporation change, or alternate package substitution followed.
Both QEMUs and all channel, PPP, and NFS services were preserved.

### Historical incorporation compatibility resolution

A host-only query attempted to resolve versions allowed by the installed
`userland-incorporation@0.5.11-2026.0.0.32451`.  The retained publisher catalog
and depot search expose only current incorporation `...34549`; the exact
historical `...32451` manifest request returned HTTP 404, and no GCC13 or GNU
make records matching epoch 32451 remain.  The current 34549 manifest pins
GCC13 `13.4.0-2026.0.0.2` and GNU make `4.4.1-2025.0.0.0`, but those constraints
cannot be attributed to the installed epoch; its GCC13 was already rejected by
the installed solver.  The fail-closed result is
`BLOCKED_HISTORICAL_INCORPORATION_MANIFEST_PRUNED`.  Evidence is retained under
`workstation-fix-verify-01/host-incorporation-resolution-20260827/`.  No guest
input, package action, disk change, or VM/network lifecycle action occurred.

### Tribblix NFS toolchain closure audit

Copies of the available GCC7, GNU make, binutils, system-header, C-runtime,
flex, and msgpack-c archives were extracted into a run-scoped host directory.
The payload includes SPARC GCC/cc1/collect2, make, as/ld, headers, and 32/64-bit
CRT objects, but it is not a self-contained NFS closure.  Exact missing package
prerequisites are `TRIBgcc4runtime`, `TRIBsys-lib-math`, `TRIBsys-library`,
`TRIBlib-zlib`, and `TRIBgnu-m4`.  Corresponding gaps include shared
`libgcc_s.so.1`, `libstdc++.so.6`, and `libz.so.1`; GCC also embeds its absolute
`/usr/versions/gcc-7` prefix and system assembler/linker paths.  Raw ZIP
extraction does not materialize SVR4 pkgmap SONAME links.  The fail-closed
result is `TOOLCHAIN_BUNDLE_BLOCKED`; no guest acceptance command was claimed.
Evidence is retained under
`workstation-fix-verify-01/tribblix-toolchain-bundle-audit-20260827/`.  Source
archives, guests, QEMUs, and live network services were untouched.

A follow-up exact-name search under `/export/solaris` and read-only `isoinfo`
enumeration of all known Tribblix installer ISOs found only
`TRIBgnu-m4.1.4.19.0.zap`.  `TRIBgcc4runtime`, `TRIBsys-lib-math`,
`TRIBsys-library`, and `TRIBlib-zlib` remain absent as standalone files and ISO
package members, although the media catalogs independently name them as exact
GCC7/binutils prerequisites.  The raw UFS image was not archive-readable by
`bsdtar` and was not mounted.  The typed result is
`BLOCKED_MISSING_ARCHIVES`; no partial extraction or misleading closure rerun
followed, and no media was mounted, hashed, or modified.
