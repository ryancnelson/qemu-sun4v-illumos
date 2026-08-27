# OpenIndiana workstation cold-reboot acceptance

This checklist gates the one remaining functional claim for
`workstation-fix-verify-01`.  It does not grant lifecycle authority.  Ryan's
explicit approval is required before any reboot, shutdown, reset, QEMU
replacement, or monitor action.  The harness never performs those actions.

## Fixed identities

- Protected control VM: PID 2719062, `workstation-reboot-01`.  It must remain
  alive with its exact console path throughout the experiment.
- Sole reboot target: tmux/run `workstation-fix-verify-01`.  Resolve its QEMU
  PID only from that run's `qemu.pid`; match its exact console, monitor, four
  disk units, and cloned unit-104 path before admitting the gate.
- Existing host transport: run-scoped channel-0 bridge on unit-101 byte 327680
  and `host-chan0.sock`, plus host PPP 10.0.5.1 peer 10.0.5.15.  Do not invoke
  legacy `host-up.sh` or any SIGUSR2 mechanism.

## Before requesting reboot authority

Run the non-mutating preflight:

```sh
tools/openindiana/workstation-cold-reboot-gate.py preflight
```

It must return `PRECHECK_PASS` and literal evidence for both QEMU identities,
all five target tmux windows, console inode/size/mtime, connected exact-byte
bridge, exact host pppd, and ppp0 addressing.  A failure is terminal until its
specific mismatch is understood.  Do not repair by signaling or replacing a
VM.

Then record the explicit Ryan approval and choose one unique evidence ID:

```sh
tools/openindiana/workstation-cold-reboot-gate.py arm \
  workstation-fix-verify-01-reboot-YYYYMMDDTHHMMSSZ
```

`arm` creates only a mode-0700 run-local evidence directory and anchors the
starting console inode/byte offset.  It prints `ARMED_NO_REBOOT_ACTION`; it does
not reboot.  Run `arm` before the approved operator action, not after it.

## Approved reboot and bounded observation

Only after Ryan's explicit approval, the console owner performs the separately
reviewed guest reboot action.  Do not use the QEMU monitor, do not quit or
replace QEMU, and never touch PID 2719062.  Immediately start observation with
the same evidence ID:

```sh
tools/openindiana/workstation-cold-reboot-gate.py observe \
  workstation-fix-verify-01-reboot-YYYYMMDDTHHMMSSZ --timeout 1800
```

Observation reads only console bytes appended after `arm`.  It samples without
input and fails closed on QEMU identity loss, console replacement/truncation,
panic, KMDB, missing OBP/kernel/root/multi-user/login milestones, or timeout.
Admission to post-login requires all of:

1. fresh OBP evidence;
2. SunOS kernel progress;
3. root on `rpool/ROOT/openindiana`;
4. execution of `/etc/rc2.d/S99niagara` or equivalent multi-user evidence;
5. literal `oi-basecamp console login:`.

## Login and functional acceptance

The console owner logs in with the documented root credential.  Stop if the
literal `root@oi-basecamp:~#` prompt does not appear.  Do not start or repair
network services manually.  At that untouched prompt run:

```sh
tools/openindiana/workstation-cold-reboot-gate.py postlogin \
  workstation-fix-verify-01-reboot-YYYYMMDDTHHMMSSZ
```

The harness sends one short command at a time through only the target console,
requires its sentinel and the exact root prompt before the next command, and
retains each result.  It requires:

- exactly one `niagara-net-supervisor`;
- sppp0 guest 10.0.5.15 peer 10.0.5.1;
- default route through 10.0.5.1;
- the exact read-only NFSv3/TCP `/mnt/nfs` mount;
- a timestamped supervisor smoke `.PASS` marker newer than the arm point;
- a fresh bounded `oi-devtools-smoke` result containing compile/link/run, PPP,
  NFS-canary, and durable-wrapper PASS markers.

Only `COLD_REBOOT_ACCEPTANCE_PASS` closes the functional gate.  Preserve the
entire run-local evidence directory on either pass or failure.  Any lifecycle
retry requires new Ryan authority and a new evidence ID.

## Live dry-run evidence

At 2026-08-27T03:41:18Z the read-only `preflight` mode returned
`PRECHECK_PASS` against the current live state:

- protected PID 2719062 matched only `workstation-reboot-01`;
- target PID 3063953 matched only `workstation-fix-verify-01` and its exact
  console, monitor, units 100/101/103/104, and cloned target-104 path;
- target tmux windows `qemu`, `console`, `monitor`, `host-chan0`, and
  `host-ppp` were all alive;
- console inode 4972593 had starting size 261973 bytes, and remained exactly
  261973 bytes after preflight, proving the dry run sent no guest input;
- bridge PID 3198609 used the exact isolated channel image and byte 327680;
  its last client event was `host bridge: ch0 client connected`;
- exact host pppd PIDs 3200619 and 3200620 were alive, with ppp0
  `10.0.5.1 peer 10.0.5.15/32`.

No evidence directory was armed, no console or monitor input was sent, and no
VM, disk, process, network service, or mount state changed.  The harness is
`COLD_REBOOT_GATE_READY`; actual execution remains
`REBOOT_AUTHORITY_REQUIRED`.

## Rollback checkpoint

The verification target has a guest-synced, live rollback point taken before
any reboot action:

```text
datapool/workstation-fix-startup-01@cold-reboot-ready-a0c09ab-20260827T034757Z
```

It exposes the exact 64,424,509,440-byte target104 file and has `clones=-`.
Protected PID 2719062 uses the different dataset
`datapool/workstation-reboot-01`; it is not represented by or dependent on
this snapshot.  The checkpoint does not grant restore, clone, rollback, or
reboot authority.  Any such action remains separately approval-gated.

### Mechanical rollback admission

The `preflight` phase now fails closed unless live QEMU argv yields exactly one
explicitly writable unit104 for each of the verification and protected PIDs.
It requires both live files to be regular 64,424,509,440-byte files, resolves
each path through the host mount table, and admits only this distinct mapping:

```text
PID 3063953 -> datapool/workstation-fix-startup-01
PID 2719062 -> datapool/workstation-reboot-01
```

It then requires the exact snapshot
`datapool/workstation-fix-startup-01@cold-reboot-ready-a0c09ab-20260827T034757Z`
and derives the snapshot target path from the verified live target relative to
that dataset mountpoint. Admission requires that snapshot view to expose a
regular file with logical size 64,424,509,440 bytes. No fallback snapshot,
dataset, path, or size is accepted.

At 2026-08-27T04:01:13Z a host-only dry run returned `PRECHECK_PASS` with the
two exact distinct datasets above and:

```text
/datapool/workstation-fix-startup-01/.zfs/snapshot/
  cold-reboot-ready-a0c09ab-20260827T034757Z/ryan/devel/masa-sun4v/ci/runs/
  term4code-herm-smp4-01/images/extra-unit104-60g.img
logical size: 64424509440
```

The focused unit suite returned `14 passed`. This dry run only inspected host
process metadata, paths, mount ownership, snapshot metadata/view, tmux state,
and existing network state. It did not arm a gate or send console/monitor
input, signal a process, checksum/copy/clone/hold/rollback a file or snapshot,
or perform any QEMU lifecycle action.
