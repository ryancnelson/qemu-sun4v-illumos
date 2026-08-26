# Biggie OpenIndiana `term4code-02` preparation

## Bounded hypothesis

With the exact hSIMD already embedded in `ppp-injected-v2-20260825` held
constant and `/etc/system` containing the exact line
`set zfs:zfs_vdev_aggregation_limit=0x20000`, no hSIMD request will exceed
`0x20000` during dataset create, write, sync, or read.

This preparation must stop at `PRELAUNCH_READY`; Ryan signoff is required
before the trial boots.

## Mechanical pipeline

`tools/openindiana/prepare-term4code-02.py` consumes an explicit JSON config.
It validates the disposable builder identity, tmux/socket ownership, unique
run-local disk units, and the proven PCFS guest device before performing any
command.  Each stage has an argv vector, timeout, expected marker, and run-local
JSONL evidence.  It then requires:

- pinned boot-archive size/hash and unchanged in-archive hSIMD size/hash;
- media fallback V2, slice-zero-first discovery, and disabled DHCP branch;
- exact aggregation-limit readback from the archive reopened read-only;
- writable RAM-root and PPP/channel payload manifest gates;
- a new immutable installer release;
- exact unit101 mailbox size, VTOC, offsets, magic, and sequence evidence;
- exact 60 GiB unit104 VTOC, featureless `tink`, required properties, clean
  export, and detached loop evidence;
- one-vCPU QEMU argv with read-only unit103, writable units101/104, and Unix
  console/monitor sockets.

The enumerated terminal outcomes are:

- `PRELAUNCH_READY` (exit 0): every stage and final manifest passed;
- `BLOCKED_MISSING_BUILDER_TOPOLOGY` (exit 20): no reviewed donor unit/slice
  manifest was supplied;
- `PREPARATION_FAILED` (exit 1): identity, timeout, marker, command, manifest,
  or argv mismatch.  Evidence already captured is preserved.

## Current result

The pinned archive is
`ppp-injected-v2-20260825/boot_archive.ufs`, 192,595,968 bytes, SHA-256
`27b12613805505594cdbfcd2b276c413205070085554ce00505566a8fc6e9676`.
The authoritative hSIMD is the file inside that archive; substituting a newer
driver would invalidate the controlled A/B.

The prior Exabyt builder endpoint was unresolved.  The successful isolated
fallback was `oi-archive-builder-biggie-06`: OpenIndiana itself booted a
writable RAM root from a run-local unit103 clone, recovered `/.cdrom`, `/usr`,
and `/mnt/misc`, and mounted a labelled raw-slice wrapper at unit104 slice3.
Solaris read the `Zcmp` method as expanded text, applied media V2, and read back
the exact literal and unchanged hSIMD.  Failed disposable Tribblix donor
attempts 02--05 are preserved with their root-mount panic evidence.

The finalized boot archive is 192,595,968 bytes, SHA-256
`e547ed68b6656a54a4fdbdced97f73677f4bf0394320f083890fd7d3ceed65df`.
Immutable release `oi-bounded-v2-20260826` has unit103 SHA-256
`e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c`.
The complete real-evidence pipeline now returns `PRELAUNCH_READY`.
Existing protected Biggie VMs and published inputs were not modified.

Run-local preparation already completed before this blocker includes a fresh
unit101 clone with valid VTOC, slice 7 at byte 327680, `NIAG` magic, zero
sequence field, and source hash
`9cebbadd4f02a79b249f4aef4505f544d65c9432847c17f2f26cddb02838ec8c`.
Fresh unit104 is exactly 60 GiB with valid s0/s2 geometry; `tink` was ONLINE
with zero errors, all 39 feature properties disabled, ashift 9, recordsize 8K,
compression/atime off, sync always, then cleanly exported and detached.  The
60 GiB sparse file was not redundantly hashed.

Fast unit tests cover the typed blocker, duplicate-unit rejection, timeout
validation, media-V2 idempotence, and a mocked complete path ending at
`PRELAUNCH_READY`.

## Execution result through installed-kernel handoff

The trial booted from unit 103 with `-k -v`.  Media V2 selected the proven
slice-zero mapping (`c4d3s0`) without entering the impossible DHCP branch.
After the native `devfsadm` ran from the mounted `/usr`, `/.cdrom`, `/usr`, and
`/mnt/misc` all passed their independent mount and payload canaries.  The live
kernel reported `zfs_vdev_aggregation_limit` as hexadecimal `20000`.

The featureless 60 GiB unit 104 pool imported without upgrade.  Dataset create,
an 8 KiB-record 256 KiB write, `sync`, and a 256 KiB read all completed without
an hSIMD assertion or panic.  Snapshot `tink/bounded@io-256k-pass` preserves
that handhold.  Unit 101 then passed a 65,536-byte random echo, PPP came up with
symmetric `asyncmap 0`, the guest pinged the host peer, and an outbound
`8.8.8.8` ping returned three of three packets.

The installer completed at `2026-08-26 06:03:58 PDT` on unit 104.  Its elapsed
time padding loops had to use the run-local correction `-lt 3` instead of
`-ne 3`; the root and `/var` copies then completed.  A long IPS live-package
uninstall child was killed while its parent installer was suspended and then
resumed; the installer continued, built the target boot archive, unmounted all
ZFS filesystems, and rebooted.  This means the installed image may retain live
packages and must be audited after first login.

The first manual installed-root boot used
`boot /virtual-devices@100/disk@4:a -k -v`.  It loaded `unix`, `genunix`, the
sun4v platform module, and KMDB.  Each of three `:c` commands stopped at the
same `page_list_add+0x9c` instruction with a data-access MMU-miss single-step
stop.  No panic was reported.  QEMU PID 1560790 was subsequently retired
through its monitor; it no longer exists, and its console and monitor sockets
are absent.  The complete console evidence remains in the run-local
`console.log`.  Protected SPARC QEMUs 911583 and 1282896 were independently
accounted for and were not touched.

The distinguishing next test is not another blind `:c`.  Boot the unchanged
run-local installer as a recovery environment, import the installed rpool
without upgrade, and inspect the target `/etc/system` and boot archive.  The
installer source removes lines beginning with `set zfs` while populating the
target, so the exact aggregation literal must be restored and the target boot
archive rebuilt before a cold installed-root boot without `-k`.  The bounded
storage gate has already passed under KMDB; omitting `-k` from this follow-up
isolates the repeatable KMDB/QEMU single-step interaction from installed-root
viability.

## Installed-root recovery and cold-boot discriminator

The isolated live-media recovery imported `rpool` with `-R /a -N` and no
upgrade.  `zfs mount -a` is unsafe in this environment: it aborted in userland
with an AVL assertion after mounting child datasets before their parent.  The
repeatable recovery sequence mounts `rpool/ROOT/openindiana` first and
`rpool/ROOT/openindiana/var` second; this restores the real `/a/var/tmp` needed
by `bootadm`.

The first installed-root failure without KMDB was narrower than the earlier
single-step stops.  The kernel loaded, then root-device loading stopped with
`disk: no major number` and `Cannot load drivers for
/virtual-devices@100/disk@4:a`.  Read-only comparison proved the live archive
registered `hsimd` as major 338 with alias `SUNW,legion-disk` and path-to-instance
entries for units 0 through 7, while the installed target omitted all three.
Major 338 was unclaimed in the target.

After recursive snapshot `@pre-hsimd-registration`, the target received those
exact live registration records.  `bootadm update-archive -R /a` completed,
using the explicitly mounted target `/var`.  A single reopened-archive strings
pass returned all four exact admission markers:

```
hsimd 338
hsimd "SUNW,legion-disk"
"/virtual-devices@100/disk@4" 4 "hsimd"
set zfs:zfs_vdev_aggregation_limit=0x20000
```

Snapshot `@hsimd-registration-bootarchive-pass` preserves the accepted target.
The pool then exported cleanly: `zpool list` reported no imported pools and
`zpool import` rediscovered `rpool` ONLINE on `c4d4s0`.

Fresh QEMU PID 2027153 owns the unchanged topology in tmux windows `owner5`,
`console5`, and `monitor5`.  Cold boot command
`boot /virtual-devices@100/disk@4:a -v` has loaded the installed boot archive,
kernel, genunix, platform module, and OpenIndiana 2025.12 banner without either
the KMDB `page_list_add+0x9c` stop or the missing-major failure.  `hsimd4`
attached the full `0xf00000000` device and the kernel mounted
`rpool/ROOT/openindiana` as its ZFS root.

The one-time SMF import completed all 191 service descriptions and persisted
multiple large transactions without an hSIMD panic.  Multiuser did not start:
at `08:36:05` and again at `08:38:02`, `svc.startd` put
`svc:/system/filesystem/root-minimal:default` into maintenance because of the
same dependency cycle.  The printed cycle includes the live-media service
`svc:/system/filesystem/root:media`, plus identity, network/physical, varpd,
device/local, `/usr`, boot-archive, and root-minimal.  No login prompt appeared.
This is consistent with the known interrupted live-package uninstall retaining
a live-media manifest or repository definition in the target.  The next
discriminator is a live-media recovery inspection of the target `root:media`
definition before any repair.
