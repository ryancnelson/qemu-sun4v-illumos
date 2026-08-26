# OpenIndiana workstation candidate — 2026-08-26

This note is the canonical handoff for the first installed, multiuser
OpenIndiana SPARC workstation candidate.  It records what exists, what is only
live runtime state, and what an AWS or other CI worker must reproduce.  The
earlier forensic transcript remains in
`notes/OPENINDIANA-INSTALLED-MULTIUSER-MILESTONE-20260826.md`.

Every PID and live-process statement below is a dated observation, not a
stable identifier.  Revalidate before operating the VM.

## Candidate identity

- Guest name: `oi-basecamp`.
- Guest architecture: SPARC (`uname -p` reported `sparc`).
- Host: Biggie.
- Run directory:
  `/home/ryan/devel/masa-sun4v/ci/runs/term4code-herm-smp4-01`.
- QEMU PID last observed at 12:27 PDT: `2366353`.
- Operator tmux session: `workstation-candidate`.
  - window 1: `console`
  - window 2: `bridge0-ppp`
  - window 3: `ppp0`
- The underlying QEMU/console windows are linked from
  `term4code-herm-smp4-01`; the QEMU itself is setsid-detached and is not owned
  by the lifetime of the operator tmux session.

The obsolete `term4code-02` QEMU died from the SIGUSR2 incident recorded in
`notes/INCIDENT-TERM4CODE-02-SIGUSR2-20260826.md`.  Its 24-window tmux session
was removed after proving that it contained only shells and channel helpers
for the dead VM.  Its run directory must **not** be deleted: the workstation
candidate still references the QEMU executable, firmware directory, and
read-only unit-103 image stored there.

## Installed-root milestone

The guest cold-booted from:

```text
boot /virtual-devices@100/disk@4:a -v
```

Observed kernel/root evidence:

```text
virtual-device: hsimd4
hsimd4 is /virtual-devices@100/disk@4
root on rpool/ROOT/openindiana fstype zfs
```

The installed guest reached a multiuser root prompt.  `zpool status -x`
reported all pools healthy.  Both completed `zfs diff -FH` comparisons from
`rpool/ROOT/openindiana@hsimd-registration-bootarchive-pass` and its `/var`
snapshot to the then-current datasets produced zero changed paths before the
workstation BE was created.

## Boot environment

At 12:25 PDT the live guest successfully created:

```text
workstation-candidate-20260826
```

The resulting `beadm list` was:

```text
BE                             Active Mountpoint Space Policy Created
openindiana                    NR     /          3.15G static 2026-08-26 05:03
workstation-candidate-20260826 -      -          140K  static 2026-08-26 12:25
```

The candidate BE is a filesystem checkpoint, not a VM snapshot.  It captures
the boot-environment datasets, including the installed software and persistent
configuration in those datasets.  It does not capture QEMU state, RAM,
OpenBoot/NVRAM, host services, channel mailboxes, PPP processes, or the host's
routing/NAT state.

The new BE was **not activated**.  The active-now and active-on-reboot BE
remained `openindiana`.  After the external artifact bundle is protected, the
bounded next action is:

```text
beadm activate workstation-candidate-20260826
beadm list
```

Do not infer that activation or a reboot test has happened.  A fresh-QEMU boot
of the activated BE is still the acceptance gate.

`beadm create` warned that `/rpool/boot/menu.lst` did not exist and generated
one.  Preserve and inspect that pool-level boot file as part of the cold-boot
test; it may live outside the BE datasets.

## Exact QEMU and storage contract

The running command uses Murayama's QEMU sun4v work:

```text
/home/ryan/devel/masa-sun4v/ci/runs/term4code-02/qemu-system-sparc64
  -M niagara
  -L /home/ryan/devel/masa-sun4v/ci/runs/term4code-02/firmware
  -m 8192 -smp 4
  -serial file:/dev/null
  -serial unix:RUN/console.sock,server=on,wait=off
  -monitor unix:RUN/monitor.sock,server=on,wait=off
  -nographic
  -drive id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file=RUN/images/carrier-unit100.img
  -drive id=channel101,format=raw,if=none,bus=0,unit=101,readonly=off,cache=none,file=RUN/images/channel-unit101.img
  -drive id=installer103,format=raw,if=none,bus=0,unit=103,readonly=on,cache=none,file=SOURCE/images/installer-unit103.img
  -drive id=target104,format=raw,if=none,bus=0,unit=104,readonly=off,cache=none,file=RUN/images/extra-unit104-60g.img
```

where `RUN` is the candidate run directory above and `SOURCE` is
`/home/ryan/devel/masa-sun4v/ci/runs/term4code-02`.

Artifact inventory:

| Unit | Role | Candidate path | Size | CI treatment |
| --- | --- | --- | ---: | --- |
| 100 | carrier | `RUN/images/carrier-unit100.img` | 1,073,741,824 | Preserve or clone sparsely |
| 101 | channel mailbox | `RUN/images/channel-unit101.img` | 33,554,432 | Regenerate/reset for each run; do not treat live PPP bytes as release state |
| 103 | installer, read-only | `SOURCE/images/installer-unit103.img` | recorded by source run | Publish immutable and attach read-only |
| 104 | installed ZFS root | `RUN/images/extra-unit104-60g.img` | 64,424,509,440 | Primary workstation artifact; preserve sparse allocation |

The QEMU executable SHA-256 recorded before this launch is
`ea9348f2565befef00b7f8628489be01bde5799df842c88cdfe70a25664bba3c`.
The immutable `oi-bounded-v2-20260826` unit-103 SHA-256 recorded by the source
run is
`e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c`.
CI must hash and manifest the firmware files and all immutable inputs as well;
that manifest has not yet been produced for this candidate.

Although the command requests 8 GiB and four vCPUs, the unchanged firmware
Machine Description exposed 3072 MiB and only `cpu0` to OpenIndiana.  Do not
label this a four-CPU guest.  AWS host selection should optimize strong
single-thread TCG performance until the firmware/MD topology is changed and
guest-visible SMP is re-proved.

## Networking state

Channel 0 and PPP were brought up manually and passed:

- host `ppp0`: `10.0.5.1` peer `10.0.5.15/32`;
- host-to-guest ping;
- guest-to-host ping;
- guest-to-Internet ping (`8.8.8.8`);
- Linux IPv4 forwarding; and
- source-scoped NAT for `10.0.5.15/32` through Biggie's external interface.

The canonical reconstruction procedure is
`docs/runbooks/openindiana-channel-ppp.md`.  PPP is runtime state and will not
survive merely because a BE or disk image was copied.

Known omissions at this checkpoint:

- no channel-1 host bridge;
- no channel-1 getty;
- no SSH listener (`10.0.5.15:22` refused connections);
- no compiler verified or installed; and
- no automatic boot-time restoration of the host bridge, guest peer, host
  `pppd`, routing, or NAT has been accepted.

A compiler precheck began after the BE was created but stopped producing
console output immediately after reporting `sparc`.  Ctrl-C and XON did not
restore the prompt.  Ryan then ordered all runtime activity stopped.  No
compiler package installation completed, and the BE predates that attempt.

## AWS/CI artifact handoff

Do not copy or hash the live writable unit-104 image.  First obtain an
authorized, guest-consistent checkpoint and a stable host-side source (clean
guest shutdown, or a proven guest flush followed by a ZFS snapshot using a
QEMU build whose synchronization mechanism has been tested).  **Never send a
signal to this QEMU binary**; SIGUSR2 terminates it.

The portable bundle should contain:

1. immutable QEMU executable plus a SHA-256 manifest;
2. the complete firmware directory plus per-file hashes;
3. immutable unit-103 installer media;
4. a stable sparse copy of unit 100;
5. a stable sparse copy of unit 104 containing the candidate BE;
6. a clean unit-101 template or deterministic initializer, not the live
   mailbox contents;
7. an argv manifest with the exact machine, unit numbers, read-only flags,
   cache mode, RAM, CPU, serial, and monitor settings;
8. the PPP SOP and host prerequisites; and
9. expected console markers and acceptance gates.

Preserve holes with ZFS send/receive where both ends use ZFS, or GNU sparse tar
or `rsync --sparse` for file transfer.  A 60 GiB apparent raw image must not be
expanded into 60 GiB of network transfer or EBS writes unnecessarily.

An AWS worker may relocate paths, but it must retain the unit numbers and
read-only semantics.  It should make per-run writable sparse/reflink copies,
launch inside a persistent named tmux session, capture the console and monitor
in separate windows, boot `disk@4:a`, and apply these gates in order:

1. OBP and intended QEMU/firmware identity;
2. hSIMD units 100, 101, 103, and 104 at the intended sizes;
3. installed ZFS root from `rpool/ROOT/...`;
4. candidate BE selection;
5. stable multiuser root or login prompt;
6. healthy pool;
7. byte-exact channel-0 echo;
8. PPP and routed packets;
9. channel-1 getty and SSH as independent recovery paths; and
10. compiler installation plus compile/link/run canary.

This card remains **Validate**, not Anchored, until a fresh QEMU cold boot of
the preserved artifact selects the candidate BE and repeats the functional
gates without manual archaeology.
