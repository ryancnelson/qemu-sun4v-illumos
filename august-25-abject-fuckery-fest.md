# The August 25 Abject Fuckery Fest

## What this is

This is the postmortem for the Niagara project work of August 25, 2026.

The day made real technical progress. It also devolved into repeated operational
mistakes, forgotten lessons, invalid experiments, wasted boot cycles, excessive
human supervision, and a growing gap between the project's written process and
what its tools actually enforced.

This account has three purposes:

1. Preserve every useful result and negative finding so that neither has to be
   rediscovered.
2. Explain why a project that had recently felt almost incapable of making a
   mistake became capable of repeating the same expensive mistakes many times.
3. Define controls that make those mistakes mechanically difficult or
   impossible, while keeping warm trial environments ready so a failed VM costs
   a console switch rather than another long boot.

This is a narrative and postmortem, not the authoritative runbook. Exact
commands, hashes, artifacts, acceptance gates, and current state belong in Run
manifests, captures, Kanban cards, and the focused technical documents linked
below.

## Executive summary

The project did not fail because it became too large. It crossed the point where
conversational memory, prose instructions, and advisory Kanban cards were no
longer an adequate control plane.

The number of agents, hosts, VMs, disks, firmware files, boot archives, patches,
and possible launch paths grew quickly. The project acquired useful process
documents, but many critical rules could still be bypassed by an ordinary shell
command. A plausible-looking QEMU launch could consume ten or twenty minutes
before revealing that it used the wrong artifact, wrong root default, wrong disk
topology, or an already disproven baseline.

Friday's productive session was monotonic. One living guest was treated as
accumulated capital. Each bounded proof made that same environment safer, more
capable, or better understood. August 25 repeatedly reset state, confused
activity with progress, and allowed identity claims to remain assumptions until
after an expensive boot.

Slow VMs did not cause the process failure. They multiplied its cost.

## The contrast in the AgentsView receipts

The principal Friday session is:

```text
codex:01a0256f-b732-7551-aca4-4c8ddcf5a32b
```

It ran for about six hours and forty-four minutes. AgentsView records 35 user
messages, no tool retries, no explicit requests to stop, ten compactions, and a
completed outcome. It ended with pkgsrc bootstrapped on Solaris 9 SPARC, a real
package built and executed, the remaining curl dependency failure explained,
and the result written into durable narrative documentation.

The principal August 25 session is:

```text
codex:01a0371e-12c6-7773-9b4b-1b0791d7902e
```

It spans roughly 26 hours. AgentsView records 4,235 messages, 509 user messages,
12 tool retries, 60 compactions, 129 duplicate prompts, and a D health grade.
Of the 509 user messages, 125 were repeated heartbeat injections and 384 were
human. The human messages include at least 18 explicit requests to stop, 17
messages about repeating or forgetting prior work, and 25 strong frustration
signals.

That session was only the coordination layer. Associated receipts include a
7,695-message Hermes session with 91 retries and 22 tool-failure signals, an
Antigravity review session, research sessions, child-agent sessions, and a set
of repeated resource-audit sessions.

The built-in signal counts understate the incident. The main Codex session
reports zero tool-failure signals even though it contains multiple serious
operational failures. A shell command returning zero is not proof that the
correct experiment ran.

## Why the good sessions worked

The successful sessions preserved a narrow chain of custody:

1. Keep one valuable guest alive.
2. Establish exact identity before changing it.
3. Make one bounded claim at a time.
4. Test the claim in the actual environment.
5. Preserve the evidence.
6. Use the new capability as the base for the next proof.

The OpenIndiana Basecamp story describes the same pattern in a more ambitious
session: storage, channel echo, PPP, routing, DNS, NFS, safe control, iSCSI, ZFS,
and DTrace were accumulated in one protected environment. The experiment became
more useful as the night continued.

The important property was not luck or model quality. It was monotonicity.

## What went wrong on August 25

### An old artifact was treated as a new candidate

The most expensive example appears around ordinals 3737--3741 of the main
AgentsView session. A read-only `/etc/dev` failure was reproduced after a fix
had already been committed. The VM was not testing that fix. It had booted the
known-old `big-disk-unit103-v5.img` because no new artifact containing the fix
had been built and verified.

The essential delivery chain was:

```text
source commit
  -> build artifact
  -> inspect embedded payload
  -> publish exact artifact
  -> launch disposable clone
  -> verify guest identity
  -> run acceptance gate
```

The work skipped the middle of that chain. A running VM was mistaken for a
candidate test, and an hour was spent waiting for a known baseline failure.

### Known answers remained interactive traps

The correct root device was answered repeatedly instead of being stored in the
per-run NVRAM and tested by a Return-only or unattended boot gate. The project
knew the answer but required an operator to remember and retype it during each
slow boot.

That is not an operator problem. A deterministic answer left as a prompt is a
harness defect.

### Log messages substituted for acceptance tests

A startup path printed that it was remounting root read/write. That message was
treated as evidence even though `/etc/dev/.devfsadm_dev.lock` remained on
read-only storage. The missing proof was a write canary in the exact directory
needed by `devfsadm`.

The new rule is stronger: do not infer writability from an attempted remount or
its log line. Create and remove the canary, and refuse to invoke `devfsadm` if
that operation fails.

### Process identity and terminal lifetime were not structural

Transient workloads were allowed to own tmux sessions reached through SSH from
WezTerm. When the workload exited, tmux exited, SSH exited, and the WezTerm
window disappeared with the failure evidence.

The policy is now documented: the tmux session must be owned by a persistent
interactive shell, and QEMU or other workloads must live in separate panes or
windows. The remaining work is to test that policy automatically during rig
preflight.

### Busy infrastructure was mistaken for progress

Multiple VMs, dashboards, panes, agents, audits, and status updates created a
large amount of observable activity. They did not guarantee movement along the
critical path. At several points Ryan still had to ask what was happening,
identify the relevant failed VM, demand that it be stopped, or supply the next
obvious action.

The five-minute heartbeat attempted to repair this, but repeated a very large
instruction block 125 times inside the main transcript. It consumed context and
attention without becoming an authoritative state controller.

Monitoring should observe declared Run state and notify on transitions, expired
progress budgets, failed gates, or unanswered questions. It should not restate
the project's operating manual every few minutes.

### The coordination session exceeded a useful lifetime

The main session accumulated 60 compactions while coordinating many agents,
hosts, VMs, documents, and automations. Important facts existed in the
transcript, but retrieval became unreliable and repeated corrections became
normal.

A long-running project needs durable state outside the conversation and a
routine fresh-session handoff. Compaction is not a substitute for a Run
manifest, resource registry, current-state snapshot, and explicit hypothesis.

## Progress that must not be lost

Despite the incident, August 25 produced substantial durable work:

- an intent-aware VM state classifier;
- a run-oriented Kanban policy with acceptance profiles;
- Basecamp state capture and an artifact build conveyor;
- a Biggie-to-Exabyte replication workflow;
- a read/write gate before `devfsadm`;
- the persistent-shell tmux/WezTerm policy;
- an OpenBoot NVRAM oracle;
- mandatory KMDB policy for new storage trials;
- default-root acceptance gates;
- fail-closed OpenIndiana and Tribblix launch-precheck designs;
- evidence that the original 10 GiB installer target was inadequate;
- evidence around the hSIMD `0x31800` request and bounded-I/O candidate; and
- a defined 25 GiB replacement trial.

These do not all have the same maturity. Some are anchored code and evidence.
Some are documentation. Some are current worktree changes. Some remain Ready or
In-progress cards. The postmortem must not call a control complete merely
because the correct rule has been written down.

## Friction-to-control ledger

Every useful failure should be recorded in this form:

```text
Receipt:
Impact:
Expected invariant:
What actually happened:
Why existing defenses allowed it:
Knowledge gained:
Immediate mitigation:
Mechanical control:
Test proving recurrence is rejected:
Owner / Kanban card:
```

The first control conversions are:

| Negative signal | Mechanical response |
| --- | --- |
| Known-old image booted as a candidate | Manifest and payload inspection required before launch |
| Running VM mistaken for current candidate | Compare expected commit with guest-reported build identity |
| `/etc/dev` remained read-only | Exact-directory canary gates `devfsadm` |
| Root answer entered repeatedly | Per-run NVRAM plus Return-only and unattended acceptance boots |
| Wrong disk, size, unit, or write mode | Typed launch topology validated before QEMU starts |
| Stale or unidentified QEMU survived | Whole-host inventory and exclusive per-instance leases |
| Workload exit destroyed terminal | Persistent-shell survival test during rig preflight |
| Agents paused during boots | Declared next-check event and a non-perturbing secondary lane |
| Heartbeats flooded the transcript | External state monitor; inject only material transitions |
| Coordination forgot earlier facts | Fresh-session checkpoint generated from durable Run state |
| Kanban warned but did not prevent | Launcher consumes and enforces the Run manifest |

## Making invalid experiments unrepresentable

Managed QEMU trials should have one legal launch path. That launcher must reject:

- an artifact whose manifest does not match the Run card;
- missing payload files, kernel settings, patches, or guest build stamp;
- unexpected disk sizes, unit numbers, or read/write modes;
- reused NVRAM, disks, sockets, tmux sessions, or run directories;
- a writable image already open by another process;
- any unidentified live QEMU on the resource;
- a tmux rig without a persistent-shell owner;
- missing root-device defaults;
- absent root and `/etc/dev` write canaries; and
- a Run without an evidence directory, rollback, and acceptance profile.

The preflight should print the complete manifest for review, but review is not
the primary defense. The launcher must derive its command from the approved
manifest rather than relying on an operator to reproduce it manually.

## Project-management controls

1. Permit one protected foreground experiment per writable environment.
2. Only bounded Run cards may enter `In progress`.
3. Every Run names its artifact, hypothesis, expected observation, failure
   condition, rollback, owner, resource, next check, and acceptance profile.
4. Preserve useful failures as closed Runs with evidence and a replacement
   card. Do not leave failed QEMUs consuming resources as ambiguous scenery.
5. Do not anchor a Capability after one warm success. Require a fresh-QEMU cold
   reproduction and a committed regression gate.
6. After the same user correction is repeated, stop execution and identify why
   the previous correction was not converted into a control.
7. Start a fresh chief-engineer session after a defined context or compaction
   threshold, using a machine-generated current-state briefing.
8. Move routine monitoring outside the main conversational transcript.

## Keeping trial environments warm

The initial development bench should contain:

- one active disposable OpenIndiana experiment;
- one fully running OpenIndiana spare at the current green checkpoint; and
- one fully running Solaris 10 donor/reference VM.

Each instance needs an immutable base and private clone, unique NVRAM, disks,
sockets, networking, logs, and tmux session, plus an exclusive lease and an
explicit state:

```text
booting -> ready -> leased -> quarantined -> recycling
```

The guest heartbeat should publish at least its boot ID, artifact build ID,
semantic stage, root writability, hSIMD unit map, channel state, PPP state, and
NFS canary result.

When an active guest panics or fails a gate:

1. Quarantine it and freeze its evidence.
2. Point the stable console/workspace alias at the ready spare.
3. Start a replacement spare in the empty slot.
4. Continue useful work immediately.
5. Recycle the failed instance only after its negative signal is captured.

Source trees and work products must live on durable ZFS/NFS storage rather than
inside an irreplaceable guest. Initially, keep spares fully running. QEMU
pause/resume and serialized VM state remain experimental until clocks, SMF,
channels, PPP, NFS, and socket reconnection pass dedicated tests.

## Immediate actions

1. Finish and commit the fail-closed launch controller and make it the only
   managed launch path.
2. Add an artifact manifest and guest-visible build stamp checked both before
   and after boot.
3. Add exclusive resource leases and reject unidentified QEMUs.
4. Deploy one active and one ready OpenIndiana instance and perform a deliberate
   panic-handoff drill.
5. Replace verbose transcript heartbeats with intent-aware state monitoring.
6. Generate fresh-session handoffs from manifests, Kanban state, live resource
   inventory, and the last accepted evidence.

## Definition of recovery

The project has recovered from this incident when:

- an old or mismatched artifact cannot be launched as a current candidate;
- two writers cannot open the same VM state;
- known root-device and storage-topology answers require no improvisation;
- every managed guest reports its exact identity and semantic health;
- a failed active VM costs console-switch time rather than another boot cycle;
- repeated user correction produces a durable control, not another promise;
- useful negative results remain linked to receipts and replacement Runs; and
- the chief engineer can answer what is running, why, what evidence is expected
  next, and when it will be checked without reconstructing the answer from a
  giant conversation.

The goal is not to eliminate experimental failure. Experimental failure is the
work. The goal is to eliminate invalid experiments, forgotten results, and
avoidable waiting.
