# Niagara Project Kanban

This file defines the project board's operating policy and provides a
repository-readable fallback if the hosted board is unavailable. The private
GitHub Project is the interactive source of truth; this document defines how
the chief engineer and agents must use it.

## Board layout

Workflow columns:

1. **Inbox** — an idea or observation that has not yet been evaluated.
2. **Ready** — bounded, safe, and executable without another decision.
3. **In progress** — an owner and resource are producing an observable result.
4. **Blocked** — cannot advance; the card must name the blocker and next
   unblock action.
5. **Validate** — implementation finished, acceptance gate not yet passed.
6. **Anchored** — acceptance gate passed, procedure and artifact recorded.
7. **Closed** — a bounded Run ended FAIL, was superseded, or was deliberately
   abandoned; its evidence and replacement card are recorded and it consumes
   no resources.  Durable Capability cards do not use this status.

Resource swimlanes:

- Exabyte
- Biggie
- Minnie
- Teddeck/MBP
- Unassigned

`Resource` means the physical compute owner. `Environment` is a separate field
for the movable or nested execution context, such as Playbox VM, Tribblix,
OpenIndiana, CI builder, donor, or host-native work. Teddeck and MBP are the
same resource. Playbox normally runs as a VM on Teddeck/MBP but may move to
Minnie; moving it changes the card's Resource without inventing another host.

Every `In progress` card must contain:

- one accountable owner;
- one primary resource;
- the command or activity actually running;
- a concrete expected artifact or observation;
- the next time or event at which progress will be checked;
- the acceptance gate that moves it to `Validate`.

## Work types and classes of service

`Work Type` separates durable outcomes from individual attempts:

- **Capability** — a reusable definition of what “working” means.
- **Run** — one bounded attempt tied to an exact resource, target, artifact,
  hypothesis, and gate-result matrix. Only Runs may enter `In progress`.
- **Chore** — recurring standard work. Success updates its last evidence;
  failure creates a scoped Run or Incident.
- **Incident** — an unexpected regression or unavailable dependency.
- **Decision** — requires Ryan's explicit prioritization or trade-off.

`Class of Service` is one of **Expedite**, **Fixed Date**, **Standard**, or
**Intangible**. A blocked critical-path dependency may be Expedite; “interesting”
does not make work Expedite.

## Acceptance profiles

A Run selects one profile and records each applicable gate as `PASS`, `FAIL`,
`BLOCKED`, `NOT APPLICABLE`, or `NOT YET TESTED`. Capability cards are referenced,
not duplicated into every Run.

- **Boot Only:** OBP loads media; kernel starts; intended live/root filesystem
  mounts; maintenance or login prompt is reachable.
- **Storage:** Boot Only plus hSIMD enumeration, exact unit mapping, bounded
  read/write persistence, pool/filesystem creation, export, and re-import.
- **Networking:** channel-device mapping, guest relay, echo, PPP negotiation,
  routed packets, NFS canary, and optional iSCSI gates.
- **Installer:** Boot Only + Storage + required Networking gates, installer
  completion, boot blocks/archive, and clean target export.
- **Full Acceptance:** Installer plus a fresh-QEMU cold boot, channels, PPP,
  NFS, developer tools, observability, and performance/regression thresholds.
- **Operations:** build, deployment, dashboard, resource, backup, and warm-spare
  gates rather than guest capability gates.

Example:

```text
[RUN SOL11-SPARC-20260826-01] Boot Oracle Solaris 11 SPARC media
Resource: Biggie
Target Identity: exact tmux/QEMU/VM identity
Artifact / Build: exact ISO, QEMU, firmware, and hSIMD versions
Acceptance Profile: Boot Only (then promote or create a new Installer run)
```

“Investigating,” “waiting,” and “preparing terminal” are not acceptable active
work descriptions. A resource with no `In progress` card is intentionally idle
or underutilized. A resource whose active card has produced no new evidence by
its next check is stalled and must be reassigned or unblocked.

## Priority rule

Ryan may reorder or move any card. The chief engineer treats that ordering as
authoritative and keeps the highest-priority safe cards supplied with resources.
New ideas become Inbox cards; they do not silently replace active work.

The current critical path is:

```text
hSIMD-visible live installer
    -> channel echo
    -> PPP
    -> NFS and iSCSI access
    -> install to persistent unit 100
    -> cold boot installed system
    -> repeatable observability and performance gates
```

## Initial cards

| Status | Priority | Resource | Environment | Card | Acceptance gate |
| --- | ---: | --- | --- | --- | --- |
| In progress | P0 | Biggie | Tribblix guest | Install Tribblix ZFS root on disposable unit 100 | Clean export and cold boot from unit 100 |
| Blocked | P0 | Exabyte | OpenIndiana smoke guest | Restore channel echo with complete guest payload | Host-to-guest-to-host echo matches |
| Anchored | P0 | Exabyte | Host-native PPP/channel services | Provide durable channel relay and `pppd` services for every network-capable Niagara run | Host `pppd 2.4.9` resolves all libraries and passes dry-run; `niagara-channel@` mock disk/socket start-connect-log-stop gate passes; `niagara-ppp@` and trial config are installed |
| Ready | P0 | Exabyte | Launch admission for network-capable runs | Refuse any PPP/channel trial whose QEMU topology omits the dedicated unit-101 channel disk or whose host service config names a different image | Expanded QEMU argv contains unit 101, config points to that exact image and mailbox offset, channel service starts, and echo passes before PPP starts |
| Ready | P0 | Exabyte | OpenIndiana smoke guest | Bring up PPP over channel socket | Both peers negotiate addresses and pass packets |
| Ready | P0 | Exabyte | OpenIndiana smoke guest | Mount NFS installer/tool content over PPP | Guest reads a named canary from NFS |
| Ready | P0 | Exabyte | OpenIndiana smoke guest | Re-prove iSCSI over PPP | Guest discovers and reads/writes a disposable target |
| Ready | P0 | Biggie | OpenIndiana installer | Boot modified installer and install to unit 100 | Installer completes without storage ambiguity |
| Closed | P0 | Exabyte | Failed run `nvram-openindiana-exa-01` | Preserve the 10 GiB installer failure as evidence, then release its compute | Storage discovery and `rpool` creation passed; dump/swap exhausted the target; hSIMD asserted on a `0x31800` request; exact QEMU is stopped; superseded by `OI-BOUNDED-25G-EXA-20260826-01` |
| Ready | P0 | Exabyte | Builder result from `oi-archive-builder-exa-01` | Revalidate or rebuild the isolated OpenIndiana archive only if the published `ppp-injected-v2-20260825` artifact cannot satisfy a current run | Reopened archive proves every required file and literal setting; no builder VM is inferred to be active from this stale card |
| Closed | P0 | Exabyte | Superseded run `OI-BOUNDED-25G-EXA-20260826-01` | Preserve the bounded-run contract; execution moved to the isolated Biggie `term4code` run with the exact published installer and a separate preseeded 60 GiB unit 104 | Superseded before launch; replacement evidence is `notes/BIGGIE-TERM4CODE-OPENINDIANA-RUN.md` |
| Closed | P0 | Biggie | Retired run `term4code` | Preserve the exact published installer run after the first dataset mutation panicked in hSIMD | Import and `tink@empty-imported` passed; dataset create issued `0x24000` and panicked; QEMU was retired through monitor/owner after authorization; run directory, logs, panic, and commit `91a5802` are preserved |
| In progress | P0 | Biggie | Trial `term4code-02` | Complete the fresh installed-root cold boot, then re-prove channel echo and PPP | Target aggregation literal, PPP payload, hSIMD major/alias/path registration, rebuilt archive, accepted snapshot, and clean export PASS; fresh PID 2027153 has loaded the installed kernel without the former KMDB or missing-major blockers; awaiting root mount and multiuser gates |
| Ready | P0 | Biggie | Installed OpenIndiana | Restore the exact aggregation literal and channel startup in the target, rebuild its boot archive, then cold-boot installed root without `-k` | Login, rpool status, persistent canary, channels, PPP, and outbound ping pass; no hSIMD request exceeds `0x20000` |
| In progress | P0 | Exabyte | Tribblix candidate-v5 boot archive | Make `/ramdisk-root:a` the literal default root and remove stale `disk@0:a` directives | `-a -k -v` displays `Enter physical name of root device [/ramdisk-root:a]` |
| Ready | P0 | Exabyte | Tribblix live-root startup | Remount the actual RAM root read/write before `devfsadm` and add an `/etc/dev` canary gate | Canary create/remove succeeds and the first `devfsadm` has no read-only error |
| Ready | P0 | Exabyte | Tribblix candidate-v5 smoke guest | Run Return-only then unattended installer-menu acceptance boots | Return at every diagnostic prompt reaches the installer menu; subsequent boot without `-a` reaches it unattended |
| In progress | P0 | Biggie | Host-native firmware tooling | Establish a disposable OpenBoot NVRAM oracle: edit with `setenv`/`nvstore`, verify with `printenv`, and dump 8 KiB using QEMU monitor `pmemsave` | Fresh QEMU reads back the intended variables from the oracle dump before any boot command |
| Ready | P0 | Biggie/Exabyte | OpenIndiana hSIMD installer | Fix large strategy requests and rerun under mandatory KMDB `-k -v` policy | A greater-than-128-KiB ZFS I/O completes, no hSIMD assertion fires, and panic evidence remains inspectable if the gate fails |
| Ready | P1 | Teddeck/MBP | Host-native firmware tooling | Implement a diagnostic `nvram1` decoder and diff tool against oracle-generated fixtures | Tool round-trips multiple oracle fixtures byte-for-byte and is never the production encoder |
| In progress | P1 | Teddeck/MBP | Host-native analysis | Diagnose `disk@3:d` becoming `disk@0:a` | One discriminating `/chosen` observation identifies layer |
| Ready | P1 | Biggie | Tribblix guest | Add an independent ZFS tool/data disk | Pool imports and a host-seeded canary is editable |
| Ready | P1 | Biggie | Host-native | Reclaim stale QEMU processes safely | Every survivor mapped to a protected or active card |
| Ready | P0 | Exabyte | Host-native launch admission | Re-run whole-host admission before any future Exabyte trial; no active Exabyte work is inferred from the former stale row | Precheck enumerates zero unidentified QEMUs and fails closed on any extra process |
| Ready | P1 | Teddeck/MBP | Playbox VM | Reclaim duplicate PASS rehearsals safely | One warm spare retained; duplicate CPU load gone |
| Ready | P1 | Exabyte | CI builder | Continuously build latest big disk and boot archive | New source change yields versioned, boot-ready artifacts |
| Ready | P1 | Exabyte | CI smoke guest | Keep one smoke guest booted or booting | Dashboard shows current build and last gate continuously |
| Ready | P1 | Minnie | Host-native | Mirror Kanban summary into fixed project dashboard | Dashboard reflects board data without template drift |
| Validate | P1 | Biggie | Host-native | Intent-aware VM state classifier | Root-shell probe passes the complete synthetic and live enum matrix |
| Ready | P1 | Minnie | Host-native | Publish managed-VM states on the private dashboard | Every expected-running VM shows intent, enum, evidence, stage age, and next check |
| Ready | P1 | Biggie | Host-native | Guest heartbeat over a control channel | Fresh boot ID, sequence, stage, storage, channel, PPP, and NFS state is observable |
| Ready | P1 | Biggie | Host-native | Probe-enabled QEMU observability build | `bpftrace` lists and consumes named hSIMD and SPARC TLB USDT probes |
| Inbox | P2 | Unassigned | Helper VM | Test NetBSD as a disposable Solaris-UFS editor | Round-trip mutation passes fsck and byte-level canaries |
| Inbox | P2 | Unassigned | Helper VM | Build tiny illumos UFS/ZFS helper VM | Scripted attach, edit, verify, and detach completes |
| Inbox | P2 | Unassigned | Disk format | Put stable markers at channel/mailbox slice starts | Recovery scan finds slices after deliberate renumbering |

## Card completion discipline

A card moves to `Anchored` only when its result is reproducible after a cold
start and its procedure, artifact identity, and regression gate are committed.
Activity, a plausible diagnosis, or one warm-VM success is not completion.

## Observability durables

The classifier, guest heartbeat, dashboard integration, and named QEMU probes
are separate durable capabilities. A concrete rebuild or dashboard deployment
is a Run; the capability card remains the reusable acceptance contract. The
recurring chore classifies every VM whose desired state is `running` and
creates a scoped Incident or Run whenever the enum changes to a failure state.

The detailed rubric and root-shell command are recorded in
`notes/NIAGARA-VM-STATE-OBSERVABILITY.md`.
