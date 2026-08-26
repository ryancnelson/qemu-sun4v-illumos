# R0 warm-checkpoint attempt: FAILED, marked DO-NOT-RESTORE

Date: 2026-08-25. Migration stream captured from the live R0 basecamp VM
(PID 709698 on niagara-playbox) after a clean quiesce (all guest/host
channel and PPP writers stopped, guest+host synced, VM paused via monitor
`stop`).

## Verdict: warm/live-state migration is NOT usable on this Niagara board
model with this exact QEMU build. This is a confirmed FAIL, not merely
"experimental" or "untested."

## Artifacts (do not restore from the migration stream; keep for forensics only)

```
migration stream   /home/niagara/sun4v/runs/basecamp-r0-20260825T055300Z/migration-checkpoint-1.raw
                    478,124,589 bytes
                    SHA-256 f7e0dcd2a5d94181a30d50cda7b832ad8ff2a33953e88b69f0c19d4f901968f5

QEMU binary used    /home/niagara/niag-proj/qemu/build/qemu-system-sparc64.baseline-11aa0b1
                    SHA-256 7073119a7c2c15527cd93a315ccce30bafacb537228e049eafb4118b46b0a053

source argv         qemu-system-sparc64.baseline-11aa0b1 -M niagara
                    -L /home/niagara/sun4v/firmware/base-1gib -m 1024 -nographic
                    -monitor unix:.../monitor.sock,server=on,wait=off
                    -serial unix:.../serial.sock,server=on,wait=off
                    -drive if=pflash,file=<R0 image>,format=raw

restore argv        same QEMU/machine/firmware, distinct pflash backing
                    file (fresh reflink of the disk-byte snapshot, never
                    the checkpoint master), distinct monitor/serial
                    sockets, plus:
                    -incoming exec:cat <migration-checkpoint-1.raw>
```

## Timing

`migrate -d exec:cat><file>` on the source (paused) completed in 3,649 ms;
466,918 KB RAM transferred, throughput ~1,049 Mbps, downtime 0 ms (measured
by QEMU itself, on the SOURCE side -- this number describes the source
guest's stop-the-world time during migration setup, not the restore).

Incoming restore attempt: RTO measured start-to-failure was 86 seconds
(includes reflink creation, QEMU launch, `-incoming` load, `cont`, and the
guest fault appearing) -- but this measures time-to-FAILURE, not a usable
recovery time. There is currently no working RTO for warm/live-state
restore on this board model.

## Exact failure evidence (from the restore instance's own stdout log,
captured before cleanup)

```
niagara: msync on SIGUSR2 -> kill -USR2 716983
niagara: vdisk 614 MB MAP_SHARED from <restore reflink path>
qemu: fatal: Trap 0x0032 while trap level (6) >= MAXTL (6), Error state
pc: 000000000040f02c  npc: 000000000040f030
%g0-3: 0000000000000000 0000000000000000 0000000000000000 0000009700000280
%g4-7: 0000000000001000 0000000000000000 0000000000000000 0000000000000000
%o0-3: 0000000000000001 0000000000000000 000000000180c000 0000000000000000
%o4-7: 0000000000000001 0000000000000012 000002a10001f0e1 000000000104405c
%l0-3: 0000000000000016 0000000000000001 000000000180c000 000000000190f870
%l4-7: 0000000000000000 0000000001915d50 0000000000000000 0000000001915e88
%i0-3: 0000000000000000 ffffffffffffffff 00000300037c5b40 00000300037c5b40
%i4-7: 0000000000000001 0000000000000000 000002a10001f191 000000000106e728
pstate: 00000014 ccr: 00 (icc: ---- xcc: ----) asi: 80 tl: 6 pil: 0 gl: 6
tbr: 0000000001000000 hpstate: 0000000000000804 htba: 0000000000404000
cansave: 6 canrestore: 0 otherwin: 0 wstate: 14 cleanwin: 7 cwp: 7
```

The guest CPU trapped into an unrecoverable double-fault (trap level
reaching MAXTL) almost immediately after `cont` on the restore side. The
migration stream loaded and the monitor reported "Migration status:
completed", but the restored SPARC CPU/trap register state was not
actually consistent with the guest's real execution context.

## Root cause (matches a pre-existing audit finding, now confirmed empirically)

Niagara board-specific UART/IOB/vdisk device state most likely lacks
complete `VMStateDescription` coverage in this QEMU port. Generic QEMU
migration serializes only devices with registered vmstate; anything
missing silently loses state, and on a real CPU-heavy trap-handling
target like sun4v that shows up exactly like this -- a `cont` that
immediately re-enters a bad trap chain.

## Consequence for the recovery-anchor design

- The disk-byte snapshot captured alongside this attempt
  (`basecamp-r0-paused-snapshot-20260825T063737Z.iso`, SHA-256
  `730386bb230006a3d299d94a2c09cf70b64cecca126c8798fb6f25ac906464ba`) is
  **NOT a standalone cold-bootable anchor**. R0's channel bootstrap staging
  (block 1046530) overwrote live bytes inside the boot archive extent
  (`[449744896, 642340864)`), so this snapshot's boot archive is already
  mutated relative to the accepted `boot_archive.hsimd` component. It must
  not be assumed reboot-safe without re-testing a fresh `boot disk -v`
  against it specifically.
- The only currently-proven recovery path is the COLD path: rebuild from
  the two immutable inputs (`iso.clean` + `boot_archive.hsimd`) plus the
  session's proven manual/scripted sequence. Measured cold RTO for this
  session's manual walkthrough was on the order of 15-20 minutes (boot to
  maintenance shell, mount `.cdrom`/`/usr`, stage channel payload, bring up
  PPP/NFS).
- A sub-few-minute warm RTO is NOT currently achievable on this board model
  with stock QEMU migration. Achieving it would require either (a) adding
  full `VMStateDescription` coverage for the Niagara-specific devices in
  this QEMU fork, or (b) a host-process-level checkpoint/restore facility
  (e.g. CRIU) operating on the QEMU process itself rather than QEMU's own
  migration protocol -- unexplored as of this writing, see companion check
  for CRIU availability on playbox.
