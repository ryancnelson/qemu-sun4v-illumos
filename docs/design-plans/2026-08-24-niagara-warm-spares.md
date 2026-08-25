# Niagara warm-spare development bench

## Goal

Hide the 10--15 minute guest boot latency behind a small pool of independently
booted Niagara VMs. A panic in the active experiment should cause a console
switch, not a development stop, while a replacement guest boots in the
background.

Initial bench:

- one active disposable experiment;
- one warm OpenIndiana spare at the current basecamp checkpoint; and
- one warm Solaris 10 donor/reference VM.

The Solaris 10 guest remains a bootstrap and regression oracle. The warm
OpenIndiana guest is intended to become the primary modern userland build host.

## Measured capacity on biggie

Read-only inventory on 2026-08-24:

```text
host                  biggie, x86_64 Linux 6.17.0-40-generic
CPU                   48 logical CPUs
RAM                   188 GiB total, 158 GiB available
datapool free         2.1 TiB
running Niagara QEMU  1.48 GiB RSS, 4.47 GiB VSZ, about one host CPU
guest uptime          nearly two days
QEMU monitor          VM status: running
```

This supports several running guests by a wide margin. Capacity is not the
current limiting hypothesis; isolation and reliable handoff are.

## Preferred two-host layout

Keep the laptop as the interactive development platform and use biggie as the
capacity/backstop platform. The Apple M5 Max host has 18 CPU cores and 64 GB of
unified memory. Its current AArch64 Linux playbox is configured with six CPUs
and about 6 GiB RAM; the live OpenIndiana QEMU uses about 1.19 GiB RSS and one
playbox CPU. The laptop therefore has substantial physical headroom, but the
UTM guest allocation must be raised before assuming it can hold several warm
Niagara guests.

This inventory and the live OpenIndiana work were performed while macOS
reported `Battery Power` (29% remaining at the observation). That is meaningful
operational evidence for the laptop's performance-per-watt, not just peak
throughput. Longer unattended boots and soak tests still belong on biggie so a
battery event cannot terminate the warm-spare pool.

A sensible first deployment is:

- active OpenIndiana experiment and watched consoles on the laptop/playbox;
- warm OpenIndiana spare and Solaris 10 donor on biggie; and
- location-neutral instance status and console attachment over SSH/Tailscale.

This retains the laptop's excellent interactive performance while biggie pays
the background boot and soak-test costs. Repositories and immutable artifacts
may be replicated normally, and work products may live on NFS/ZFS, but writable
VM images remain private to one instance and host. Measure boot time, command
latency, and channel throughput on both hosts before making placement policy
automatic.

## Why independent warm guests are the default

QEMU monitor `stop` and `cont` can pause and resume a process without serializing
VM state, so this is different from the known-broken save/restore path. It still
needs a disposable-guest test: long pauses may expose timekeeping, timer, SMF,
PPP, channel, or socket-reconnect defects. A paused guest also retains its RAM
and file mappings, though it should consume almost no CPU.

Until that test passes, keep spares fully running. At roughly one host CPU and
well under a few GiB of resident memory per measured guest, avoiding a boot-cycle
stall is worth the small steady resource cost. Never treat QEMU VMState
save/restore as part of this design.

## Required instance isolation

No two QEMUs may open the same writable disk image. Each instance requires:

- an immutable base plus its own reflink/ZFS clone;
- an instance ID and exact PID/lock file;
- unique serial and monitor sockets;
- unique tmux sessions and transcript paths;
- unique host channel sockets such as `/run/niagara-<id>-ch0`;
- per-instance TAP/PPP addresses, routes, logs, and process supervision;
- unique iSCSI initiator/target/LUN identities if that fallback is active; and
- an explicit owner/state record: `booting`, `ready`, `active`, `paused`,
  `failed`, or `recycling`.

Channel byte offsets may remain identical when every guest has its own disk
clone; host socket and daemon namespaces may not. The current launcher has a
global `pgrep` guard that deliberately permits only one Niagara QEMU, so the
harness must replace that with per-instance collision checks rather than bypass
it manually.

## Test-driven rollout

1. **Two-instance isolation test.** Boot two disposable clones with distinct
   IDs. Prove disk path, PID, monitor, console, tmux, channel socket, network,
   and logs cannot cross.
2. **Pause/resume test.** On one disposable ready guest, record guest and host
   clocks plus channel/network health; issue monitor `stop`; confirm host CPU
   falls and the other guest is unaffected; wait a bounded interval; issue
   `cont`; retest SMF, console, channel traffic, DNS, NFS, and clock behavior.
3. **Panic handoff drill.** Deliberately stop a disposable active guest. Switch
   the stable console alias to the ready spare, prove its saved development
   dataset and tests are usable, and boot a replacement in the empty slot.
4. **Long-idle soak.** Leave one OpenIndiana and one Solaris 10 spare running
   for at least one normal development interval. Measure CPU/RSS growth and
   periodically test console and networking.
5. **Automation only after evidence.** Add commands such as `bench status`,
   `bench switch <id>`, and `bench recycle <id>` only after the manual gates
   pass. Switching changes an alias or attachment; it never shares a writable
   disk or silently reassigns an instance identity.

## Acceptance criteria

- A failed active VM costs only console-switch time, not boot time.
- At least one ready OpenIndiana spare and the Solaris 10 donor remain healthy.
- Replacement boot happens in the background with visible progress.
- Every guest's writable disk and all control/data endpoints are isolated.
- Pause/resume is optional: if any timing or reconnect test fails, running warm
  spares remain the supported mode.
- Sources and work products live on durable ZFS/NFS storage, so switching VMs
  does not lose the development workspace.
