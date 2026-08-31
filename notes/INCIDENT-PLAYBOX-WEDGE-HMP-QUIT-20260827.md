# Incident: OpenIndiana wedge and accidental HMP quit, 2026-08-27

## Result

The productive run `workstation-playbox-known-good-20260827T165948Z` is
stopped. QEMU was not relaunched. This note supersedes only claims that the
run remains live; its earlier boot, ZFS, BBS, channel, and PPP evidence remains
valid historical evidence.

At `2026-08-27T20:18:59Z` and `20:19:09Z`, QEMU PID 34442 was alive and the
monitor reported `running`. Its single vCPU thread 34491 consumed 97.7% CPU,
but these values did not change across the samples:

- console log: 44,567 bytes, mtime `2026-08-27 19:44:41.904778707 +0000`;
- `/proc/34442/io`: `read_bytes=552294400`, `write_bytes=664763392`, and all
  syscall/character counters flat;
- console Unix receive queue: 1,089 bytes, not consumed;
- channel-0 host socket receive queue: 100 bytes;
- no host `ppp0` or live pppd remained.

The QEMU vCPU was executing at guest PC `0x0000000001044074`, nPC
`0x0000000001044078`, TL 0, PIL 0. That proves active emulation with no visible
I/O progress, but a single architectural sample does not distinguish an
illumos guest loop from a QEMU emulation/translation defect.

## Accidental termination

During a read-only HMP inspection, the client sent:

```
info status
info registers
quit
```

The final command was mistakenly treated as a client disconnect operation.
In HMP it terminates QEMU. The owner pane then reported dead with status 0 and
PID 34442 no longer existed at `2026-08-27T20:19:22Z`.

## What was preserved and lost

Preserved:

- all durable run logs and notes;
- the run-local disk chain and unit-101 mailbox artifacts as they existed at
  process exit;
- host-staged GCC 11.5 archive evidence;
- QEMU register output above and host process/thread samples.

Lost:

- live guest RAM, kernel stacks, threads, KMDB state, and pending interrupts;
- live QEMU device/coroutine state;
- the chance to compare multiple guest PC/register samples;
- a guest-synchronized or QEMU-paused disk checkpoint at the incident point.

The existing disk is crash-consistent at best. It must not be described as a
guest-synchronized checkpoint. Niagara migration remains unusable; see
`notes/BASECAMP-R0-WARM-MIGRATION-FAILED.md`.

## Binding safety rule

No unrestricted HMP client may be used for future Niagara trials. In
particular, do not pipe text ending in `quit` to a monitor. QEMU control must
use fixed-purpose QMP clients whose command allowlists are encoded in code and
tests. Observation, stop, continue, and serial-break operations must be
separate programs with no arbitrary command argument. The private QMP socket
must not be exposed to ordinary operator workflows. A VM may be terminated
only by an explicit, separately authorized teardown path.
