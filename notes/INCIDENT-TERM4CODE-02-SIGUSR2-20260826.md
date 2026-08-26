# Incident: SIGUSR2 terminated `term4code-02`

Date: 2026-08-26, approximately 12:05 PDT.

## Impact

Protected OpenIndiana trial `term4code-02`, QEMU PID 2156055, terminated while
PPP recovery was in progress. It was not rebooted afterward. Its channel and
root-disk images were not opened by another writer after the termination.

The independent `term4code-herm-smp4-01` QEMU, PID 2366353 at the time of the
incident, remained alive and was not signaled or otherwise touched.

## Sequence and evidence

The trial's exact unit-101 mapping was revalidated:

```text
QEMU PID:       2156055
QEMU SHA-256:   ea9348f2565befef00b7f8628489be01bde5799df842c88cdfe70a25664bba3c
channel image:  /home/ryan/devel/masa-sun4v/ci/runs/term4code-02/images/channel-unit101.img
QEMU fd:        /proc/2156055/fd/10
host byte:      327680
guest device:   /dev/rdsk/c1d1s2
```

Before PPP, channel 0 was stopped on both sides, initialized to sequence/ack
zero, and restarted with one host bridge and one guest daemon. Channel 1
remained an interactive root recovery shell. Two independent random echo gates
passed:

```text
ch0: 65536 B  0.18s  698 KB/s round-trip  MATCH
ch0: 65536 B  0.13s  995 KB/s round-trip  MATCH
```

The first clean PPP attempt used symmetric `asyncmap 0`. Both peers emitted LCP
Configure-Requests but parsed no received requests. The bridge exchanged
frames, then stopped with host sequence 6 not acknowledged by the guest. Both
bounded peers timed out and exited.

For a second clean attempt, the operator copied the old synchronization order
from `host-up.sh` and `tools/basecamp-r0-cold-anchor.sh`: start both peers, wait
three seconds, and send `SIGUSR2` to the exact Run-owned QEMU PID. The
pre-signal `kill -0 2156055` succeeded. Immediately after `kill -USR2 2156055`,
the post-signal liveness check failed.

The owner pane preserved the decisive result:

```text
qemu-owner.sh: line 43: 2156055 User defined signal 2 setsid "$@" ...
OWNER_EXIT_140
```

## Root cause

The `SIGUSR2` premise was false for this pinned QEMU binary. A read-only source
search of `/home/ryan/devel/masa-sun4v/qemu-tlb-integration` found ordinary
QEMU memory `msync` functions and coroutine signal machinery, but no
system-emulator SIGUSR2 handler implementing an hSIMD flush. Therefore the
process retained the normal terminating disposition for SIGUSR2.

This was an operator-process failure: an old comment and prior harness behavior
were treated as proof that the current binary supported a signal hook. Exact PID
validation prevented collateral damage to another QEMU, but cannot make an
unsupported signal safe.

## Corrective rule

Never signal QEMU for PPP/channel synchronization. A QEMU signal hook is not
admissible until the exact binary passes an automated handler/liveness test on
a disposable VM and the active Run pins that build. Function names containing
`msync`, old helper comments, and a previously used command are not proof.

The canonical PPP SOP has been corrected. The terminated trial must not be
restarted or its writable disks inspected with write-capable tools without a
new explicit recovery decision.
