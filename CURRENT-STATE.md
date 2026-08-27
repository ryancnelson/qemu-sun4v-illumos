# Current State

## Current execution gate (2026-08-27)

Persistent-NVRAM sprint update: QEMU file backing was implemented and built,
but the live firmware canary proved that OpenBoot routes these variable writes
through a missing LDOM provider and never modifies physical NVRAM. No generated
NVRAM passed fresh-process readback, no unattended boot was attempted, and all
canary QEMUs are stopped. See `notes/NIAGARA-PERSISTENT-NVRAM-SPRINT.md`. The
next normal recovery boot still requires the explicit proven OBP boot command.

Recovery run `workstation-playbox-recovery-20260827T214436Z` launched on
playbox at 21:44 UTC as an explicit writable child of the preserved productive
candidate
`workstation-playbox-known-good-20260827T165948Z/images/root-unit104.qcow2`
(SHA-256 `69722011fe0931a0aa27d2dbcd7f75e7e0c9c1aefb05ab8dde6207f957595e62`).
It is not a child of the older checkpoint used by the disposable debug run.
QEMU PID 66870 started with a Unix QMP socket, Unix gdbstub, no HMP endpoint,
and a fresh writable qcow2 child. Unit 101 is RAM-backed but, unlike the prior
debug run, was copied from the accepted template (SHA-256
`8259bb9af59e409b69ae057223548d96cf89d3ed0ebf8a0fe38721fed2a92fdf`) and
passed `tools/vtoc.py verify` before launch. The immediate recovery goal is to
verify the operator's files under `/export/home/ryan` and `/root`; do not claim
them recovered until observed in the guest.

Disk-lineage correction: the stopped run
`workstation-playbox-known-good-20260827T165948Z` is now classified
**CANDIDATE / PRESERVE_UNPROMOTED** because it contains productive guest writes
that were not promoted. The later debug run is a **DISPOSABLE** sibling from an
older parent and therefore does not show those files. Do not delete, rebase, or
flatten either overlay. The next boot must be a writable recovery child of the
preserved candidate and must verify files under `/export/home/ryan` and `/root`.
See `notes/DISK-LINEAGE-AND-PROMOTION.md`.

Productive run `workstation-playbox-known-good-20260827T165948Z` stopped at
20:19 UTC after an
unrestricted HMP client accidentally sent `quit` while investigating an apparent
guest wedge.  The exact observations, preserved evidence, and losses are recorded
in `notes/INCIDENT-PLAYBOX-WEDGE-HMP-QUIT-20260827.md`.  A separate disposable
run, `workstation-playbox-debug-20260827T203510Z`, was launched at 20:36 UTC
with one vCPU, 3072 MiB, a Unix QMP socket, a Unix SPARC gdbstub, and no HMP
monitor.  It is booting the known-good unit-104 lineage.  No BBS, PPP peer, or
channel bridge is claimed live.  All later references in this ledger to those
services “running” are dated historical observations.

The next action before any debug interaction with the disposable run is to
implement and rehearse the restricted capture-first crash-debugging harness in
`notes/NIAGARA-CRASH-DEBUG-HARNESS-SPRINT.md`.  Arbitrary interactive HMP access
is prohibited; monitor clients must expose a fixed read-only QMP allowlist, with
separate deliberate stop/resume helpers that cannot encode `quit`.

`KERMIT-GET` and its harmless `KERMET-GET` alias are implemented and covered by
non-live fake-process tests.  They are blocked from live acceptance because
G-Kermit is absent on both the playbox host and OpenIndiana guest; no file has
been transferred with the protocol.  See `notes/BBS-KERMIT-GET.md`.

GCC 11.5 is host-staged only, not installed in the guest.  The immutable input
observed at
`/mnt/disk-images/runs/workstation-playbox-known-good-20260827T165948Z/staging/gcc-11.5.0/gcc-11.5.0.tar.xz`
is 48,796,924 bytes with SHA-256
`e281603bec615ef09f9a8c4b58a55f1da4e6c47999567da521c87011a2fa8b6e`.

Publication note (2026-08-24): this is the detailed Solaris 10 and Tribblix lab
ledger last reconciled on 2026-08-22.  It is not the top-level status page.
For the later OpenIndiana live-environment result, Murayama comparison, and
performance measurements, start with `README.md`,
`THE-OPENINDIANA-BASECAMP-STORY.md`, and the dated notes under `notes/`.
Where a dated later observation conflicts with this ledger, the later evidence
controls.

## Current OpenIndiana workstation candidate (2026-08-26 12:27 PDT)

The current installed-root result supersedes the 2026-08-25 live-environment
experiment immediately below.  Biggie run `term4code-herm-smp4-01` cold-booted
unit 104 from `disk@4:a`, mounted `rpool/ROOT/openindiana`, reached a multiuser
root prompt, reported a healthy pool, and passed manual channel-0 PPP and
routed Internet packets.  QEMU PID 2366353 was the last observed process
identity; revalidate it rather than treating the PID as configuration.

The operator view is tmux session `workstation-candidate`, with only `console`,
`bridge0-ppp`, and `ppp0` windows.  BE
`workstation-candidate-20260826` exists but was not activated or cold-boot
tested.  Channel 1/getty, SSH, a compiler, and automatic network restoration
are not present at this checkpoint.

The old `term4code-02` QEMU is dead and its tmux session was removed.  Do not
delete its run directory: the surviving candidate still references its QEMU
binary, firmware, and read-only unit-103 image.  Full artifact paths, QEMU
argv, limitations, and the AWS/CI transfer contract are in
`notes/OPENINDIANA-WORKSTATION-CANDIDATE-20260826.md`.

## Historical OpenIndiana experiment (2026-08-25 03:53 UTC)

This was the foreground experiment at the stated timestamp and is retained as
historical evidence.  It is newer than the Tribblix/Solaris 10 ledger below.

- Playbox QEMU PID 345276 is a one-vCPU Niagara guest using verified build ID
  `8ad4fe2ec3d93dc923149035727d48822575b64d`.  The range-flush patch is present
  in that executable.
- The writable reflink is
  `OpenIndiana_Text_SPARC_12_2025.install-6g.patched-8ad4fe2e.iso`.  It was
  cloned from the old-binary failed-install image, whose pool was not cleanly
  exported.  It is an experiment/evidence image, **not a clean baseline**.
- `boot disk -s -v` reached the maintenance root prompt in about 6 minutes.
  At the first prompt, manual `/etc/rc2.d/S99niagara start` was still required;
  the live-media path does not run that rc2 script automatically.
- Channel 1 passed an actual second-shell proof at 03:40:47 UTC: root identity,
  `uname -a`, date, and bidirectional mailbox acknowledgements.  It remains the
  required observation path before launching the installer.
- PPP and SSH did **not** pass on this boot.  Do not generalize the older
  OpenIndiana basecamp PPP success into a claim about this candidate.

The failed PPP attempt exposed two harness defects.  Playbox had a stale
`tools/chan/host-up.sh` (SHA-256 `5305eee2...`) containing `persist maxfail 0`.
When the guest endpoint was absent, host pppd PID 579344 rapidly accumulated
unreaped pppd children and exhausted fork capacity.  The parent and waiting
host-up process were killed; zombie count returned to zero.  The stale script
is preserved as `host-up.sh.zombie-storm-20260825`.  The project copy (deployed
SHA-256 `0fbc4f88...`) removes those flags and adds the QEMU sync hook.

The corrected script still has a false-negative sync gate: its QEMU lookup
matches the two sudo wrappers plus the real worker and therefore reports
"expected one VM".  Guest `S99niagara stop` is also not idempotent: it kills
`pppd`, `guest-chand`, and `socat`, but does not reliably reap
`guest-ppp-chan.pl` or `guest-rootpty.sh`; repeated stop/start produced duplicate
rootpty helpers.  These are P0 harness bugs before another PPP attempt.

Historical safe state at the end of that incident: QEMU and exactly one host bridge
for channels 0 and 1 remained running, channel 1 was reconnected to a root
prompt, PPP/host-up were stopped, host zombie count was zero, and playbox had
about 4.0 GiB available memory.  The Solaris 10 donor was not stopped.

Baseline last verified: 2026-08-22. Everything below is backed by a passing test or a
recorded measurement. Claims without evidence are marked UNVERIFIED.
CORRECTION 2026-08-20: the "Disposable ZFS-on-hsimd experiment" section below
carried claims that a later read-only host survey falsified. They are corrected
in place and annotated. Re-read that section before acting on s7.

## Test suite: 7 tests

```
sudo QEMU_BIN=$PWD/qemu/build/qemu-system-sparc64 bash tests/run-all.sh
  PASS  test-boot-to-login
  PASS  test-disk-writes-persist
  PASS  test-exchange-channel      <- host->guest bulk data transfer
  PASS  test-md-roundtrip
  PASS  test-reboot-obp-intact     <- FLAKY, see Known gaps #4
  PASS  test-toolchain-compiles    <- in-guest gcc compiles, links AND runs
  PASS  test-fat-exchange          <- BIDIRECTIONAL host<->guest file exchange
```

Runs in ~5-7 min. `test-reboot-obp-intact` intermittently times out waiting for
the login prompt; boots occasionally exceed even the 180s timeout under load
because each pins guest RAM. Each VM test clones its own throwaway dataset from
`images@baseline` and destroys it on exit, so tests cannot corrupt each
other or the daily driver.

## What works

- **Tribblix m34 installed UFS root, cold-booted and online.** The corrected
  2,158,034,944-byte image on biggie boots from `disk@0:a` UFS. Persisted channel
  services provide PPP on channel 0 and a respawning ttymon login on channel 2.
  Cold-boot acceptance passed IPv4 ping, DNS, HTTP 200, SSH, and NFSv3/TCP; the
  full illumos source tree is visible at `/mnt/host/illumos-ppp-src`. Tribblix
  slice 7 begins at host byte 710,737,920; do not reuse `CHAN_HOST_BYTE` from the
  larger primary image. Full evidence is in
  `notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md`.

- **Solaris 10 boots** to a login prompt in ~40s. Root, no password.
- **Disk writes persist.** Verified end-to-end: write to `/etc`, clean exit,
  canary found in the raw image file, then a *second boot* reads the file back and
  the image is still bootable. This is `test-disk-writes-persist`.
- **2GB disk**, 1.9GB UFS, ~1.6GB free. Volume is 2560MB to carry slice 3.
- **1GiB of guest RAM** (was 256MB). Artyom Tarasenko's sun4v MD files lift the
  ceiling; `prtconf` in Solaris 10 reports "Memory size: 1024 Megabytes". It is
  a drop-in: `openboot.bin`, `q.bin`, `nvram1`, `reset.bin` are byte-identical
  to ours, and ONLY `1up-md.bin` / `1up-hv.bin` differ, so 1GiB is purely a
  Machine Description change. Firmware lives in `/datapool/niagara/base-1gib`.
  Select with `NIAGARA_MEM=1024 S10DIR=/datapool/niagara/base-1gib`.
  Source: `github.com/artyom-tarasenko/qemu-sun4v-md` @ `1GiB-experimental`.
- **A working C toolchain in the guest.** Plain `gcc` — no `-B`, no PATH
  games — compiles, links against `libm`, and produces a binary that runs:
  `SUM=5050 RC=1.41421`. Guarded by `test-toolchain-compiles`, which asserts
  the binary's own stdout, because "gcc exited 0" is not evidence.
  Snapshot: `primary@toolchain-working`. Details under "Toolchain" below.
- **Machine Descriptions are editable as text.** `1up-md.bin` / `1up-hv.bin`
  regenerate byte-identically from `.pdesc`/`.hdesc` source via a locally
  built `mdgen`. Guarded by `test-md-roundtrip`.
- OBP survives a guest `reboot` far enough to answer `devalias`
  (`test-reboot-obp-intact`). Note this is a weak assertion — see Known gaps.
- Perl 5.8.4 is present in the guest (`/usr/bin/perl`). No python.
- **NETWORKING: a root shell over TCP/IP.** `telnet 10.0.5.15` gives a Solaris
  root login. PPP over the qcn console (`pppd notty` + `asyncmap 0xffffffff` +
  `stty raw -echo`), telnetd served by a 20-line perl mini-inetd because SMF's
  inetd is stuck `offline` on an absent `svc:/milestone/name-services`.
  Bring-up: `tools/guest-ppp-up3.sh` in the guest, host side
  `pppd <pty> 115200 noauth nolock local nodetach novj noccp asyncmap 0xffffffff
  10.0.5.1:10.0.5.15`. 0% loss at 500B, ~60ms RTT.
  CAVEAT: a PPP session cannot be shut down cleanly yet -- `init 5` afterwards
  always breaks OBP -- so treat such sessions as disposable and roll back to
  `primary@networked`.

  Snapshot **`primary@networked`** is the starting point: PPP installed
  (`pppd` 2.4.0b1 + `libmd.so.1` + sppp/sppptun registered), `/etc/default/login`
  already permitting root network login, the telnet/ftp/shell/login/rexec SMF
  manifests imported, and the bring-up scripts on the FAT slice. VERIFIED to boot
  clean and halt with `Program terminated` before it was taken.
- **Bidirectional host <-> guest file exchange** via FAT32 on VTOC slice 3.
  Host mounts it with `mount -t vfat` on a loop device, guest with
  `mount -F pcfs /dev/dsk/c0t0d0s3:c`. Verified with two exact `cksum` matches
  on the same 256KB of random data — host->guest and guest->host
  (`test-fat-exchange`). Drive it with `tools/exchange.sh mkfs|put|get|ls`.
  Guest writes are visible to the host as soon as the kernel flushes the page —
  no shutdown required (see "How storage actually works").
- **Bulk host -> guest data channel** via a raw VTOC slice. Verified
  byte-for-byte: a 256KB random binary transfers with a matching `cksum`
  (`test-exchange-channel`). See "Data channel" below.

## How storage actually works

**P2-012 (2026-08-18): the vdisk is a `MAP_SHARED` mapping of a regular file.**
There is no load, no writeback, and no second copy of the disk anywhere.

```
UFS -> hcall_disk_write (0xf1) -> q.bin -> vdisk mapping
                                               |
                          kernel page writeback |  (dirty_expire ~30s,
                                               v   or msync on demand)
                              /datapool/niagara/images/primary.img
```

A guest store lands in the page cache for the image file, so it IS the persisted
state. Consequences, all measured:

- **Durability without any code.** A canary written in the guest, quiesced, then
  `kill -9` on QEMU — no `atexit`, no writeback path at all — was present in the
  image file afterwards.
- **~2.4GB of host RAM per VM returned.** Measured on a running guest:
  `RssAnon 422172 kB` (guest RAM) + `RssFile 125012 kB` (vdisk pages touched so
  far), against 2560MB of pinned anonymous RAM before. The file pages are
  evictable page cache that grows only as the guest touches blocks.
- **No 2560MB read at boot, no 2560MB write at exit.**
- The writeback-clobbers-host-writes race is gone, because there is no stale copy
  left to clobber anything with.

**`SIGUSR2` still exists** but now does `msync(MS_SYNC)` — an explicit durability
*point*, not a copy. Durability is automatic; what msync buys is a known instant.

**CONSISTENCY is unchanged and is still the thing that bites.** A running guest
may be mid-transaction, so an image captured at an arbitrary moment can carry a
dirty LUFS journal whose replay panics at `ufs:readlog -> vfs_mountroot`. Quiesce
with `sync; lockfs -f /` first. `tools/checkpoint.sh` does that.

The image MUST be a regular file: block devices do not support `MAP_SHARED`
writeback reliably. `niagara.c` checks `S_ISREG` and refuses rather than mapping
something whose writes go nowhere.

q.bin uses **direct hypercalls (0xf0 read / 0xf1 write), not LDC.** There is
no LDC implementation in the hypervisor source. This resolves the old open
question in the backlog (P1-005).

## Tribblix m34 boot archive boots on Niagara (verified 2026-08-19)

The Tribblix m34 SPARC ISO was copied from `/dev/sr0` to a regular file because
the patched Niagara vdisk requires a `MAP_SHARED`-mappable regular file:

    /home/niagara/sun4v/media/tribblix-m34.iso
    710717440 bytes
    sha256 afc1b115633c5a3c63bb683c0608fd22c41568eb5909f09556e045caa04aa323

The verified launch command on `niagara-playbox` is:

    /home/niagara/niag-proj/qemu/build/qemu-system-sparc64 \
      -M niagara \
      -L /home/niagara/sun4v/firmware/base-1gib \
      -m 1024 \
      -nographic \
      -drive if=pflash,file=/home/niagara/sun4v/media/tribblix-m34.iso,format=raw

At OBP, `boot disk -v` loaded `/platform/sun4v/boot_archive`, loaded the
sun4v kernel, and mounted `root on /ramdisk-root:a fstype ufs`. This closes the
uncertainty in P2-029: OBP can load the kernel and boot archive without
`hsimd`; disk access is lost only after the kernel takes over. The Niagara
machine does not use QEMU `-kernel`/`-initrd`, and `-cdrom` is not applicable.

The first boot then panicked in the performance-counter path, independently of
storage:

    BAD TRAP: type=10 (illegal instruction)
    pcbe.SUNW,UltraSPARC-T1:ni_pcbe_program+88
    genunix:kcpc_program+ec
    unix:cu_cpc_program+170
    unix:cu_init+110

illumos `cap_util.c` initializes `cu_flags` to `CU_FLAG_ENABLE` and explicitly
allows the counters to be disabled at boot. QEMU does not implement the T1
performance-counter instruction used by `ni_pcbe_program`. The following
non-persistent kmdb workaround was verified:

    ok boot disk -kvd
    [ kmdb prompt ]
    unix`cu_flags/X
    unix`cu_flags/W 0
    unix`cu_flags/X
    :c

After changing `cu_flags` from 1 to 0, Tribblix passed the previous panic,
mounted the RAM root again, created later pseudo-devices, completed SMF startup,
and reached a verified login prompt and root shell. The live system is entirely
RAM-root based and has no disk device nodes.

The permanent fix is now verified. A copied m34 boot archive was mounted via
Solaris 10 `lofiadm`, checked before and after the edit, and given
`set cu_flags=0` in `/etc/system`. It was written back at its unchanged ISO9660
extent (LBA 9391) in a copied ISO. A fresh QEMU booted that media with
`boot disk -sv`, with no kmdb intervention, passed the former counter panic,
loaded 95/95 SMF descriptions, and reached `SINGLE USER MODE` and the
maintenance username prompt. Artifacts on `niagara-playbox`:

    tribblix-m34.iso
      sha256 afc1b115633c5a3c63bb683c0608fd22c41568eb5909f09556e045caa04aa323
    tribblix-m34-cuflags.iso
      sha256 c5f576b79344d9216b7d4da7408c12aa49368588050f717a7760d888dab4cbc7

The source checksum remained unchanged. The test VM is in tmux session
`tribblix-cuflags-test`; the older live root session remains untouched.

The running Solaris 10 reference guest also established the exact storage
driver contract. `/virtual-devices@100/disk@0` advertises
`compatible='SUNW,legion-disk'` and binds through `vnex` to `hsimd` major 251.
The installed module is `/platform/sun4v/kernel/drv/sparcv9/hsimd` (24472
bytes), and disassembly confirmed `hv_disk_read` and `hv_disk_write` issue
FAST_TRAP 0xf0 and 0xf1 respectively. The Solaris donor has `uuencode`,
`uudecode`, Perl, `modload`, `add_drv`, `devfsadm`, `mdb`, and `nm`. The
Tribblix RAM root has `openssl`, `uuencode`, `uudecode`, `mdb`, and analysis
tools, but none of `modload`, `add_drv`, or `devfsadm`.

The Solaris 10 module has now been transferred and verified in the live
Tribblix RAM root as `/tmp/hsimd3` (24472 bytes, `sum` = `12843 48`). It has
not been loaded. Read-only analysis found all 45 required symbols in the live
kernel, an exact 136-byte `cb_ops` match, and a safe legacy `dev_ops` contract:
the module's table is 80 bytes because its first word is `devo_rev = 3`; the
current 88-byte illumos table is revision 4 with `devo_quiesce`, and the kernel
checks the revision before reading that last member. `hsimd_attach` performs
DDI allocation/minor-node setup but no hypervisor disk I/O.

The first attempt to bootstrap the RAM archive's missing module-loader
userland transferred `/usr/sbin/modload` as `/tmp/modadm` (10044 bytes, `sum`
= `13262 20`, donor-matching MD5). A no-argument probe proved this is only the
32-bit ISA dispatcher, not a multicall implementation; it searches ISA
subdirectories for the real program. The actual Solaris 10 SPARCV9 `modload`
is now complete as `/tmp/real-modload` (11792 bytes, `sum` = `26064 24`, MD5
= `8c8a308502b7232b37dedafc138194b8`) and has not been executed. Transfer of
the actual 55984-byte SPARCV9 `add_drv` has verified parts 0 through 22, but
then the Tribblix serial input path stopped executing commands. QEMU remains
alive and the guest did not panic; no driver registration or kernel module
state has changed. See
`HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` for the complete evidence, volatile state,
transfer procedure, and exact continuation.

That volatile loader path is no longer the primary route. A second disposable
boot archive now includes the Solaris 10 `hsimd` module plus Tribblix-native
major 265, the `SUNW,legion-disk` alias, and the disk instance binding. A fresh
QEMU boot loaded and attached it as `hsimd0`; `modinfo` confirmed major 265 and
devfs created `c1d0s0` through `c1d0s7` in both `/dev/dsk` and `/dev/rdsk`.
One 512-byte read from `/dev/rdsk/c1d0s2` matched host sector zero exactly
(SHA-256 `77d82f36b345774a9f55e7f6c5b939da956cd1ddf161b7ae0881ed349d84e958`).
Another 512-byte read at sector 37564, the first sector of the embedded boot
archive, also matched its host SHA-256 exactly
(`076a27c79e5ace2a3d47f9dd2e83e4ff6ea8872b3c2218f66c92b89b55f36560`).
**Caveat (2026-08-20): that digest is also the SHA-256 of 512 zero bytes.**
The match discriminates against "hsimd always returns sector zero" (sector 0
hashes `77d82f36...`, which differs), but it does NOT discriminate against
"hsimd returns zeros for any nonzero offset": both the guest read and the host
region are all-zero. Treat nonzero-offset addressing as proven only by the
later s7 canary and ZFS-label evidence, which use discriminating nonzero
content. No write or mount had been attempted at that point.
The verified ISO is
`/home/niagara/sun4v/media/tribblix-m34-hsimd.iso`, SHA-256
`e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6`.

A subsequent read-only HSFS mount attempt failed safely and left no mount
active. This is not media corruption: ioctl `0x4a4` is `CDROMREADOFFSET`.
HSFS expects an unsupported driver to return an error and then defaults to
volume descriptor sector 16, but `hsimd_ioctl()` warns and returns success for
all unknown commands without initializing the offset. HSFS then reads from a
bogus out-of-range sector and receives `ENOSPC` (28). The next driver change is
therefore precise: return `ENOTTY` for unsupported ioctls or implement
`CDROMREADOFFSET` as offset zero. No live/binary patch has been attempted.

### Disposable ZFS-on-hsimd experiment (2026-08-20)

Tribblix m34's durable boot archive already contains `/sbin/zpool`, `/sbin/zfs`,
the SPARC V9 ZFS module, `zfs.conf`, and the normal disk-label tools. A separate
scratch image was therefore made without modifying the known-good hsimd ISO:

```
/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso
1046282240 bytes / 2043520 sectors
s2 = whole 997.8 MiB image
s7 = 320 MiB at absolute sector 1388160
```

The original `tribblix-m34-hsimd.iso` is the rollback source. QEMU session
`tribblix-zfs-test` booted the scratch copy, OBP accepted its recomputed Sun
label checksum, and the illumos kernel attached both storage layers:

```
virtual-device: hsimd0
hsimd0 is /virtual-devices@100/disk@0
pseudo-device: zfs0
zfs0 is /pseudo/zfs@0
```

This proves the remastered Tribblix kernel can load hsimd and ZFS together on
the emulated sun4v machine. On the boot originally recorded here, the VM then
stalled after keymap/IPsec/IPMP/nwam failures and `svc.startd`'s
`failed to abandon contract 44: Permission denied`, before a usable maintenance
shell. That describes one specific boot: a later boot of the same image (QEMU
PID 2803, started 19:13:51 UTC) was observed parked cleanly at the maintenance
username prompt. Tag console observations with the QEMU instance and boot they
came from.

**CORRECTED 2026-08-20 (read-only host survey).** The sentence previously here
— "No canary write and no `zpool create` have occurred" — is FALSE. Both had
already happened on an earlier boot of this same scratch image. Host-side
inspection of `tribblix-m34-hsimd-zfs-scratch.iso` found, inside s7:

```
s7 + 0            "HSIMD-ZFS-CANARY-20260820\n"   (26 bytes, guest-written)
s7 + 16K          ZFS vdev label L0 nvlist   name=hsimdz  txg=0  state=0
s7 + 256K+16K     L1  (identical)
s7 + 320M-512K    L2  (identical)
s7 + 320M-256K    L3  (identical)
~54 KB total nonzero, incl. MOS/DSL ZAP residue at s7+4/36/68/316 MiB
```

PROVEN by that evidence: guest writes traverse `hsimd_strategy -> hcall_diskio
-> hv_disk_write` (FAST_TRAP 0xf1) and QEMU's `MAP_SHARED` vdisk to the exact
predicted host offsets. s7 writes ARE proven.

NOT PROVEN, and specifically not true as of this survey: **there are zero
uberblocks anywhere in s7.** A byte scan of all 655360 sectors for the
uberblock magic `0x00bab10c` in BOTH byte orders (`\x00\xba\xb1\x0c` and
`\x0c\xb1\xba\x00`) returned no match; the L0 uberblock ring holds 42 nonzero
bytes, i.e. empty but for a trailing checksum. `zpool create` writes labels
with `txg=0` before `spa_sync()` lays the first uberblock, so this pool cannot
be opened, imported, or mounted. It is a half-created pool, not a pool.

Two hypotheses remain live and MUST NOT be collapsed into one:

- **H-B (better supported):** `zpool create` hung before `spa_sync()`. The
  earlier session directly observed the command failing to return while QEMU
  pinned a host core and the backing mtime froze.
- **H-A (circumstantial):** the uberblock was in dirty `MAP_SHARED` pages when
  the host went down uncleanly (no `shutdown` record precedes the Aug 20 18:43
  boot). Consistent with the bytes, but not eyewitnessed.

Do not cite backing-file mtime as evidence that no guest write occurred: under
`MAP_SHARED`, mtime advances on writeback/msync, not on store. Force
`kill -USR2 <qemu pid>` first, then read the bytes.

A possible label-geometry inconsistency (2048 advertised cylinders versus s7
ending at cylinder 3193) remains a hypothesis, not a diagnosis. Evidence so far
favours "cosmetic": OBP booted, hsimd attached, and s7 writes landed at the
correct absolute offsets despite it.

Parallel SMF research recommends first timing explicit single-user milestones,
then disabling only measured offenders in a copied repository. Keep device
configuration, console login, `svc.configd`, `svc.startd`, hsimd, and ZFS; start
dependency analysis with keymap, IPsec algorithms, IPMP, and nwam. Do not
delete manifests merely to reduce the displayed `95/95` count. Full details
and the exact scratch layout are in `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md`.

#### s7 byte mapping (derived, arithmetically verified 2026-08-20)

Every s7 number in this project follows from the Sun label alone. Geometry is
1 head x 640 sectors/cylinder, inherited from the CD label:

```
s7 start    cyl 2169 * 640           = sector 1388160  = byte  710737920
s7 length   655360 sectors           = 335544320 bytes = 320.0 MiB exactly
s7 end                                 byte 1046282240 = the image size exactly
base ISO                               byte  710717440
gap between ISO end and s7 start       20480 bytes -> s7 CANNOT overlap the
                                       boot archive (extent 19232768..375748608)
```

Predicted host byte offsets of the four ZFS labels on this vdev — any nvlist
found anywhere else means ZFS bound the wrong device:

| label | blank@ | nvlist@ | uberblock ring |
|---|---|---|---|
| L0 | 710737920 | 710754304 | 710868992 - 711000064 |
| L1 | 711000064 | 711016448 | 711131136 - 711262208 |
| L2 | 1045757952 | 1045774336 | 1045889024 - 1046020096 |
| L3 | 1046020096 | 1046036480 | 1046151168 - 1046282240 |

#### Import alias hazard: s2 and s7 share their L2/L3 slots

s7 ends at byte 1046282240, which is *exactly* the image end, and s2 spans the
whole image. ZFS places L2/L3 at `size-512K` and `size-256K` of a vdev, so
**s2's L2/L3 byte positions are identical to s7's** (1045757952, 1046020096).

Consequence: a bare `zpool import` scans `/dev/dsk`, finds two valid trailing
labels on `c1d0s2`, and may present or select **s2** as the vdev. Writing that
vdev's L0/L1 lands at image bytes 0 and 262144 — the Sun label and the ISO /
boot-archive region. That destroys the bootable media.

Rules, non-negotiable:

- Never run bare `zpool import`. Use `zpool import -d <dir>` where `<dir>`
  contains a single symlink to s7 and nothing else.
- Always name the vdev by full path `/dev/dsk/c1d0s7`, never bare `c1d0s7`.
- `c1d0s0`, `s1`, `s3`..`s6` all still map to the 677.5 MiB ISO region
  (cyl 0, 1387520 blocks) and are equally destructive targets.
- After any pool operation, re-verify two invariants host-side: sha256 of bytes
  `0..1048576`, and sha256 of the boot-archive extent
  (`dd bs=2048 skip=9391 count=174080`). Either changing = hard abort.

#### Raw-device EOF semantic — UNVERIFIED, blocking

hsimd's `hsimd_strategy()` returns `ENOSPC` (28) for an out-of-slice read; that
is the only end-of-media behaviour this project has observed, and it was
observed indirectly, via the HSFS `CDROMREADOFFSET` failure above. What a raw
`read(2)` at or past the end of `/dev/rdsk/c1d0s7` returns — 0 (clean EOF),
`ENOSPC`, `ENXIO`, or a short transfer — has NOT been measured. ZFS label and
uberblock writes land in the last 512 KiB of the vdev, so this is directly on
the critical path: a driver that errors instead of reporting EOF at the vdev
boundary is a plausible cause of the `zpool create` hang.

This slot is reserved for the result of the dedicated read test. Fill it with
the observed syscall return, errno, and transfer count at s7 end-1, end, and
end+1 sectors. **Do not mark it resolved from a command that was merely
attempted.**

#### Single-console ownership

The Niagara QEMU is launched with plain `-nographic` and no QMP or monitor
socket. Its stdin, stdout and stderr are all the same pty, reached through a
double `sudo` layer inside a tmux pane. Established consequences:

- There is exactly one input path to the guest, and whatever currently owns the
  tty consumes every keystroke. A hung foreground command owns it.
- `Ctrl-A c` is NOT intercepted as a monitor escape; it was echoed literally as
  `^Acinfo status`. There is no out-of-band control channel.
- `Ctrl-C` and `Ctrl-D` have previously killed shells and logged out root
  sessions that were expensive to recreate. They are never an abort mechanism.
- Therefore every abort path is host-side only: capture the pane, `kill -USR2`
  for an msync barrier, read the backing bytes (which needs no cooperation from
  the guest), and only then terminate the disposable VM — identified by start
  time *and* exact backing-file path, never by a remembered PID.
- Console claims must name which QEMU instance and which boot they came from.
  Records in `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` and the survey disagree about
  whether `root` was typed at the maintenance prompt; they describe different
  boots, and neither says so.

Operational lesson from this session: do not infer that a QEMU PID is the old
halted guest. Verify its start time and the live console before signalling it.
The Solaris guest had been booted again and was mistakenly terminated; its
current `primary.img` may therefore be dirty. The user-provided clean-copy
rollback mechanism remains the recovery path, but no rollback was performed.

### START HERE (written 2026-08-19 at the end of a long session)

Read this, then the top entries of `BACKLOG.md`. Everything is measured unless marked.

**Two machines matter.**
- `biggie` (this repo's home, Linux + ZFS): original dev host. Image at
  `datapool/niagara/images/primary.img`, ZFS snapshots, test suite in `tests/`.
- `niagara@niagara-playbox` (Ubuntu 24.04 arm64, UTM on a Mac): the PORTABLE target and
  what we intend to ship. **Tailscale SSH as user `niagara`, NOT `ryan`.** Passwordless
  sudo installed. Repo `~/niag-proj`, data `~/sun4v/`.

**Working on the playbox right now:**

    ~/sun4v/run.sh      boot the guest (type 'boot disk'; root, no password)
    ~/sun4v/doctor.sh   ~28 checks for every failure mode we have hit -- START HERE
    ~/sun4v/update.sh   refresh tooling from git (needs NIAGARA_REMOTE)
    sudo bash ~/niag-proj/tools/chan/host-up.sh    channels + PPP + NAT

`doctor.sh` is the fastest route to understanding this system: every check corresponds to
a real incident and prints its own remedy, including how to start the BBS and why not to
run a local LLM here.

**Verified end to end on arm64:** Solaris 10 boots (`SunOS Release 5.10
Generic_118822-23`), guest reaches the internet (`ping 8.8.8.8` 3/3), reflink rollback
copies take 0.00s, dropbear SSH with curve25519/ed25519, BBS oracle answering over a
channel.

**Immediate goal: GTD #3653 `ship-the-niagara-utm-image`** -- publish to a public remote,
run `tools/guest-scrub-for-release.sh` (LAST, from the console; it removes all SSH access
into the guest), add a systemd unit for `host-up.sh`, write a README, then `fstrim` and
export the UTM bundle.

**Rules that will save you hours:**
- Verify the ARTIFACT, not the attempt. `curl` exits 0 having saved an HTML error page; a
  `cp` can silently not happen; an rc script can print "started" after a failed bind.
- NEVER kill a booted guest without `init 5` -- it leaves the UFS log dirty and the next
  boot panics in `ufs:readlog`, unrecoverably. Roll forward from the `.clean` copy.
- Snapshot order: guest `lockfs -f / ; sync`, THEN host msync (SIGUSR2), THEN copy, THEN
  read the copy back.
- A channel that failed a test MUST be re-initialised before the next test.
- Pattern kills self-match: `pkill -f "[q]emu-system-sparc64"`.
- `init 6` does not reboot this machine; it halts and OBP then cannot boot. Restart QEMU.
- Solaris `/bin/sh` has no `$(...)`; `/bin/grep` has no `-E`; libc ceiling `SUNW_1.22.1`.
- Missing usually means MISPLACED: `/usr/sfw/lib`, `/opt/csw/lib`, `/usr/openwin/bin`.

### LIVE STATE THAT IS NOT IN GIT (written 2026-08-19, before a context reset)

**The distribution host: `niagara@niagara-playbox`** (tailscale, arm64 UTM VM on Ryan's
Mac). Tailscale SSH policy permits user `niagara`, NOT `ryan`. Passwordless sudo was
installed at `/etc/sudoers.d/niagara-nopasswd` and validated with `visudo -c`.
  - repo copy at `~/niag-proj` (piped over ssh; Gitea on biggie needs auth for a clone)
  - **patched QEMU already built** at `~/niag-proj/qemu/build/qemu-system-sparc64`,
    verified: 8.2.2, aarch64, 1 niagara machine type, 7 MAP_SHARED in niagara.c
  - root fs grown online 14G -> 27G via `lvextend -l +100%FREE` + `resize2fs`; 19G free
  - `/dev/ppp` present; `magic-wormhole` present (0.16.0). biggie has 0.12.0.
  - **Nothing Solaris is on it yet.** The 2.5 GB image still has to be wormholed over.

**The working guest on biggie.** QEMU is running against
`/datapool/niagara/images/primary.img`. Reach it with

    ssh -l root -i ~/.ssh/id_rsa 10.0.5.15

Channel 0 carries PPP + SSH. After ANY guest boot the host side needs one command,
`sudo bash tools/chan/host-up.sh` -- it is idempotent and is the supported recovery.
The BBS on channel 1 may be stale; re-init that channel before re-testing it.

**`/tmp/dbtest_key` is a THROWAWAY key I generated**, and its public half is one of the
3 entries in the guest's `/.ssh/authorized_keys`. It must not ship. `guest-scrub-for-
release.sh` removes the file entirely.

**THE SCRUB IS NOT RUN, DELIBERATELY.** `tools/guest-scrub-for-release.sh` must be run
LAST, FROM THE CONSOLE, because it deletes `authorized_keys` and therefore all SSH access
into the guest. Run it only when no further work is planned in the image, then flush and
snapshot in the documented order. It also deletes all 6 SSH host keys, which is a
security requirement rather than tidiness: shipping them gives every downloader one host
identity. `/etc/init.d/dropbear` regenerates the dropbear pair at boot.

**Latest verified snapshot: `datapool/niagara/images@bbs-dialer`**, confirmed by reading
it back through `peek.sh` (guest-dial.pl 4446 bytes, S99dropbear present, 3 keys).

**Kept for P2-024:** `/datapool/niagara/media/snv77-with-slirp.img` (80 MB, Tarasenko's
OpenSPARC ramdisk, the only image known to contain `hsimd`).

**Remaining for a shippable VM:** wormhole the image over, run the scrub, add a systemd
unit for `host-up.sh` so a stranger's first boot does not look broken, and write a README
for someone who has never seen this.

### Dial the BBS oracle from the guest (P2-020)

Host, once per channel (order matters -- bridge before BBS):

    sudo python3 tools/chan/host-chan.py init 1        # only if the channel failed a test
    sudo sh -c 'setsid nohup python3 tools/chan/host-chan.py bridge 1 \
        > /var/tmp/niag/br1.log 2>&1 &'
    sudo sh -c 'BBS_PPP_LOCAL=10.0.6.1 BBS_PPP_REMOTE=10.0.6.15 \
        BBS_LLM_URL=http://100.87.104.29:8317/v1/chat/completions \
        BBS_LLM_MODEL=gpt-5.4-mini \
        setsid nohup python3 tools/chan/host-bbs.py /run/niag1 \
        > /var/tmp/niag/bbs1.log 2>&1 &'

Guest:

    perl /opt/niag/bin/guest-dial.pl 1                          # interactive terminal
    perl /opt/niag/bin/guest-dial.pl 1 --ppp 10.0.6.15:10.0.6.1 # dial up networking

ASK asks an oracle primed with this image's constraints. GET fetches a file to
/export/solaris/chan and reports the guest-visible path plus cksum; it HEADs for status
and validates magic bytes, because the first version delivered a 345-byte HTML error
page as a .pkg.gz with curl exiting 0. STARTPPP hands the caller's own fd to pppd --
VERIFIED: guest sppp1 10.0.6.15 <-> host ppp1 10.0.6.1, ping 3/3, running alongside
ch0's SSH link.

`BBS_LLM_URL` and `BBS_LLM_MODEL` are host-daemon settings. Exporting them in the
Tribblix shell cannot configure the BBS, because the BBS process runs on the playbox.

A CHANNEL THAT FAILED A TEST MUST BE RE-INITIALISED before the next test, with BOTH
sides detached, or you are measuring the previous experiment. A stale 65536-byte
chan-test payload sitting in the region produced three separate wrong diagnoses (P2-019).

### SNAPSHOTTING GUEST WORK -- ORDER IS LOAD-BEARING

    guest#  lockfs -f / ; sync                 # dirty UFS pages sit ~30s otherwise
    host$   sudo kill -USR2 <qemu-pid>         # msync the host mapping
    host$   sudo zfs snapshot datapool/niagara/images@<name>
    host$   sudo bash tools/peek.sh -s @<name> 'grep -c <marker> $MNT/<file>'

The last line is not optional. host msync alone flushes only the HOST mapping, so
snapshotting without the guest flush captures the PREVIOUS version of a file just
written -- which happened, and nearly led to the conclusion that the write had failed.
Always read the snapshot back.

### SSH into the guest (dropbear, port 22)

    ssh -l root -i ~/.ssh/id_rsa 10.0.5.15

dropbear 2022.83 listens on 22 inside the guest. Verified crypto:

    kex: curve25519-sha256
    host key: ssh-ed25519
    cipher: chacha20-poly1305@openssh.com

Binaries /opt/niag/bin/{dropbear,dbclient,dropbearkey}; host keys /etc/dropbear.

AUTHORIZED KEYS LIVE AT /.ssh/authorized_keys, NOT /root/.ssh. dropbear takes the home
directory from the passwd entry and root's home on this image is '/'. It also refuses
to read the file unless ALL THREE of these are owned by the user or root and NOT
group/world writable: '/' itself, '/.ssh', and '/.ssh/authorized_keys'. When it
refuses, it says so precisely in its log -- read /var/tmp/dropbear.log before
theorising:

    / must be owned by user or root, and not writable by group or others

10.0.5.15 IS THE ONLY ADDRESS THAT REACHES THE GUEST. 127.0.0.1 is biggie itself, and
biggie has an unrelated container on 2222 which will answer and refuse your key,
looking exactly like a dropbear auth failure. That is why dropbear was moved to 22.

NEVER PKILL THE DAEMON SERVING YOUR OWN SESSION. 'pkill -f "dropbear -p 2222"' kills
the parent AND your connection, so every later command in that invocation silently
never runs. Start the replacement listener FIRST, then kill the old one. The same trap
took down PPP earlier via 'pkill guest-chand'. Telnet on 23 and the console pane are
the two rescue paths.

NEVER EXTRACT A HOST-BUILT TAR AT '/' IN THE GUEST without forcing ownership. Tars
built on biggie carry uid/gid 1000; 'cd / && tar xf' as root re-owned '/' to
1000:1000 drwxrwxr-x. Nothing complained for hours, then dropbear's permission audit
rejected every key. Use --owner=root --group=root when building, and chown afterwards.

### THE RULE FOR THIS IMAGE: missing usually means misplaced

Three instances in one day, each of which cost real time before someone checked the
obvious place:

| looked missing | actually was |
|---|---|
| `tcpd.h` (socat build failed) | present, in `/usr/sfw/include` |
| `libwrap` / `libmd` / `libcrypto` | present, in `/usr/sfw/lib` (not `/usr/lib`) |
| SMF milestone manifests | present in `/var/svc/manifest/milestone/`, never imported |

**Check for misplacement before building or downloading anything.**

### inetd works: the SMF repository was unpopulated, not the packages missing

`svc:/network/inetd:default` sat `offline` on an unsatisfiable dependency,
`svc:/milestone/name-services`. The earlier reading was "the repository has only 22
services and no `milestone/network`", which was true but stopped one question short.
The manifests were on disk the whole time. Two commands:

```
svccfg import /var/svc/manifest/milestone/name-services.xml
svccfg import /var/svc/manifest/milestone/network.xml
```

Result: inetd `online`, service count 33 -> 35, online 20 -> 25. Then
`inetadm -e svc:/network/telnet:default` and telnet works with the perl stand-in
DEAD.

So this image ships a populated manifest directory with an unpopulated repository.
Fetching `SUNWcsr` would have installed files that were already present.

**`tools/guest-pinetd.pl` is now redundant.** It was 20 lines of perl standing in for
two commands. Keep it only as a fallback if the repository is ever wiped; prefer real
inetd, because `ftp`/`shell`/`login`/`rexec` come with it via `inetadm -e` and it is
SMF-managed so it survives reboots.

### HOST-side traps that produce silently wrong results

**`sed` on biggie is `sed 0.1.1`, NOT GNU sed, and it silently ignores `\b`.**
No error, no warning — the substitution simply does not happen. This bit me twice
in one afternoon:

```
$ printf 'zvol_destroy "$X"\n' | sed -e 's#\bzvol_destroy\b#disk_destroy#g'
zvol_destroy "$X"        <- unchanged, exit 0
$ printf 'zvol_destroy "$X"\n' | sed -e 's#zvol_destroy#disk_destroy#g'
disk_destroy "$X"        <- works
```

Worse than a plain failure: in a multi-`-e` command the non-`\b` expressions DO
apply, so the file's mtime changes and it looks processed. First occurrence left
two files unconverted; the second left every test with `$DISK` referenced but
`ZVOL=` still assigned, so all six VM tests died on `DISK: unbound variable`.
**Never use `\b` in sed here.** Verify a rename by grepping for the old name.

**A leaked loop device makes `zfs destroy` fail quietly enough to believe.** A
tool that dies between `losetup` and `losetup -d` leaves the image open; the
destroy then fails but the caller carries on thinking the dataset is gone. One
held `/datapool/niagara/xtest` alive at 585M after a destroy that appeared to
succeed. `tests/lib/disk.sh` detaches loops BEFORE destroying, and
`tests/reap-orphans.sh` reaps orphaned loops (skipping mounted ones).

**A cleanup helper that no-ops on the wrong type is a silent leak.** `disk_exists`
originally tested `-t filesystem` only, so `disk_destroy` returned 0 for a zvol
clone and leaked it with no message. It now accepts either type.

**A checksum that matches your expectation is not one that discriminates.**
`cksum` of 512 zero bytes is **4135437457**. A "successful" round-trip test
reported exactly that and was reading an empty region. Any checksum assertion must
be against known non-zero content, and should explicitly fail on that value.

### Rules for touching the disk from inside the guest

Learned the hard way 2026-08-18. Violating any of these looks like a hung or
broken machine.

**Raw writes MUST be whole 512-byte blocks.** `/dev/rdsk/*` is a character
device with no partial-block support. A 17-byte `dd` reported success
(`0+1 records out`) and silently wrote NOTHING -- verified afterwards by reading
the region from the host and finding zeros. Pad with `conv=sync` or write
512-byte multiples.

**NEVER write to `/dev/rdsk/c0t0d0s2`.** s2 is the whole-disk slice and overlaps
the mounted root filesystem; writes to it hang indefinitely. Use s3 with an
offset instead. s3 block N == absolute block 4194304+N.

**USE `iseek=`/`oseek=`, NEVER `skip=`/`seek=`, for random access.** This is the
single most expensive wrong belief this project has carried. MEASURED 2026-08-18
on a live guest:

```
dd ... bs=512 skip=1015808  count=1     ~254 SECONDS   (linear scan)
dd ... bs=512 iseek=1015808 count=1        0.1 seconds  (lseek)
```

`skip=` on this raw character device reads and discards every intervening block.
Sequential read rate is ~4000 blocks/sec (2000 blocks in 0.5s, ~2 MB/s), so
skipping a quarter-million blocks takes minutes. `iseek=` issues a real `lseek`
and is instant at any offset.

**The old rule here claimed "reads at high offsets hang" and told you to expect a
wedged driver. That was WRONG and it blocked P2-014 for a day.** The reads were
never hung; they were scanning. Processes I declared wedged had 79s, 44s and 36s
of accumulated CPU — consistent with scanning, and inconsistent with blocking on
I/O, which consumes none.

Corollary about interrupting: Ctrl-C during one of those scans is not what wedges
anything, and nothing was ever wedged. But a spinning `dd` does burn a core, so
kill it deliberately (`pkill -9 dd`) rather than leaving several behind. Four
accumulated during this investigation at ~20% CPU each.

**Diagnostic rule this cost me:** a process consuming CPU is working, not stuck. A
process blocked on I/O accumulates no CPU time. Check `ps -ef` CPU columns before
concluding anything is hung, and measure the throughput rate before deciding a
duration is unreasonable.

**`fmthard` cannot work here.** It asks the driver for geometry, `hsimd` does not
implement the ioctl (the familiar `WARNING: hsimd_ioctl: cmd 760b not
implemented`), so it computes nonsense and refuses:
`does not fit. The full disk contains 14087 sectors` -- that 14087 is the
CYLINDER count from the label. Same root cause as `format(1M)` rejecting the
disk. To change the VTOC, edit sector 0 from the host with `tools/vtoc.py` while
the VM is DOWN.

**`mkfs -F pcfs` needs `nofdisk`.** The `:c` suffix assumes an fdisk partition
table and fails with `No such logical drive (missing extended partition entry)`.
Correct form, and how the 496MB filesystem was made:

```
mkfs -F pcfs -o nofdisk,fat=32,size=1015808 /dev/rdsk/c0t0d0s3
```

### The 16MB scratch region at the tail of s3

`s3` is 512MB (1048576 blocks) but its FAT filesystem is now only 496MB
(1015808 blocks), so the last **16MB is outside any filesystem** and safe to
trample:

```
s3 block 1015808 .. 1048575          (guest: /dev/rdsk/c0t0d0s3)
absolute block 5210112 .. 5242879
absolute byte  2667577344 .. 2684354559
```

INVARIANT: anything that re-runs `mkfs -F pcfs` at the full 512MB destroys this.
`tools/exchange.sh mkfs` currently does exactly that -- fix it before using it
again, or the region silently disappears.

### Reading guest memory from the host: use the monitor, not /proc

`pmemsave` works and is fast. Two traps:

**Quote the filename** or the monitor parses it as part of the size expression:
`invalid char 't' in expression`. The monitor also echoes character-by-character
over a socket, which garbles naive line sends.

```
(printf 'pmemsave 0x80000000 1048576 "/tmp/out.bin"\r\n'; sleep 2) \
  | socat - UNIX-CONNECT:/tmp/sol-mon.sock
```

MEASURED cost: **~135 ms fixed + ~1.5 ms/MB.** 4KB=135ms, 1MB=150ms, 4MB=154ms,
16MB=160ms -- so marginal throughput is ~700MB/s and the payload is nearly free.
An earlier claim of "8.6MB/s" in this repo's history was WRONG: it measured a
`sleep 40` rather than the transfer.

Consequence: excellent for bulk reads, useless as a message channel, because
every round trip pays the 135ms floor (~7 msg/s).

Guest RAM is at physical **0x80000000**, not 0. Other bases in `niagara.c`:
`HV_RAM 0x100000`, `UART 0x1f10000000`, `NVRAM 0x1f11000000`,
`MD_ROM 0x1f12000000`, `VDISK 0x1f40000000`, `IOB 0x9800000000`.

### Guest console: do not let a pty close under it

If a driving process closes the console pty, the shell gets SIGHUP and SMF's
`console-login` does NOT respawn it. The result is a guest that is fully alive --
kernel executing, PC in kernel text, a full host core busy -- and completely
unreachable: no console, no shell, and no network if PPP was not up. Recovery is
a restart. `tools/net-up.sh`'s expect closes the pty by design after handing off
to PPP, which is safe ONLY because PPP then owns the line.

### What is installed in the guest now

- gcc 4.3.3 + GNU as/ld 2.21.1, 254 headers, crt objects -- verified compiling
- **bash 3.2** (`/usr/bin/bash`) and **Sun_SSH 1.1** (`/usr/lib/ssh/sshd`),
  native Solaris packages, all under the SUNW_1.22.1 ceiling (bash 1.22,
  ssh 1.19, sshd 1.21). Needed two libraries the image lacked:
  `libmd.so.1` from SUNWcslr and `libwrap.so.1.0` from SUNWcsl (both to
  `/usr/sfw/lib`, with `LD_LIBRARY_PATH=/usr/sfw/lib`).
- A modern client needs legacy algorithms to reach that sshd:
  `ssh -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa
  -o PubkeyAcceptedAlgorithms=+ssh-rsa root@10.0.5.15`
- perl 5.8.4, and `tools/guest-pinetd.pl` serving telnetd
- **NOT installed** (staged at `/tmp/devtools.tar`, ~1.5MB): SUNWbtool, SUNWsprot,
  SUNWtoo, SUNWgzip, SUNWgmake, SUNWesu -- i.e. `make`, `gmake`, `ar`, `ranlib`,
  `nm`, `gzip`, `ldd`, `od`, `strings`, `lex`, `yacc`. Needed for P2-007.

### 40GB NFS share

`datapool/niagara/share` (quota 40G) at `/export/solaris`, exported
`10.0.5.15/32(rw,sync,no_subtree_check,no_root_squash,insecure)`, mounted in the
guest as `/share`:

```
mount -F nfs -o vers=3,proto=tcp,rsize=8192,wsize=8192 10.0.5.1:/export/solaris /share
```

Verified bidirectional and byte-exact. BUT it runs at ~11KB/s over PPP, so it is
for convenience, not bulk -- a 3.7MB install took ~7 minutes. Hypervisor source
is staged there at `/share/hv/src` (198 files, 10593029 bytes, byte-identical).

### How fast is the guest, actually? ~3.7x slower than native

MEASURED 2026-08-18, identical C with `unsigned int` so host and guest do the
same 32-bit arithmetic (`unsigned long` would not: 64-bit on x86-64, 32-bit in a
SPARC32 binary). 500M iterations of `s += i ^ (i >> 3)`, gcc -O2 both sides,
same result `2132397440`:

```
host  (Xeon E5-2690 v3):  0.35 - 0.39 s
guest (TCG sun4v):        1.4 s          -> ~3.7x slower
```

**Do NOT call this a "5 MHz" machine.** The MD declares
`clock-frequency = 5000000` / `stick-frequency = 5000000`, so `prtconf` and the
boot log report 5 MHz -- but that is a DECLARATION, not throughput. It controls
what the guest reports about itself and how it calibrates spin delays like
`drv_usecwait()`; a low value there is arguably helpful, since delay loops come
out short. Effective compute is ~360M simple ops/sec, call it 700 MHz-class.

TCG gets close to native on tight integer code because the translation is a few
near-native x86 instructions per guest instruction. What makes the guest FEEL
slow is everything else:

| operation | cost | bound by |
|---|---|---|
| 500M integer ops | 1.4s | CPU, only 3.7x down |
| trivial gcc compile+run | ~10s | process startup, syscalls, small-file I/O |
| 3.7MB tar over NFS | ~7 min | the PPP link at ~11 KB/s |

Planning consequence: a q.bin build (P2-007) will NOT be CPU-bound, so SMP
(P3-007) buys less than fixing the I/O path (P2-013, ~11 MB/s through the shared
region). Benchmark only when `uptime` is quiet -- under load average 170 the
guest starved so badly that raw `dd` stopped returning.

### CHECKPOINTING A RUNNING SESSION

You no longer need a clean shutdown to keep work:

```
sudo bash tools/checkpoint.sh            # quiesce + msync + snapshot
sudo bash tools/checkpoint.sh mywork     # ... and snapshot as @mywork
kill -USR2 <qemu-pid>                    # msync only, no snapshot
NIAGARA_SYNC_SECS=120 ...                # unattended periodic msync
```

SIGUSR2, not SIGUSR1 — QEMU uses SIGUSR1 as SIG_IPI to kick CPU threads and
swallows it.

**What P2-012 changed here: durability no longer needs a checkpoint.** The kernel
writes dirty pages back on its own schedule, verified by writing a file over
telnet and then `kill -9`-ing QEMU with no `atexit` path in the binary at all —
the file was in the image afterwards. `msync` now buys a KNOWN durability point,
not durability that was otherwise absent.

A mid-run flush is still crash-consistent only, so `checkpoint.sh` quiesces the
guest first with `sync; lockfs -f /` over telnet. Verify any checkpoint boots
before trusting it.

### EXIT PROCEDURE — quiesce, then stop QEMU

```
guest:  sync; lockfs -f /          (or `init 5`, waiting for "syncing ... done")
host:   kill -TERM <qemu-pid>
```

**SIGTERM is no longer load-bearing for data.** There is no `atexit` writeback to
run, so `kill -9` does not lose the disk — it only risks catching the guest
mid-transaction. The reason to quiesce is CONSISTENCY, not durability.

**Do not rely on `Ctrl-A c` from a scripted expect.** It does not reach QEMU:
with no `interact`, expect delivers `\x01c` to the guest, which echoes it
verbatim at the OBP prompt (observed as `ok s^Ac`) while expect waits forever
for a `(qemu)` prompt that never comes. Interactively it is fine; in a script,
signal the pid.

**Never kill a guest sitting at a shell prompt without quiescing.** Doing so
persists a dirty LUFS journal and the next boot panics (trace below). This was
re-learned the hard way: a killed session was snapshotted, and every clone of
that snapshot panicked in `vfs_mountroot`. Recovery was to roll back to the
last cleanly-shut-down snapshot and redo the work, since the payloads were all
reproducible from `tools/` — which is the reason to keep them reproducible.

**`lockfs -f / && sync` alone is NOT sufficient** if the guest keeps running. It
flushes, but the shell, syslog and atime updates keep writing afterwards, so the
journal is dirty again moments later. The next boot then panics replaying it:

```
BAD TRAP type=10  addr=0x300005e7840
  ufs:readlog -> ufs:fetchbuf -> ufs:ldl_read -> ufs:lufs_read_strategy
  -> ufs:ufs_getpage_miss -> vfs_mountroot
```

`init 0` unmounts the filesystems properly, closing that window. Verified with a
two-pass test: write a marker, `init 0`, quit; then boot again — marker present,
no panic. `lockfs` is still worth running before long-lived sessions, but it is
not a substitute for a real shutdown.

Recover a panicking disk with `./run-solaris.sh reset`.

## Known gaps

1. **No networking.** The Niagara machine has no PCI or virtio bus. OBP lists
   `net -> /virtual-devices/network@0` in `devalias` but no such node exists in
   the device tree and QEMU backs nothing. `iscsi` and `scsi_vhci` are loaded
   and force-attached in the guest, waiting for a network that isn't there.

2. **`format(1M)` refuses the disk.** It reports
   `controller name (SUNW,sun4v-virtual) is invalid`. `format` validates
   against a compiled-in controller table containing only `SCSI`, `ata`,
   `pcmcia`; this cannot be fixed via `/etc/format.dat` (the `ctlr` field there
   is a controller *class*, not a name). `iostat -En` is also blank for the same
   reason. Use `fmthard`, `newfs`, `prtvtoc`, and `dd`, which don't consult it.

3. **No second serial (`ttyb`) — blocked in the guest, not fixable from here.**
   Adding a `console@4` node to the MD works: OBP enumerates it
   (`show-devs` lists `/virtual-devices@100/console@4`). But Solaris will not
   bind a driver to it — `prtconf` shows `console (driver not attached)` and
   `/dev/term/` still has only `a`. Cause, from illumos
   `usr/src/uts/sun4v/io/qcn.c`: line 347 *"There is only once instance of this
   driver"*, and line 87 `static qcn_t *qcn_state;` — one global, not
   per-instance. `qcn` is a singleton by construction. Fixing it means
   rebuilding the guest driver, which needs a compiler in the guest, which is
   circular. The node stays in `md/common.pdesc`, documented, and the
   regenerated MD is deliberately NOT installed. Superseded by the exchange
   slice below.

4. **`test-reboot-obp-intact` is weak AND flaky.** It intermittently times out
   waiting for the login prompt (seen once in five runs). It matches `"ok"` and then
   `"disk"` in `devalias` output, both of which appear in plenty of unrelated
   output. It passes, but it is not strong evidence OBP is truly healthy after
   a reboot. The guest still prints
   `panic - kernel: prom_reboot: reboot call returned!` on reboot.

5. **`exchange` zvol — DESTROYED 2026-08-17, reclaimed 569MB.** It was an early
   FAT32 attempt on a *second* `-drive`, which Solaris cannot see without an MD
   node (and q.bin tracks only one disk anyway — a single `disk_pa` in
   `vdev_simdisk.s`). Superseded by the exchange *slice*.

   **Read that reason narrowly.** What failed was the *second drive*, not FAT.
   Putting a FAT32 filesystem on **slice 3 of the one disk we already have** is
   a different proposition and is strictly better than the current raw
   `dd`+`tar` channel, because it is bidirectional and random-access:

   - Host side is **verified working**: `mkfs.vfat -F 32` on a loop device at
     offset `4194304*512`, length 512MB, mounted `rw`, files written, unmounted,
     remounted, read back. 2.25s, no boot. Linux vfat read-write support is
     solid, unlike UFS.
   - Guest side is **VERIFIED** too: `mount -F pcfs /dev/dsk/c0t0d0s3:c /x`
     works on the FIRST try with a Linux-made FAT32 — no geometry tweaking, no
     fallback form needed. Solaris reports it as
     `/dev/dsk/c0t0d0s3:c  523244 kbytes  1% /x`. The only noise is a harmless
     `WARNING: hsimd_ioctl: cmd 760b not implemented` as pcfs probes an ioctl
     the RAM-disk driver lacks; the mount succeeds regardless.
     Guarded by `test-fat-exchange`.

   Note the host CANNOT write the guest's UFS root: this kernel has
   `CONFIG_UFS_FS=m` but no `CONFIG_UFS_FS_WRITE`, so `ufs.ko` is read-only by
   construction — an `rw` mount attempt is silently downgraded to `ro` and
   writes fail with EROFS. Host reads are fine (`tools/peek.sh`). Writing the
   root FS from the host would need a rump kernel or a NetBSD VM; see BACKLOG.

## Toolchain

Snapshot: `primary@toolchain-working`. Guarded by `test-toolchain-compiles`.

```
gcc 4.3.3   /opt/csw/gcc4/bin/gcc          (target sparc-sun-solaris2.8)
as, ld      /opt/csw/sparc-sun-solaris2.9/bin/   (GNU binutils 2.21.1)
```

**The 2.8/2.9 mismatch is the whole problem.** gcc was built for
`sparc-sun-solaris2.8` but its binutils are installed under `solaris2.9`, so
gcc cannot find its assembler and dies with:

```
gcc: error trying to exec 'as': execvp: No such file or directory
```

Fixed permanently by symlinking into gcc's own private exec dir, which it
searches before PATH:

```
cd /opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3
ln -s /opt/csw/sparc-sun-solaris2.9/bin/as as
ln -s /opt/csw/sparc-sun-solaris2.9/bin/ld ld
```

`-B/opt/csw/sparc-sun-solaris2.9/bin/` also works but only per-invocation, so
it breaks anything that calls `gcc` for you (configure scripts, makefiles).

### Where the headers came from

`/usr/include` shipped with only 12 third-party entries — no `stdio.h`. Now 254.

| package  | supplies                                              | media |
|----------|-------------------------------------------------------|-------|
| SUNWhea  | `stdio.h`, `stdlib.h`, `string.h`, `unistd.h`, + 1200  | CD5   |
| SUNWarc  | `crti.o`, `crtn.o`, `values-*.o` (+ `sparcv9/`)        | CD5   |
| SUNWlibm | `math.h`, `floatingpoint.h`, `iso/math_*.h`, `ieeefp.h`| CD5   |

**`math.h` is in SUNWlibm, NOT SUNWhea** — that cost a boot to discover.

**`crt1.o` is a red herring.** It is absent from SUNWhea/SUNWarc/SUNWarcr/
SUNWsprot, and it does not matter: gcc ships its own at
`/opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3/crt1.o`. Do not hunt for it
in Solaris media.

Extraction: these ISOs are *repacked*, so each package holds
`archive/none.7z` with an empty `reloc/`. Unwrap in two layers —
`7z x none.7z` yields a single file named `none`, which is a cpio archive:
`cpio -idm < none`. `tools/iso-extract.py` pulls a package straight out of a
remote ISO over HTTP range requests when the ISO is not local.

### libc version ceiling: `SUNW_1.22.1`

This image is `Generic_118822-23` (Solaris 10 3/05) and caps at `SUNW_1.22.1`.
OpenCSW's 2014 `SunOS5.10` builds need `SUNW_1.22.2` and die at load with
`ld.so.1: fatal: libc.so.1: version 'SUNW_1.22.2' not found`. **Always take
`SunOS5.8` or `SunOS5.9` builds.** Check before installing:

```bash
readelf -V <lib> | grep -oE 'SUNW_1\.[0-9.]+' | sort -uV | tail -1
```

## Driving the guest over the serial console

**Lines sent to the console MUST stay under 256 bytes.** The Solaris tty
canonical input buffer truncates anything longer *and drops the carriage
return*, so the command never executes and the session looks hung — the pane
shows a command cut off mid-word with no new prompt. `cd` into a directory and
use short relative paths instead of one long absolute command.

Two more things that make a live run look dead:

- **expect buffers `puts` when stdout is a pipe.** Start every expect script
  with `fconfigure stdout -buffering none`.
- **`| tail -N` buffers until the pipeline ends**, so a tmux pane stays blank
  for the whole run. Use plain `| tee logfile` when a human is watching, and
  set `VM_TRANSCRIPT` for tests (whose output is otherwise captured whole by
  `out=$(vm_run ...)` and only echoed at the end).
- **A helper that reports a missing prompt must ABORT, not continue.** Marching
  through ten dead commands at 20s each is how a permanent failure disguises
  itself as a five-minute hang. `tools/waitfor.sh` also fails fast now: if the
  log stops growing for `WAITFOR_STALL` seconds (default 45) without matching,
  it exits 3 and dumps the tail instead of waiting out the timeout.

## Inspecting the guest WITHOUT booting

```bash
sudo bash tools/peek.sh 'ls $MNT/opt/csw/bin'      # ~0.5s
sudo bash tools/peek.sh -s @baseline 'df -h $MNT'
sudo bash tools/peek.sh                            # interactive shell
```

Clones the dataset, mounts the clone's image read-only (`-o ro,loop,ufstype=sun`),
runs the command,
destroys the clone. 0.5s versus a ~60s boot. Use this for any read-only
question about the guest filesystem.

Do NOT mount the live image directly: a running guest dirties its pages
continuously, so you would read a torn, mid-transaction view. Formerly the whole
device on exit, so reading it races with that and can return a torn view. A
clone is a stable point-in-time image and is safe even while the VM runs.
Linux UFS write support for Solaris format is unreliable — to *change* the guest
filesystem, push a tar through `tools/exchange.sh`.

## Waiting for a VM run to finish

```bash
sudo expect /tmp/x.exp 2>&1 | tee /tmp/x.log &
bash tools/waitfor.sh /tmp/x.log 'Program terminated' 1800 'PANICKED|BOOT TIMEOUT'
```

Polls and returns the moment the marker appears. Do not use `sleep N` — it
wastes real time when the job finishes early and lies when it needs longer.
`vdisk writeback complete` NO LONGER EXISTS — P2-012 deleted the writeback. Match
`Program terminated` (the guest's own last word) or `vdisk synced` from an msync.

## Data channel (host -> guest bulk transfer)

q.bin serves the whole vdisk, and its size comes from VTOC slice 2's `nblk` at
offset 0x1d0. Slices are just byte offsets into that same disk — so an unused
slice is readable in the guest as `/dev/rdsk/c0t0d0sN` with **no new MD node,
no new QEMU device, no q.bin change and no new driver.**

```
s0  blocks       0 .. 4194295   2048MB  root UFS (untouched)
s3  blocks 4194304 .. 5242879    512MB  exchange, raw, no filesystem
s2  blocks       0 .. 5242879   2560MB  whole disk -> q.bin's served size
```

Host:
```bash
tools/exchange.sh setup datapool/niagara/vms/primary   # grow + lay out s3
tar cf payload.tar -C payload .
tools/exchange.sh push  datapool/niagara/vms/primary payload.tar
```
Guest:
```
dd if=/dev/rdsk/c0t0d0s3 bs=512 count=<blocks> 2>/dev/null | tar xvf -
```

Slice 2 MUST cover the exchange slice or q.bin will not serve those blocks —
`tools/vtoc.py verify` checks exactly that. `tools/vtoc.py` also recomputes the
label checksum at 0x1fe on every write; OBP validates it and rejects the disk
with "Bad checksum in disk label" if it is wrong, while QEMU does not check it.

Cost: the served size is allocated as anonymous host RAM, so a 2560MB disk uses
2560MB per running VM and moves that much on every boot and every clean exit.

Solaris `/bin/sh` is not POSIX — no `$(...)`. Use backticks in payload scripts.

## Environment

- Host: biggie (Linux x86_64, Xeon E5-2690 v3)
- QEMU: `./qemu/build/qemu-system-sparc64`, upstream 8.2.2 +
  `patches/0001-niagara-vdisk-writeback.patch`
- Firmware: `/datapool/niagara/base/` (openboot.bin, q.bin, nvram1, 1up-*.bin)
- Hypervisor + MD source: `~/vms/opensparc/`
- MD source of record: `~/vms/opensparc/legion/src/config/niagara/{1up,common}.pdesc`
- Repo: `http://biggie:3000/ryan/qemu-sun4v-illumos`

### ZFS layout

```
datapool/niagara/base                    firmware ROMs (filesystem)
datapool/niagara/images                  disk dataset, recordsize=8K + lz4
datapool/niagara/images/primary.img      THE DISK (2560MB, MAP_SHARED)
datapool/niagara/images@baseline         test + reset baseline   <-- DEFAULT
datapool/niagara/images@pre-mapshared    first copy off the zvol
datapool/niagara/<name>-<pid>            ephemeral test/peek clones (DATASETS)

datapool/niagara/vms/primary             PRE-P2-012 zvol, kept as a fallback
datapool/niagara/vms/primary@pre-p2012-cutover   state at the moment of cutover
```

**Clones are dataset clones**, so the image file comes along:
`zfs clone .../images@baseline .../test-x` gives
`/datapool/niagara/test-x/primary.img`. Instant, no extra space, identical
semantics to the old zvol clones — the review's key correction was that files lose
nothing here.

`recordsize=8K` because `MAP_SHARED` writeback is 4K-page granular and ZFS's 128K
default would turn each dirtied page into a 128K read-modify-write. With lz4 the
image is **585M on disk against 2.5G apparent**.

The old zvol at `vms/primary` is retained deliberately as a rollback path. It is
not used by anything and can be destroyed once the file stack has proven itself
over a few sessions.

**All disk paths go through `img_require()` in `tools/lib/image.sh`.** Nothing
reconstructs the path itself — six tools each building `/dev/zvol/$ds` is how a
literal `2668003328`, wrong by 832 blocks, got hardcoded into `niagara.c`. Handed
a zvol, `img_require` refuses with the `dd` conversion spelled out.

## Operating it

```bash
./run-solaris.sh            # boot the image (takes the lock)
./run-solaris.sh status     # dataset/snapshot state + lock holder
./run-solaris.sh reset      # rollback to @baseline
sudo bash tools/net-up.sh   # boot WITH networking, then: telnet 10.0.5.15
sudo bash tools/net-down.sh # tear it down  (--rollback to discard the session)
sudo bash tools/peek.sh 'ls $MNT/opt/csw'   # inspect the FS, no boot, ~0.6s
sudo bash tools/checkpoint.sh [snapname]    # quiesce + msync + snapshot
sudo bash tests/run-all.sh                  # full suite, 7 tests
sudo bash tests/reap-orphans.sh             # reclaim clones AND loop devices
bash tools/exchange.sh scratch              # sourceable scratch-region offsets
bash tools/build-mdgen.sh                   # build the MD compiler
```

Run VM work in the `sparc` tmux session so it is watchable:
`~/bin/sane-send-keys sparc "<cmd>" Enter`.

## Toolchain status: WORKING — compiles, links, runs

`gcc (GCC) 4.3.3` runs in the guest at `/opt/csw/gcc4/bin/gcc`, with GNU
`as`/`ld` 2.21.1 symlinked into gcc's exec dir. Snapshots:
`primary@toolchain-working`, and every later snapshot inherits it.

**Verified end to end** (re-confirmed 2026-08-18 over telnet against the live
guest, not inferred):

```
# cat > r.c   ... #include <stdio.h> <stdlib.h> <string.h> <math.h>
#              ... malloc, strcpy, sqrt, strlen
# /opt/csw/gcc4/bin/gcc -O2 -o r r.c -lm && ./r
REVIEW 1.41421 6
# file r
r: ELF 32-bit MSB executable SPARC32PLUS Version 1, V8+ Required,
   dynamically linked, not stripped
```

`/usr/include` now has **262 entries** including `stdio.h`, `stdlib.h`,
`string.h`, `unistd.h`, and `math.h`. crt objects (`crti.o`, `crtn.o`,
`values-*.o`) are in `/usr/lib` and `/usr/lib/sparcv9`.

Installed from packages extracted off the Solaris 10 3/05 media: `SUNWhea`
(1217 headers), `SUNWarc`, `SUNWarcr`, `SUNWlibm` (`math.h`,
`floatingpoint.h`, `iso/math_c99.h`, `iso/math_iso.h`, `sys/ieeefp.h`).

**`crt1.o` was never needed** — that hunt was a dead end. gcc ships its own at
`/opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3/crt1.o`, so plain `gcc` links
with no `-B` flag required.

### HOST-SIDE printf will silently corrupt guest C source

Burned twice, so it is recorded here. Generating a `.c` file with a host
`printf '...'` lets the HOST shell consume `%s`, `%d`, `%.5f` as its own format
specifiers. The file that lands in the guest has them substituted away, gcc
compiles it happily, and the program prints garbage — which looks exactly like a
broken compiler. First occurrence produced `SQRT2=%.4F` baked in as a literal;
second produced ` 0.00000 0` instead of `REVIEW 1.41421 6`.

Use a quoted heredoc (`cat > r.c <<'XEOF'`) or double every `%`. If a freshly
compiled program prints zeros or empty strings, suspect the harness before the
toolchain.

### Still not installed (staged at `/tmp/devtools.tar`, ~1.5MB)

`SUNWbtool`, `SUNWsprot`, `SUNWtoo`, `SUNWgzip`, `SUNWgmake`, `SUNWesu` — i.e.
`make`, `gmake`, `ar`, `ranlib`, `nm`, `gzip`, `ldd`, `od`, `strings`, `lex`,
`yacc`. Needed for P2-007 (building q.bin in-guest), not for ordinary compiling.
Note `strings` and `od` being absent has broken verification commands before.

### libc version ceiling (important for any future OpenCSW package)

This image's `libc.so.1` provides up to **`SUNW_1.22.1`**.

OpenCSW's 2014-era `SunOS5.10` builds require **`SUNW_1.22.2`** and fail at
runtime with:
```
ld.so.1: gcc-4.9: fatal: libc.so.1: version `SUNW_1.22.2' not found
```
Always prefer **`SunOS5.8` / `SunOS5.9`** builds from
`http://mirror.opencsw.org/opencsw/allpkgs/` — they need only symbols this libc
has. Check any candidate with:
```bash
readelf -V <lib> | grep -oE 'SUNW_1\.[0-9.]+' | sort -uV | tail -1
```
`libz.so.1` from CSWlibz1 (2013) is one of the casualties; Solaris' own
`/usr/lib/libz.so.1` needs only `SUNW_1.1` and works, so symlink to that.

## Next actions

### Networking direction — PPP milestone complete, Ethernet remains next

The earlier quarantine on Solaris 10 PPP is superseded by measured Tribblix
acceptance on 2026-08-22. The four donor kernel/STREAMS modules loaded, a
Tribblix-built 64-bit `pppd` negotiated IPv4 over channel 0, outbound DNS/HTTP
worked through Linux NAT, and NFSv3/TCP mounted `/export/solaris` as a 40 GB
source disk. Exact hashes and the 32-bit ABI diagnosis are in
`notes/TRIBBLIX-PERSISTENT-UFS-AUTOBOOT.md`.

Ethernet over channel remains the performance-oriented follow-on: a userland
DLPI-to-channel relay in the guest paired with a channel-to-TAP relay on Linux.
Two VNICs on an illumos etherstub provide the guest IP port and wire-facing
relay port. This yields ordinary Ethernet without a new kernel driver and lets
Linux provide routing/NAT.

The data-link half is already partially proved: temporary etherstub and VNIC
creation succeeded.  The immediate blocker is the broken illumos IP-management
substrate (`ipadm` cannot open its library handle and `ifconfig` aborts during
its IPv6 socket setup), not `dladm` or VNIC support.

Full topology, framing, caveats and validation sequence:
[`notes/ETHERNET-OVER-CHANNEL.md`](notes/ETHERNET-OVER-CHANNEL.md).

1. **Resolve system headers + crt objects** (see above) — this is the only thing
   standing between us and a working build environment.
2. **Get a compiler in.** The channel exists and is tested. Fetch gcc4core +
   deps from OpenCSW (`http://mirror.opencsw.org/opencsw/stable/sparc/5.10/`,
   ~137MB compressed) — note the 512MB exchange slice holds it, but check the
   installed size against the 1.6GB free. Then `pkgadd -d` from the extracted
   payload. First thing to build once it works: a `format(1M)` that does not
   reject the `SUNW,sun4v-virtual` controller name (Known gaps #2).
2. **Strengthen and de-flake `test-reboot-obp-intact`** so it asserts something
   real and stops timing out.
3. `ttyb` is parked — blocked on the qcn singleton (Known gaps #3).
