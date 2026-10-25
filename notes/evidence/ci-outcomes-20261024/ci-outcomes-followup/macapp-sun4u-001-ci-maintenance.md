# CI maintenance follow-on — ready for independent review
2026-10-24T20:37:10.772909-07:00

Isolated candidate: /Users/ryan/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/ci-outcomes-followup/candidate
Follow-on patch: /Users/ryan/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/ci-outcomes-followup/maintenance-followon.patch
Patch SHA256: 375a5cab5e3eb3a00d095be39de11c02b3ff1ac40209f3f9ea6965d38200b122
Base is frozen original outcomes candidate; original outcomes.patch SHA256
9929981622460b8dad43ac5ac331c4ffb54475924bd01b7fd28ebb8354230566 unchanged.
No main checkout edits, real Docker/guest/CI, build or firmware artifact change.

Validation:25/25 meaningful full-harness/adversarial fixtures pass, smoke3/3,
bash syntax checks pass. Patch applies to isolated copy of original candidate
and produces identical candidate bytes. Raw final results: validation-wkzpbh05.
Tests: test_followon.py; full log followon-tests-final.log.

Four concrete failing-before blockers preserved:
1. Mica late-panic: unformatted inspect appends panic after final wait.
   Original exits0/PASS although console-final contains panic.
2. Mica evidence-write: outcome.env is a directory. Original exits1 instead of
   primary20 and skips cleanup.
3. Flint external SIGTERM during EXIT final PASS inspect: original exits143
   but outcome.env says PASS/0, console snapshot and cleanup absent.
4. Mica create-time TERM after owned creation/output but before flag assignment:
   original exits143 without final inspect or stopping its owned guest.
Exact original Mica repro run is recorded in mica-failing-before.log and
/tmp/macapp-sun4u-001-mica-ci-4i9bipm1. Flint original result:
term-during-final-pass/result.json. Original sources/tests remain unchanged.

Fixes:
- Classification stays provisional; finalizer gathers evidence best-effort,
  then checks health again (also baseline/no-observation), snapshots console,
  completes cleanup/preservation, and only then publishes final outcome.
- Evidence errors cannot trigger set-e abandonment or replace primary status.
  Finalizer explicitly exits with selected outcome code.
- Cancellation overrides all outcomes, including maintenance/PASS, during
  finalization without aborting cleanup. Final marker goes via saved stdout FD3
  to avoid being swallowed by docker-run output redirection during a trap.
- Record --cidfile and recover ownership from valid64-hex CID/stdout ID when
  run is interrupted. Reject preexisting identity files before launch; never
  clean up a preexisting same-name container when creation fails without ID.
- New SUN4U_KEEP_MAINTENANCE=1 (default0; only0/1 accepted) preserves solely
  final MAINTENANCE/21 after fresh live/non-OOM state verification.
  It prints MAINTENANCE_GUEST_PRESERVED and remains exit21, NEVER PASS.
  Panic/OOM/cancellation override; exited/unknown state disallows retention.
  Normal healthy KEEP_GUEST preservation remains separately scoped.

Cases prove default cleanup, opt-in maintenance preservation, healthy+flag still
cleaned, simultaneous/stale panic/OOM/stopped state, late maintenance-to-panic/
OOM/stopped transition, final inspect failure, late panic after stage PASS,
inspect/log evidence failure with console retained, unwritable outcome file,
real external TERM during final PASS and maintenance, real TERM at create
with CID/stdout-only ownership, failed creation unrelated-name safety, stale
CID/stdout rejection. Signals target only each test's own shell; Docker is a
shell-function fixture throughout. No failure fixtures claim live CI behavior.

Final contract: process exit + final SUN4U_OUTCOME/outcome.env agree when file
writable. If outcome file cannot be written, stderr reports this, final stdout
and process status remain authoritative. Captured evidence may be partial on
I/O failures; errors are reported and cleanup still attempted.
SIGINT/TERM/HUP are latched until final commit. At the final publication boundary
(after blocking evidence/cleanup), traps ignore those signals during builtin
result publication and exit; no external commands follow. SIGKILL/host loss
remain controller-side cancellation cases.
An unidentifiable creation without CID/stdout cannot justify stopping by name;
the implementation avoids unrelated-container deletion rather than guessing.
Native Docker/CI integration and independent review remain required.

Mica should specifically assess late-failure ordering, capture failure semantics,
signal precedence/reentrancy and ownership recovery. Mac app owns integration
and future media replay. All firmware work stays frozen; native failure would
take priority.
