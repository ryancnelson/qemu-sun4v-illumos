# What If We Went the Other Way?

## Booting Solaris on QEMU's Existing `sun4u` Machine

Status: research direction, not yet implemented  
Last updated: 2026-08-19

## Executive Summary

QEMU already has a mature `sun4u` machine with useful emulated hardware:
PCI, IDE, SCSI, and network adapters for which Solaris has native drivers. It
boots Linux and BSD systems using OpenBIOS, an open-source IEEE-1275/Open
Firmware implementation.

Our earlier Solaris experiment got farther than "OpenBIOS cannot boot
Solaris." OpenBIOS loaded the Solaris kernel and transferred control to it.
The first observed failure was later, when Solaris attempted to attach its
`su` console driver to the emulated EBus serial device. The OpenBIOS device
tree did not describe that device in the form Solaris expected, so console
output disappeared.

That changes the shape of the problem. The most promising experiment is not
to write a complete replacement for Sun OpenBoot PROM, and not to transplant
the Niagara firmware. It is to make QEMU's existing SPARC64 OpenBIOS expose a
Solaris-compatible firmware contract, beginning with the console device tree
and then implementing only the runtime Client Interface services Solaris
actually uses.

If this works, Solaris could use QEMU's existing `sun4u` storage and network
devices. That would avoid the central limitation of the Niagara machine: it
boots Solaris with genuine OpenSPARC firmware, but does not provide a normal
disk device visible to Solaris without `hsimd` or equivalent work.

## The Important Distinction

There are two very different meanings of "fake real Solaris firmware":

1. **Transplant genuine Niagara OBP onto another machine.** This is not a
   promising route. Niagara's `openboot.bin` runs on top of `q.bin`, consumes
   a sun4v Machine Description, uses sun4v hypercalls, and assumes Niagara
   traps, MMU behavior, and device layout. QEMU's generic `sun4u` machine is a
   different platform.

2. **Make OpenBIOS satisfy the firmware contract Solaris observes.** This is
   plausible. OpenBIOS already performs the initial load and handoff. We can
   repair its device tree and runtime behavior incrementally, guided by
   measurements from a real Solaris system.

The second interpretation is the subject of this directory.

## What We Know

### OpenBIOS already crosses the first major boundary

The observed Solaris 10 boot on QEMU `sun4u` reached the kernel. This means at
least the following were sufficiently correct for early boot:

- executable loading;
- initial memory mappings;
- kernel entry and boot arguments;
- an IEEE-1275 Client Interface entry point;
- enough device-tree structure for the kernel to begin platform startup.

The first visible failure occurred when the kernel changed from firmware
console use to its native `su` driver. This is much narrower than a failure to
load or enter the kernel.

### The first compatibility seam is visible in source

QEMU's `sun4u` machine loads `openbios-sparc64` as its PROM. It creates a
synthetic EBus containing a PC-compatible serial controller and routes its ISA
interrupt through the Sabre PCI host bridge.

OpenBIOS responds by creating an EBus child named `su`, setting its
`device_type` to `serial`, constructing `reg` and `interrupts` properties, and
installing a `ttya` alias. Its serial package supplies `open`, `close`, `read`,
and `write` methods.

Relevant source locations:

- `qemu/hw/sparc64/sun4u.c`: machine construction, EBus, serial hardware,
  interrupt routing, IDE, PCI, and OpenBIOS loading;
- `qemu/roms/openbios/drivers/pci.c`: EBus device-tree construction and the
  call that creates the `su` node;
- `qemu/roms/openbios/drivers/pc_serial.c`: serial node properties, methods,
  and `ttya` alias;
- `qemu/roms/openbios/arch/sparc64/openbios.c`: `/chosen`, input device, and
  output device setup;
- `qemu/roms/openbios/arch/sparc64/init.fs`: SPARC64 initialization,
  preopened handles, and an explicitly Solaris-oriented `va>tte-data` hook.

We have not yet established which exact property or method causes `su` attach
to fail. Candidates include:

- node name or `compatible` values;
- the number, interpretation, or parentage of `reg` cells;
- EBus `ranges` translation;
- `interrupts`, `interrupt-map`, or `interrupt-map-mask`;
- missing clock or UART properties;
- the relationship among `ttya`, `/chosen`, and stdin/stdout ihandles;
- package methods expected by Solaris but absent or differently shaped in
  OpenBIOS.

This list is a set of hypotheses, not a diagnosis.

### The hardware payoff is large

Unlike the Niagara machine, QEMU `sun4u` already provides conventional buses
and devices. The existing machine includes:

- CMD646 IDE;
- PCI buses and Simba bridges;
- EBus;
- supported network adapters;
- optional SCSI controllers.

Solaris already contains drivers for this class of hardware. If the firmware
contract can carry the kernel through platform and console initialization, we
may get disk and networking without writing a new virtual disk transport.

The first milestone is therefore not "boot to multiuser." It is simply:

> Keep the Solaris console alive after the kernel attempts to attach `su`.

## What the Niagara and Tribblix Work Added

The `hsimd` investigation did not make Niagara's genuine OBP portable to
`sun4u`. It did, however, give this alternative direction several powerful
tools.

### A real firmware behavior oracle

We have access to a Solaris system booted under genuine Sun firmware. It can
answer empirical questions such as:

- What properties are present under `/chosen` and `/aliases`?
- What is the exact path and property set of the serial console node?
- Which package methods exist on that node and its ancestors?
- Which PROM Client Interface services does Solaris invoke during console
  initialization and later runtime?
- What arguments and return shapes does Solaris expect?

The donor should be treated as an oracle, not as a source of firmware blobs.
Its value is the ability to measure the contract.

### A modern illumos observability environment

Tribblix has booted an illumos SPARC kernel from a `boot_archive` RAM disk on
the virtual Niagara machine. We also developed a reliable, checksummed method
for moving small tools and modules into that constrained environment without
requiring a working disk.

This gives us another place to inspect modern illumos PROM interfaces,
platform code, driver attachment, and kernel symbols. The RAM-root constraint
is acceptable for firmware and console experiments because persistent storage
is not required to collect the initial evidence.

### A way to preserve visibility

The previous `sun4u` experiment became blind when native console attachment
failed. Future runs should record information somewhere other than the one
console being debugged. Options include:

- instrumenting OpenBIOS's Client Interface dispatcher and logging services
  before entering the kernel;
- emitting a compact log to QEMU's debug console or another emulated UART;
- storing a ring buffer in reserved guest RAM and extracting it through the
  QEMU monitor after failure;
- stopping in KMDB before `su` attachment, if the firmware/debugger
  interaction is stable enough;
- adding temporary kernel instrumentation to a boot archive.

## Compatibility Surfaces

The work can be divided into three layers.

### 1. Bootstrap and handoff

This includes loading the kernel, constructing boot arguments, initial MMU
mappings, and passing the Client Interface handler. Existing evidence says
this layer mostly works.

### 2. Device-tree personality

Solaris expects the firmware tree to describe recognizable Sun platform
hardware with exact property encodings and relationships. The console failure
places this layer first in the investigation.

This is likely the highest-leverage layer because it can be changed directly
inside OpenBIOS without redesigning QEMU's machine.

### 3. Runtime Client Interface behavior

Solaris continues to call firmware after kernel entry. Depending on release
and configuration, uses may include console I/O, property lookup, memory
services, debugger interaction, power operations, watchdog behavior, and
crash handling.

We should not assume OpenBIOS implements every required method with Sun-identical
semantics. We should also not assume a complete OBP clone is necessary. The
right scope is the measured set of calls made by the target Solaris release.

## Future Two-VM Ralph Loop

The eventual development harness should use two VMs and repeatedly erode the
known compatibility blockers rather than treating each Solaris boot as a
manual, one-off experiment.

### VM 1: protected reference oracle

This VM runs Solaris 10 with genuine Sun/OpenSPARC firmware. Its purpose is to
answer questions about the contract Solaris expects:

- firmware device-tree nodes, properties, aliases, and handles;
- PROM wrapper calls and Client Interface argument conventions;
- normal driver attachment behavior;
- MDB, KMDB, and DTrace observations from a working system.

The harness should treat this VM as read-mostly and valuable. It must never
automatically reboot it, enter KMDB, modify its disk, or send console control
characters. Potentially disruptive oracle experiments should require an
explicit human step or run against a separate rollbackable clone.

### VM 2: disposable candidate

This VM runs the QEMU `sun4u` machine with the OpenBIOS build under test and a
Solaris boot target. It should be cheap to reset and restored from known-good
disk state for every iteration.

The candidate side may be instrumented freely. Each iteration can rebuild
OpenBIOS, boot Solaris, collect the firmware trace and console transcript, and
classify how far the boot progressed.

### Host-side controller

The host orchestrator should maintain an explicit blocker queue and perform a
small loop:

1. Select the earliest reproducible blocker.
2. Gather or consult the corresponding evidence from the oracle VM.
3. Express the expected behavior as a device-tree, CIF, or boot-progress
   test.
4. Make one focused OpenBIOS change.
5. Build and run fast firmware-level tests.
6. Boot the disposable candidate VM with a timeout.
7. Capture console output, CIF logs, memory logs, and exit state.
8. Compare the result with the previous run and the oracle contract.
9. Keep a change only when it passes existing tests and moves or removes the
   blocker; otherwise revert that candidate change.
10. Record the newly exposed blocker and repeat.

The loop should produce durable artifacts for every attempt: source revision,
OpenBIOS binary hash, QEMU command line, disk-overlay identity, firmware-tree
snapshot, console transcript, CIF trace, test results, and a concise outcome
classification. This makes long boot times useful even when an iteration
fails.

### Tests before full boots

Most iterations should not begin with a full Solaris boot. The harness should
first test generated OpenBIOS state directly where possible:

- normalized node and property snapshots;
- exact cell counts and byte encodings;
- path and alias resolution;
- `/chosen` package and instance handles;
- package method presence and stack effects;
- recorded Client Interface request/response fixtures;
- Linux or NetBSD smoke boots to detect OpenBIOS regressions.

Only candidates that pass these cheaper checks should consume a long Solaris
boot cycle.

### Safety and convergence rules

The controller must keep the two consoles and their commands unmistakably
separate. It should use deterministic prompts or machine-readable channels,
never infer success from a quiet console, and never send Control-C,
Control-D, Stop-A, or serial break to the oracle VM automatically.

The loop should optimize for the earliest stable increase in boot progress,
not for accumulating speculative patches. One hypothesis, one behavioral
test, and one candidate change per iteration will make regressions and false
progress identifiable.

This is future harness work, not a prerequisite for the first manual
OpenBIOS-versus-OBP comparison. The manual captures should be designed so
their formats can later become fixtures for this loop.

## Proposed Investigation

### Phase 1: Capture the reference contract

On the genuine-firmware Solaris donor:

1. Dump the complete trees beneath `/chosen`, `/aliases`, and the console's
   PCI/EBus ancestry.
2. Record every property with type and raw byte length, not just a formatted
   `prtconf` interpretation.
3. Resolve stdin and stdout ihandles back to their packages and paths.
4. Enumerate methods on the serial package and relevant ancestors where
   tooling permits.
5. Trace calls through Solaris's PROM wrapper functions during early console
   and `su` initialization. DTrace FBT, MDB, and static kernel inspection are
   possible approaches.

Care is required on the donor: it is valuable live state, and console control
characters can terminate the shell. Prefer non-invasive collection and small,
checksummed outputs.

### Phase 2: Capture the OpenBIOS contract

Before booting Solaris on QEMU `sun4u`:

1. Dump the same normalized portions of the OpenBIOS tree.
2. Record the resolved `ttya`, input-device, and output-device paths.
3. Record the `su` node's methods and parent methods.
4. Add tracing at the OpenBIOS Client Interface service dispatcher.
5. Boot Solaris and preserve the trace through the point where console output
   disappears.

The two captures should use a common representation so integer cells, strings,
string lists, and raw bytes can be distinguished reliably.

### Phase 3: Repair console attachment

Diff the normalized trees and patch the smallest defensible discrepancy first.
Likely files are `drivers/pci.c`, `drivers/pc_serial.c`, and the SPARC64
initialization code.

After each change:

1. verify OpenBIOS can still operate the serial console;
2. verify Linux or NetBSD still boots, as a regression check;
3. boot Solaris with identical media and arguments;
4. note whether the failure moves;
5. retain the CIF trace and complete console log.

Do not batch speculative property changes. A one-change-at-a-time sequence is
more likely to reveal which part of the firmware contract matters.

### Phase 4: Fill runtime gaps incrementally

Once `su` attaches, continue booting until the next reproducible failure. For
each missing or incompatible Client Interface operation:

1. identify the service and exact call signature from the OpenBIOS trace;
2. confirm expected behavior on the donor where possible;
3. implement or repair the smallest corresponding OpenBIOS method;
4. add a focused regression test or scripted firmware probe;
5. retry the Solaris boot.

This produces a measured Solaris compatibility layer rather than an
open-ended firmware rewrite.

### Phase 5: Exercise native storage

After stable console and platform initialization:

1. boot from a read-only or disposable copy of the Solaris media;
2. inspect device attachment for CMD646 IDE and any configured SCSI adapter;
3. confirm reads before permitting writes;
4. use the project's rollback mechanism for every writable disk experiment;
5. only then test installation or multiuser boot.

## Success Criteria

The direction should be evaluated through progressively stronger milestones:

1. Solaris reaches the same kernel point reproducibly under instrumented
   OpenBIOS.
2. The `su` driver attaches and console output continues.
3. Solaris reaches a shell from a RAM-root or installation environment.
4. Solaris enumerates a native QEMU IDE or SCSI disk.
5. Read-only disk access works reliably.
6. Controlled writes survive reboot and filesystem verification.
7. Networking attaches using an existing Solaris driver.
8. A normal installed system reaches multiuser mode.

Milestone 2 alone would validate the central hypothesis.

## Stop Conditions and Alternative Conclusions

This path is worth a focused prototype, but it should not become an unlimited
attempt to reproduce every undocumented OBP behavior.

Reassess if:

- Solaris requires large, implementation-specific portions of Sun OBP after
  console attachment;
- required services depend on hardware state that QEMU `sun4u` does not
  model;
- each repaired method merely reveals another broad class of incompatible
  firmware behavior;
- the target Solaris release performs platform identity checks that cannot be
  satisfied without misrepresenting fundamentally different hardware.

If that occurs, the evidence will still inform two fallback designs:

- a small purpose-built IEEE-1275 Client Interface shim entered through a
  Linux/kexec-style handoff;
- a new firmware-independent illumos `sparc64-virt` platform using FDT and
  modern virtual devices.

Both are significantly larger projects than repairing OpenBIOS's existing
Solaris compatibility boundary.

## Current Assessment

- **High confidence:** genuine Niagara OBP is not directly portable to the
  generic `sun4u` machine.
- **High confidence:** OpenBIOS already satisfies enough of the contract to
  load and enter Solaris.
- **High confidence:** the first observed blocker is narrow enough for a
  source-guided experiment around EBus serial description and `/chosen`.
- **Medium confidence:** repairing console attachment will expose QEMU devices
  that existing Solaris drivers can use.
- **Unknown:** the number and difficulty of later runtime Client Interface
  incompatibilities.

The immediate next action is a normalized firmware-tree and PROM-call capture
from the genuine-firmware donor, followed by the equivalent capture from
QEMU `sun4u` OpenBIOS. No firmware transplantation is required.

## Network-boot as an independent, cheaper diagnostic path (2026-08-20, unexplored until now)

Raised in discussion with Codex, not yet attempted. Captured here because it
reframes several open questions from this doc as one cheap, falsifiable
experiment instead of requiring firmware-side instrumentation work.

### The NIC's bus is confirmed, directly from source, not inferred

`sun4u`'s default NIC is `sunhme` (QEMU's emulated Sun Happy Meal Ethernet),
confirmed by reading `qemu/hw/sparc64/sun4u.c` locally:

```
mc->default_nic = "sunhme";               // both sun4u AND sun4v machine classes
```

It is attached as a **PCI device** — `pci_new_multifunction(PCI_DEVFN(1, 1), ...)`
onto `pci_busA` (onboard) or `pci_new(-1, ...)` onto `pci_busB` (additional
cards), both hung off the Sabre/Simba PCI host-bridge complex `sun4u` emulates.
EBus itself (which carries the `su` serial device) is ALSO a PCI device in this
source (`EbusState.parent_obj` is a `PCIDevice`) — so the same PCI/Simba
device-tree-construction code path in OpenBIOS is shared by both the broken
serial node and the NIC. That shared code path is worth keeping in mind: a
device-tree construction bug affecting one could plausibly (not confirmed)
affect the other.

**Do not confuse this with the Niagara/`sun4v` machine's networking claim.**
The main project README explicitly states `sunhme` does NOT work on Niagara
("the Niagara machine has no PCI bus"). Both statements are true and
non-contradictory: `sunhme` is real and PCI-attached on `sun4u`; it is
irrelevant on `sun4v` because that machine has no PCI bus at all. Don't let a
future reader conflate the two mentions of "sunhme" in this project's docs as
a contradiction.

### The reframe: `boot-device=net` gives an externally observable checkpoint BEFORE the `su` failure

The `su`/console blocker (see "The first compatibility seam is visible in
source" above) is a **driver ATTACH failure**, not a "firmware can't find the
device" failure — OpenBIOS's own firmware console works fine up to that point;
only the Solaris kernel's own `su` driver fails to bind afterward. This means:

- Bootstrap/handoff (loading the kernel + boot_archive) happens BEFORE the `su`
  switch-over. If that fetch happens over the network (TFTP/BOOTP, standard
  IEEE-1275 `network` package machinery — same mechanism real Sun `boot net`
  diskless boot always used), a real TFTP/BOOTP server sees the request land
  or fail with completely normal host-side visibility, independent of whether
  OpenBIOS's Forth console or the kernel's own console driver is working at
  all.
- This is strictly cheaper instrumentation than anything in the "preserve
  visibility" list above (OpenBIOS CIF-dispatcher logging, ring-buffer +
  `pmemsave` extraction, a second emulated UART) for answering ONE specific
  open question: **does OpenBIOS's network stack function at all against
  `sunhme` on this machine?** That question was completely unresearched as of
  the previous session (zero mentions of network/UDP/TFTP/BOOTP anywhere in
  this project's docs before this discussion).
- It's also a real candidate for sidestepping the console fix (Phases 2-4)
  entirely for a specific goal: SPARC NFS-root diskless boot has been a
  standard Solaris/SPARC OBP capability since real Sun hardware existed. If
  the kernel survives the `su` attach failure and continues booting headless
  far enough to reach network autoconfiguration and NFS-root mount, that
  bypasses BOTH the console problem AND the entire Niagara-side hsimd/disk
  problem from the other half of this project, using this project's own
  ALREADY-PROVEN NFS `/share` export (`10.0.5.1:/export/solaris`, confirmed
  bidirectional in `CURRENT-STATE.md`).

**The one load-bearing unknown that determines whether this whole idea has
legs**: does the Solaris/illumos kernel actually keep booting (headless, no
console) after `su` fails to attach, or does it hang/panic there? The original
`what-if` observation ("console output disappeared") does not by itself
distinguish these two outcomes. This is the single most valuable fact to
establish next, and `boot-device=net` is a reasonable way to attempt to
establish it empirically (watch the TFTP/NFS server logs for activity that
could only happen if the kernel is still alive and progressing).

### Two separable, ordered checkpoints (decompose before attempting)

1. **Checkpoint 1 (do first, cheapest, no Solaris kernel needed at all):** does
   OpenBIOS's network stack work against `sunhme` on `sun4u` at all? Set
   `boot-device=net`, stand up a real BOOTP/TFTP responder, and watch for
   OpenBIOS actually making a BOOTP request / pulling ANY file (a placeholder
   is fine). This alone answers whether OpenBIOS's Forth network machinery
   (mentioned as existing but unverified in earlier discussion — IEEE-1275
   `network` package with `open`/`read`/`write`/`load` methods, BOOTP/RARP
   address config, TFTP transfer) is actually functional in this build,
   independent of Solaris entirely.
2. **Checkpoint 2 (only after 1 passes):** point the TFTP/BOOTP server at a
   REAL sun4u-targeted kernel + boot_archive and see whether it fetches,
   starts executing, and — the actual question this whole thread is chasing —
   whether it survives past the `su` attach failure into NFS-root
   autoconfiguration. This is the experiment that would actually validate or
   kill the "network boot bypasses the console blocker" hypothesis.

### The artifact gap for Checkpoint 2 — needs a sun4u-targeted kernel, NOT sun4v

**Critical distinction, easy to get wrong**: everything this project has
working today (the Solaris 10 donor, the extracted Tribblix boot_archive from
the hsimd work) is **`sun4v`-targeted**. `sun4u` is a materially different
illumos/Solaris platform directory — a `sun4v` kernel/boot_archive will NOT
run on `sun4u`, and is not the right thing to serve over TFTP for this
experiment.

Ryan's recollection (2026-08-20, **UNVERIFIED — needs confirmation before
relying on it**): Tribblix ships a `sun4u` kernel variant, or OpenSolaris did.
This is plausible and worth checking FIRST, before any TFTP infrastructure
work, because:

- Tribblix SPARC media has already been shown (P2-032, `BACKLOG.md`) to
  contain a `sun4v`-targeted `boot_archive` (the one extracted and used for
  the hsimd bootstrap work). Whether the SAME Tribblix distribution, or a
  different release/ISO, also ships a `sun4u` variant has not been checked in
  this project.
- OpenSolaris (and its early SPARC support) predates the sun4v/LDoms-era split
  in some illumos/Solaris lineages, and historically supported both `sun4u`
  and `sun4v` platform directories from a shared distribution — this matches
  Ryan's recollection, but has not been verified against any actual media in
  this project's possession.
- **Concrete next step, read-only, cheap**: mount/inspect any available
  Tribblix or OpenSolaris SPARC ISO (the same `tools/peek.sh`-style read-only
  inspection technique already proven in this project) and look specifically
  for `/platform/sun4u/` alongside (or instead of) `/platform/sun4v/` in the
  media's own file tree, and for a distinct `sun4u`-targeted `boot_archive`
  file. This is the same kind of "positive/negative control" search already
  used successfully in P2-032 (`find /mnt -name 'hsimd*'` to confirm hsimd's
  absence from Tribblix) — apply the identical technique here:
  `find /mnt -path '*platform/sun4u*'` against any Tribblix/OpenSolaris ISO
  already staged in this project, before assuming a sun4u artifact needs to be
  found/downloaded from scratch.

### Status

Nothing above has been attempted. This section exists to capture the
reasoning and the concrete next steps (Checkpoint 1's BOOTP/TFTP test, and the
`/platform/sun4u` media search) before the next working session, so this
doesn't need to be re-derived from scratch.

## Which SPARC-capable illumos/OpenSolaris source tree to actually target (2026-08-20)

Raised by Ryan: could raw illumos-gate SPARC source, targeted at a machine
with OpenBIOS, be a viable path — pointing at the `richlowe/arm64-gate`
precedent (illumos successfully retargeted to a new architecture, booting via
U-Boot instead of OBP-family firmware). Checked directly against live
illumos-gate; the premise needed a correction, then Ryan refined the question
to OpenSolaris/Tribblix-gate specifically. Findings below.

### CORRECTION: illumos-gate master's SPARC kernel BUILD TOOLING was removed in 2024 — this is not just "needs adaptation," it needs resurrection first

Checked directly, not assumed. GitHub commit `689b9301078f0c35c7f198fcee8032a0d30eff3a`,
**"16375 remove SPARC kernel makefiles"** (2024-03-02, illumos-gate master),
touched **66,940 files** (1 addition, 66,939 deletions):

```
removed usr/src/uts/sparc/Makefile
removed usr/src/uts/sparc/Makefile.files
removed usr/src/uts/sparc/Makefile.rules
removed usr/src/uts/sparc/Makefile.sparc
removed usr/src/uts/sparc/Makefile.targ
removed usr/src/uts/sfmmu/Makefile.files
removed usr/src/uts/sfmmu/Makefile.rules
... (and every other SPARC-specific Makefile in the tree)
```

**The SPARC/sun4u/sun4v C source files themselves are still physically present**
in illumos-gate master as of this check (`usr/src/uts/sun4u/`, `usr/src/uts/sun4v/`
directories confirmed to still exist, with even small edits — typo/man-page
fixes — landing as recently as 2026-06-04). But **the build system needed to
actually compile a SPARC kernel from illumos-gate master no longer exists.**
This is qualitatively different from the arm64-gate situation: arm64-gate is
new platform code being actively built INTO a working, currently-maintained
build. Current illumos-gate SPARC is source whose build tooling was
deliberately, wholesale removed. Targeting illumos-gate-master-as-is at
OpenBIOS would first require resurrecting the entire SPARC kernel Makefile
infrastructure (from git history or from a fork that kept it) before any
SPARC kernel could be built at all, independent of the firmware question.

**Do not attempt to build against raw illumos-gate master's SPARC tree
without first confirming a fork with intact build tooling.** This is exactly
that fork question, addressed next.

### Ryan's corrected question: is there a Tribblix-gate or OpenSolaris-gate that still supports SPARC?

**Confirmed, from tribblix.org directly**: Tribblix ships a **currently
maintained, actively released SPARC ISO** — `tribblix-sparc-0m34.iso`
(milestone m34, "roughly matches m39 for x86" per the live release notes,
dated to this project's own present — OpenSSL 3.5, OpenSSH 10.2, current
package versions). This is the SAME ISO this project already has staged and
has already booted on the Niagara/`sun4v` machine (P2-032, `BACKLOG.md`). So
**Tribblix's SPARC support is real, current, and not a historical relic** —
it is being actively released in lockstep with their x86 releases.

**NOT YET LOCATED: a distinctly-named "Tribblix illumos gate" source repo.**
Searched the `tribblix` GitHub org (confirms `overlays.sparc` — a real,
maintained SPARC-specific package-overlay repo — plus `tribblix-build`,
`tribblix-media`, `tribblix-release`) and Peter Tribble's (Tribblix's author,
GitHub handle `ptribble`, also a long-standing illumos-gate reviewer/committer
per the commit trailers seen in illumos-gate itself) personal repos. Neither
turned up an obviously-named "gate" or "illumos" kernel-source fork.
`tribblix-build`'s own README states plainly: *"It's assumed that you've
built the gate and created all the SVR4 packages already"* — confirming
Tribblix's build process depends on a separate illumos gate/source tree that
is NOT itself one of the repos found so far. **This is the concrete open
item**: find which specific fork (or which commit/tag of illumos-gate BEFORE
the 2024-03-02 SPARC-makefile removal, which Tribblix may simply be pinned to
and maintaining independently) Tribblix actually builds its SPARC kernel from.
Worth directly asking on the Tribblix mailing list/IRC, or searching
tribblix.org's own build documentation more thoroughly, rather than guessing.

### Ryan's original point, reframed correctly: OpenSolaris

Ryan's corrected framing — that OpenSolaris, not modern illumos-gate, is the
right thing to check for `sun4u` SPARC kernel support — is well-founded and
NOT yet verified in this project. OpenSolaris (2008-2010 era, before the
Oracle acquisition ended the open-source releases and before illumos forked
from it) predates the SPARC-makefile removal by well over a decade, and
predates the sun4v/LDoms-era split discussed earlier in this doc. Historically,
Solaris/OpenSolaris SPARC distributions shipped BOTH `sun4u` and `sun4v`
platform directories from a single build — this is the same claim raised
earlier in this doc and still unverified against actual media.

**Concrete next step, unchanged from the previous section, now with a second
candidate source confirmed real**: search for `/platform/sun4u/` in (a) an
OpenSolaris SPARC ISO if one can be sourced from an official/archival mirror,
and (b) the Tribblix SPARC ISO already staged in this project — using the
same `find`-based technique already proven in P2-032. Do not assume either
direction without running this check; the previous section already lays out
the exact command.

### Status

Illumos-gate master is confirmed NOT directly usable for SPARC without first
resurrecting removed build tooling — ruled out as a starting point. Tribblix's
SPARC support is confirmed real, current, and actively maintained, but its
exact upstream gate/source repo is not yet located. OpenSolaris remains the
other named candidate, unverified. Nothing has been built or attempted;
this section records the corrected picture and the concrete next research
step (find Tribblix's actual gate source, and/or source an OpenSolaris SPARC
ISO) before assuming either path is viable.

## CONFIRMED: OpenSolaris/Nevada SPARC media already staged has real sun4u kernels (2026-08-20)

Ryan corrected the open item above directly: OpenSolaris Nevada SPARC ISOs
already exist locally, at `~/Downloads/` on this machine (not a remote host —
this session's own filesystem). Verified read-only, no VM/mount-state changes:

```
sol-nv-b59-sparc-dvd-iso.iso        3.88 GB   (Solaris Nevada build 59, SPARC)
osol-dev-134-ai-sparc.iso           291.9 MB  (OpenSolaris dev build 134, automated installer)
textinstall-134-sparc.iso           472.8 MB  (OpenSolaris build 134, text install)
```

Method: macOS recognizes the Sun VTOC label on each (`diskutil list` shows
`SOL_11_SPARC`, `automated_installer...`, `OpenSolaris` as the partition
names) but has no native UFS filesystem driver to mount and browse them
directly. Used `strings -a` against the raw ISO bytes instead — a valid
read-only substitute for the `find`-inside-a-mount technique used in P2-032,
since UFS package-manifest text and path strings are stored as plain ASCII
inside the image regardless of whether it's mounted.

**Result — `/platform/sun4u/` is present in ALL THREE, and outnumbers
`/platform/sun4v/` mentions in every case:**

```
                              sun4u hits   sun4v hits
sol-nv-b59-sparc-dvd-iso.iso      1872         847
osol-dev-134-ai-sparc.iso           97          53
textinstall-134-sparc.iso         141          64
```

**Decisive, not just a generic string match**: the b59 media's own package
manifest lists the real kernel binary path directly —

```
platform/sun4u/kernel/unix=sparcv9/unix    (SUNWcakr package entry, appears 3x)
```

— confirming an actual `sun4u`-targeted `unix` kernel binary ships on this
media, not merely incidental string mentions of "sun4u" elsewhere. The other
two build-134 images show the `platform/sun4u/kernel/` directory tree present
too (`sckmd`, `sckmd.xml`, `cpu/sparcv...` subdirectories), though the exact
`unix` binary line wasn't isolated in the same grep pass for those two — worth
a follow-up grep specifically for `platform/sun4u/kernel/unix` on those two if
one is chosen for the actual experiment.

**This confirms Ryan's original recollection was correct**: OpenSolaris
(unlike modern illumos-gate, whose SPARC build tooling was removed in 2024 —
see previous section) genuinely ships both `sun4u` and `sun4v` platform
kernels from a single distribution, exactly as expected from an era before the
sun4v/LDoms-era split and well before any SPARC-build-tooling removal.

**This directly unblocks Checkpoint 2 from the network-boot section above**:
a real candidate `sun4u`-targeted kernel + platform tree now exists,
already staged, no download needed. The b59 DVD ISO is the strongest
candidate given the confirmed literal `unix` kernel manifest entry.

### Still not done / next steps

- Have not yet extracted or examined the ACTUAL `sun4u/kernel/unix` binary
  bytes from any of these images (only confirmed its path string exists in
  the package manifest so far) — should verify it's a real, non-empty SPARC
  ELF binary, the same kind of positive-control check already applied to
  hsimd in P2-032, before relying on it for a TFTP-boot experiment.
- Have not checked whether a `boot_archive` (RAM-root archive, the same kind
  of artifact the hsimd work already handles) exists for the sun4u platform
  specifically, or whether b59-era Solaris instead boot-archives-per-platform
  differently (this era pre-dates some later Solaris/illumos boot-archive
  conventions — worth verifying rather than assuming it matches the m34
  Tribblix layout used elsewhere in this project).
- These are Nevada/OpenSolaris DEVELOPMENT builds (b59, b134) — expect rough
  edges distinct from the more polished Solaris 10 3/05 donor already in use
  elsewhere in this project.

## References

- Project strategy and original observed console failure: `../STRATEGY.md`
- QEMU SPARC64 machine source: `../qemu/hw/sparc64/sun4u.c`
- OpenBIOS EBus construction: `../qemu/roms/openbios/drivers/pci.c`
- OpenBIOS PC serial package: `../qemu/roms/openbios/drivers/pc_serial.c`
- OpenBIOS SPARC64 initialization: `../qemu/roms/openbios/arch/sparc64/`
- QEMU SPARC64 documentation:
  <https://www.qemu.org/docs/master/system/target-sparc64.html>
- QEMU OpenBIOS mirror: <https://github.com/qemu/openbios>
