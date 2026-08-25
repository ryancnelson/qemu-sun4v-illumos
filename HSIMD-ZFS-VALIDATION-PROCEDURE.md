# hsimd + ZFS validation procedure (read-only survey 2026-08-20 20:11 UTC;
# updated 2026-08-20 ~20:35 UTC with verified Stage 2-3 execution;
# reconciled 2026-08-20 by Shell — PLAN section only, see notes/SHELL-PROGRESS.md)

Gilfoyle discipline: every line below is either FACT (observed output in this
session), HYPOTHESIS (labelled, unproven), or PLAN (not yet executed).

**Mutation-gate status as of this update:** guest keystrokes and read-only
guest commands HAVE occurred (Stage 2 and Stage 3, below, executed by the
live console operator). No `zpool create`, no guest write, no QEMU stop/
signal/kill, and no media write have occurred — the scratch ISO's mtime and
size are unchanged from the original survey (verified again at the time of
this update). Stages 4 onward remain PLAN, not executed.

## FACT — host

Host `niagara-playbox` 100.112.174.2, user `niagara` (tailscale SSH).

```
uptime          19:59 up 1:16          (booted Thu Aug 20 18:43 UTC)
last -x reboot  reboot 18:43 still running
                previous entry: reboot Wed Aug 19 21:16   <- NO matching
                                                             'shutdown' record
```

The 18:43 boot has no preceding `shutdown` record. The host went down
uncleanly some time between Aug 19 21:16 and Aug 20 18:43.

Filesystems:

```
/dev/mapper/ubuntu--vg-ubuntu--lv   15G   14G  402M  98%  /
/dev/mapper/ubuntu--vg-images       12G  2.9G  9.1G  24%  /home/niagara/sun4v/images
ubuntu-vg VFree = 0
```

`/` (which holds `~/sun4v/media/`) has **402 MB free**. A second 998 MB
scratch image does not fit there. `~/sun4v/images` has 9.1 GB free and is the
only place a new disposable image can be staged.

No `zdb`, `zpool`, `zfs` binary and no `zfs` kernel module on the host.
Host-side verification must be raw-offset (`dd`/`xxd`/`strings`/`grep -P`).

## FACT — live QEMU and console

```
PID  2803   started Thu Aug 20 19:13:51 UTC   ELAPSED ~57m   %CPU 100   STAT Sl+
     tty pts/6, fd 0/1/2 -> /dev/pts/6
     ppid 2801 (sudo, pts/6) -> ppid 2797 (sudo, pts/5) -> ppid 2159 (tmux)
/home/niagara/niag-proj/qemu/build/qemu-system-sparc64 \
  -M niagara -L /home/niagara/sun4v/firmware/base-1gib -m 1024 -nographic \
  -drive if=pflash,file=/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso,format=raw
```

tmux sessions on the host: `rootpane` (root shell) and `tribblix-zfs-test`.
The guest console is `tribblix-zfs-test` **window 1, pane 0**; window 0 is an
idle `bash`. There is a double `sudo` pty layer between the tmux pane and
QEMU — that is the same shape as the input path that previously stopped
executing commands.

QEMU banner in that pane:

```
niagara: msync on SIGUSR2 -> kill -USR2 2803
niagara: vdisk 997 MB MAP_SHARED from .../tribblix-m34-hsimd-zfs-scratch.iso
```

**STALE, superseded below:** the original survey found the console
"unchanged across two captures 12 minutes apart" and "parked at the
maintenance username prompt... nothing typed into it this boot." That is no
longer true. The live console operator has since typed into this session.

Earlier in the same scrollback (this boot, `ok boot disk -sv`):

```
virtual-device: hsimd0
hsimd0 is /virtual-devices@100/disk@0
pseudo-device: zfs0
zfs0 is /pseudo/zfs@0
```

## FACT — Stage 2/3 executed by the live console operator (2026-08-20 ~20:27 UTC)

Read via `sane-look-at-pane tribblix-zfs-test:1.0` — see "sane-tmux tooling"
note below; this replaced raw `tmux capture-pane` for read-only console
inspection with no risk of injecting keystrokes.

Console tail, in order:

```
Enter user name for system maintenance (control-d to bypass): root
Invalid input. Please input a number (1,2,...):47
/usr/share/lib/keytables/type_6/layout_21, line 78: invalid function key number
root
Enter root password (control-d to bypass):
single-user privilege assigned to root on /dev/console.
Entering System Maintenance Mode
Aug 20 13:24:46 su: 'su root' succeeded for root on /dev/console
The illumos Project     tribblix-m34    April 2026
root@tribblix:/root# modinfo | grep hsimd
115 7bab25e8   1e48 265   1  hsimd (hsimd)
root@tribblix:/root# ls -l /dev/dsk/c1d0s* /dev/rdsk/c1d0s*
[... all 8 slices present under both /dev/dsk and /dev/rdsk ...]
root@tribblix:/root# dd if=/dev/rdsk/c1d0s7 bs=512 count=1 2>/dev/null | head -1
HSIMD-ZFS-CANARY-20260820
root@tribblix:/root# digest -a sha256 /dev/rdsk/c1d0s7
digest: error reading file: No space left on device
digest: crypto operation failed for file /dev/rdsk/c1d0s7: CKR_GENERAL_ERROR
root@tribblix:/root# dd if=/dev/rdsk/c1d0s7 bs=512 count=10 2>/dev/null | digest -a sha256
3b0765bdc7171a059616724e07d5c0f1190dec556da6eb88af1d41ff9279d3b7
root@tribblix:/root#
```

**Console-discipline note, worth preserving for future operators:** entering
`root` at the username prompt the first time was consumed by an unrelated,
still-running keymap subsystem prompt ("Invalid input. Please input a
number... invalid function key number") rather than by the login prompt
itself. `root` had to be sent a second time to actually reach the username
prompt. This is consistent with the already-known `system/keymap:default`
SMF failure (see the maintenance-mode transition banner above) still owning
part of the console at that moment. Not a corruption or a dropped line — a
second, identical keystroke resolved it. Operators should expect this and
read back before assuming a stuck prompt.

**Stage 3 gate — PASSED, independently re-verified:**
- `modinfo` shows hsimd at major 265. Matches expected.
- `c1d0s0`..`c1d0s7` present in both `/dev/dsk` and `/dev/rdsk`. Matches expected.
- s7 sector-0 dump shows `HSIMD-ZFS-CANARY-20260820`. Matches the planted
  canary exactly — s7 guest addressing maps to host offset 710737920 with no
  skew.

**NEW FAILURE MODE, not in the original Stage 3 script — BLOCKER for any
future unbounded raw read of `/dev/rdsk/c1d0s7`:** `digest -a sha256` against
the whole 320 MiB raw device failed with `error reading file: No space left
on device` / `CKR_GENERAL_ERROR`. HYPOTHESIS (unproven): this is the same bug
class already diagnosed for HSFS elsewhere in this project — `hsimd_ioctl()`
warns and returns success on an unsupported command instead of erroring,
sending some consumer (here, whatever `digest`/libc uses to size or seek the
raw device before reading) to a bogus offset that then reads past the real
device and surfaces as `ENOSPC`. Falsifiable prediction: a bounded
`dd ... count=655360 2>/dev/null | digest -a sha256` (full s7 length via a
tool that never probes device size/seek) will succeed where the unbounded
`digest` call does not; if that bounded call *also* fails at a fixed offset,
the hypothesis is false and something in the read path itself is broken past
that point, not just the size/seek probe. Alternative HYPOTHESIS (host-side
real space exhaustion) is disfavored but not excluded by source reasoning
alone: at the time of the failure `/` had 402M free and `~/sun4v/images` had
9.1G free, with no ISO write in progress — checked moments later, not at the
exact instant of the error.

**Independent readback — PASSED, verified by both sides, not inferred:**
guest command `dd if=/dev/rdsk/c1d0s7 bs=512 count=10 2>/dev/null | digest -a
sha256` produced `3b0765bdc7171a059616724e07d5c0f1190dec556da6eb88af1d41ff9279d3b7`.
Independently, host-side (this session, read-only, against the live scratch
ISO, not inferred from the guest output):
```
dd if=/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso \
   bs=512 skip=1388160 count=10 2>/dev/null | sha256sum
3b0765bdc7171a059616724e07d5c0f1190dec556da6eb88af1d41ff9279d3b7  -
```
Byte-identical. This is the first *quantitative* (not just textual-canary)
proof in this project that guest reads through hsimd land on the exact
correct host byte range, matching the doc's own "matching checksum can prove
nothing" caution (see `THE-TRIBBLIX-HSIMD-STORY.md`) precisely because both
the guest and host sides were computed independently from raw bytes, not
asserted from one side.

## FACT — sane-tmux console tooling installed on the playbox (2026-08-20)

Per direct authorization from Ryan, the `sane-*` read-only/guarded tmux
helpers were installed on `niagara-playbox`:
- Source: `minnie:~/devel/claudehelpers-project/bin/sane-*` (canonical source
  per each script's own `REPO:` header) — 28 scripts, 168K total.
- Deployed to `~niagara@100.112.174.2:~/bin/`, `chmod +x`, `PATH` line
  appended to `~/.bashrc`. `tmux`, `jq`, `bash` were already present on the
  host (verified via `command -v` before copying).
- Smoke-tested read-only against the live session, no keystrokes sent:
  `sane-list-panes tribblix-zfs-test` correctly enumerated window 0 (idle
  `bash`) and window 1 pane 0 (`sudo`-wrapped QEMU pane, `%2`), matching the
  tmux target already on record above. `sane-look-at-pane
  tribblix-zfs-test:1.0 [lines]` then produced the console reads used
  throughout this section, with no raw `tmux capture-pane` invocation
  (avoids the harness's own fragile-tmux guardrail and gives clean JSON
  instead of relying on ad-hoc `tmux` calls).

## Stage 1 decision — MOOT, superseded by events

The original "pick 1a or 1b before touching the VM" decision point (below,
unchanged) has been overtaken: **1a is already in progress** — the live
console operator has been typing into the running guest and the existing
scratch ISO since before this update, without a documented explicit choice
being recorded. This is not being flagged as an error, only as a fact:
whoever continues past this point should treat 1a as the path already
committed to, not a still-open decision, and should not attempt a parallel
1b (fresh image on the images LV) against the same guest identity.

## FACT — media inventory and hashes

`/home/niagara/sun4v/media/`:

| file | bytes | sha256 | status |
|---|---|---|---|
| tribblix-m34.iso | 710717440 | afc1b115633c5a3c63bb683c0608fd22c41568eb5909f09556e045caa04aa323 | pristine source, matches CURRENT-STATE.md |
| tribblix-m34-cuflags.iso | 710717440 | c5f576b79344d9216b7d4da7408c12aa49368588050f717a7760d888dab4cbc7 | matches docs |
| **tribblix-m34-hsimd.iso** | 710717440 | **e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6** | **KNOWN-GOOD, matches docs, unmodified** |
| **tribblix-m34-hsimd-zfs-scratch.iso** | 1046282240 | **17e39e63f4f1f59e6532dcd71a49289b41a40d4cf6a89c440b3d017855316617** | disposable, in use by PID 2803 |
| tribblix-m34.boot_archive.cuflags | 356515840 | (not rehashed) | intermediate |
| tribblix-m34.boot_archive.hsimd | 356515840 | (not rehashed) | intermediate |

The scratch ISO's sha256 was **not** previously recorded anywhere; this was
its first checksum of record. Its mtime is `2026-08-20 16:08:13 UTC` and has
**still not advanced** as of this update's re-check (originally checked
20:06/20:11, reconfirmed ~20:35) — despite Stage 2/3 guest keystrokes and
read commands having occurred in the interim (see above), no guest write has
reached the host file. Read-only commands do not touch the backing file;
this is expected, not a surprise, and confirms the labels/uberblock/zero-
magic-count findings below are still a valid **pre-write baseline**.

`~/sun4v/images/`: `primary.img` and `primary.img.clean`, 2684354560 bytes each
(the Solaris 10 guest, untouched by this work).

## FACT — Sun labels

`tools/vtoc.py show`, both images, magic `0xDABE`, checksum XOR 0x0000 valid.

```
known-good hsimd.iso     s0..s7 all cyl 0 / 1387520 blk   (plain CD label)
zfs-scratch.iso          s2 = 0 / 2043520 blk  (997.8 MB, whole served disk)
                         s7 = cyl 2169 / 655360 blk (320.0 MB)
```

Raw label geometry, sector 0 bytes 0x1b0-0x1b7, **identical in both images**:

```
0x1b0 dkl_ncyl  = 0x0800 = 2048
0x1b2 dkl_acyl  = 0
0x1b4 dkl_nhead = 1
0x1b6 dkl_nsect = 0x0280 = 640
```

Derived: s7 absolute start = 2169 * 640 = sector **1388160**; s7 length
**655360** sectors; s7 ends at cylinder 3193, and s2's 2043520 blocks = 3193
cylinders exactly. Host byte range of s7 = offset **710737920**, length
**335544320**. The base ISO is 710717440 bytes, so s7 begins 20480 bytes past
the end of the ISO image and cannot overlap the boot archive.

**The `ncyl` inconsistency in HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md is confirmed as
real**: `s2`/`s7` were extended to 3193 cylinders but `dkl_ncyl` was left at
2048. OBP and hsimd both accepted it anyway.

## FACT — s7 already contains a partially-written ZFS pool (pre-write baseline, reconfirmed unchanged above)

This contradicts the handoff note "no canary write and no `zpool create` have
occurred". Read-only inspection of the host file:

```
s7 + 0          "HSIMD-ZFS-CANARY-20260820\n"   (26 bytes)
s7 + 16K        ZFS vdev label L0 nvlist
s7 + 256K+16K   L1 nvlist   (identical)
s7 + 320M-512K  L2 nvlist   (identical)
s7 + 320M-256K  L3 nvlist   (identical)
```

Decoded nvlist content (all four labels agree):

```
name          hsimdz
version       5000
state         0            (POOL_STATE_ACTIVE)
txg           0
pool_guid     cbe213f04a285342
top_guid/guid 5728d836fa6ebefa
hostname      tribblix
hostid        0x80112233
vdev_tree     type=disk
              path      /dev/dsk/c1d0s7
              phys_path /virtual-devices@100/disk@0:h
```

Additional guest-written metadata further into s7:

```
chunk @ s7+0MiB     1154 nonzero bytes   (canary + L0/L1 nvlists)
chunk @ s7+4MiB    19575 nonzero bytes   MOS/DSL ZAP: "normalization",
chunk @ s7+36MiB   19575 nonzero bytes    "utf8only", "casesensitivit",
chunk @ s7+68MiB   12540 nonzero bytes    "VERSION", "SA_ATTRS",
chunk @ s7+316MiB   1130 nonzero bytes    "DELETE_QUEUE", "ROOT", "_SHARE"
total nonzero in s7: 53974 bytes
```

**No uberblock exists anywhere in s7.** A byte search of the entire 320 MB
slice for the uberblock magic in both byte orders returned nothing:

```
grep -abo -P "\x00\xba\xb1\x0c"   -> no match
grep -abo -P "\x0c\xb1\xba\x00"   -> no match
```

The uberblock ring in L0 (label offset 128K-256K) is 42 nonzero bytes, i.e.
empty apart from a trailing checksum.

### What that proves and does not prove

PROVEN: guest ZFS writes reached the host backing file through
`hsimd_strategy -> hcall_diskio -> hv_disk_write` (FAST_TRAP 0xf1) and through
QEMU's MAP_SHARED vdisk. The write path works. The `zpool create` wrote its
vdev labels and at least three ditto copies of MOS metadata.

NOT PROVEN, and specifically NOT true today: the pool is not committed.
`zpool create` writes labels with `txg=0` before `spa_sync()` lays down the
first uberblock. With no uberblock the pool cannot be opened or imported.

**CORRECTED 2026-08-20 (Shell reconciliation):** this paragraph previously
framed host-crash uberblock loss as the "most economical explanation" and the
hang as a mere alternative. That weighting is superseded — CURRENT-STATE.md's
already-committed correction (`dd252f0`) has direct eyewitness evidence for
the opposite ranking:

- **H-B (better supported):** `zpool create` hung before `spa_sync()`. An
  earlier session directly observed the command failing to return while QEMU
  pinned a host core and the backing mtime froze.
- **H-A (circumstantial):** the uberblock reached dirty `MAP_SHARED` pages and
  was lost when the host went down uncleanly (no `shutdown` record precedes
  the 18:43 boot; consistent with the bytes, not eyewitnessed).

Both remain live and must not be collapsed into one; H-B is the leading
hypothesis for T2's hang classifier, not a coin-flip alternative.

## FACT — rollback assets

- `tribblix-m34-hsimd.iso` is byte-identical to the documented known-good ISO
  and is the rollback source for any scratch image. It is not open by any
  QEMU (only the scratch ISO is).
- `tribblix-m34.iso` (pristine Tribblix media) and `tribblix-m34-cuflags.iso`
  are also intact.
- There is **no** `.clean` copy of the scratch image. Rollback of the scratch
  means regenerating it, which needs 998 MB — only available on the `images`
  LV, not on `/`.
- `primary.img.clean` covers the Solaris 10 guest, which this work does not
  touch.

## HYPOTHESIS list (each must be tested or explicitly parked)

1. H1 — the lost uberblock is a host-crash artifact, not an hsimd/ZFS defect.
   Test: repeat `zpool create` and immediately force writeback
   (`kill -USR2 <qemu pid>`), then look for the uberblock magic host-side.
2. H2 — `dkl_ncyl = 2048` vs s7 ending at cylinder 3193 is cosmetic for this
   path. Evidence so far supports H2 (OBP booted, hsimd attached, guest wrote
   through s7 correctly), so a relabel is hygiene, not a prerequisite.
3. H3 — the earlier "console stalls before a usable shell" report is not
   reproducible: the current boot is sitting cleanly at the maintenance
   username prompt. Test: type `root` once, at the gate, and watch.

**Diagnostic-lane note (Shell reconciliation, 2026-08-20):** the raw `s7`
path below is one of two lanes this project has committed to keeping
separate (THE-TRIBBLIX-HSIMD-STORY.md: "Keep the UFS file-vdev and raw-vdev
lanes separate in names and claims"). The other lane — a ZFS file vdev on a
UFS filesystem built on `c1d0s7` — deliberately hides ZFS's direct disk-ioctl
probing and isolates whether failures are in the raw-vdev contract or in
hsimd I/O generally. It is a parallel diagnostic, not a fallback to run only
if Stage 4 fails, and a pass on one lane must never be reported as a pass for
the other. Status of that lane as of this reconciliation: the Solaris 10
donor had started creating `/share/tribblix-s7-ufs.img` when the project
narrative was last updated; whether that file is a completed, formatted UFS
image has not been re-verified here and must be checked, not assumed, before
that lane is used.

## PLAN — staged validation (NOT EXECUTED; requires Codex authorization)

Console discipline for every guest step: keep each line **under 256 bytes**
(Solaris canonical tty truncates and drops the CR), send nothing beginning
with an uppercase-then-lowercase token through `sane-send-keys`, never send
Ctrl-C or Ctrl-D casually, and read back the prompt before sending the next
line.

Host discipline: never write to `tribblix-m34-hsimd.iso`, `tribblix-m34.iso`,
`tribblix-m34-cuflags.iso`, or either `boot_archive.*`. Never write to
`/tmp` on the host beyond a few KB — `/` has 402 MB free (this survey briefly
staged a 335 MB scan file there and removed it; do not repeat that).

### Stage 0 — preserve evidence and protect the known-good set

```
# on niagara-playbox
chmod 444 ~/sun4v/media/tribblix-m34.iso \
          ~/sun4v/media/tribblix-m34-cuflags.iso \
          ~/sun4v/media/tribblix-m34-hsimd.iso
cp ~/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso \
   ~/sun4v/images/scratch-forensic-20260820.iso        # 998 MB, images LV
sha256sum ~/sun4v/images/scratch-forensic-20260820.iso
# expect 17e39e63f4f1f59e6532dcd71a49289b41a40d4cf6a89c440b3d017855316617
```

Gate: the copy's sha256 must equal the source's. Stop on mismatch.

### Stage 1 — decide the target image

Two options; pick one before touching the VM.

- **1a (recommended) — reuse the running guest and the current scratch.**
  Costs nothing, keeps the 57-minute-old boot, and directly tests H1. The
  stale `hsimdz` labels are handled with `zpool labelclear -f` or
  `zpool create -f`.
- **1b — fresh disposable image on the images LV.** Regenerate from the
  known-good ISO, fix `dkl_ncyl`, boot it. Costs a full boot cycle and
  another 998 MB, and abandons the currently-parked guest.

```
# 1b only, all on the images LV, never in ~/sun4v/media
cp ~/sun4v/media/tribblix-m34-hsimd.iso ~/sun4v/images/zfs-scratch-2.iso
truncate -s 1046282240 ~/sun4v/images/zfs-scratch-2.iso
python3 ~/niag-proj/tools/vtoc.py set ~/sun4v/images/zfs-scratch-2.iso 2 0 2043520
python3 ~/niag-proj/tools/vtoc.py set ~/sun4v/images/zfs-scratch-2.iso 7 2169 655360
python3 ~/niag-proj/tools/vtoc.py verify ~/sun4v/images/zfs-scratch-2.iso
printf 'HSIMD-ZFS-CANARY2-%s\n' "$(date -u +%Y%m%dT%H%M%S)" | \
  dd of=~/sun4v/images/zfs-scratch-2.iso bs=512 seek=1388160 conv=notrunc
# ncyl fix (H2 hygiene): tools/vtoc.py has no ncyl setter. `verify` is
# read-only (see tools/vtoc.py:cmd_verify) — it CANNOT recompute or write a
# checksum. Do not rely on "re-run verify" to fix a hand-patched label. Patch
# 0x1b0 to 3193 (0x0C79) with a tool that also calls fix_checksum() and
# writes the label back (extend vtoc.py with a `set-ncyl` command, or patch
# and recompute inline), THEN run `vtoc.py verify` only to confirm the result.
```

Gate: `vtoc.py verify` reports magic ok and XOR 0x0000 before any boot.

### Stage 2 — reach a maintenance shell (first guest keystrokes)

Watch the console live before anything is typed. Then, one short line at a
time, reading the echo back after each:

```
root                 <- at "Enter user name for system maintenance"
                     <- expect a password prompt or a '#' prompt
```

Gate: a `#` prompt. If `root` echoes but nothing advances (the previously
reported symptom), STOP. Do not send control characters. Report and re-plan.

### Stage 3 — prove device nodes and the read path, before any write

```
modinfo | grep hsimd
ls /dev/dsk/c1d0s*
prtvtoc /dev/rdsk/c1d0s2
dd if=/dev/rdsk/c1d0s7 bs=512 count=1 | od -c | head -3
```

Gate: `modinfo` shows hsimd at major 265; `c1d0s0`..`c1d0s7` present in both
`/dev/dsk` and `/dev/rdsk`; the s7 sector-0 dump shows
`HSIMD-ZFS-CANARY-20260820`. That last check is the host-planted canary and
proves guest-visible s7 addressing maps to host offset 710737920 with no
skew. Stop on any mismatch — a wrong offset here is the difference between
writing to scratch and writing over the boot archive.

`prtvtoc` is informational only and MUST NOT gate this stage.
THE-TRIBBLIX-HSIMD-STORY.md:298 already recorded prtvtoc "exposed another
unsupported ioctl and reported an invalid VTOC" on this same hsimd path, and
the already-committed HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md (`dd252f0`) makes the
same call. No source in this project pins down prtvtoc's specific failing
ioctl number — the two unsupported ioctls that are documented, `0x4a4`
(`CDROMREADOFFSET`) and `0x760b`, both belong to other callers (HSFS mount
and `fmthard`/geometry), not `prtvtoc` — so do not assert one.

### Stage 4 — zpool create on s7 only

```
zpool labelclear -f /dev/rdsk/c1d0s7     # clears the stale hsimdz labels
zpool create -f hsimdz /dev/dsk/c1d0s7   # full path — never bare "c1d0s7"
zpool status hsimdz
zpool list hsimdz
```

Gate: `zpool status` reports `state: ONLINE`, one `c1d0s7` vdev, no errors.
`zpool create` returning 0 is not proof; the readback below is.

Explicitly forbidden in this stage: any device other than `c1d0s7`. Never
`c1d0s2` (whole disk, contains the bootable ISO and the boot archive), never
`c1d0s0`/`s1`/`s3`..`s6` (all still map to the 677.5 MB ISO region).

### Stage 5 — write and checksum proof

```
mkfile 8m /hsimdz/proof.dat        # or: dd if=/dev/urandom of=... bs=1024k count=8
digest -a sha256 /hsimdz/proof.dat
zfs list hsimdz
```

Record the digest. Also write a small human-greppable marker so the host can
find it by string search without ZFS tooling:

```
echo ZFSPROOF-20260820-A > /hsimdz/marker.txt
digest -a sha256 /hsimdz/marker.txt
```

Gate: both digests recorded verbatim in the session log before proceeding.

### Stage 6 — clean export

```
sync
zpool export hsimdz
zpool list                          # expect "no pools available"
```

Gate: export returns 0 and `zpool list` shows nothing. Then force host
writeback and confirm it landed:

```
# on the host — do NOT gate on mtime. Under MAP_SHARED, mtime advances on
# writeback/msync timing, not on store, and background writeback
# (dirty_expire ~30s, see CURRENT-STATE.md "How storage actually works") can
# advance it independently of this signal, or leave it unchanged if nothing
# was dirty. mtime is a hint to time the read, never proof of content.
kill -USR2 <qemu pid>
```

The actual gate is Stage 7's byte/hash readback below, not this timestamp.

### Stage 7 — host-side verification (no ZFS tooling required)

```
F=<image path>; S7=1388160
# uberblock must now exist — this is the check that failed today
dd if=$F bs=512 skip=$S7 count=655360 2>/dev/null | grep -c -aP '\x00\xba\xb1\x0c'
# labels
dd if=$F bs=512 skip=$((S7+32)) count=64 2>/dev/null | strings | head -20
# the marker string, found by brute force
dd if=$F bs=512 skip=$S7 count=655360 2>/dev/null | strings | grep ZFSPROOF
sha256sum $F
```

Do not stage a 335 MB temp file on `/`; stream through the pipe as above.

Gate: at least one uberblock magic match, `state` in the nvlist now
`1` (POOL_STATE_EXPORTED) rather than `0`, a nonzero `txg`, and the
`ZFSPROOF-20260820-A` marker recoverable from the raw image. That combination
is the actual proof that guest ZFS writes are durable through hsimd.

### Stage 8 — re-import and checksum readback

```
zpool import -d /path/to/isolated-dir     # dir contains ONLY a symlink to
                                           # c1d0s7 — see the import-alias
                                           # hazard in CURRENT-STATE.md: a
                                           # bare `zpool import` can see s2's
                                           # byte-identical trailing labels
                                           # and bind s2 instead, whose L0/L1
                                           # overwrite the Sun label and the
                                           # boot archive. NEVER run bare
                                           # `zpool import` against this vdev.
zpool import -d /path/to/isolated-dir hsimdz
zpool status hsimdz
digest -a sha256 /hsimdz/proof.dat
digest -a sha256 /hsimdz/marker.txt
zpool scrub hsimdz
# poll to actual completion — a single status check right after issuing
# scrub will show "scan: scrub in progress", not a result. Loop until the
# scan line reports "scrub repaired ... with 0 errors" or a nonzero error
# count; do not stop at "in progress".
while true; do
  s=$(zpool status hsimdz | grep -A1 '^  scan:')
  echo "$s"
  echo "$s" | grep -q 'in progress' || break
  sleep 5
done
```

Gate: both digests byte-identical to the Stage 5 values, and the scrub scan
line reports completion with 0 errors — an "in progress" read is not a pass.

### Stage 9 — record

Append measured results to `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` and
`CURRENT-STATE.md`, including the corrected statement that a partial
`zpool create` had already occurred before this session and why it was not
committed.

## Rollback path

| failure | rollback |
|---|---|
| pool corrupt / s7 garbage | `zpool destroy` is unnecessary — the image is disposable. Re-derive from `tribblix-m34-hsimd.iso` per Stage 1b. |
| scratch image damaged outside s7 | Same: regenerate from `tribblix-m34-hsimd.iso` (sha256 `e98d3a5e…a6f33cf6`). Never edit that file. |
| guest panics / kmdb | Preserve the console, capture the pane, do NOT send Ctrl-C or reboot. The image is disposable; the console evidence is not. |
| known-good ISO suspected modified | Re-verify sha256 against the table above; if it differs, restore from `tribblix-m34.iso` + the documented cuflags/hsimd archive rebuild. |
| host out of space on `/` | Work exclusively under `~/sun4v/images` (9.1 GB free). `/` has 402 MB. |

Losing the current QEMU (PID 2803) costs one boot cycle, nothing more: every
byte of state it holds is either in the disposable scratch image or already
captured above.
