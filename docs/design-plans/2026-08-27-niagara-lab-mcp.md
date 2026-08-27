# Niagara Lab MCP Design

**Status:** proposed design for implementation

**Date:** 2026-08-27

## Purpose

Build a project-specific MCP server that lets a Codex agent investigate and
operate the complete virtual Niagara laboratory.  The Solaris or illumos SPARC
guest is the primary subject, but the agent may cross the guest, emulated
machine, QEMU, debugger, and VM-host layers whenever the evidence demands it.

The server is an out-of-band control plane.  Guest networking is evidence under
test, never a prerequisite for control.

## Goals

- Make the guest feel like the agent's immediate operating subject while
  retaining host- and hypervisor-level visibility.
- Expose existing per-run serial, monitor, channel, PID, manifest, classifier,
  and log interfaces through stable MCP tools.
- Permit bounded GDB and host tracing workflows without requiring the guest to
  be network-reachable.
- Preserve evidence provenance so guest facts cannot be confused with QEMU or
  host facts.
- Apply Ryan's Gilfoyle method: falsifiable hypotheses, differential tests,
  evidence-only conclusions, and immediate recording of facts.
- Preserve the project's existing safety invariants, especially single-writer
  channel ownership and the prohibition on sending terminal signals to QEMU's
  controlling terminal.

## Non-goals

- Reimplement QEMU, GDB, bpftrace, the shared-disk channels, or the VM
  classifier inside the MCP server.
- Require SSH, PPP, Ethernet, or any other in-band guest network.
- Hide which layer produced an observation.
- Continuously profile QEMU.  Expensive tracing remains bounded and
  hypothesis-driven.
- Publish private host paths, socket paths, PIDs, command lines, or captured
  guest data to a public dashboard.
- Treat ignored QEMU source-tree edits as project deliverables.  Reviewable
  QEMU changes continue to land as patches under `patches/`.

## Established project facts

The design relies on contracts that already exist in this repository:

- Current launchers create per-run `console.sock`, `monitor.sock`, `qemu.pid`,
  manifests, and logs.
- `tools/openindiana/qemu-owner.sh` gives QEMU no controlling terminal; serial
  and monitor sockets are the supported control paths.
- `tools/chan/guest-rootpty.sh` and the host channel bridge provide an
  out-of-band guest PTY that cannot deliver a host terminal's Ctrl-C to QEMU.
- `tools/chan/host-root-command.exp` and
  `tools/openindiana/r0-guest-command.exp` already define bounded,
  exit-status-aware guest-command protocols for two guest states.
- `tools/ci/classify-niagara-vm.py` produces a stable semantic state and a JSON
  evidence record from process, console, monitor, and retained state.
- A live QEMU GDB stub can be enabled from HMP without rebooting the guest.
  Connecting stops guest CPUs, and every automated debugger path must detach or
  resume them even after an error.
- The current QEMU build is unstripped and has debug information.  Bounded host
  uprobes are possible; QEMU's built-in eBPF support is not itself a general
  observability probe set.

## Considered approaches

### 1. Guest-shell-only MCP

Expose only the channel or serial shell and treat Solaris as the entire world.
This is simple but discards QEMU monitor, debugger, host scheduler, block I/O,
and tracing evidence.  It also becomes least useful during early boot, kernel
failure, or channel failure.  Rejected.

### 2. One unrestricted host-shell tool

Give the agent an arbitrary shell on the VM host and describe the available
commands in instructions.  This preserves power but erases layer boundaries,
makes evidence hard to structure, and invites accidental violation of existing
run ownership and console rules.  Retain a deliberately explicit expert escape
hatch later if needed, but do not make it the primary interface.

### 3. Layered lab control plane

Expose small, composable tools grouped by observation layer.  Reuse existing
scripts and sockets, return a common evidence envelope, and keep potentially
state-changing operations explicit.  Transport adapters allow the MCP server
to run on the VM host or reach it through an out-of-band relay.  Chosen.

## Architecture

```text
Codex
  |
  | MCP over stdio
  v
Niagara Lab MCP (modern host)
  |
  +-- run discovery / manifests / evidence ledger
  +-- guest adapter ------ channel PTY or maintenance serial socket
  +-- QEMU adapter ------- HMP Unix socket, later QMP if launched
  +-- debugger adapter --- live GDB stub plus SPARC-capable GNU GDB
  +-- trace adapter ------ bounded host process/eBPF/perf probes
  +-- artifact adapter --- console, logs, captures, patches
```

The first implementation runs as a local stdio MCP process on the VM host.
This keeps Unix sockets and `/proc` local and avoids making the MCP transport or
guest control depend on the network being tested.  A later relay may carry MCP
or individual tool requests from Ryan's primary Mac without changing tool
contracts.

## Run identity

All live operations are scoped to a run directory.  A run resolver validates
the directory before use and derives only known artifacts from it:

- `run.manifest` or the run's equivalent manifest
- `qemu.pid`
- `console.sock`
- `monitor.sock`
- `console.log`
- `classifier-state.json`
- channel socket declarations when present

Tools accept an explicit run identifier or use one configured default.  They
must not locate a target by taking the first process matching
`qemu-system-sparc64`.

## Common evidence envelope

Every observational tool returns the same top-level fields:

| Field | Meaning |
|---|---|
| `ok` | Whether the tool completed its requested observation |
| `layer` | `guest`, `emulator`, `debugger`, `host`, `artifact`, or `lab` |
| `operation` | Stable operation name |
| `run` | Resolved run identity |
| `observed_at` | UTC timestamp generated by the MCP server |
| `source` | Socket, file, PID, command adapter, or script that produced data |
| `mutated` | Whether the operation may have changed target state |
| `data` | Structured result plus bounded raw output when useful |
| `warnings` | Timeouts, truncation, stale data, cleanup facts, or uncertainty |

Outputs are size-bounded.  Truncation is reported rather than silently applied.
Secrets and configured private fields are redacted before results are returned.

## Initial tool surface

### Lab and run tools

- `lab.list_runs`: enumerate validated run directories and their declared
  intent without process-name guessing.
- `lab.describe_run`: return the sanitized manifest, available control
  surfaces, PIDs, and artifact paths for one run.
- `lab.classify`: invoke the existing semantic classifier and return its JSON
  evidence unchanged inside the common envelope.

### Guest tools

- `guest.exec`: execute one bounded command through an established guest
  command adapter and return output plus the guest exit status.  The caller
  chooses or auto-detects an available adapter; it does not fall back to SSH.
- `guest.console_tail`: read bounded current console evidence from the run log.
  Reading a live serial stream is separate because attaching a second reader
  may consume bytes intended for the console owner.

### QEMU tools

- `qemu.hmp_query`: issue a query-class HMP command through `monitor.sock`.
- `qemu.hmp_control`: issue an explicitly state-changing HMP command, recording
  caller intent and observed post-state.
- `qemu.status`: combine PID identity, HMP status, and socket availability
  without duplicating the semantic classifier.

The server labels commands conservatively.  Unknown HMP commands use the
control path rather than being guessed read-only.

### Debugger tools

- `debugger.capture`: enable or reuse a loopback-bound live GDB stub, collect a
  bounded SPARC register/instruction/backtrace sample, and detach in guaranteed
  cleanup.
- `debugger.raw_batch`: run a bounded reviewed GDB batch for investigations not
  covered by `capture`, with the same detach/resume guarantee.

Debugger results include `guest_was_stopped`, `cleanup_attempted`, and
`guest_resumed_or_detached`.  Failure to prove cleanup is a first-class warning
and attention condition.

### Host tracing tools

- `host.process_sample`: bounded `/proc`, scheduler, CPU, and I/O observations
  for the exact run PID.
- `host.trace`: run a named, bounded probe recipe against the exact run PID.
  Initial recipes target TCG execution, hSIMD activity, host syscall/I/O
  blocking, and stack samples.
- `host.trace_capabilities`: report available host kernel, debugger, perf,
  bpftrace, symbols, and permissions before choosing a recipe.

Arbitrary probe source is not required for the first release.  Named recipes
are reviewable project artifacts.  An expert raw-probe operation may be added
after its audit and cleanup contract is designed.

### Evidence and hypothesis tools

- `evidence.record`: append one immutable JSON-lines fact to a run-local
  investigation ledger.
- `evidence.read`: return bounded ledger entries for an investigation.
- `hypothesis.start`: record competing falsifiable hypotheses, predicted
  observations, and discriminating tests.
- `hypothesis.update`: link evidence IDs to support, weaken, falsify, or leave a
  hypothesis unresolved.  It must not convert absence of evidence into proof.

The ledger records tool result hashes and references artifacts instead of
duplicating large captures.

## Agent instructions

The MCP initialization instructions establish this operating model:

> Your primary subject is the Solaris/illumos SPARC guest in the selected
> Niagara run.  You may observe and act through guest, emulator, debugger, and
> VM-host layers.  Begin at the layer nearest the symptom, cross layers when a
> discriminating test requires it, and always state which layer produced a
> fact.  Prefer competing falsifiable hypotheses to undirected command
> collection.  Guest networking is evidence under test and is never required
> for control.  Record consequential facts immediately.  Treat debugger
> attach, register writes, physical-register reads with acknowledge side
> effects, monitor controls, signals, and disk operations as potentially
> state-changing.

## Mutation and safety model

Power is preserved by making effects explicit rather than forbidding useful
operations.

- Read-only observations use query tools.
- State-changing operations use distinct control tools and return
  `mutated=true`.
- Every live operation resolves an exact run and verifies its QEMU PID.
- No tool sends Ctrl-C, Ctrl-D, or signals through QEMU's original terminal.
- No channel management operation may introduce a second writer.
- Debugger operations guarantee detach/resume cleanup and report whether that
  guarantee was proved.
- Traces have mandatory duration, output, and process-identity bounds.
- Disk checkpoint and VM lifecycle operations remain separate future tools
  because they require explicit quiescence and recovery contracts.
- The first release performs no automatic root escalation.  Missing privilege
  is returned as evidence; the operator can configure a narrowly scoped host
  privilege mechanism later.

## Failure behavior

- Timeouts return captured partial output and a typed warning.
- A missing socket is distinguished from a refused or unresponsive socket.
- Guest-command adapter failure does not silently fall back to guest SSH.
- Host-tool absence is reported by capability discovery, not treated as a
  negative observation about the guest.
- If a debugger cleanup cannot be proved, subsequent debugger calls are
  blocked until `qemu.status` establishes the guest state or the operator
  deliberately overrides the block.
- Evidence recording is append-only and uses atomic local writes.

## Delivery phases

1. **Core and run discovery**: stdio MCP server, configuration, path
   validation, common evidence envelope, run description, and unit tests.
2. **Existing observations**: classifier, console tail, QEMU status, and HMP
   query tools using current project scripts and sockets.
3. **Guest command adapters**: maintenance-serial and channel-root command
   execution with exact exit-status capture and no SSH dependency.
4. **Evidence and hypotheses**: append-only ledger and Gilfoyle-style
   hypothesis state transitions.
5. **Debugger capture**: live GDB enablement, bounded capture, and guaranteed
   cleanup tests using a fake monitor/debugger before any live VM test.
6. **Host tracing**: capability discovery and named bounded probe recipes.
7. **Controlled mutations**: explicit HMP control and later checkpoint/lifecycle
   tools with pre/post evidence.
8. **Host relay and packaging**: optional out-of-band relay, Codex MCP
   configuration, project instructions, and operator runbook.

## Acceptance criteria

The initial usable release is complete when:

1. Codex can start the server over stdio and list its tools without network
   access.
2. Given a fixture run directory, every tool resolves only fixture-contained
   paths and rejects traversal or an unvalidated arbitrary socket.
3. `lab.describe_run`, `lab.classify`, `guest.console_tail`, and `qemu.status`
   return the common evidence envelope with correct layer and source.
4. A guest command executed through a fake socket adapter returns distinct
   stdout, timeout, transport failure, and guest nonzero-exit results.
5. HMP query and control operations are distinguishable in both tool names and
   `mutated` results; unknown commands are never silently labeled read-only.
6. An investigation can record competing hypotheses, attach evidence, and
   falsify one without overwriting the historical record.
7. Debugger tests prove cleanup is attempted on success, timeout, malformed
   output, and debugger failure.
8. Trace tests enforce exact PID identity, duration, and output bounds.
9. No test requires guest networking, a live VM, root, or a destructive disk
   image.  A separately documented live smoke test is opt-in.
10. Existing repository tests still pass, and no existing uncommitted user
    files are modified.

## Open questions deferred to implementation planning

- Which run root or roots should be configured by default on each VM host?
- Which channel socket is the canonical guest command surface for the current
  OpenIndiana workstation candidate?
- Which SPARC-capable GDB binary and symbol roots are canonical on each host?
- Which narrowly scoped privilege mechanism should later authorize eBPF/perf
  operations that need elevation?
- Should the optional relay carry MCP itself or call the same backend library
  through a smaller Unix-socket RPC protocol?

These are configuration choices, not reasons to couple the first release to
guest networking or reduce its cross-layer tool model.
