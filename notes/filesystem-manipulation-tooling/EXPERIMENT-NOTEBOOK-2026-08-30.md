# Niagara boot-unit experiment notebook

Date opened: 2026-08-30  
Time standard: UTC unless marked otherwise  
Scope: OpenIndiana SPARC boot repair and repeatable boot-unit assembly on
Tribblix

## Notebook discipline

Each experiment entry records:

- the live run identity and artifact identity;
- the observation layer: OpenBoot, guest userland, guest kernel, QEMU, or host;
- the command or action;
- whether the action observes or changes state;
- the result, including negative results;
- the next test justified by that result.

Source images remain immutable. Work happens in named copies or overlays. A
candidate must record its inputs, byte ranges, hashes, assembly commands, and
output hash. Volatile identifiers such as PIDs, console target IDs, and socket
paths must be rediscovered after a restart.

## Development objective

The development cycle is:

```text
assemble candidate boot unit on Tribblix
    -> boot a disposable QEMU trial
    -> observe OpenBoot and OpenIndiana SPARC
    -> identify a required change
    -> extract and modify the relevant component
    -> assemble and identify the next candidate
```

## Accepted three-unit boot contract

Recorded 2026-08-30 after the login-proven OpenIndiana run. These roles are
deliberate and must not be inferred again from unit numbers:

| QEMU unit | Role | Persistence and format |
| ---: | --- | --- |
| 100 | Channel carrier only: framed host/guest channels used by PPP, BBS, rootpty/console, and related transports | Disposable RAM-backed **plain raw** image; recreate and initialize for each run |
| 103 | Firmware-facing boot media: the place OpenBoot finds the kernel and boot archive | Persistent boot artifact; OpenBoot boots `disk@3` |
| 104 | OpenIndiana root filesystem | Current persistent 60 GiB raw disk containing the ZFS root that reached the login prompt |

The intended boot sequence is therefore: OpenBoot loads the kernel and boot
archive from unit103, that early boot environment hands root to the ZFS pool on
unit104, and unit100 supplies transport only. Unit100 contains no authoritative
boot or root state and must never be described or searched as a boot/root disk.

The channel helper contract requires QEMU and `host-chan.py` to access the same
plain raw unit100 object. A qcow2 overlay violates that contract because guest
writes land in the overlay while the direct-offset host helper reads the raw
backing. For this topology, unit100 should be a RAM-backed raw object rather
than the run-local qcow2 overlay used by the current login-proof launcher.

### EXP-20260830-28: channel/PPP/BBS preflight on the proven login run

Time: 2026-08-30T18:43Z–18:45Z

Live run identity: `oi-login-raw-20260829T101109Z-20588`, QEMU PID 20615 on
`ec2trib`, console target `786b00d8c183d3d60e3102ed`.

Artifact identities:

- unit100 role: carrier/channel;
- QEMU unit100 frontend:
  `/tink/runs/oi-login-raw-20260829T101109Z-20588/disks/carrier-unit100.qcow2`;
- unit100 raw backing:
  `/tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img`;
- helper bundle SHA-256:
  `621cd03b5b53bea400eebb694e339031376ca9f0a07fcdf0493dfcaee75555b8`;
- installed guest `guest-chand` SHA-256:
  `5140f20cb0845d19867039aa3648c15fe00b0e91f340f1f3607a4b1c3f6a3e62`;
- installed guest `guest-ppp-chan.pl` SHA-256:
  `8ef65b0769d0cc823207b28e6c8bd1153508a1fa7cb836577ac43501c8cc2979`.

Layer: unit100 shared-disk mailbox transport and host/guest support processes.

Hypothesis: the helpers can be started on the current login-proven guest after
identifying the exact shared unit100 object, channel placement, and existing
writers.

Prediction: safe startup requires QEMU and `host-chan.py` to read and write the
same plain raw file. The dedicated carrier maps host byte 327680 to guest
`/dev/rdsk/c1d0s2` block 640.

Action and mutation class: read-only topology/process inventory; a parser-only
guest test using a nonexistent device; staging helper sources; launcher repair.
No mailbox was initialized, no bridge/PPP/BBS daemon was started, QEMU was not
signalled, and no network route was changed.

Commands:

```sh
pargs -l 20615
qemu-img info --backing-chain \
  /tink/runs/oi-login-raw-20260829T101109Z-20588/disks/carrier-unit100.qcow2
pfiles 20615
qemu-img map --output=json \
  /tink/runs/oi-login-raw-20260829T101109Z-20588/disks/carrier-unit100.qcow2
pgrep -lf 'host-chan.py|host-bbs.py|pppd|socat|qemu-system'
zap search ppp
zap install TRIBsys-net-ppp
pkginfo -l TRIBsys-net-ppp
/usr/bin/pppd --version
```

Guest console preflight:

```sh
pgrep -lf 'guest-chand|guest-echocli|guest-ppp-chan|pppd|guest-rootpty|socat'
ls -l /tmp/niag* /var/tmp/*chan* /var/tmp/*ppp*
ls -l /dev/rdsk/c1d0s2 \
  /devices/virtual-devices\\@100/disk\\@0:c,raw
digest -a sha256 /opt/niag/bin/guest-chand \
  /opt/niag/bin/guest-ppp-chan.pl
NIAG_CHAN_DEV=/no/such/device NIAG_CHAN_GUEST_BLK=640 \
  /opt/niag/bin/guest-chand 15 /tmp/niag-parser-test
```

Helper staging from Minnie:

```sh
tar -czf /private/tmp/niag-channel-helpers-20260830.tar.gz \
  tools/chan/chan.h tools/chan/host-chan.py tools/chan/chan-test.py \
  tools/chan/host-bbs.py tools/chan/host-pppd-once.sh \
  tools/chan/guest-dial.pl
shasum -a 256 /private/tmp/niag-channel-helpers-20260830.tar.gz
scp /private/tmp/niag-channel-helpers-20260830.tar.gz \
  root@ec2trib:/tink/runs/oi-login-raw-20260829T101109Z-20588/
```

The bundle was unpacked under
`/tink/runs/oi-login-raw-20260829T101109Z-20588/helpers/tools/chan/`.

Result:

- no host or guest channel, PPP, BBS, echo, or rootpty helper was already
  running;
- the guest unit100 whole-disk raw node is `/dev/rdsk/c1d0s2`;
- the installed guest daemon accepted `NIAG_CHAN_GUEST_BLK=640`; it reached the
  expected open failure on `/no/such/device`, so the test touched no disk;
- the initial host probe checked `/usr/sbin/pppd` and missed Tribblix's package
  location. `zap search ppp` identified `TRIBsys-net-ppp`; installing it placed
  native pppd 2.4.0b1 at `/usr/bin/pppd` and installed/loaded the amd64 `sppp`,
  `sppptun`, `spppasyn`, and `spppcomp` components. `/dev/sppp` and
  `/dev/sppptun` are present, and no pppd process was left running;
- QEMU has the raw carrier backing open read-only and the run-local qcow2
  overlay open read/write.

Interpretation: starting `host-chan.py` against the raw backing would be
incorrect. Guest writes go through QEMU into the qcow2 overlay while the host
bridge would read the backing file. The two peers would cease to share a
mailbox as soon as either side wrote. Concurrently modifying qcow2 metadata
with a second image writer is also unsafe. This live run therefore requires a
restart with a run-local raw carrier before the requested channel helpers can
be started.

Artifacts created:

- the verified helper bundle and unpacked helper tree in the live run;
- `helpers/run-sun4v-ec2trib-login-raw-trial.next.sh` on ec2trib;
- a local launcher repair in
  `scripts/run-sun4v-ec2trib-login-raw-trial.sh`: create a sparse raw carrier
  with the exact command
  `qemu-img convert -q -f raw -O raw -S 4096 "$CARRIER_BASE" "$RUN_DIR/disks/carrier-unit100.raw"`,
  attach it as `format=raw`, and record byte 327680 ↔ guest block 640 in the
  run manifest.
- `tools/chan/host-pppd-once.sh` now locates either `/usr/sbin/pppd` or
  Tribblix's `/usr/bin/pppd`, with an explicit `PPPD` override. `sh -n` and the
  invalid-override failure path passed; the updated wrapper was copied into the
  live run's helper tree.

Next test: after explicit authorization to stop and restart the login-proven
QEMU, launch it with the direct raw carrier, initialize channels 0 and 1 before
either daemon, start the two bridges and guest daemons, require the 65536-byte
echo gate, then attach the host PPP peer and BBS without assigning the same
channel socket to competing clients.

The current repair target is the boot archive. The running guest reached
maintenance mode because `/usr/bin/awk` is absent from the boot archive.
`devfsadm` invoked the missing program during device configuration and failed:

```text
/usr/sbin/devfsadm[38]: /usr/bin/awk: not found [No such file or directory]
NIAGARA_DEVFSADM_RW_GATE_FAIL: cannot parse mount table
```

A corrected boot archive must be placed into a bootable parent UFS image. That
image may replace the corresponding object in unit 103 or become a separate
boot unit, such as unit 106. A separate boot unit still needs a valid SPARC
VTOC, UFS boot support, the sun4v kernel and modules, and
`/platform/sun4v/boot_archive`.

### EXP-20260830-29: final inventory of the login-proven guest

Time: 2026-08-30T19:01Z–19:05Z (guest clock: 2026-08-29T10:34Z)

Live run identity: `oi-login-raw-20260829T101109Z-20588`, QEMU PID 20615 on
`ec2trib`, console target `786b00d8c183d3d60e3102ed`.

Layer: running OpenIndiana userland/kernel and its unit104 ZFS root.

Hypothesis: a bounded pre-restart inventory can preserve the exact working
kernel, root-pool, device, helper, and SMF identities without hashing the 60 GiB
disk or modifying boot state.

Action and mutation class: read-only guest queries, streamed through the Old
Sun console and appended to a new evidence file on the current unit104 root:

```sh
OUT=/var/tmp/niagara-login-baseline-20260830.txt

uname -a
isainfo -kv
hostname
eeprom boot-device
prtconf -b
df -h / /var /rpool
mount -p
zpool status -LPv rpool
zpool get guid,bootfs,cachefile,autoexpand,autoreplace rpool
zfs list -r -o name,used,avail,refer,mountpoint,mounted rpool
beadm list
cat /etc/system
cat /etc/vfstab
ls -l /platform/sun4v/boot_archive \
  /platform/sun4v/kernel/sparcv9/unix
digest -a sha256 /platform/sun4v/kernel/sparcv9/unix \
  /opt/niag/bin/guest-chand /opt/niag/bin/guest-echocli \
  /opt/niag/bin/guest-ppp-chan.pl /opt/niag/bin/guest-rootpty.sh \
  /opt/niag/bin/socat
iostat -En
find /dev/dsk /dev/rdsk -type l -ls
modinfo | egrep 'hsimd|zfs|sppp|sppptun|spppasyn|spppcomp'
find /kernel /usr/kernel -type f -name '*hsimd*' -ls
dmesg | egrep 'hsimd|virtual-device|root on|ZFS|rpool' | tail -240
svcs -xv
pgrep -lf 'guest-chand|guest-echocli|guest-ppp-chan|pppd|guest-rootpty|socat'
cksum "$OUT"
digest -a sha256 "$OUT"
```

The initial `pkg info entire` metadata query made no progress after roughly one
minute. It was interrupted with console Ctrl-C, recorded as
`PKG_INFO_ENTIRE=SKIPPED_STALLED`, and all remaining sections were executed in
bounded batches. The interrupt did not affect QEMU or another guest process.

Result:

- system: `SunOS oi-basecamp 5.11 illumos-31d3d510d0 sun4v sparc
  SUNW,Sun-Fire-T200`, 64-bit SPARC V9 kernel modules;
- OpenBoot property observed by `eeprom`: `boot-device=vdisk`;
- `/` is `rpool/ROOT/openindiana`;
- `zpool status -LPv rpool` proves the only rpool vdev is
  `/devices/virtual-devices@100/disk@4:a` (unit104), ONLINE with zero read,
  write, or checksum errors;
- rpool GUID: `18135893029031842473`;
- rpool `bootfs`: `rpool/ROOT/openindiana`;
- active BE: `openindiana`; inactive BE:
  `workstation-candidate-20260826`;
- `/etc/system` contains `set zfs:zfs_vdev_aggregation_limit=0x20000` and no
  explicit `rootdev` override; `/etc/vfstab` contains the rpool swap zvol but
  no static root entry;
- unit104's `/platform/sun4v/boot_archive` is 248,651,776 bytes, timestamped
  2026-08-29 03:28. It was identified by size/time only, not hashed;
- unit104's `/platform/sun4v/kernel/sparcv9/unix` SHA-256 is
  `300e2b11956675686a6864bbc398eff96ab0202017e7a996e2804c995807294c`;
- loaded hSIMD module reports `hsimd v0.0.6_aio2`; loaded PPP components include
  `sppp` and `sppptun`;
- the complete `/dev/dsk` and `/dev/rdsk` links for `disk@0`, `disk@1`,
  `disk@3`, and `disk@4` were captured;
- no channel, BBS, PPP-daemon, echo, or rootpty helper was running;
- SMF evidence preserves the disabled identity/cryptosvc services, offline
  multi-user-server milestone, and the root-minimal dependency-cycle
  maintenance state.

Artifact created inside unit104:

```text
/var/tmp/niagara-login-baseline-20260830.txt
size:   18312 bytes
cksum:  285267887 18312
sha256: db758f4081556e731061d7140adbddcf329a6f2ccf9f32907dce66ee3e1ebabd
```

The host QEMU transcript through `INVENTORY_COMPLETE` was copied to
`notes/filesystem-manipulation-tooling/boot-traces/oi-login-raw-20260829T101109Z-20588/console-through-final-inventory.log`:

```text
size:   39582 bytes
sha256: 1bfe4eea5f521902be976e08cf7125addfd11679104994ef278fe15c3bc40757
```

Interpretation: this is direct runtime proof—not an inference from QEMU argv—
that unit104 is the healthy ZFS root used by the login-proven guest. The
inventory file persists in that exact root image for later host-side extraction.

Next test: preserve the final host console transcript, shut down the guest
cleanly, and relaunch the same unit103/unit104 boot/root pair with unit100
replaced by the disposable RAM-backed plain raw channel carrier.

## Current laboratory

### Host

- Host: `ec2trib`
- Operating system: Tribblix, an illumos distribution
- Interactive control: Minnie tmux session `shareme`, pane `shareme:1.0`
- Current pane state: authenticated `root@ec2trib` shell

Tribblix provides illumos storage tools such as `lofiadm`, `fstyp`, `fsck`,
`prtvtoc`, `dd`, `od`, and `digest`. The QEMU launcher records
`/usr/bin/qemu-img` as its image tool. Native Tribblix x86 UFS tools do not
mount or repair SPARC big-endian UFS. Byte-level inspection and image assembly
remain valid on the host; filesystem-level SPARC UFS edits need a SPARC guest
or another byte-order-aware method.

### QEMU trial

Observed process identity:

```text
QEMU name: oi-basecamp
PID:       19686
Run:       /tink/runs/oi-basecamp-20260829T032052Z-19658
Machine:   niagara
Memory:    3072 MiB
vCPUs:     1
```

The PID and run directory are observations for this trial, not stable names.

### Guest

- Operating system: OpenIndiana SPARC
- Machine model: sun4v/Niagara
- State: maintenance-mode root shell
- Current console prompt: `root@openindiana:/#`
- Boot command used at OpenBoot:

```text
boot /virtual-devices@100/disk@3:a -k -v
```

The guest boot is reproducible to this state. Device configuration is
incomplete because of the boot-archive failure and current hSIMD storage-driver
behavior.

## QEMU storage presented to this trial

The live QEMU argv was read with `pargs -l 19686` on `ec2trib`.

| QEMU unit | Guest path | QEMU role | Backing object | Policy |
| ---: | --- | --- | --- | --- |
| 100 | `/virtual-devices@100/disk@0` | carrier/channel | run-local `carrier-unit100.qcow2` | writable overlay |
| 103 | `/virtual-devices@100/disk@3` | installer/boot media | `installer-unit103.img` | read-only |
| 104 | `/virtual-devices@100/disk@4` | root target | run-local `root-unit104.qcow2` | writable overlay |

Unit 100 activates the current QEMU hSIMD multi-disk scan and carries the
guest-sockets-over-storage transport. This trial uses the legacy 1 GiB carrier
form, which also contains a pre-staged guest payload. It is not the OpenBoot
source for this trial and must not be scanned as a candidate boot filesystem.

Unit 103 is the OpenBoot source. Its verified host identity is:

```text
path:   /tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img
size:   2791702528 bytes
sha256: e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c
```

The size and SHA-256 were computed visibly in `shareme:1.0`. No source bytes
were changed.

## Guest storage observations

The guest has physical device nodes for `disk@0`, `disk@3`, and `disk@4`, with
slice minors `a` through `h` and raw minors. Device aliases under `/dev` are
incomplete because `devfsadm` did not finish.

`fstyp` produced:

- `disk@0`: no recognized filesystem on the tested whole-device and slice
  minors;
- `disk@3`: every slice minor `a` through `h` reported `hsfs`;
- `disk@4`: no recognized filesystem on the tested whole-device and slice
  minors.

The `disk@3` results do not describe eight HSFS partitions. A sector-aligned
read at device byte offset 32769 returned the ISO-9660 identifier `CD001` from
every slice minor:

```text
slice a: CD001
slice b: CD001
slice c: CD001
slice d: CD001
slice e: CD001
slice f: CD001
slice g: CD001
slice h: CD001
```

The hSIMD slice geometry presented to the guest aliases all unit-103 slices to
the same start of the raw image. `fstyp` is correctly identifying the bytes it
receives. Slice names cannot currently be trusted to select the VTOC regions.

Raw hSIMD reads must be sector aligned. A one-byte read returned no data. A
512-byte device read followed by byte extraction from a pipe succeeded.

The four bytes at the canonical primary UFS magic location for a filesystem
starting at device byte zero, offset 9564, were zero. The sequence
`00 01 19 54` found at stream offset 575568 is therefore not the primary
superblock of a UFS filesystem starting at byte zero.

## Identity-matched unit-103 map from prior work

The verified unit-103 SHA-256 matches the image documented in
`notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md`.
That investigation recorded one SPARC big-endian UFS extent:

```text
start sector:        878408
start byte:          449744896
length:              192595968 bytes
end byte, exclusive: 642340864
```

The primary UFS magic is expected at image byte offset 449754460, which is the
extent start plus 9564. Backup superblocks were recorded within the same
extent. No UFS superblock was found in the appended slice-7 region.

Prior work also recorded a lossless split under:

```text
/tink/lab/images/IMG-20260828-unit103-ufs-split/
```

with `insideufs.raw` holding the 192595968-byte UFS extent. Its current
availability and identity have not yet been rechecked in this experiment.

## Console control

Two console paths are available at the same time.

The browser console permits human typing. The generated mcporter CLI permits
scripted discovery, status, reads, and writes without guest networking or SSH:

```text
/private/tmp/old-sun-console-cli.mjs
```

The current MCP target was observed as:

```text
host:      ec2trib
QEMU name: oi-basecamp
PID:       19686
socket:    /tink/runs/oi-basecamp-20260829T032052Z-19658/console.sock
target ID: 051ae14e49afe0176a7c7c88
```

The target ID is opaque and changes when QEMU restarts. The target must be
rediscovered and its host, PID, and socket confirmed before each write.

The broker originally retained its maximum 262144-byte history. MCP reads
failed because the control client received the full history before applying
the requested tail limit. Reselecting the current target cleared broker
history. MCP reads then worked. This is a broker read-path defect and a current
operational workaround.

Minnie tmux session `shareme` provides visible shared terminal work:

- `shareme:0.0`: local Minnie shell;
- `shareme:1.0`: root shell on `ec2trib`.

Agent tmux actions use `sane-list-panes`, `sane-look-at-pane`, and
`sane-send-keys`. Commands and their output remain visible to the human
operator.

## Observation capabilities

| Layer | Available observations | Status today |
| --- | --- | --- |
| OpenBoot | device paths, boot commands, firmware errors | used to boot `disk@3:a` |
| Guest userland | mounts, device nodes, raw reads, filesystem probes | used from maintenance shell |
| Guest illumos kernel | DTrace of device, filesystem, syscall, and driver paths | available through the serial console; new probes must be recorded here |
| QEMU process | argv, run files, QMP state, logs, process sampling | argv and exact drive topology verified |
| Host illumos kernel | DTrace around QEMU, storage calls, scheduling, and host kernel paths | bounded QEMU DTrace sampling performed |
| Host storage | raw-image reads, VTOC parsing, lofi, hashes, copies, QEMU image inspection | source size and hash verified |

A bounded host DTrace sample showed that QEMU remained active while the SPARC
guest booted. Event-loop and serial callbacks continued firing. Host DTrace
does not by itself prove guest boot progress; console output and guest probes
provide that evidence.

Guest DTrace and host DTrace answer different questions. Guest probes observe
the OpenIndiana kernel and hSIMD behavior. Host probes observe QEMU and the
Tribblix kernel. Each captured result must identify its layer.

## Current assembly problem

The candidate-building process needs to manipulate nested objects:

```text
unit-103 raw image
    -> bootable SPARC UFS extent
        -> /platform/sun4v/boot_archive
            -> filesystem used as the early guest root
```

The intended edit is to add the required `awk` binary and any dependencies to
the boot archive, rebuild the archive without changing its required boot
semantics, place it into a writable copy of the parent UFS, and assemble a new
QEMU boot-unit image.

Native Tribblix x86 `fstyp` and `fsck_ufs` reject the SPARC big-endian UFS
superblock. They must not be allowed to create a generic replacement
superblock. Candidate work may use the running SPARC guest for filesystem
mounts and edits while Tribblix handles immutable copies, byte ranges, hashes,
and final image assembly.

## Experiment log

### EXP-20260830-01: establish shared console control

Layer: console broker and guest serial  
Mutation: target reselection cleared broker history; later writes sent
read-only guest commands

Result:

- Current target identity matched `ec2trib` QEMU PID 19686.
- MCP typing was unblocked.
- The maintenance prompt was readable.
- Browser typing remained available.

### EXP-20260830-02: distinguish UFS and HSFS at unit-103 offset zero

Layer: guest block device  
Mutation: observation only

Commands used sector-aligned reads from `disk@3:a,raw`, then extracted bytes
from the pipe.

Result:

```text
UFS magic at offset 9564: 00 00 00 00
ISO identifier at offset 32769: CD001
```

Conclusion: the unit-103 stream begins with ISO/HSFS data, not a UFS
filesystem beginning at byte zero.

### EXP-20260830-03: test hSIMD slice aliasing

Layer: guest hSIMD device  
Mutation: observation only

Result: every unit-103 slice returned `CD001` at the same logical offset.

Conclusion: current hSIMD slice selection cannot expose the embedded UFS by
choosing another unit-103 slice minor.

### EXP-20260830-04: verify immutable unit-103 identity

Layer: Tribblix host storage  
Mutation: observation only

Commands executed visibly in `shareme:1.0`:

```sh
wc -c /tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img
digest -a sha256 /tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img
```

Result:

```text
2791702528 bytes
e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c
```

The source has not been copied or modified during this notebook session.

### EXP-20260830-05: revalidate the preserved split

Layer: Tribblix host storage  
Mutation: observation only

The recorded split directory exists:

```text
/tink/lab/images/IMG-20260828-unit103-ufs-split/
```

Observed artifact sizes:

```text
beforeufs.raw                449744896
insideufs.raw                192595968
afterufs.raw                2149361664
installer-unit103-copy.raw  2791702528
```

The preserved full copy returned the same SHA-256 as the live unit-103 source:

```text
e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c
```

A four-byte read at offset 9564 in `insideufs.raw` returned:

```text
00 01 19 54
```

Conclusion: the preserved full copy is byte-identical to the current unit-103
source, and `insideufs.raw` begins at the recorded SPARC UFS boundary.

### EXP-20260830-06: create the writable UFS candidate

Layer: Tribblix host storage  
Mutation: created a new directory and copied one preserved artifact

Free space on `/tink` was approximately 30 GiB. The candidate target did not
exist before creation.

Created:

```text
/tink/lab/images/IMG-20260830-unit106-bootufs-candidate-01/boot-ufs.raw
```

Source and candidate size:

```text
192595968 bytes
```

Source and candidate SHA-256:

```text
e547ed68b6656a54a4fdbdced97f73677f4bf0394320f083890fd7d3ceed65df
```

Conclusion: `boot-ufs.raw` is a writable, byte-identical pre-edit candidate.
The protected source and split artifacts remain unchanged.

### EXP-20260830-07: recover the prior ec2cicd workbench path

Layer: ec2cicd experiment records and saved guest consoles  
Mutation: observation only

The ec2cicd current-run marker names:

```text
workstation-ec2-ch8-20260826T210446Z
```

Its launch manifest records:

```text
unit 103: installer, read-only
unit 104: writable qcow2 overlay over the immutable workstation candidate
boot: boot /virtual-devices@100/disk@4:a -k -v
gate: reach login: without guest input
immutable root-base SHA-256:
964d10a2f0bba82bffb940db4e30c7fb111f27b6acd3400d0da6fe826ecc3fbd
```

`qemu-img info --backing-chain` identifies the immutable unit-104 base as:

```text
/srv/niagara/artifacts/workstation-candidate-20260826/images/extra-unit104-60g.img
raw, 64424509440 bytes
```

The saved console proves that this run booted from disk@4, selected
`rpool/ROOT/openindiana` as its ZFS root, and reached:

```text
oi-basecamp console login:
```

The same console also records an SMF dependency cycle. Therefore this is
evidence for a usable ZFS-root SPARC workbench and passage beyond the current
installer archive's awk/devfsadm failure, not evidence for a fully healthy
multi-user system.

A later saved maintenance console records the exact device-discovery
workaround used when the installer archive lacked `/usr/bin/awk`:

1. Mount `/devices/pseudo/lofi@1:disk` on `/usr` to expose the compressed
   Solaris payload directly, without relying on `/dev/lofi/1`.
2. Use the payload's `mknod` to replace stale disk@4 links with block/raw
   nodes for major 338, minors 32 (`s0`) and 34 (`s2`).
3. Run `zpool import`; this exposed rpool through `c1t4d0s0`.
4. Use files in rpool as lofi-backed UFS work objects.

That earlier session mounted three 500 MiB UFS images from rpool and copied a
192595968-byte `boot_archive` out of one of them to
`/rpool/rebuilt-boot-archive`. A separate single-user transcript records an
orderly shutdown updating `/platform/sun4v/boot_archive (CPIO)`.

Conclusion: ec2cicd contains a proven SPARC-side filesystem workbench recipe.
The essential boot source was unit104, not unit103.

### EXP-20260830-08: test today's unit104 lineage as a workbench

Layer: ec2trib host image chain and current OpenIndiana guest  
Mutation: four ephemeral `/dev/{dsk,rdsk}` nodes were replaced; no pool was
imported and no pool data was written

The live unit104 chain is:

```text
/tink/runs/oi-basecamp-20260829T032052Z-19658/disks/root-unit104.qcow2
  -> /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/root-unit104.qcow2
  -> /tink/disk-images/runs/workstation-playbox-known-good-20260827T165948Z/images/known-good-state.qcow2
  -> /mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
```

The immutable base path and timestamp correspond to the ec2cicd login-pass
artifact. The current guest exposes disk@4 with the same device numbers used
by the earlier workaround:

```text
disk@4:a      block 338,32
disk@4:a,raw  char  338,32
disk@4:c      block 338,34
disk@4:c,raw  char  338,34
```

The Solaris payload is already mounted at `/mnt/1`; it contains `awk`, `nawk`,
`ln`, and `sbin/mknod`. After recreating the four disk nodes, `zpool import`
found pool GUID `18135893029031842473` on `c1t4d0s0`, but reported the pool as
faulted. A forced, read-only, no-mount probe:

```sh
zpool import -f -o readonly=on -N rpool
```

failed with `cannot import 'rpool': I/O error`. No pool became available.

Conclusion: today's upper unit104 chain is not a usable workbench. This does
not disprove the immutable base, which has independent saved evidence of a
successful boot. Do not attempt in-place pool repair in the current chain.

### EXP-20260830-09: verify the immutable unit104 baseline identity

Time: 2026-08-30 17:17 UTC  
Layer: ec2trib host storage  
Mutation: observation only

Candidate:

```text
/mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
```

Observed size:

```text
64424509440 bytes
```

Command executed visibly in `shareme:1.0`:

```sh
digest -a sha256 /mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
```

Expected SHA-256 from the ec2cicd
`workstation-ec2-ch8-20260826T210446Z` launch manifest:

```text
964d10a2f0bba82bffb940db4e30c7fb111f27b6acd3400d0da6fe826ecc3fbd
```

Observed SHA-256 on ec2trib:

```text
964d10a2f0bba82bffb940db4e30c7fb111f27b6acd3400d0da6fe826ecc3fbd
```

Result: **PASS**. The immutable ec2trib raw image is byte-identical to the
unit104 base named by the saved ec2cicd run that booted disk@4, selected
`rpool/ROOT/openindiana`, and reached the console login prompt. This image is
the accepted source baseline for the next clone/import experiment.

### EXP-20260830-10: identify the outer ZFS ownership of unit104

Time: 2026-08-30 17:18 UTC  
Layer: ec2trib host storage  
Mutation: observation only

Test: determine whether the accepted unit104 baseline is already stored on a
local Tribblix ZFS filesystem that can provide snapshot/clone provenance.

Observed path resolution:

```text
/mnt/disk-images -> /tink/disk-images
```

`df -k` for the accepted image reported filesystem `tink`, mounted at
`/tink`. Direct ZFS queries returned:

```text
dataset:       tink
dataset type:  filesystem
mountpoint:    /tink
readonly:      off
checksum:      on
snapdir:       hidden
dataset GUID:  4707822291607400823
create txg:    1
pool GUID:     966488110517373488
```

Result: **PASS**. The accepted image already resides on local Tribblix ZFS,
so outer ZFS can provide integrity checking and snapshot/clone lineage.

Constraint discovered: ZFS snapshots operate on an entire dataset, not an
individual image file or directory. The accepted file currently resides in
the broad `tink` dataset. Do not snapshot all of `tink` as the normal trial
workflow. Create a dedicated child dataset for this project's controlled
baseline and trial artifacts before establishing the first named snapshot.

### EXP-20260830-11: create the dedicated outer ZFS dataset

Time: 2026-08-30 17:22 UTC  
Layer: ec2trib host storage  
Mutation: created one ZFS child filesystem

Precondition test:

```text
tink/qemu-sun4v-illumos-ci: dataset does not exist
/tink/qemu-sun4v-illumos-ci: MOUNTPOINT_UNUSED
```

Action executed visibly in `shareme:1.0`:

```sh
zfs create tink/qemu-sun4v-illumos-ci
```

Observed result:

```text
CREATE_STATUS=0
dataset:       tink/qemu-sun4v-illumos-ci
type:          filesystem
used:          24K
available:     30.0G
mountpoint:    /tink/qemu-sun4v-illumos-ci
dataset GUID:  2994193311312296752
create txg:    22194
checksum:      on
compression:   off
readonly:      off
snapdir:       hidden
```

A depth-one `find` returned no entries, confirming that the new filesystem is
empty.

Result: **PASS**. This project now has a dedicated outer ZFS snapshot domain.
Future snapshots of this child will not include unrelated contents of the
parent `tink` dataset. No baseline image has been copied into it yet, and no
snapshot has been created yet.

### EXP-20260830-12: make and verify the dedicated sparse baseline copy

Time: 2026-08-30 17:25-17:32 UTC  
Layer: ec2trib host storage  
Mutation: created `baselines/` and one raw sparse image in the dedicated ZFS
dataset

Tooling precheck: the ec2trib tooling audit found `/usr/bin/qemu-img` 8.1.5
with `convert -S sparse_size` support. No package installation was required.

Source:

```text
/mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
```

Destination:

```text
/tink/qemu-sun4v-illumos-ci/baselines/unit104-login-proven-20260826T210446Z.raw
```

Preconditions observed:

```text
destination: TARGET_UNUSED
dataset available: 30.0G
```

Exact conversion commands executed visibly in `shareme:1.0`:

```sh
mkdir /tink/qemu-sun4v-illumos-ci/baselines
qemu-img convert -p -f raw -O raw -S 4k \
  /mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img \
  /tink/qemu-sun4v-illumos-ci/baselines/unit104-login-proven-20260826T210446Z.raw
echo CONVERT_STATUS=$?
```

Conversion result:

```text
CONVERT_STATUS=0
```

Exact size, allocation, and metadata commands:

```sh
wc -c /tink/qemu-sun4v-illumos-ci/baselines/unit104-login-proven-20260826T210446Z.raw
du -h /tink/qemu-sun4v-illumos-ci/baselines/unit104-login-proven-20260826T210446Z.raw
zfs list -H -o used,referenced,available tink/qemu-sun4v-illumos-ci
qemu-img info --output=json \
  /tink/qemu-sun4v-illumos-ci/baselines/unit104-login-proven-20260826T210446Z.raw
```

Observed results:

```text
logical size:       64424509440 bytes
du allocation:      4.9G
qemu actual-size:   5224186368 bytes
dataset used:       4.87G
dataset referenced: 4.87G
dataset available:  25.2G
format:             raw
dirty flag:         false
```

Exact byte-equivalence command:

```sh
qemu-img compare -p -f raw -F raw \
  /mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img \
  /tink/qemu-sun4v-illumos-ci/baselines/unit104-login-proven-20260826T210446Z.raw
echo COMPARE_STATUS=$?
```

Comparison result:

```text
Images are identical.
COMPARE_STATUS=0
```

Result: **PASS**. The dedicated file is a sparse, byte-identical raw copy of
the already SHA-256-verified ec2cicd login-proven unit104 source. This full
logical-image comparison is a one-time import gate. After the first immutable
outer ZFS snapshot is established, routine trial identity should use recorded
snapshot/clone lineage rather than repeat this scan.

### EXP-20260830-13: establish and hold the authoritative baseline snapshot

Controller observation time: 2026-08-30 17:37 UTC  
ec2trib host time after the operation: 2026-08-29 09:51 UTC  
Layer: ec2trib outer ZFS  
Mutation: created one snapshot and one ZFS hold; no image content changed

Clock note: ec2trib's clock was approximately one day behind the controller
clock. Both observations are recorded rather than treating the host timestamp
as current UTC.

Precondition commands:

```sh
zfs list -H -t snapshot \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
zfs holds \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
```

Both commands reported that the snapshot did not exist.

Exact creation and hold commands executed visibly in `shareme:1.0`:

```sh
zfs snapshot \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
echo SNAPSHOT_STATUS=$?
zfs hold accepted-baseline \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
echo HOLD_STATUS=$?
```

Exact verification commands:

```sh
zfs list -H -t snapshot \
  -o name,guid,createtxg,used,referenced,written,userrefs \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
zfs holds \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
wc -c \
  /tink/qemu-sun4v-illumos-ci/.zfs/snapshot/baseline-unit104-login-proven-20260826T210446Z/baselines/unit104-login-proven-20260826T210446Z.raw
date
date -u
```

Observed result:

```text
SNAPSHOT_STATUS=0
HOLD_STATUS=0
snapshot GUID: 7270416549033559117
create txg:    22277
used:          0B
referenced:    4.87G
written:       4.87G
userrefs:      1
hold tag:      accepted-baseline
snapshot file logical size: 64424509440 bytes
```

Result: **PASS**. The byte-verified unit104 file now has an immutable,
held outer-ZFS identity. The snapshot GUID and hold tag, together with the
previously recorded source SHA-256, are the authoritative parent identity for
future writable trial clones.

### EXP-20260830-14: prove writable-clone isolation

Controller observation time: 2026-08-30 17:45 UTC  
Layer: ec2trib outer ZFS  
Mutation: created one writable ZFS clone and one empty probe file; no raw image
bytes were changed

Source snapshot:

```text
tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
```

Clone:

```text
tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
```

Precondition commands:

```sh
zfs list -H tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
test -e /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
```

The dataset did not exist and the mountpoint was unused.

Exact clone command:

```sh
zfs clone \
  tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z \
  tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
echo CLONE_STATUS=$?
```

Exact identity and inherited-image checks:

```sh
zfs get -H -o property,value \
  origin,guid,createtxg,used,referenced,mountpoint,readonly \
  tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
wc -c \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw
```

Observed before the probe write:

```text
CLONE_STATUS=0
origin:     tink/qemu-sun4v-illumos-ci@baseline-unit104-login-proven-20260826T210446Z
clone GUID: 3622654130444150513
create txg: 22326
used:       0B
referenced: 4.87G
readonly:   off
image size: 64424509440 bytes
```

Exact isolation probe:

```sh
touch \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/CLONE-WRITE-PROBE
test -f \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/CLONE-WRITE-PROBE \
  && echo CLONE_PROBE_PRESENT
test ! -e /tink/qemu-sun4v-illumos-ci/CLONE-WRITE-PROBE \
  && echo LIVE_PARENT_UNCHANGED
test ! -e \
  /tink/qemu-sun4v-illumos-ci/.zfs/snapshot/baseline-unit104-login-proven-20260826T210446Z/CLONE-WRITE-PROBE \
  && echo SNAPSHOT_UNCHANGED
sync
zfs list -H -o name,used,referenced,written \
  tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
```

Observed result:

```text
CLONE_PROBE_PRESENT
LIVE_PARENT_UNCHANGED
SNAPSHOT_UNCHANGED
post-write clone used:    15K
post-write clone written: 15K
clone referenced:         4.87G
```

Result: **PASS**. A trial clone can inherit the verified 60 GiB raw image at
zero initial additional cost, accept writes through normal ZFS copy-on-write,
and leave both the live baseline dataset and held snapshot unchanged. This is
the outer-ZFS operation that the future Woodpecker workflow should reproduce.

### EXP-20260830-15: test native labeled-lofi parsing of the trial disk

Controller observation time: 2026-08-30 17:46-17:48 UTC  
Layer: ec2trib block-device presentation  
Mutation: created and then detached one read-only lofi mapping; no pool import
and no image write

Hypothesis: Tribblix labeled-lofi presentation of the full raw SPARC disk will
expose the guest's unit104 root slice directly.

The tooling audit warned that several lofi IDs were already active. The
supported syntax and current mappings were therefore inspected first:

```sh
lofiadm -h 2>&1 | head -40
echo CURRENT_LOFI_MAPPINGS
lofiadm
```

This Tribblix build reports the labeled, read-only attach form as:

```text
lofiadm [-r] [-l] -a file [ device ]
```

Exact attach command:

```sh
lofiadm -r -l -a \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw
```

The allocated mapping was captured from `lofiadm`; no device number was
predicted:

```text
/dev/dsk/c5t8d0p0
```

Exact inspection commands:

```sh
lofiadm /dev/dsk/c5t8d0p0
ls -l /dev/dsk/c5t8d0* /dev/rdsk/c5t8d0*
prtvtoc /dev/rdsk/c5t8d0p0
```

Labeled lofi generated `s0` through `s15` device names, but `prtvtoc` did not
describe a root slice 0. Its material output was:

```text
512 bytes/sector
16065 sectors/cylinder
125788950 accessible sectors

Unallocated:
First Sector 16065
Sector Count 125772885
Last Sector  125788949

Partition 2: first 0, count 125788950
Partition 8: first 0, count 16065
```

Exact cleanup and verification commands:

```sh
lofiadm -d /dev/dsk/c5t8d0p0
echo DETACH_STATUS=$?
lofiadm /dev/dsk/c5t8d0p0 2>&1
```

Cleanup result:

```text
DETACH_STATUS=0
lofiadm: /dev/dsk/c5t8d0p0: No such file or directory
```

Result: **FAIL** for the hypothesis, with successful cleanup. Native labeled
lofi on the x86 Tribblix host must not be trusted to translate this SPARC
layout into the guest's expected root slice. The next experiment must expose
an explicit, independently verified byte-offset view of the candidate instead
of selecting a generated `s0` node by name.

### EXP-20260830-16: materialize and inspect an explicit offset view

Controller observation time: 2026-08-30 17:52-17:56 UTC  
Layer: ec2trib host image view and ZFS label inspection  
Mutation: created one sparse derived view inside the disposable trial clone;
no pool import and no source-image write

Initial interpretation of the guest hSIMD geometry:

```text
start sector: 16065
second value: 125788950, initially treated as an exclusive end sector
sector size:  512
byte offset:  16065 * 512 = 8225280
view size:    (125788950 - 16065) * 512 = 64395717120
```

Target:

```text
/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
```

Preconditions and image-option validation:

```sh
test -e \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
zfs list -H -o available \
  tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
qemu-img info --image-opts \
  "driver=raw,offset=8225280,size=64395717120,file.driver=file,file.filename=/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw"
```

Observed preconditions:

```text
VIEW_TARGET_UNUSED
available: 25.2G
validated virtual size: 64395717120 bytes
```

Exact sparse-view conversion command:

```sh
mkdir /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views
qemu-img convert --image-opts -p -O raw -S 4k \
  "driver=raw,offset=8225280,size=64395717120,file.driver=file,file.filename=/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw" \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
echo VIEW_CONVERT_STATUS=$?
```

Conversion and allocation result:

```text
VIEW_CONVERT_STATUS=0
logical size: 64395717120 bytes
du allocation: 4.9G
clone used: 4.86G
clone referenced: 9.72G
clone available: 20.3G
```

Exact label inspection command:

```sh
zdb -l \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
echo ZDB_LABEL_STATUS=$?
```

Labels 0 and 1 decoded successfully and proved the offset:

```text
name: 'rpool'
txg: 3071
pool_guid: 18135893029031842473
top_guid: 4578789811724481955
path: '/dev/dsk/c1d4s0'
phys_path: '/virtual-devices@100/disk@4:a'
ashift: 11
asize: 64399081472
labels = 0 1
```

Trailing-label result:

```text
failed to unpack label 2
failed to unpack label 3
ZDB_LABEL_STATUS=1
```

Result: **PARTIAL PASS**. The 8,225,280-byte offset is correct and identifies
the expected inner pool and guest device. The view is too short for labels 2
and 3. The shortfall is exactly 16,065 sectors, the same as the start offset.
This evidence indicates that hSIMD's `125788950` is a sector count rather than
an exclusive end sector.

Next falsification test: extend the disposable view by exactly 16,065 sectors
copied from the corresponding source position, producing a total view length
of `125788950 * 512 = 64403942400` bytes, then rerun `zdb -l`. Pass requires
all four labels to decode and `ZDB_LABEL_STATUS=0`.

### EXP-20260830-17: correct the explicit slice length

Controller observation time: 2026-08-30 17:59 UTC  
Layer: ec2trib disposable host view  
Mutation: appended 16,065 sectors to the derived view only

Exact correction and verification commands:

```sh
/usr/gnu/bin/dd \
  if=/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw \
  of=/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw \
  bs=512 skip=125788950 seek=125772885 count=16065 conv=notrunc
echo EXTEND_STATUS=$?
wc -c \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
zdb -l \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
echo ZDB_LABEL_STATUS=$?
```

Observed result:

```text
16065+0 records in
16065+0 records out
8225280 bytes copied
EXTEND_STATUS=0
view size: 64403942400 bytes
pool: rpool
pool GUID: 18135893029031842473
labels = 0 1 2 3
ZDB_LABEL_STATUS=0
```

Result: **PASS**. hSIMD's second partition value is confirmed as a sector
count. The correct explicit unit104 root-slice geometry is start sector 16,065
and length 125,788,950 sectors. The derived view contains all four consistent
ZFS labels and identifies the expected rpool.

### EXP-20260830-18: verify the corrected view through allocated lofi nodes

Controller observation time: 2026-08-30 17:59-18:00 UTC  
Layer: ec2trib lofi block presentation  
Mutation: created one read-only non-labeled lofi mapping; mapping intentionally
left attached for the next read-only pool-discovery experiment

Exact attach command:

```sh
lofiadm -r -a \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/views/unit104-s0-zfs.raw
```

Allocated device returned by `lofiadm`:

```text
/dev/lofi/8
```

The first label command established that `zdb` does not accept the block node:

```sh
lofiadm /dev/lofi/8
zdb -l /dev/lofi/8
echo DEVICE_ZDB_STATUS=$?
```

```text
cannot use '/dev/lofi/8': character device required
DEVICE_ZDB_STATUS=1
```

Exact corrected verification command:

```sh
ls -l /dev/lofi/8 /dev/rlofi/8
zdb -l /dev/rlofi/8
echo RAW_DEVICE_ZDB_STATUS=$?
```

Observed result:

```text
pool: rpool
pool GUID: 18135893029031842473
labels = 0 1 2 3
RAW_DEVICE_ZDB_STATUS=0
```

Result: **PASS**. The corrected slice view works as an allocated read-only
lofi device. `lofiadm` returns the block path, but ZFS label inspection must
derive and validate the matching `/dev/rlofi/N` character path. Automation
must record both paths and must not assume device number 8 in another run.

### EXP-20260830-19: discover the inner pool without importing it

Controller observation time: 2026-08-30 18:00 UTC  
Layer: ec2trib ZFS pool discovery  
Mutation: created a trial-specific `/tmp` directory and one symlink; no pool
import or image write

The first exact-device attempt:

```sh
zpool import -d /dev/rlofi/8
echo DISCOVERY_STATUS=$?
```

was rejected because this `zpool` implementation treats `-d` as a directory:

```text
cannot open '/devices/pseudo/lofi@8:disk,raw/': Not a directory
DISCOVERY_STATUS=1
```

Exact restricted-directory commands:

```sh
mkdir /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs
ln -s /dev/rlofi/8 \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs/unit104-s0
ls -l /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs
zpool import -d /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs
echo DISCOVERY_STATUS=$?
zpool list -H -o name,guid | grep 18135893029031842473 \
  || echo INNER_RPOOL_NOT_IMPORTED
```

Observed result:

```text
pool: rpool
id: 18135893029031842473
state: ONLINE
status: pool was last accessed by another system
vdev: /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs/unit104-s0 ONLINE
DISCOVERY_STATUS=0
INNER_RPOOL_NOT_IMPORTED
```

Result: **PASS**. A one-entry scan directory restricts discovery to the exact
allocated raw lofi device, finds the expected inner rpool ONLINE, and leaves
it unimported. A future script must create a unique scan directory and symlink
from the actual `lofiadm` return value rather than scan all host devices.

### EXP-20260830-20: import the inner pool read-only with no mounts

Controller observation time: 2026-08-30 18:01 UTC  
Layer: ec2trib inner ZFS pool ownership  
Mutation: imported the derived inner pool into host memory read-only under a
trial name; no datasets mounted and no pool data written

Exact import and verification commands:

```sh
zpool import -f -o readonly=on -N \
  -d /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs \
  18135893029031842473 rpool_trial0001
echo IMPORT_STATUS=$?
zpool status rpool_trial0001
zpool get -H -o property,value readonly,cachefile rpool_trial0001
zfs list -H -r -o name,mounted,mountpoint rpool_trial0001
```

Observed result:

```text
IMPORT_STATUS=0
pool state: ONLINE
vdev: /dev/rlofi/8 ONLINE
read errors: 0
write errors: 0
checksum errors: 0
known data errors: none
readonly: on
cachefile: -
```

Every filesystem dataset reported `mounted=no`; the dump and swap volumes
reported no mount state.

Discovered boot-environment datasets include:

```text
rpool_trial0001/ROOT/openindiana
rpool_trial0001/ROOT/openindiana/var
rpool_trial0001/ROOT/workstation-candidate-20260826
rpool_trial0001/ROOT/workstation-candidate-20260826/var
```

Result: **PASS**. The exact derived pool can be safely owned by Tribblix in a
read-only, no-mount state with no persistent cachefile entry. The dataset
inventory proves that both the openindiana and workstation-candidate boot
environments are present for later read-only inspection.

### EXP-20260830-21: identify bootfs and boot-environment lineage

Controller observation time: 2026-08-30 18:01-18:02 UTC  
Layer: ec2trib read-only inner ZFS metadata  
Mutation: observation only

Exact metadata commands:

```sh
zpool get -H -o property,value bootfs rpool_trial0001
zfs list -H -r -o name,used,referenced,creation rpool_trial0001/ROOT
zfs get -H -r -o name,property,value \
  mountpoint,canmount,guid,origin rpool_trial0001/ROOT
```

Selected bootfs:

```text
rpool_trial0001/ROOT/openindiana
```

Root dataset identities:

```text
openindiana GUID: 10349450307531540087
mountpoint: /
canmount: noauto

workstation-candidate-20260826 GUID: 4990579676110941692
mountpoint: /
canmount: noauto
origin: rpool_trial0001/ROOT/openindiana@2026-08-26-19:25:13
```

The openindiana history includes these named snapshots:

```text
pre-fortify                         GUID 17765999520257796250
fortified-files                     GUID 12650319278342661960
fortified-bootarchive-pass          GUID 4108393647285143120
pre-hsimd-registration              GUID 15402876410597739060
hsimd-registration-bootarchive-pass GUID 1471822987198211444
2026-08-26-19:25:13                 GUID 11030686307240931441
```

The matching `/var` dataset has corresponding snapshot names and the
workstation candidate's `/var` is a clone of the dated OpenIndiana `/var`
snapshot.

Result: **PASS**. The pool records OpenIndiana as its selected bootfs and
preserves explicit boot-archive and hSIMD milestone snapshots. Snapshot names
are lineage evidence only; the next content test must mount the selected root
read-only and verify actual files before treating any milestone name as proof.

### EXP-20260830-22: mount the selected root under a controlled read-only altroot

Controller observation time: 2026-08-30 18:02-18:03 UTC  
Layer: ec2trib read-only inner ZFS mount  
Mutation: exported and reimported the read-only pool with an altroot; created
temporary host directories; a false host-side probe file was removed

The first manual-mount attempt was intentionally checked and rejected:

```sh
mkdir /tmp/qemu-sun4v-illumos-ci-trial-0001-root
mount -F zfs -o ro rpool_trial0001/ROOT/openindiana \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-root
echo ROOT_MOUNT_STATUS=$?
```

```text
filesystem cannot be mounted using 'mount -F zfs'
ROOT_MOUNT_STATUS=1
```

A subsequent `touch` targeted the still-empty host directory and succeeded;
it did not test the inner pool. The exact false probe was removed and verified
absent:

```sh
rm /tmp/qemu-sun4v-illumos-ci-trial-0001-root/READONLY-WRITE-PROBE
echo FALSE_PROBE_CLEANUP_STATUS=$?
test ! -e \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-root/READONLY-WRITE-PROBE \
  && echo FALSE_PROBE_REMOVED
```

Exact supported altroot sequence:

```sh
zpool export rpool_trial0001
echo EXPORT_FOR_ALTROOT_STATUS=$?
mkdir /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot
zpool import -f -o readonly=on -N \
  -R /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot \
  -d /tmp/qemu-sun4v-illumos-ci-trial-0001-vdevs \
  18135893029031842473 rpool_trial0001
echo ALTROOT_IMPORT_STATUS=$?
zpool get -H -o property,value altroot,readonly,cachefile rpool_trial0001
zfs mount rpool_trial0001/ROOT/openindiana
echo ZFS_MOUNT_STATUS=$?
mount | grep qemu-sun4v-illumos-ci-trial-0001-altroot
```

Observed mount state:

```text
EXPORT_FOR_ALTROOT_STATUS=0
ALTROOT_IMPORT_STATUS=0
altroot: /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot
readonly: on
cachefile: none
ZFS_MOUNT_STATUS=0
mount: rpool_trial0001/ROOT/openindiana, read only
```

Exact valid write-rejection probe:

```sh
touch \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/READONLY-WRITE-PROBE
echo ALTROOT_WRITE_PROBE_STATUS=$?
test ! -e \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/READONLY-WRITE-PROBE \
  && echo ALTROOT_READONLY_CONFIRMED
```

```text
touch: Read-only file system
ALTROOT_WRITE_PROBE_STATUS=1
ALTROOT_READONLY_CONFIRMED
```

Result: **PASS**. Non-legacy ZFS roots must be mounted with `zfs mount` after
importing the pool with a controlled `-R` altroot. The selected bootfs root is
now visible read-only at the trial altroot, and a real write probe was rejected
without leaving a file.

### EXP-20260830-23: verify awk and boot-archive objects in the selected root

Controller observation time: 2026-08-30 18:03-18:04 UTC  
Layer: ec2trib read-only selected-root content  
Mutation: observation only

Exact file checks:

```sh
ls -l \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/usr/bin/awk \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/usr/bin/nawk \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/platform/sun4v/boot_archive
file \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/usr/bin/awk \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/platform/sun4v/boot_archive
test -x /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/usr/bin/awk
echo AWK_EXECUTABLE_STATUS=$?
wc -c \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/platform/sun4v/boot_archive
```

Observed file state:

```text
awk:  147124 bytes, mode -r-xr-xr-x
nawk: 147124 bytes, mode -r-xr-xr-x
awk file type: ELF 32-bit MSB SPARC32PLUS, dynamically linked
AWK_EXECUTABLE_STATUS=0
boot_archive size: 248651776 bytes
boot_archive file output: English text
```

The unqualified checksum command failed because PATH selects the pkgsrc tool
first:

```sh
digest -a sha256 BOOT_ARCHIVE_PATH
```

```text
digest: illegal option -- a
digest is /tink/pkg-2023Q3/bin/digest
digest is /usr/bin/digest
```

Exact successful checksum command:

```sh
/usr/bin/digest -a sha256 \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/platform/sun4v/boot_archive
echo NATIVE_DIGEST_STATUS=$?
```

```text
2da75aab5707fbeb66fc4583b1f866f14501e3a07fa1087dffa0848cbfb10c07
NATIVE_DIGEST_STATUS=0
```

Result: **PASS**. The selected root contains an executable big-endian SPARC
awk and a concrete, checksummed sun4v boot-archive object. This proves root
filesystem contents only; it does not prove that awk is present inside the
boot archive's UFS. Automation must use audited absolute tool paths because
the pkgsrc and native `digest` CLIs are incompatible.

### EXP-20260830-24: identify boot archives in named milestone snapshots

Controller observation time: 2026-08-30 18:04 UTC  
Layer: ec2trib read-only inner ZFS snapshot content  
Mutation: observation only

Exact comparison loop, using the native checksum binary:

```sh
for P in \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/.zfs/snapshot/fortified-bootarchive-pass/platform/sun4v/boot_archive \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/.zfs/snapshot/hsimd-registration-bootarchive-pass/platform/sun4v/boot_archive \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/platform/sun4v/boot_archive
do
  echo BOOT_ARCHIVE=$P
  ls -l $P
  wc -c $P
  /usr/bin/digest -a sha256 $P
done
```

Observed immutable identities:

```text
fortified-bootarchive-pass
size:   263725056
sha256: 8dbe6f04301116143c761e1068354d11f92e010b44bdb9ee5513acf8f73dba6f

hsimd-registration-bootarchive-pass
size:   263725056
sha256: 8cff4ff265c0a475a459d6dd7805b1f83c61c6b12615908d3005c776482f3a98

current openindiana root
size:   248651776
sha256: 2da75aab5707fbeb66fc4583b1f866f14501e3a07fa1087dffa0848cbfb10c07
```

Result: **PASS**. Both named milestone snapshots contain concrete boot-archive
files. The fortified and hSIMD-registration archives have equal sizes but
different hashes, proving that hSIMD registration changed archive content.
The current root contains a smaller, third archive. These identities can now
be used to extract explicit candidate artifacts without relying on snapshot
names alone.

### EXP-20260830-25: extract the hSIMD milestone boot archive

Controller observation time: 2026-08-30 18:05-18:06 UTC  
Layer: ec2trib artifact assembly in disposable outer clone  
Mutation: created one extracted boot-archive candidate; source snapshot stayed
read-only

Source:

```text
/tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/.zfs/snapshot/hsimd-registration-bootarchive-pass/platform/sun4v/boot_archive
```

Destination:

```text
/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/artifacts/boot-archives/boot_archive.hsimd-registration-pass.ufs
```

Exact extraction and verification commands:

```sh
TARGET=/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/artifacts/boot-archives/boot_archive.hsimd-registration-pass.ufs
test -e $TARGET && echo ARCHIVE_TARGET_EXISTS \
  || echo ARCHIVE_TARGET_UNUSED
mkdir -p \
  /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/artifacts/boot-archives
/usr/gnu/bin/cp --sparse=always \
  /tmp/qemu-sun4v-illumos-ci-trial-0001-altroot/.zfs/snapshot/hsimd-registration-bootarchive-pass/platform/sun4v/boot_archive \
  $TARGET
echo ARCHIVE_COPY_STATUS=$?
wc -c $TARGET
/usr/bin/digest -a sha256 $TARGET
```

Observed result:

```text
ARCHIVE_TARGET_UNUSED
ARCHIVE_COPY_STATUS=0
size:   263725056
sha256: 8cff4ff265c0a475a459d6dd7805b1f83c61c6b12615908d3005c776482f3a98
```

Result: **PASS**. The disposable outer clone now contains a named,
byte-identified boot-archive candidate extracted from the immutable hSIMD
registration milestone. It is a candidate for a UFS booter, not yet a
boot-qualified artifact and not yet proof that awk is present inside it.

### EXP-20260830-26: audit the pinned hsimd source snapshot

Layer: project source and driver provenance.

Hypothesis: commit `f419e93` contains a complete, clean, provenance-pinned
hsimd source subtree that can replace binary-only reasoning with source-level
investigation, while preserving the unresolved relationship to the captured
SPARC V9 module.

Exact commands run from the project repository on Minnie:

```sh
git show -s --format='FULL_COMMIT=%H%nSUBJECT=%s%nDATE=%ci' f419e93
git ls-tree --name-only f419e93:third_party/hsimd
git status --short third_party/hsimd
git diff --exit-code HEAD -- third_party/hsimd
echo HSIMD_SUBTREE_DIFF_STATUS=$?
sed -n '1,220p' third_party/hsimd/UPSTREAM.md
sed -n '1,220p' third_party/hsimd/Makefile
rg -n 'hsimd_ioctl|not implemented|dki_maxtransfer|128|panic' \
  third_party/hsimd/hsimd.c
sed -n '430,570p' third_party/hsimd/hsimd.c
sed -n '750,890p' third_party/hsimd/hsimd.c
```

Observed source commit:

```text
FULL_COMMIT=f419e9376e46c86fae23af21846920d97d32667f
SUBJECT=vendor pinned hsimd source
DATE=2026-08-30 11:03:42 -0700
```

The pinned subtree contains:

```text
LICENSE
Makefile
README.hsimd
UPSTREAM.md
hsimd.c
hsimd_asm.s
```

`git status` produced no subtree changes and the diff exit status was zero.
`UPSTREAM.md` pins the snapshot to Artyom Tarasenko's upstream commit
`a04793b34219e5c31a6c7635c512231655174a1e`, dated 2025-01-25, under GPLv2.
It explicitly records that exact source correspondence with
`captures/openindiana-live-20260824/extracted/hsimd` has not been proved.

The first source audit found these concrete investigation points:

- `hsimd_diskio()` splits a request at virtual-page boundaries using
  `min(size, va2tsize(va))`; it has no literal 128-KiB limit in this source.
- A hypervisor result of zero or `(size_t)-1` becomes a short transfer, but an
  unexpectedly large result is not checked before subtracting it from the
  remaining size.
- `hsimd_strategy()` turns every short transfer into a full-buffer residual
  and sets `B_ERROR`, losing the successfully transferred byte count.
- `DKIOCINFO`, `DKIOCGVTOC`, and `DKIOCGGEOM` are implemented. The default
  ioctl case logs `cmd ... not implemented` and nevertheless returns success.
- `dki_maxtransfer` is advertised as `PAGESIZE / DEV_BSIZE` blocks.
- The Makefile is a Solaris gate module Makefile with `UTSBASE=../..` and
  includes the sun4v gate rules; it is not a standalone portable build.

Result: **PASS**. We now have inspectable, modifiable driver source with pinned
upstream provenance and an unchanged local subtree. The observed 128-KiB panic
and tiny-read behavior remain phenomena to reproduce and trace; this audit did
not locate a literal 128-KiB panic condition. Building and comparing a module
requires a Solaris/illumos sun4v kernel gate compatible with the target guest.
Until that build is reproduced and compared, do not claim that this source
commit produced the captured SPARC V9 binary.

### EXP-20260830-27: launch the login-proven root as a direct raw unit104 trial

Layer: ec2trib outer ZFS clone, QEMU launch, and OpenBoot console.

Hypothesis: the checksum-matched unit104 lineage can reach the saved login
path on ec2trib when QEMU uses the writable raw file in the outer ZFS clone
directly, avoiding the known-bad multi-layer qcow2 chain.

The obsolete maintenance-mode QEMU was PID 19686. Its live arguments proved
that it used:

```text
unit100: carrier-unit100.qcow2
unit103: installer-unit103.img, raw and read-only
unit104: root-unit104.qcow2 from the failed multi-layer lineage
```

The guest had no ZFS pool imported. Exact console shutdown command:

```sh
sync; init 5
```

SMF began stopping 73 services but made no further console progress. After
the completed `sync`, the exact host termination and verification commands
were:

```sh
kill -TERM 19686
ps -p 19686 -o pid,ppid,s,time,args
pgrep -fl qemu || echo NO_QEMU_PROCESS
```

The process exited after SIGTERM. The read-only host inspection ownership was
then released using:

```sh
zfs unmount rpool_trial0001/ROOT/openindiana
zpool export rpool_trial0001
lofiadm -d /dev/lofi/8
zpool list -H -o name,guid | grep 18135893029031842473 \
  || echo TRIAL_POOL_NOT_IMPORTED
lofiadm | grep unit104-s0-zfs.raw \
  || echo TRIAL_LOFI_NOT_ATTACHED
```

All three state-changing commands returned zero. The pool was not imported
and the trial lofi mapping was absent afterward. Other host lofi mappings
were not changed.

A dedicated repository launcher was added at:

```text
scripts/run-sun4v-ec2trib-login-raw-trial.sh
```

It was copied to `/root/run-sun4v-login-raw-trial.sh` on ec2trib. Both copies
had SHA-256:

```text
896946253571f6b663ae1b882f568e6e3b676a5ff43ef846147b6b5eeeb0a042
```

The script passed `/usr/bin/bash -n`. It refuses to launch if the expected
inner pool GUID is imported on the host or if the exact target file has a
lofi attachment. It assigns unit100 only to the carrier/channel object,
unit103 to the read-only installer media, and the direct writable raw clone
to unit104.

Exact target:

```text
/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw
```

Observed size was 64,424,509,440 bytes and the file was writable. Before
launch, this recoverable snapshot and hold were created:

```sh
zfs snapshot \
  tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe@pre-boot-unit104-login-trial-0001
zfs hold trial-input \
  tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe@pre-boot-unit104-login-trial-0001
```

Snapshot GUID:

```text
370532935438843004
```

Exact launcher command:

```sh
/root/run-sun4v-login-raw-trial.sh
```

Run identity:

```text
/tink/runs/oi-login-raw-20260829T101109Z-20588
QEMU PID: 20615
QEMU name: oi-login-raw
console: /tink/runs/oi-login-raw-20260829T101109Z-20588/console.sock
```

After rediscovering and selecting the new opaque console target, the exact
OpenBoot command was:

```text
boot /virtual-devices@100/disk@4:a -k -v
```

Observed live gates so far:

```text
Boot device: /virtual-devices@100/disk@4:a
module /platform/sun4v/kernel/sparcv9/unix
module /platform/sun4v/kernel/sparcv9/genunix
Loading kmdb...
OpenIndiana Hipster 2025.12 Version illumos-31d3d510d0 64-bit
```

Later observed gates:

```text
hsimd4 is /virtual-devices@100/disk@4
root on rpool/ROOT/openindiana fstype zfs
Hostname: oi-basecamp
hsimd3 is /virtual-devices@100/disk@3
Mounting ZFS filesystems: (8/8)
oi-basecamp console login:
```

At login, the outer clone had written at least 32.1 MiB since the held
pre-boot snapshot. This proves the direct raw unit104 served as the writable
ZFS root, not merely as firmware boot media. Unit103 also attached during
device enumeration. Unit100 retained its carrier/channel role.

Result: **PASS**. The direct writable raw unit104 clone booted on ec2trib to
`oi-basecamp console login:`. The ec2trib run was created at 10:11:10Z and the
login gate was first observed at 10:19:57Z, an elapsed 8 minutes 47 seconds.
The complete comparison record is in
`notes/filesystem-manipulation-tooling/boot-traces/oi-login-raw-20260829T101109Z-20588/`.

### EXP-20260830-28: inventory the proven login guest before shutdown

Layer: running OpenIndiana sun4v guest, unit104 ZFS root, and captured console
record.

Hypothesis: an inventory taken from the proven login system will give later
trials a concrete kernel, pool, boot-environment, storage, module, and service
baseline rather than relying on remembered behavior.

Commands were run in bounded groups at the guest console and accumulated in:

```text
/var/tmp/niagara-login-baseline-20260830.txt
```

The inventory included `uname`, kernel and boot-archive identities, `zpool`
and `zfs` properties, boot environments, mount and device topology, loaded
hsimd/PPP modules, SMF failures, and helper processes. The package inventory
command stalled and was interrupted with Ctrl-C; the remaining bounded groups
then completed.

Important observed identities and gates:

```text
SunOS oi-basecamp 5.11 illumos-31d3d510d0 sun4v sparc SUNW,Sun-Fire-T200
rpool GUID: 18135893029031842473
rpool bootfs: rpool/ROOT/openindiana
only rpool vdev: /devices/virtual-devices@100/disk@4:a
active BE: openindiana
inactive BE: workstation-candidate-20260826
hsimd: hsimd v0.0.6_aio2
unix SHA-256: 300e2b11956675686a6864bbc398eff96ab0202017e7a996e2804c995807294c
/platform/sun4v/boot_archive: 248651776 bytes, Aug 29 03:28
```

Inventory-file verification:

```text
cksum: 285267887 18312
SHA-256: db758f4081556e731061d7140adbddcf329a6f2ccf9f32907dce66ee3e1ebabd
```

The console record through this inventory was copied to:

```text
notes/filesystem-manipulation-tooling/boot-traces/oi-login-raw-20260829T101109Z-20588/console-through-final-inventory.log
```

At capture it was 39,582 bytes with SHA-256
`1bfe4eea5f521902be976e08cf7125addfd11679104994ef278fe15c3bc40757`.

Result: **PASS**. The proven login configuration now has a repeatable comparison
record. No host channel, PPP, or BBS helper was active during the inventory.

### EXP-20260830-29: request orderly shutdown and test for disk release

Layer: guest SMF shutdown, QEMU host process, and unit104 ownership.

Hypothesis: `init 5` will stop the guest, let QEMU exit, and release the exact
unit104 raw image before the next assembly or boot trial.

Exact guest command entered by Ryan:

```sh
init 5
```

The last console output was:

```text
svc.startd: The system is coming down.  Please wait.
svc.startd: 78 system services are now being stopped.
```

The Old Sun MCP broker subsequently returned `CONSOLE_UNAVAILABLE` with
`Operation not permitted`; this was treated only as a broker failure, not as
proof that QEMU had exited. Read-only host verification used:

```sh
pgrep -lf qemu-system-sparc64
test -d /proc/20615 && echo present || echo absent
lofiadm
zpool list -H -o name,guid
ls -l /tink/runs/oi-login-raw-20260829T101109Z-20588/console.log
ps -o pid,ppid,s,etime,args -p 20615
tail -100 /tink/runs/oi-login-raw-20260829T101109Z-20588/console.log
prstat -p 20615 1 3
pfiles 20615 | grep -n 'unit104-login-proven-20260826T210446Z.raw'
wc -c /tink/runs/oi-login-raw-20260829T101109Z-20588/console.log
```

Observed result:

```text
QEMU PID 20615: still present
QEMU CPU: approximately 51%, increasing one CPU-second per second
QEMU unit104 descriptor: still open
console.log size: 39748 bytes, not advancing
host-imported pools: only host rpool and tink; guest rpool GUID absent
```

Result: **STALLED**. The guest did not reach a halt or QEMU exit, and unit104
is not released. No signal was sent to QEMU. After Ryan terminates the stalled
run, repeat the process/open-file/lofi/pool checks and capture the final console
and run manifest before any next trial.

Follow-up on 2026-08-31: Ryan authorized termination of PID 20615. Before a
signal was sent, the old `lab-ec2trib` terminal had disappeared and a fresh
connection showed that PID 20615 no longer existed. No signal was therefore
sent to a potentially reused PID. Final read-only release verification used:

```sh
ps -e -o pid,comm | grep qemu-system-spa || echo no-qemu-process
lofiadm | grep unit104-login-proven-20260826T210446Z.raw || echo none
zpool list -H -o name,guid | grep 18135893029031842473 || echo not-imported
fuser /tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw
```

Observed final state:

```text
QEMU process: absent
unit104 lofi mapping: absent
guest rpool GUID on host: not imported
unit104 fuser PIDs: none
launcher finished_utc: 2026-08-29T10:59:13Z
launcher qemu_exit_status: 129
NVRAM SHA-256 before and after: unchanged
```

The finalized host artifacts were copied without transformation and verified
against hashes computed on ec2trib:

```text
console-through-init5-shutdown.log
  bytes: 40348
  SHA-256: e3ce5db56a1220cb3cc65217a6b7fbcac437e50cccd005359b17a6783110a3ce
run-manifest-after-shutdown.txt
  bytes: 1413
  SHA-256: 60030753951e2a7bc15d9ee56d02fdfc7b14e12276b3f9aa7351eb9f36845ab3
```

Both are stored under
`notes/filesystem-manipulation-tooling/boot-traces/oi-login-raw-20260829T101109Z-20588/`.

Final result: **RELEASED AFTER STALLED SHUTDOWN**. Unit104 is safe for the next
host-owned inspection or clone operation. Exit status 129 proves a signal-based
QEMU exit but does not identify who sent that signal; do not describe this as a
successful guest halt.

### EXP-20260831-30: prove a RAM-backed raw unit100 on ec2trib

Layer: Tribblix host tmpfs, accepted unit100 carrier, and next-run launcher.

Hypothesis: the accepted raw unit100 carrier can be reproduced byte-for-byte
in a confirmed RAM filesystem and used directly by both QEMU and the host
channel helpers, avoiding the qcow2 split-mailbox failure.

Before changing the launcher, the existing `tribblix-woodpecker` example was
reviewed. Its useful orchestration pattern is: branch-selected pipeline,
persistent SSH execution on ec2trib, a pipeline-numbered remote staging
directory, ordered preflight/build/boot gates, a bounded Unix-socket console
probe, retained run evidence, and unconditional QEMU cleanup. It currently
uses GitHub/exabyt conventions, does not use Doppler, and escalates cleanup to
SIGKILL after five seconds. Those details are not copied blindly into this
project's biggie/Gitea workflow.

Exact read-only host discovery commands:

```sh
mount -p
df -k /tmp /var/tmp /tink
grep -n tmpfs /etc/vfstab /etc/system
prtconf | grep Memory
df -n /tmp
df -n /tink
mount -v | grep /tmp
ls -ls /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img
wc -c /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img
qemu-img info /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img
digest -a sha256 /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img
```

Observed host facts:

```text
/tmp filesystem: tmpfs
/tink filesystem: zfs
physical memory: 8192 MiB
initial /tmp available: approximately 6.0 GiB
carrier format: raw
carrier apparent size: 1073741824 bytes (1 GiB)
carrier allocated size on ZFS: 642 KiB
carrier SHA-256: 70d436dab85c3fc9444c2df0cf47075c11e27fab4cc2fbe72929b2ead37fd735
```

Exact disposable-copy experiment:

```sh
mkdir /tmp/niagara-unit100-proof-20260831
qemu-img convert -q -f raw -O raw -S 4096 \
  /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/carrier-unit100.img \
  /tmp/niagara-unit100-proof-20260831/unit100.raw
ls -ls /tmp/niagara-unit100-proof-20260831/unit100.raw
wc -c /tmp/niagara-unit100-proof-20260831/unit100.raw
qemu-img info /tmp/niagara-unit100-proof-20260831/unit100.raw
digest -a sha256 /tmp/niagara-unit100-proof-20260831/unit100.raw
df -k /tmp
rm -f /tmp/niagara-unit100-proof-20260831/unit100.raw
rmdir /tmp/niagara-unit100-proof-20260831
test ! -e /tmp/niagara-unit100-proof-20260831 && echo proof-path-absent
df -k /tmp
```

The tmpfs copy was raw, exactly 1 GiB, and had the same SHA-256 as its source.
Unlike the ZFS source, Tribblix tmpfs charged the full 1 GiB despite the sparse
conversion request. `/tmp` rose from 1% to 18% capacity during the proof and
returned to 1% after exact-path cleanup. This is acceptable for one trial but
requires a capacity gate and reliable cleanup; overlapping trials must be
refused.

`scripts/run-sun4v-ec2trib-login-raw-trial.sh` now:

- fails closed unless `UNIT100_RAM_ROOT` reports `tmpfs` through `df -n`;
- checks tmpfs capacity before allocation;
- makes a unique raw unit100 under `/tmp/<run-id>/`;
- verifies the complete initial SHA-256 against the accepted source;
- records tmpfs identity, path, source hash, and initial hash in the manifest;
- attaches that exact raw file to QEMU as unit100; and
- removes only that trial's exact unit100 path when QEMU exits.

The known login-producing OpenBoot command remains
`boot /virtual-devices@100/disk@4:a -k -v`; changing the boot source is not part
of this isolated test. Unit103 and unit104 assignments are unchanged.

Validation commands:

```sh
bash -n scripts/run-sun4v-ec2trib-login-raw-trial.sh
git diff --check -- scripts/run-sun4v-ec2trib-login-raw-trial.sh \
  notes/filesystem-manipulation-tooling/EXPERIMENT-NOTEBOOK-2026-08-30.md
```

Both passed. ShellCheck was not installed on Minnie. Launcher SHA-256 after
this change:

```text
1ee92503ce1308925b4377436aaf3c19e481a237d6b82fba3c7e18dd2362e990
```

Result: **PASS**. A byte-identical RAM-backed raw unit100 is feasible on
ec2trib, its actual memory cost is measured, and the next-run launcher now
enforces and cleans that topology.

### EXP-20260831-31: add and execute the Woodpecker ec2trib preflight

Layer: repository Woodpecker definition, staged ec2trib scripts, and immutable
outer-ZFS source identity.

Hypothesis: the first Woodpecker gate can fail closed against the real ec2trib
state without creating a clone or launching QEMU.

Added:

```text
.woodpecker/niagara-login-preflight.yml
scripts/ec2trib-niagara-login-preflight.sh
```

The pipeline is selected only by pushes to `niagara-login-ci`. It creates a
pipeline-numbered remote stage, copies the preflight and launcher, verifies
their permissions, and runs the preflight over the existing `ec2trib` SSH
convention demonstrated by `tribblix-woodpecker`.

The preflight checks:

- exact QEMU, qemu-img, ZFS, lofi, digest, unit100, unit103, NVRAM, and launcher
  availability;
- launcher Bash syntax;
- absence of the selected QEMU process;
- confirmed tmpfs and capacity for the full 1 GiB unit100 allocation;
- exact unit100 bytes and SHA-256;
- immutable outer unit104 snapshot name, GUID, and `trial-input` hold;
- readability and exact 64,424,509,440-byte size of the raw file through the
  snapshot namespace;
- absence of the inner pool GUID from host-imported pools; and
- absence of a lofi attachment to the immutable snapshot file.

Local definition validation:

```sh
bash -n scripts/ec2trib-niagara-login-preflight.sh \
  scripts/run-sun4v-ec2trib-login-raw-trial.sh
git diff --check -- .woodpecker/niagara-login-preflight.yml \
  scripts/ec2trib-niagara-login-preflight.sh \
  scripts/run-sun4v-ec2trib-login-raw-trial.sh
ruby -e 'require "yaml"; YAML.load_file(ARGV[0]); puts "YAML_PARSE=PASS"' \
  .woodpecker/niagara-login-preflight.yml
```

All passed. The same files were then copied to the exact disposable stage
`/tmp/niagara-login-preflight-proof-20260831/` on ec2trib and run as:

```sh
/usr/bin/bash \
  /tmp/niagara-login-preflight-proof-20260831/ec2trib-niagara-login-preflight.sh \
  /tmp/niagara-login-preflight-proof-20260831/run-sun4v-ec2trib-login-raw-trial.sh
```

Important output:

```text
NIAGARA_LOGIN_PREFLIGHT=PASS
qemu_commit=049affb20df67162cf58deeaf74d5ad4b83cbdc3
unit100_fs=tmpfs
unit100_available_kib=6039548
unit100_sha256=70d436dab85c3fc9444c2df0cf47075c11e27fab4cc2fbe72929b2ead37fd735
unit104_source_snapshot=tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe@pre-boot-unit104-login-trial-0001
unit104_source_snapshot_guid=370532935438843004
unit104_bytes=64424509440
unit104_inner_pool_guid=18135893029031842473
launcher_sha256=1ee92503ce1308925b4377436aaf3c19e481a237d6b82fba3c7e18dd2362e990
```

The exact temporary stage was removed after the proof. No QEMU, ZFS clone,
lofi mapping, pool import, or disk mutation was performed.

Result: **PASS**. The Woodpecker preflight exists, validates against ec2trib's
real immutable source and current ownership state, and is ready to precede a
separate clone-assembly stage.

### EXP-20260831-32: dry-run clone assembly and deterministic launch

Layer: ec2trib outer ZFS assembly, QEMU launch orchestration, and Woodpecker
workflow selection.

Hypothesis: clone creation and QEMU launch can be represented as two explicit,
independently dry-runnable gates, with Woodpecker as the first actor permitted
to execute their mutating modes.

Added:

```text
scripts/ec2trib-niagara-assemble-unit104.sh
scripts/ec2trib-niagara-launch-unit104.sh
.woodpecker/niagara-login-trial.yml
```

The assembly script accepts only `--dry-run` or `--create` plus a restricted
trial ID. It verifies the held source snapshot and GUID, source raw-file size,
idle QEMU state, unimported inner pool, and absent lofi ownership. Create mode
uses an atomic `/tmp/niagara-unit104-assembly.lock`, rechecks ownership after
locking, creates exactly one outer ZFS clone, verifies its origin/GUID/writable
raw file, and writes an assembly manifest outside the candidate dataset. It
does not destroy a partially created clone on failure; such a candidate is
preserved for diagnosis.

Exact real-host dry run:

```sh
/usr/bin/bash /tmp/ec2trib-niagara-assemble-unit104-proof-20260831.sh \
  --dry-run woodpecker-proof-20260831
```

Important output:

```text
NIAGARA_UNIT104_ASSEMBLY_MODE=dry-run
source_snapshot=tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe@pre-boot-unit104-login-trial-0001
source_snapshot_guid=370532935438843004
target_dataset=tink/qemu-sun4v-illumos-ci/woodpecker-proof-20260831
expected_target_file=/tink/qemu-sun4v-illumos-ci/woodpecker-proof-20260831/baselines/unit104-login-proven-20260826T210446Z.raw
unit104_bytes=64424509440
inner_pool_guid=18135893029031842473
NIAGARA_UNIT104_ASSEMBLY=DRY_RUN_PASS
```

No target dataset was created.

The launch script accepts only `--dry-run` or `--launch`, the trial ID, and a
staged launcher path. It resolves the assembled dataset and exact raw file,
checks size and exclusive ownership, assigns deterministic run ID
`niagara-<trial-id>`, and in launch mode starts the blocking launcher under
`nohup` with closed stdin. It waits at most 20 seconds for both a live QEMU PID
and console socket, then returns their paths to Woodpecker. The QEMU launcher
itself remains responsible for final manifest and tmpfs-unit100 cleanup.

Exact real-host dry run against the released existing dataset:

```sh
/usr/bin/bash /tmp/niagara-launch-dryrun-20260831/ec2trib-niagara-launch-unit104.sh \
  --dry-run trial-0001-clone-probe \
  /tmp/niagara-launch-dryrun-20260831/run-sun4v-ec2trib-login-raw-trial.sh
```

Important output:

```text
NIAGARA_UNIT104_LAUNCH_MODE=dry-run
target_dataset=tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe
unit104_path=/tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe/baselines/unit104-login-proven-20260826T210446Z.raw
run_id=niagara-trial-0001-clone-probe
NIAGARA_UNIT104_LAUNCH=DRY_RUN_PASS
```

No QEMU was started. Both exact temporary staging paths were removed after
their dry runs.

CI workflow selection is deliberately split:

- pushes to `codex/niagara-login-preflight` run only the read-only preflight;
- pushes to `codex/niagara-login-ci` run ordered preflight, writable outer-ZFS
  clone assembly, and detached QEMU launch.

This prevents the first unproven biggie runner/SSH test from creating a clone.
The launch workflow does not promote any result and does not contain secret
values. Doppler integration remains required when a later gate actually needs
credentials; the current SSH convention expects the Woodpecker agent's
dedicated ec2trib key, as in the reviewed example.

Validation:

```sh
bash -n scripts/ec2trib-niagara-login-preflight.sh \
  scripts/ec2trib-niagara-assemble-unit104.sh \
  scripts/ec2trib-niagara-launch-unit104.sh \
  scripts/run-sun4v-ec2trib-login-raw-trial.sh
git diff --check -- .woodpecker scripts/ec2trib-niagara-*.sh \
  scripts/run-sun4v-ec2trib-login-raw-trial.sh
ruby -e 'require "yaml"; ARGV.each { |p| YAML.load_file(p) }' \
  .woodpecker/niagara-login-preflight.yml \
  .woodpecker/niagara-login-trial.yml
```

All passed.

Result: **PASS**. The next mutable trial is mechanically defined, but only the
read-only preflight branch should be pushed first. A successful runner
preflight is the gate before pushing the launch branch.

Delivery follow-up: the scoped workflow and evidence files were committed on
local branch `codex/niagara-login-preflight` as commit `eb30dcc` (subsequently
amended only to include this delivery note). Pushes and `git ls-remote` to the
configured `http://biggie:3000/` remote hung without producing an
authentication prompt or establishing upstream tracking. The same push in the
shared visible terminal was interrupted with Ctrl-C and returned 130. `biggie`
resolved locally to Tailscale address `100.92.67.88`, but SSH to the host also
hung before producing output. Therefore no remote branch or Woodpecker run is
claimed. Restore the Minnie-to-biggie path, then push only
`codex/niagara-login-preflight` and inspect its read-only result before pushing
the separate `codex/niagara-login-ci` trial branch.

Second delivery follow-up: the failed path was an offline laptop configured as
Minnie's Tailscale exit node. After that was corrected, `tailscale ping` reached
biggie in 9 ms and commit `6248dd0` was pushed successfully to Gitea branch
`codex/niagara-login-preflight`. This still did **not** create a Woodpecker
pipeline. Biggie's maintained `/opt/tribblix-woodpecker/README.md` proves that
the active Woodpecker 3.18 service is configured for GitHub only and explicitly
does not configure local Gitea. Biggie had neither `woodpecker-cli` nor a local
checkout of this repository. No clone or QEMU was created. The next delivery
decision is architectural: deploy a separate Gitea-specific Woodpecker on
biggie, add an intentional GitHub mirror for this repository, or install and
use a local Woodpecker CLI runner as a temporary non-server bridge.

### EXP-20260831-33: reconcile the Gitea and GitHub histories

Layer: repository history and isolated Git worktree; no host storage or QEMU
mutation.

Ryan corrected the delivery model: this repository does have the GitHub
counterpart `https://github.com/ryancnelson/qemu-sun4v-illumos.git`. The local
checkout had only its Gitea `origin` configured even though a stale
`github/main` remote-tracking ref existed. The `github` remote was restored and
fetched.

Pre-merge history inspection found:

```text
common merge base: a61791bb7984b04f3d78e07e5fa2172db514e0e5
Gitea master only: 5 commits
GitHub main only: 34 commits
GitHub main before merge: 6493d5ab0d8c224b62494e394583c2e1d025dd22
```

To preserve the dirty primary workspace, `.worktrees/` was added to
`.gitignore`, committed, and Ryan selected the project-local isolated path:

```text
.worktrees/github-reconcile/
branch: codex/github-reconcile
```

The pre-merge unit baseline ran eight tests: seven passed and one failed because
`tests/unit/test_prepare_term4code02.py` hardcodes `/bin/printf`, while Minnie
provides `/usr/bin/printf`. Ryan explicitly approved proceeding with that known
baseline failure.

Exact merge command:

```sh
git merge --no-ff github/main \
  -m 'merge GitHub main into Niagara CI reconciliation'
```

The merge completed without conflicts as commit
`8729172` before this notebook update. Both `github/main` and the complete
Gitea/preflight lineage were verified as ancestors. The Niagara Woodpecker
definitions, assembly script, launcher, and evidence notebook all survived.

A disposable pytest environment was created outside the repository at
`/private/tmp/niagara-reconcile-pytest`. Exact expanded test command:

```sh
/private/tmp/niagara-reconcile-pytest/bin/pytest -q tests/unit
```

Result:

```text
72 passed
16 subtests passed
1 failed: the same pre-existing /bin/printf portability failure
```

The four Niagara Bash scripts passed `bash -n`, and both Woodpecker YAML files
parsed successfully with Ruby's YAML parser. `git diff --check 42df967..HEAD`
reported only three blank-line-at-EOF findings from GitHub content:

```text
notes/DISK-LINEAGE-AND-PROMOTION.md
notes/EC2-WORKSTATION-CHANNEL-RUN-20260826.md
what-is-this-disk-lunacy-sir.md
```

They were not introduced or silently rewritten during reconciliation.

Result: **PASS WITH KNOWN BASELINE PORTABILITY FAILURE**. The two histories are
now one conflict-free lineage in the isolated branch. The next safe delivery
is to push this reconciled HEAD to GitHub branch
`codex/niagara-login-preflight`, which selects only the read-only Woodpecker
gate.

Private-delivery follow-up: publishing this evidence to the public
`qemu-sun4v-illumos` repository was rejected. Ryan selected a private GitHub
sibling instead. `ryancnelson/niagara-qemu-solaris-lab` was created with
private visibility and `main` as its default branch. Reconciled commit
`3a7190a8237b8cef91f44083a08a896ae08c4dd1` was pushed to both `main` and
`codex/niagara-login-preflight`; the public repository was not modified.

After explicit action-time approval, the private repository was enabled in
biggie's GitHub-backed Woodpecker 3.18 service as repository ID 2. The UI
confirmed the private forge URL and initially reported that no pipelines had
started, as expected because the first branch push predated activation. This
notebook commit is the deliberate fresh push used to trigger only the
branch-scoped, read-only preflight workflow.

### EXP-20260831-34: Woodpecker preflight success and tmpfs O_DIRECT failure

Layer: private GitHub delivery, biggie Woodpecker, ec2trib outer ZFS assembly,
tmpfs unit100, and QEMU process creation.

Private Woodpecker pipeline 1 ran commit `e67fa16b2b` on branch
`codex/niagara-login-preflight` and passed in 10 seconds. Its ec2trib output
included:

```text
NIAGARA_LOGIN_PREFLIGHT=PASS
qemu_commit=049affb20df67162cf58deeaf74d5ad4b83cbdc3
unit100_fs=tmpfs
unit100_available_kib=6031100
unit100_sha256=70d436dab85c3fc9444c2df0cf47075c11e27fab4cc2fbe72929b2ead37fd735
unit104_source_snapshot_guid=370532935438843004
unit104_bytes=64424509440
unit104_inner_pool_guid=18135893029031842473
launcher_sha256=d256e46fbb8e31e47acadd9f435037acf44f527a1c0d85bfde719c55f50e6485
```

The same commit was then pushed to `codex/niagara-login-ci`. Pipeline 2 passed
preflight and assembled clone:

```text
dataset: tink/qemu-sun4v-illumos-ci/woodpecker-2
dataset GUID: 5217046573466983192
origin: tink/qemu-sun4v-illumos-ci/trial-0001-clone-probe@pre-boot-unit104-login-trial-0001
unit104: /tink/qemu-sun4v-illumos-ci/woodpecker-2/baselines/unit104-login-proven-20260826T210446Z.raw
```

The launch step failed before a live console appeared. The preserved launcher
and QEMU logs identified the exact boundary:

```text
qemu-system-sparc64: ... carrier-unit100.raw: filesystem does not support O_DIRECT
qemu_exit_status=1
```

Root cause: unit100 moved from ZFS to Tribblix tmpfs, but its QEMU drive retained
`cache=none`. QEMU implements that setting with `O_DIRECT`, which this tmpfs
does not support. QEMU never started. No QEMU process remained, the 1 GiB
tmpfs unit100 was removed and `/tmp` returned to 1% use, NVRAM was unchanged,
and the newly assembled unit104 clone was preserved.

A regression test was added at
`tests/unit/test_niagara_login_launcher.py`. Before the fix it failed because
the unit100 drive contained `cache=none`. The one-variable implementation
change sets only unit100 to `cache=writeback`; unit103 and unit104 retain
`cache=none`. Host and QEMU access to the tmpfs regular file now share the host
page cache, while the persistent disks keep their previous direct-I/O policy.

Verification:

```text
targeted regression: 1 passed
full unit suite: 73 passed, 16 subtests passed
known baseline: 1 failure from hardcoded /bin/printf on Minnie
launcher bash -n: PASS
Woodpecker YAML parse: PASS
```

The fix was committed as `6fdbaf9` and replayed through both branch-scoped
workflows. Private pipeline 3, on `codex/niagara-login-preflight`, passed in 9
seconds. Private pipeline 4, on `codex/niagara-login-ci`, then passed all three
stages (preflight, clone, launch) in 34 seconds. Its launch output was:

```text
trial_id=woodpecker-4
target_dataset=tink/qemu-sun4v-illumos-ci/woodpecker-4
unit104_path=/tink/qemu-sun4v-illumos-ci/woodpecker-4/baselines/unit104-login-proven-20260826T210446Z.raw
run_id=niagara-woodpecker-4
run_dir=/tink/runs/niagara-woodpecker-4
assembly_manifest=/tink/runs/woodpecker-niagara-login/woodpecker-4/assembly-manifest.txt
launcher_pid=12549
qemu_pid=12613
console_socket=/tink/runs/niagara-woodpecker-4/console.sock
qmp_socket=/tink/runs/niagara-woodpecker-4/qmp.sock
launch_log=/tink/runs/woodpecker-niagara-login/woodpecker-4/launcher.log
NIAGARA_UNIT104_LAUNCH=PASS
```

The launch is therefore independently reproducible from a private GitHub
branch push. `woodpecker-4` is the first successful Woodpecker-created live
trial; `woodpecker-2` remains preserved as the failed O_DIRECT experiment and
must not be relabeled. At the time of this entry, Old Sun MCP target discovery
and status both failed at the broker control socket with `[Errno 1] Operation
not permitted`. No console target was guessed or written, and QEMU PID 12613
was left running untouched for broker recovery and boot verification.

Result: **PASS THROUGH LIVE QEMU CREATION; GUEST BOOT VERIFICATION PENDING**.

### EXP-20260831-35: Woodpecker owns the OpenBoot transition

Layer: private GitHub delivery, Woodpecker orchestration, ec2trib QEMU serial
ownership, and shared Old Sun console handoff.

Pipeline 4 had stopped at a live `ok` prompt. Inspection showed that
`scripts/ec2trib-niagara-launch-unit104.sh` declared
`NIAGARA_UNIT104_LAUNCH=PASS` as soon as `console.sock`, `qemu.pid`, and a live
process existed. The proven command was only printed and recorded in the run
manifest; no workflow component sent it. This was an orchestration defect, not
an OpenBoot or disk failure.

Firmware auto-boot was deliberately not substituted. The prior persistent
NVRAM sprint proved that this Niagara firmware routes variable changes through
the missing LDOM Variable Updates provider: `setenv auto-boot? true` is accepted
only in-process and does not update the mapped NVRAM image. The bounded CI
mechanism instead owns the initial serial connection:

1. Woodpecker stages `scripts/ec2trib-niagara-openboot.py` on ec2trib.
2. The launch wrapper sets `CONSOLE_WAIT=on`, causing QEMU's serial socket to
   wait for this bootstrap client before firmware begins.
3. The helper connects, waits for a line-start OpenBoot `ok ` prompt, sends
   exactly `boot /virtual-devices@100/disk@4:a -k -v` plus carriage return,
   and requires the command echo.
4. Only after that handshake does the wrapper emit
   `NIAGARA_OPENBOOT_COMMAND=PASS` and `NIAGARA_UNIT104_LAUNCH=PASS`.
5. The helper closes, allowing the shared Old Sun broker to attach for the
   continuing human/MCP console session.

Local verification at commit `2699f08`:

```text
focused protocol/wiring tests: 3 passed
full unit suite: 75 passed
known baseline: 1 failure from hardcoded /bin/printf on Minnie
launcher bash -n: PASS
OpenBoot helper py_compile: PASS
Woodpecker YAML parse: PASS
git diff --check: PASS
```

The exact private delivery commands were:

```text
git push private-github HEAD:refs/heads/codex/niagara-login-preflight
git push private-github HEAD:refs/heads/codex/niagara-login-ci
```

Private pipeline 5 passed the read-only preflight in 9 seconds. Before the live
replay, the still-idle trial-4 launcher PID 12549 was sent TERM after its
parent/child relationship to QEMU PID 12613 was reverified. Its normal cleanup
recorded QEMU status 143, unchanged before/after NVRAM hashes, and removal of
only `/tmp/niagara-woodpecker-4/carrier-unit100.raw`; its outer unit104 clone
and logs remain preserved.

Private pipeline 6 passed in 53 seconds and created:

```text
trial_id=woodpecker-6
target_dataset=tink/qemu-sun4v-illumos-ci/woodpecker-6
unit104_path=/tink/qemu-sun4v-illumos-ci/woodpecker-6/baselines/unit104-login-proven-20260826T210446Z.raw
run_id=niagara-woodpecker-6
qemu_pid=14649
console_socket=/tink/runs/niagara-woodpecker-6/console.sock
openboot_log=/tink/runs/woodpecker-niagara-login/woodpecker-6/openboot-injector.log
```

Its launch-stage log captured the discriminating evidence:

```text
ok boot /virtual-devices@100/disk@4:a -k -v
NIAGARA_OPENBOOT_COMMAND=PASS command=boot /virtual-devices@100/disk@4:a -k -v
NIAGARA_OPENBOOT_COMMAND=PASS
NIAGARA_UNIT104_LAUNCH=PASS
```

Old Sun rediscovery found the new target as ec2trib PID 14649, socket
`/tink/runs/niagara-woodpecker-6/console.sock`, opaque ID
`d09fab405700507a6f384ded`. After explicit selection, the broker connected and
observed the continuing OpenBoot disk-loading spinner. No human or MCP boot
command was sent.

The spinner subsequently transitioned into the illumos kernel. The attach
block is a useful cross-layer identity check:

```text
hsimd4: hsimd_attach: size:0xf00000000, cap:0x5
hsimd4: hsimd_attach: part 0 16065 - 125788950 a 0x0
hsimd4: hsimd_attach: part 2 0 - 125829120 c 0x5
hsimd4: add_intr failed err:1
hsimd4 is /virtual-devices@100/disk@4
root on rpool/ROOT/openindiana fstype zfs
```

`0xf00000000` is exactly 64,424,509,440 bytes, the recorded unit104 image
size. The partition values are consistent with VTOC start/count pairs: slice
`a` starts at sector 16,065 and has 125,788,950 sectors, while slice `c`
covers all 125,829,120 sectors. That interpretation agrees with the vendored
source's `dk_map32` to `p_start`/`p_size` conversion, but is deliberately not
claimed as proof that the running binary was built from the pinned source
commit. The interrupt-registration error was nonfatal in this boot: attachment
completed and ZFS mounted the device as root.

After root mount, the guest printed:

```text
WARNING: svccfg apply /etc/svc/profile/generic.xml failed
svc.startd: Transitioning svc:/system/filesystem/root-minimal:default to maintenance
because it completes a dependency cycle
```

The reported cycle runs through identity, physical network, varpd,
device/local, `/usr`, boot-archive, root, and root-minimal. It was reported
twice while device initialization continued (`zfs0`, `devinfo0`, `drctl0`,
`iscsi0`, and `fcode0` attached afterward). This is not the earlier
missing-`/usr/bin/awk` devfsadm failure and not a storage attach failure. The
guest then completed all eight ZFS filesystem mounts and produced:

```text
Mounting ZFS filesystems: (1/8) ... (8/8)
oi-basecamp console login:
```

Pipeline 6 itself ended after the OpenBoot command-echo handshake; the shared
broker independently observed the later kernel, root-mount, hsimd, and login
evidence. Therefore this experiment proves the full assembly/launch/boot/login
outcome, while also preserving the precise current CI boundary: the workflow
does not yet withhold its PASS marker until the login prompt.

Result: **PASS: WOODPECKER ASSEMBLED AND BOOTED UNIT104; GUEST REACHED LOGIN**.

### EXP-20260831-36: make guest login the Woodpecker success boundary

Time: 2026-08-31 15:09-15:29 America/Los_Angeles (Woodpecker UI time)

Live run identity: `niagara-woodpecker-9`; launcher PID 15138; QEMU PID
15202; console socket `/tink/runs/niagara-woodpecker-9/console.sock`.

Artifact identities: private GitHub commit `1c607a5` (`ci: gate Niagara trials
on guest login`); outer dataset
`tink/qemu-sun4v-illumos-ci/woodpecker-9`, dataset GUID
9603146211994785326; unit104 inner-pool GUID 18135893029031842473.

Layer: fake Unix-socket tests, Woodpecker preflight and trial pipelines,
ec2trib QEMU serial ownership, illumos kernel/SMF boot, and Old Sun broker
handoff.

Hypothesis: the launch job can retain the single QEMU serial connection after
sending the OpenBoot command and withhold PASS until the guest emits
`oi-basecamp console login:`. It must fail on timeout, panic, a returned
OpenBoot prompt, or an actual maintenance-shell prompt, while allowing the
known nonfatal SMF dependency-cycle wording.

Prediction: command echo alone will no longer pass. The unchanged accepted
unit104 lineage will attach as hsimd4, mount its ZFS root, pass through the
known SMF warnings, reach login, persist `login_gate=pass`, and only then
release the socket for the shared broker.

Action and mutation class: repository code/tests plus one fresh writable outer
ZFS clone. The protected source snapshot was read-only. The previous live run
was retired through its launcher before creating the new run. No guest login
input or filesystem mutation was sent.

Commands used locally:

```sh
python3 -m pytest -q tests/unit/test_niagara_openboot.py \
    tests/unit/test_niagara_login_launcher.py
python3 -m pytest -q
bash -n scripts/ec2trib-niagara-launch-unit104.sh
python3 -m py_compile scripts/ec2trib-niagara-openboot.py
git diff --check
git push private-github HEAD:refs/heads/codex/niagara-login-preflight
git push private-github HEAD:refs/heads/codex/niagara-login-ci
```

Host lifecycle and broker commands used after verifying the exact PIDs and
paths:

```sh
ssh root@ec2trib '/usr/bin/ps -fp 14587,14649; \
    /usr/bin/cat /tink/runs/niagara-woodpecker-6/qemu.pid'
ssh root@ec2trib '/usr/bin/kill -TERM 14587'
/private/tmp/old-sun-console-cli.mjs -o json guest-console-targets
/private/tmp/old-sun-console-cli.mjs -o json guest-console-select-target \
    --target-id 340872efaa3d196b3680a96b \
    --reason 'Select Woodpecker pipeline 9 QEMU after the login gate passed'
/private/tmp/old-sun-console-cli.mjs -o json guest-console-status
/private/tmp/old-sun-console-cli.mjs -o json guest-console-read --max-bytes 4096
```

The focused suite passed 9 tests. The full suite passed 80 tests and retained
the known Minnie-only failure in `test_prepare_term4code02.py`, whose fixture
requires `/bin/printf`. Bash syntax, Python compilation, and `git diff --check`
passed.

The first preflight push created pipeline 7 and failed closed as designed:

```text
14649 ... qemu-system-sparc64 ...
NIAGARA_LOGIN_PREFLIGHT=FAIL reason=the selected sun4v QEMU is already running
```

The exact ownership chain was verified before shutdown: launcher PID 14587
owned QEMU PID 14649, and the run's `qemu.pid` also contained 14649. TERM was
sent to the launcher, not directly to QEMU. Both processes exited; only
`/tmp/niagara-woodpecker-6` was removed; the unit104 clone and run logs were
preserved. The run manifest recorded `qemu_exit_status=143`, unchanged NVRAM,
and `unit100_removed_utc=2026-08-30T00:15:46Z` (ec2trib clock).

Woodpecker pipeline 8 restarted the identical preflight commit after the host
became idle and passed in 9 seconds. The exact same commit was then pushed to
the trial branch. Pipeline 9 performed these gates:

```text
clone                               PASS  00:16
preflight-ec2trib-niagara-login     PASS  00:06
assemble-writable-unit104-clone     PASS  00:00
launch-niagara-login-trial          PASS  16:15
pipeline total                      PASS  16:38
```

The 16-minute launch duration is important: this job no longer returns after
the OpenBoot command echo. The staged helper used one absolute 900-second
console deadline after launch setup. Its successful exit is possible only
after the configured marker is observed; the launcher then persists the gate
result before emitting its own PASS.

The durable console log records the discriminating boot evidence:

```text
ok boot /virtual-devices@100/disk@4:a -k -v
OpenIndiana Hipster 2025.12 Version illumos-31d3d510d0 64-bit
hsimd4: hsimd_attach: size:0xf00000000, cap:0x5
hsimd4: hsimd_attach: part 0 16065 - 125788950 a 0x0
hsimd4: hsimd_attach: part 2 0 - 125829120 c 0x5
hsimd4: add_intr failed err:1
hsimd4 is /virtual-devices@100/disk@4
root on rpool/ROOT/openindiana fstype zfs
WARNING: svccfg apply /etc/svc/profile/generic.xml failed
Transitioning svc:/system/filesystem/root-minimal:default to maintenance
because it completes a dependency cycle
Mounting ZFS filesystems: (1/8) ... (8/8)
oi-basecamp console login:
```

The generic SMF maintenance wording did not falsely trip the maintenance-shell
detector. The run manifest agrees with the console:

```text
login_gate=pass
login_marker=oi-basecamp console login:
login_gate_observed_utc=2026-08-30T00:24:28Z
```

After the helper released serial ownership, Old Sun target discovery returned
exactly one live ec2trib target: PID 15202, socket
`/tink/runs/niagara-woodpecker-9/console.sock`, opaque target ID
`340872efaa3d196b3680a96b`. It was explicitly selected and connected. Broker
history began at zero because attachment occurred after login; the preserved
host console log is the authoritative pre-handoff transcript. MCP writes are
not blocked, but no guest input has been sent.

Result: **PASS: WOODPECKER ITSELF GATED THE TRIAL ON THE GUEST LOGIN PROMPT**.

### EXP-20260831-37: qualify b134 and Solaris 11.4 boot archives for hsimd injection

Time: 2026-08-31 PDT

Artifact identities:

- OpenSolaris b134 text installer source:
  `~/Downloads/textinstall-134-sparc.iso`
- b134 `/platform/sun4u/boot_archive.`: 191,527,936 bytes,
  SHA-256
  `95f2ca0fdb3b3fd1206e98694d4aa1fa720ed4c0e058cc63a946f2d3278a70c7`
- Complete Solaris 11.4 AI SPARC source on ec2trib:
  `/tink/sol-11_4-ai-sparc.iso`, 648,458,240 bytes
- Solaris 11.4 `/platform/sun4v/boot_archive.`: 417,894,400 bytes,
  SHA-256
  `5a116f5b2c36994008906003f9b290caed67ba07132256d9c16a865b8122fd74`
- Original Solaris 10 hsimd candidate:
  `captures/openindiana-live-20260824/extracted/hsimd`, 19,576 bytes,
  POSIX cksum `851234025 19576`, SHA-256
  `d6d5f292ac5a395ad0ad763784e017c81b9200105c1b62a6c0f48acdccf01205`

Layer: fixed-size UFS boot archives inside SPARC installation ISOs.

Hypothesis: the already-proven Tribblix/OpenIndiana archive-injection method is
structurally applicable to both b134 and Solaris 11.4 media. Tribblix/x86 may
identify and mount these SPARC big-endian UFS archives directly; if it cannot,
a SPARC Solaris-family donor remains the required archive editor.

Prediction: both extracted files contain a big-endian UFS superblock. A
read-only lofi probe either mounts them without changing them or establishes a
clean, reproducible host-endianness boundary.

Commands:

```text
python3 tools/iso-extract.py get \
  ~/Downloads/textinstall-134-sparc.iso \
  /platform/sun4u/boot_archive. \
  /private/tmp/niagara-iso-inspect-b134

scp /private/tmp/niagara-iso-inspect-b134/boot_archive. \
  root@ec2trib:/tink/tmp/niagara-iso-inspect-b134/boot_archive.b134.ufs

/tmp/niagara-iso-extract.py get \
  /tink/sol-11_4-ai-sparc.iso \
  /platform/sun4v/boot_archive. \
  /tink/tmp/niagara-iso-inspect-s114

/tmp/ec2trib-inspect-boot-archive.sh \
  /tink/tmp/niagara-iso-inspect-b134/boot_archive.b134.ufs

/tmp/ec2trib-inspect-boot-archive.sh \
  /tink/tmp/niagara-iso-inspect-s114/boot_archive.

stat -f "%z %N" captures/openindiana-live-20260824/extracted/hsimd
cksum captures/openindiana-live-20260824/extracted/hsimd
shasum -a 256 captures/openindiana-live-20260824/extracted/hsimd
```

The repository copy of the inspection command is
`scripts/ec2trib-inspect-boot-archive.sh`. It attaches with `lofiadm -r`, uses
the corresponding `/dev/rlofi` node for `fstyp`, requests a read-only mount,
and unmounts/detaches automatically on every exit path.

Result:

- Both archives have UFS magic `00 01 19 54` at byte offset 17,756.
- b134 is an uncompressed big-endian UFS v1 archive last written 2010-03-10.
- The complete Solaris 11.4 archive is also an uncompressed big-endian UFS
  archive. The much smaller Minnie copy of `sol-11_4-ai-sparc.iso` is
  truncated and is explicitly disqualified as an input.
- On ec2trib, both files attached read-only as `/dev/lofi/8` with matching
  `/dev/rlofi/8`, but Tribblix/x86 `fstyp` returned
  `unknown_fstyp (no matches)` for each raw node. The cleanup trap removed
  each temporary unit8 mapping. Pre-existing lofi units 2, 3, 6, and 7 were
  observed and left untouched.
- The exact 19,576-byte Solaris 10 driver used in the prior OpenIndiana work
  is present in the repository and matches its recorded POSIX checksum.

Interpretation: **PASS for archive qualification; BLOCKED for direct
Tribblix/x86 UFS mounting.** The fixed-size replacement method applies to both
media layouts, but archive contents must be edited in a SPARC workbench. The
Solaris 10 origin of the original hsimd binary is encouraging for b134 and its
successful load on modern OpenIndiana is encouraging for Solaris 11.4, but
each target still needs independent module-load and device-attach gates.

Artifacts created:

- `scripts/ec2trib-inspect-boot-archive.sh`
- `/tink/tmp/niagara-iso-inspect-b134/boot_archive.b134.ufs`
- `/tink/tmp/niagara-iso-inspect-s114/boot_archive.`

Next test: boot or reuse an isolated SPARC Solaris-family workbench, attach the
b134 archive read-only first, and inventory its existing hsimd files and three
driver-registration databases. Do not modify it until that inventory and an
exact writable-copy/readback procedure are recorded. Repeat independently for
Solaris 11.4.

### EXP-20260831-38: prove lofi in the fast Solaris 9 SPARC workbench

Time: 2026-08-31 PDT

Live run identity: Woodpecker repository 1
`ryancnelson/tribblix-woodpecker`, pipeline 19, commit
`f92fdc4a28fbf58c8a82ea4f2c1eae44609f7bf9` on branch
`codex/solaris9-lofi-probe`.

Layer: disposable-overlay Solaris 9 sun4m workbench on ec2trib.

Hypothesis: the proven fast Solaris 9 SPARC VM includes lofi even though it
predates ZFS, making it suitable for native-endian standalone UFS archive
inspection and editing.

Prediction: `/usr/sbin/lofiadm` exists, opens successfully, and causes a lofi
kernel module to appear in `modinfo`.

Action and mutation class: Woodpecker booted the existing Solaris 9 VM using
six explicit qcow2 overlays. The guest-root disks were disposable; no target
archive was attached and no durable guest filesystem was changed.

Guest command sent by the checked-in console probe:

```text
if test -x /usr/sbin/lofiadm; then
  echo SOLARIS9_LOFI_BINARY=present
  /usr/sbin/lofiadm 2>&1
  /usr/sbin/modinfo 2>&1 | /usr/bin/grep -i lofi
else
  echo SOLARIS9_LOFI_BINARY=absent
fi
echo SOLARIS9_LOFI_PROBE_DONE
```

Result:

```text
SOLARIS9_LOFI_BINARY=present
Block Device File
98 f5a6b78b 1beb 147 1 lofi (loopback file driver (1.13))
SOLARIS9_LOFI_PROBE_DONE
SOLARIS9_LOFI_TEST=PASS
```

Pipeline 18 is explicitly invalid as evidence: its first probe accepted marker
text echoed in the command line before the guest executed the command. Commit
`f92fdc4` changed the parser to require marker-only output lines. Pipeline 19
then passed that corrected gate in 1 minute 30 seconds.

Interpretation: **PASS. Solaris 9 has a functional lofi control path and is a
credible native-SPARC UFS archive workbench.** This proves lofi availability,
not yet attachment or mounting of either target archive.

Artifacts created in the `tribblix-woodpecker` repository:

- `.woodpecker/solaris9-lofi-probe.yml`
- lofi mode in `scripts/solaris9-console-probe.py`
- `PROBE_MODE` selection in `scripts/ec2trib-solaris9-boot-test.sh`

Related backlog: `P3-037` now records the separate possibility of combining a
Solaris 9-compatible FUSE implementation with zfs-fuse for read-only SPARC
workbench use. That is not on the critical UFS path.

Next test: expose the immutable b134 archive to this same disposable Solaris 9
guest, attach it with `lofiadm`, run `fstyp` on the raw lofi device, mount it
read-only, and inventory the hsimd module and driver-registration files. The
pipeline must prove cleanup of the guest lofi mapping and QEMU work disk.

### EXP-20260831-39: attach b134 archive read-only to Solaris 9 sun4m

Time: 2026-08-31 PDT

Artifact: immutable host file
`/tink/tmp/niagara-iso-inspect-b134/boot_archive.b134.ufs`, attached to QEMU as
a raw, read-only `scsi-hd` at target 7 by
`scripts/qemu-with-readonly-work-disk.sh` in `tribblix-woodpecker`.

The workbench uses its normal six explicit qcow2 overlays. Each trial now also
uses pipeline-number-specific `VM_ROOT` and `RUN_ROOT` paths; it does not share
the non-atomic global `latest` symlink with another trial.

Trial chronology:

- Pipeline 20 failed before QEMU exec while using the shared VM root. It
  removed the prior `latest` link but created neither a replacement link nor
  QEMU logs. This is harness evidence only, not a Solaris result.
- Pipeline 21 proved that QEMU accepted the read-only target and Solaris 9
  still booted to a root console. The first inventory command exceeded the
  Solaris 9 console tty input limit, produced bell characters, and was
  truncated before execution. The disposable run was canceled; no filesystem
  command ran against the archive.
- Pipeline 22 correctly refused to overlap the still-cleaning pipeline-21
  QEMU. A host check then confirmed that no Solaris 9 QEMU remained.
- Pipeline 23 is the unchanged restart at commit `5fdea6c`, using a short
  marker-gated command below the measured tty limit. It passed its execution
  gate in 1 minute 33 seconds after waiting behind an unrelated GCC job on the
  single Woodpecker agent.

Short guest command for pipeline 23:

```text
R=/dev/rdsk/c0t7d0s2;if test -c $R;then echo WD=present;/usr/sbin/fstyp $R 2>&1;else echo WD=absent;fi;echo WD=DONE
```

Pipeline 23 result:

```text
SOLARIS9_WORK_DISK_ACTION=readonly-inventory
WD=absent
WD=DONE
SOLARIS9_WORK_DISK_PROBE=COMPLETE
```

Interpretation: **PASS for a valid bounded negative result.** QEMU accepted the
read-only target-7 disk and Solaris 9 booted normally, but the guest did not
create `/dev/rdsk/c0t7d0s2`. SCSI ID 7 is the initiator slot in this topology,
so it is not a usable guest disk target. No `fstyp` or mount ran.

Next test: in a staged copy of the proven launcher, replace its empty target-6
CD device with the same archive as a read-only disk and probe
`/dev/rdsk/c0t6d0s2`. If Solaris does not expose the standalone unlabeled UFS
archive there, carry it into the guest as a regular file and use the proven
Solaris 9 `lofiadm` path.

### EXP-20260831-40: probe standalone b134 archive at SCSI target 6

Time: 2026-08-31 PDT

Woodpecker pipeline: repository 1, pipeline 24, commit `cba8022`.

Hypothesis: target 7 failed because it is the SCSI initiator slot; replacing
the launcher's empty target-6 CD with the immutable b134 archive as a raw,
read-only `scsi-hd` may expose the archive as a usable whole disk.

Runner-generation command:

```sh
/tmp/woodpecker-solaris9-lofi-24/prepare-sun4m-workdisk-runner.sh \
    /tink/sun4m-solaris9/run-qemu.sh \
    /tmp/woodpecker-solaris9-lofi-24/run-qemu-workdisk.sh \
    /tink/tmp/niagara-iso-inspect-b134/boot_archive.b134.ufs
```

Recorded identities:

```text
source launcher SHA256:    5febe79d1f0a7b33a029f5cfa04e2175b6354d92a2bcd482bc779fb4dea555ff
generated launcher SHA256: 216db6e58e7fbbb40fc35c11c8ebbbbf372dd3b09a4991884b50ef2a464bd38d
```

Guest probe result: Solaris 9 created `/dev/rdsk/c0t6d0s2`, but `sd6` reported
`Corrupt label; wrong magic number`. `fstyp` attempted `hsfs`, encountered I/O
errors, and ended with `Unknown_fstyp (no matches)`.

Interpretation: **bounded negative result.** The standalone boot archive is a
UFS filesystem image, not a Sun-labeled whole disk. QEMU can attach it at a
usable target, but Solaris's physical-disk path expects a disk label before it
will expose the embedded filesystem correctly. Do not add a label to the
immutable archive merely to satisfy this path; carry the unchanged archive as
a regular file and attach that file through lofi.

### EXP-20260831-41: carry b134 archive into Solaris 9 and mount through lofi

Time: 2026-08-31 PDT

Successful Woodpecker pipeline: repository 1, pipeline 29, commit `f53a080`.

Hypothesis: an ISO9660 carrier can preserve the standalone b134 archive as a
regular file. Solaris 9 can mount the carrier as HSFS, attach the archive file
through its native lofi 1.13 driver, identify the resulting raw device as UFS,
and mount it read-only without relying on a Sun disk label.

The reproducible carrier build is implemented by
`scripts/build-solaris9-archive-carrier.sh` in `tribblix-woodpecker`. Its
material construction command is:

```sh
/usr/bin/mkisofs \
    -quiet \
    -iso-level 1 \
    -R \
    -V NIAGB134 \
    -graft-points \
    -o "$OUTPUT" \
    B134.UFS="$ARCHIVE" \
    PROBE.SH="$PROBE"
```

The script then verifies the exact ISO on the Tribblix host without reading
the 191 MB archive a second time solely for a checksum:

```sh
LOFI=$(/usr/sbin/lofiadm -r -a "$OUTPUT")
/usr/sbin/mount -F hsfs -o ro "$LOFI" "$CHECK_MOUNT"
test -r "$CHECK_MOUNT/B134.UFS"
test -r "$CHECK_MOUNT/PROBE.SH"
/usr/bin/cmp "$PROBE" "$CHECK_MOUNT/PROBE.SH"
/usr/sbin/umount "$CHECK_MOUNT"
/usr/sbin/lofiadm -d "$LOFI"
```

Tribblix already had the required ISO builder. No package installation was
performed:

```text
/usr/bin/mkisofs: mkisofs 3.01 (i386-pc-solaris2.11)
owner: TRIBcdrtools 3.01.1
```

The documented pkgsrc tool prefix `/tink/pkg-2023-Q3` was incorrect on this
host; the actual prefix is `/tink/pkg-2023Q3`. The pkgsrc cdrtools source is
`/tink/pkgsrc/pkgsrc/sysutils/cdrtools`, but it was not needed.

The carrier remains a CD at target 6. The generated launcher replaces only
the empty `drive7` declaration with this read-only ISO and preserves the
existing `scsi-cd` device. The guest-side console command is 160 bytes:

```sh
/etc/init.d/volmgt stop;umount /dev/dsk/c0t6d0s0 2>/dev/null;mkdir -p /mnt/carrier;mount -F hsfs -o ro /dev/dsk/c0t6d0s0 /mnt/carrier&&sh /mnt/carrier/PROBE.SH
```

The `volmgt` stop is required because Solaris 9 automatically mounts inserted
CD media before root login. The probe logs in as `root` with no password at
`solaris console login:` and deliberately ignores later desktop/X-server
messages.

Iteration chronology:

- Pipeline 25 failed in host verification because `TRIBcdrtools` supplies
  `mkisofs` but not `/usr/bin/isoinfo`. Verification was changed to the host's
  proven lofi + HSFS path.
- Pipeline 26 passed carrier creation and host verification, then found target
  6 already mounted by Solaris volume management. The run was canceled after
  capturing that result.
- Pipeline 27 mounted the carrier and ran `PROBE.SH`; Solaris 9 lofi 1.13
  rejected the newer `-r` option. The guest invocation was changed from
  `lofiadm -r -a` to the Solaris 9 syntax `lofiadm -a`. The carrier and UFS
  mounts remain read-only.
- Pipeline 28 attached `/dev/lofi/1` and reported UFS, then exposed that
  Solaris 9 `/bin/sh` `test` lacks `-e`. The inventory check now uses `-r`.
- Pipeline 29 passed the complete construction, host verification, boot,
  login, HSFS mount, lofi attach, UFS identification and mount, inventory,
  unmount, lofi detach, and QEMU cleanup sequence.

Pipeline 29 identities and gates:

```text
SOLARIS9_CARRIER_ARCHIVE_SHA256=95f2ca0fdb3b3fd1206e98694d4aa1fa720ed4c0e058cc63a946f2d3278a70c7
SOLARIS9_CARRIER_PROBE_SHA256=11480c10daedd91df8fd65d5c3a6baa4679b45240c5f958a76182f13a8118e1e
SOLARIS9_CARRIER_ISO_SHA256=99e6738c0538623ef92ab343cbdede9689168796e218289c879448632c04d532
SOLARIS9_CARRIER_ISO_BYTES=191889408
SOLARIS9_CARRIER_HOST_VERIFY=PASS
SOLARIS9_CARRIER_RUNNER_SOURCE_SHA256=5febe79d1f0a7b33a029f5cfa04e2175b6354d92a2bcd482bc779fb4dea555ff
SOLARIS9_CARRIER_RUNNER_SHA256=a544364103fd69a9062ec96c942afc404c295bdc76b3c26451043ec4a341d9df
SOLARIS9_LOGIN_ACTION=root
SOLARIS9_B134_LOFI=/dev/lofi/1
SOLARIS9_B134_RAW_LOFI=/dev/rlofi/1
SOLARIS9_B134_FSTYP=ufs
SOLARIS9_B134_LOFI_PROBE=PASS
SOLARIS9_CARRIER_PROBE=PASS
```

Read-only b134 inventory:

```text
-rw-r--r-- 1 root sys  3125 Mar  9 2010 /mnt/b134/etc/name_to_major
-rw-r--r-- 1 root sys  3474 Mar 10 2010 /mnt/b134/etc/driver_aliases
-r--r--r-- 1 root root   90 Mar 10 2010 /mnt/b134/etc/path_to_inst
-rw-r--r-- 1 root sys  1425 Mar 10 2010 /mnt/b134/etc/system
SOLARIS9_B134_MISSING=platform/sun4v/kernel/drv/sparcv9/hsimd
```

No `hsimd` registration lines were present in `name_to_major`,
`driver_aliases`, or `path_to_inst`.

Interpretation: **PASS.** The fast Solaris 9 sun4m workbench is now a proven
big-endian UFS inspection path for standalone boot archives. This answers the
foundational read side of the archive-editing loop without guest networking,
guest SSH, or a Sun disk label.

Next test: make a uniquely named writable copy of the b134 archive, carry that
copy into Solaris 9 on writable media, mount it read/write through lofi, add
the pinned hsimd binary and the minimum required registration, cleanly unmount
and detach, then prove byte-for-byte readback before attempting ISO splice or
boot. Keep the original b134 archive immutable.

## Resume here — current state after EXP-41

This section is the canonical restart point. Conversation search is optional
archaeology; it is not required to determine what to do next.

Current proven system:

- Private GitHub repository: `ryancnelson/niagara-qemu-solaris-lab`.
- Tested orchestration commit on both Woodpecker branches:
  `1c607a5` (`ci: gate Niagara trials on guest login`).
- Notebook/evidence branch: `codex/github-reconcile`; this EXP-36 entry is the
  first documentation change after `1c607a5`.
- Woodpecker pipeline 9 created outer ZFS clone
  `tink/qemu-sun4v-illumos-ci/woodpecker-9` from the protected held source
  snapshot and gated its launch on the guest login marker.
- Live run: `niagara-woodpecker-9`, launcher PID 15138, QEMU PID 15202,
  console socket `/tink/runs/niagara-woodpecker-9/console.sock`.
- Old Sun target at discovery time: `340872efaa3d196b3680a96b`. This ID is
  opaque and must be rediscovered after any QEMU restart.
- The guest is intentionally left running at `oi-basecamp console login:`;
  no login input has been sent.

Current unit contract:

- unit100: disposable RAM-backed raw carrier/channel object only;
- unit103: immutable installer/boot-media object;
- unit104: writable 60 GiB outer-ZFS-cloned OpenIndiana root candidate.

What EXP-36 proves:

- Woodpecker, not a human or MCP client, sends
  `boot /virtual-devices@100/disk@4:a -k -v` after an observed OpenBoot prompt.
- illumos attaches the QEMU unit104 object as `hsimd4`, reads its VTOC, and
  mounts `rpool/ROOT/openindiana` as ZFS root.
- The SMF root-minimal dependency cycle and `svccfg ... generic.xml` warnings
  are nonfatal in this exact run; device initialization continues and all
  eight ZFS filesystems mount.
- The complete assembly/launch/boot sequence reaches a console login prompt,
  and Woodpecker withholds PASS until that exact prompt is observed.

What is not yet proved or implemented:

- No candidate mutation input has yet been applied by Woodpecker to the inner
  ZFS root. The workflow currently clones and boots an unchanged accepted
  source.
- The selected long-term architecture still calls for a stable firmware-facing
  UFS boot object plus an iterative ZFS root. The present proof boots directly
  from unit104's ZFS lineage and therefore proves the assembly/control loop,
  not the final boot-device architecture.
- The running hsimd binary has not been proved byte-for-byte reproducible from
  the pinned vendored source commit.
- The b134 and Solaris 11.4 ISO boot archives have now been extracted and
  qualified as fixed-size big-endian UFS inputs. Tribblix/x86 cannot identify
  either through `fstyp`, so their contents require a SPARC workbench.
- Woodpecker repo 1 pipeline 19 proves that the fast disposable-overlay
  Solaris 9 sun4m workbench has `/usr/sbin/lofiadm` and loads loopback file
  driver version 1.13.
- Woodpecker repo 1 pipeline 29 proves the complete read path for b134:
  Tribblix builds and verifies an HSFS carrier, Solaris 9 logs in as root with
  no password, mounts that carrier, attaches the unchanged archive as
  `/dev/lofi/1`, identifies `/dev/rlofi/1` as UFS, mounts it read-only,
  inventories it, and cleans up. The b134 archive contains no hsimd module or
  hsimd registration in the files checked by EXP-41.

Safety boundary on resume:

- Do not mutate or delete the held source snapshot, `woodpecker-2`,
  `woodpecker-4`, `woodpecker-6`, or `woodpecker-9` while their evidence is
  still referenced.
- Do not import the inner rpool on Tribblix while QEMU PID 15202 owns unit104.
- Retire the live run through its launcher cleanup path before a new trial.
- Rediscover and exactly match host, PID, and socket before any Old Sun console
  selection or write.

## Architecture direction: stable boot path, iterative ZFS root

The preferred end state is now:

- a protected, checksummed boot path whose contents change only through an
  explicit promotion step;
- a ZFS root used for iterative system changes;
- a named snapshot or clone for every trial;
- a manifest connecting the boot object, root-pool object, QEMU unit numbers,
  pool GUID, parent snapshot, and observed boot result.

ZFS's on-disk byte-order handling allows the SPARC guest pool to be imported
and manipulated by the x86 Tribblix host. The UFS byte-order problem therefore
does not constrain the normal iterative root workflow.

There are two distinct ZFS layers in the proposed workflow:

1. **Outer Tribblix ZFS.** Store raw guest-disk image files in a host dataset.
   A named host snapshot is the immutable identity of every accepted image.
   Use read-only snapshot views for hashing and inspection, and create a
   writable host clone for each assembly or QEMU trial. Promote a tested clone
   by giving its resulting snapshot a new baseline name.
2. **Inner guest ZFS.** The raw disk image contains the OpenIndiana rpool.
   Tribblix can attach a snapshot view read-only for inspection, or attach a
   writable host clone when the inner pool must be changed. Record the inner
   pool GUID and dataset/boot-environment state alongside the outer snapshot
   identity.

This outer snapshot/clone lineage should replace multi-layer qcow2 ancestry as
the primary artifact-versioning mechanism. Qcow2 may still be used for a
disposable experiment, but it is not the authoritative history.

Pool ownership is exclusive. Before host manipulation, QEMU must be stopped
or detached from that exact candidate and the guest must have exported the
pool. Before guest launch, Tribblix must export the pool and release every
lofi or other host attachment. A pool must never be writable from host and
guest at the same time.

The selected architecture is a separate immutable UFS boot device plus a ZFS
root device. Ryan's operational experience is that OpenBIOS's ZFS reader is
too buggy to make ZFS the dependable firmware-facing boot path. The saved
ec2cicd run proves only that OpenBoot can sometimes load the tested system from
unit104's ZFS-root lineage; it does not make that path reliable enough for the
trial assembly system.

The UFS boot device should hold the OpenBIOS-visible kernel and boot-archive
payload. The separately versioned ZFS root remains the normal target for
iterative system changes. Tribblix outer-ZFS snapshots and clones provide
artifact lineage for both devices.

ZFS does not remove the boot-archive constraint. Tribblix can use the inner
ZFS pool to extract, replace, checksum, and version
`/platform/sun4v/boot_archive`, but that file itself contains a SPARC
big-endian UFS filesystem. Read/write manipulation of that inner UFS still
requires a SPARC guest workbench. Today's work is therefore foundational:
establish a reproducible SPARC archive editor and a Tribblix ZFS-backed image
assembly/versioning system, then keep the boot object stable while most later
changes occur in cloned ZFS roots.

## Automation requirement: Woodpecker CI on biggie

Once the writable outer-clone workflow has succeeded manually, normal trials
must be assembled and launched by Ryan's Woodpecker CI system on `biggie`.
The CI job must execute the same sequence every time; an interactive shell is
for developing or diagnosing the sequence, not for producing an accepted
candidate.

The eventual pipeline contract must include:

- explicit immutable source snapshot identity;
- unique trial and writable-clone identity;
- an exclusive lock preventing concurrent host/guest ownership of the inner
  pool;
- declared filesystem or boot-archive change inputs;
- host attach, inner-pool import, validation, export, and detach stages;
- a pre-QEMU assertion that the inner pool is exported and no host attachment
  remains;
- exact QEMU build, firmware, launcher, unit map, and boot command identities;
- console and host logs plus checksums and a machine-readable trial manifest;
- explicit pass/fail gates;
- promotion of a passing candidate to a new immutable snapshot identity;
- preservation of failed candidates long enough for diagnosis, followed by a
  deliberate cleanup policy.

The execution topology is now verified for clone assembly and boot trials:
the GitHub-backed Woodpecker service on `biggie` runs repository ID 2 and its
agent stages the pinned scripts over SSH to ec2trib, which owns the images and
runs the Tribblix ZFS and QEMU operations. The next unimplemented boundary is
the host-side attach/import/mutate/export/detach stage for the inner rpool.

## Next experiment

The current priority is the writable half of the ISO/archive lane introduced
by EXP-37. Build a disposable, host-mountable PCFS transfer disk containing a
uniquely named copy of the b134 archive and the mutation script. Attach that
disk at a usable non-initiator SCSI target in the Solaris 9 workbench, prove
Solaris 9 can mount PCFS read/write, then attach the archive file through lofi
and mount its UFS read/write. This preserves the archive as a regular file
while providing a bidirectional handoff: Solaris 9 performs big-endian UFS
changes; Tribblix later mounts PCFS to recover and checksum the resulting
archive. Do not mutate the immutable source archive.

After the PCFS shuttle is proved, inject the exact recorded Solaris 10 hsimd
binary with a target-specific unused major number, unmount and check UFS, and
prove byte-for-byte readback before splicing the unchanged-size archive into a
copied ISO. Boot that candidate with separate module-load, attach, and
installer-progress gates. Apply the same procedure to Solaris 11.4 as a
separate experiment; do not infer its ABI result from b134.

The previously planned first declared inner-ZFS mutation remains queued after
this archive-injection lane. Its EXP-36 requirements are unchanged.

## Entry template

```markdown
### EXP-YYYYMMDD-NN: short description

Time:
Live run identity:
Artifact identities:
Layer:
Hypothesis:
Prediction:
Action and mutation class:
Commands:
Result:
Interpretation:
Artifacts created:
Next test:
```
