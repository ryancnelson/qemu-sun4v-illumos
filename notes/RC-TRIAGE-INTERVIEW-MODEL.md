# RC triage interview model

This is a worked model for defining a release-candidate test before changing or
booting the candidate. It was captured during the OpenIndiana sun4v workstation
RC triage on 2026-08-26.

## Why this interview worked

The operator began with an outcome, not an implementation: prove that the image
reaches a login prompt without intervention, then validate and repair the tools
needed for its intended workstation role. The interview separated observation
from mutation and made persistence a first-class acceptance criterion.

The resulting phases were:

1. **Synchronize** the canonical project checkout with `git pull --ff-only`
   from its GitHub remote before trusting local scripts, notes, or runbooks.
2. **Plan** host services and QEMU/guest configuration so optional facilities
   cannot block boot.
3. **Observe** an untouched boot through the login prompt. Boot the VM with its
   live console attached to the tmux pane Ryan provided so he can watch the
   complete boot directly. Do not repair while measuring the baseline.
4. **Mutate** only after login: inspect, install, configure, and test missing
   guest tools.
5. **Persist** repairs in the writable candidate and use SMF retry semantics for
   services that may start before a host dependency appears.
6. **Reboot and prove** that the promoted candidate recreates the desired state
   without manual intervention.
7. **Document and publish** the outcome: update the project status, runbooks,
   milestone evidence, failure/root-cause notes, and relevant Kanban state;
   review the complete diff; then commit and push the tested repository state to
   GitHub. An RC exercise is not finished while its evidence exists only in a
   terminal, run directory, or unpushed worktree.

## The interview

The first question established the terminal milestone:

> What is the exact success milestone: console login, multi-user milestone, SSH
> access, graphical desktop, or all of them?

The operator selected an unattended console login prompt. This prevented
"QEMU is alive" or "OBP appeared" from being mistaken for RC success.

The next questions made implicit dependencies explicit:

- Which virtual hardware must work?
- What workstation functionality must be tested after login?
- Is the first boot observational, or are repairs allowed immediately?
- What evidence must be retained?
- Which credentials and timeout policy apply?
- Should the imported image be modified directly or protected behind an
  overlay?

The operator then supplied the functional contract:

- channel 0 is the serial console;
- channel 1 is reserved for PPP transport, without establishing networking in
  this test;
- channels 2 and 3 present guest login prompts through host-side Unix sockets;
- channel 4 reaches a host BBS;
- the BBS must eventually use Vibeproxy on Minnie for LLM access, but the
  endpoint is TBD and must not block boot;
- additional channels must exist for ad-hoc use so another boot is not required
  merely to add capacity;
- `root` / `root` is the expected test login;
- kmdb mode should be enabled;
- the operator must be consulted before a slow boot is declared failed.

The image policy was agreed explicitly: keep the transferred raw candidate
hash-addressed and read-only; run through a writable qcow2 overlay; after the RC
passes, flatten and check a new standalone image rather than silently changing
the imported base.

## Evidence-led clarification

Repository documentation was consulted before constructing the launch. It
revealed that the project has two distinct transports:

- QEMU's serial console socket; and
- a unit-101 shared-disk channel protocol exposed by `host-chan.py` as
  `niagN` Unix sockets.

It also revealed older role assignments (`niag0` PPP, `niag1` BBS, `niag2`
getty, `niag3` bulk) that conflicted with the proposed RC numbering. The right
response was not to guess. The conflict was shown to the operator with an exact
mapping and a concrete capacity question.

The operator clarified the real requirement: provide *enough* channels; do not
repeat a design that creates only two and forces another reboot later. The RC
therefore provisions a serial console plus eight independent unit-101 channels.
Role compatibility is tested after the observational boot rather than made a
new prerequisite for reaching login.

## Acceptance criteria

An RC run is not complete until evidence answers all of these:

- Was the VM booted in the tmux pane Ryan explicitly provided, with the live
  console visible there for the full observational boot?
- Did the guest reach `login:` without input after the initial boot action?
- Did kmdb mode remain available without stopping ordinary boot?
- Were all planned host sockets created before guest services needed them?
- Did channels 1 through 7 transport bytes independently?
- Did channels 2 and 3 present real, respawning authenticated login prompts?
- Could the guest reach the host BBS on channel 4?
- Did absence of the optional Vibeproxy endpoint leave boot and the BBS service
  healthy, with a clear degraded response instead of a boot dependency?
- Were failures, root causes, commands, hashes, wall times, and service states
  captured?
- After repair and reboot, did SMF recreate or retry the desired guest services
  without manual intervention?
- Was the immutable base unchanged, and was any promoted image independently
  flattened, checked, hashed, and made read-only before `READY`?
- Was the repository pulled from the authoritative GitHub branch before the
  test, using a fast-forward-only update and with pre-existing worktree changes
  identified rather than overwritten?
- Were the project status, runbook, milestone evidence, root-cause notes, and
  Kanban state updated to reflect what actually happened?
- Was the final diff reviewed, committed with a meaningful message, pushed to
  GitHub, and verified present on the intended remote branch?

## Behavioral rules for the triager

- Begin every RC test by identifying the canonical checkout, branch, GitHub
  remote, and worktree state, then run `git pull --ff-only` before using project
  guidance. Stop on divergence instead of merging or rebasing implicitly.
- Ask about outcomes before proposing commands.
- Separate baseline observation from repair.
- Consult canonical project evidence before relying on remembered topology.
- Surface documentation conflicts; do not quietly normalize them.
- Boot the VM in the operator-provided tmux pane so Ryan can watch it; do not
  substitute a hidden background console, a different pane, or log-only
  observation unless he explicitly redirects the run.
- Treat slow semantic progress as progress. Ask the operator before declaring
  timeout when the budget is intentionally open-ended.
- Never let an optional host service become a boot dependency.
- Keep credentials and LLM tokens out of logs, manifests, and command history.
- Record failed host-side setup attempts as evidence, even when no VM started.
- Verify the exact process, disk, firmware, socket, and backing-chain lineage
  before launch and again before promotion.
- End every completed RC test by updating durable project documentation and
  Kanban evidence, reviewing `git diff` and `git status`, committing the scoped
  changes, pushing them to GitHub, and verifying the remote ref. Preserve and
  exclude unrelated pre-existing changes.
