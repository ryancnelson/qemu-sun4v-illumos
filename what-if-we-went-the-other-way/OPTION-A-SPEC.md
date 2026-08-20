# OPTION-A-SPEC.md — TDD plan: repair OpenBIOS console attach for Solaris/sun4u

Status: spec + plan, NOT YET IMPLEMENTED. Written 2026-08-20.

## 0. What this is, in one paragraph

QEMU's `sun4u` machine + OpenBIOS already load a Solaris kernel and hand off
control (see `what-if-we-went-the-other-way/README.md`). The Solaris kernel
then fails to attach its native `su` (16550 UART) driver to the emulated
serial device OpenBIOS describes, and console output disappears at that exact
point. This spec is a bounded, test-driven plan to repair ONLY the OpenBIOS
device-tree/property construction for that `su` node, using a real,
already-staged `sun4u`-targeted Solaris/OpenSolaris kernel as the test
oracle, and an automated QEMU harness modeled on this project's existing
`tests/` framework. Scope is deliberately narrow: fix console attach only.
Everything past that (disk, network, multiuser) is out of scope and belongs
to later phases already outlined in the `what-if` doc.

## 1. Confirmed facts this spec is built on (verified this session, not assumed)

- **The exact failing call site is identified, in local source**:
  `qemu/roms/openbios/drivers/pci.c` line 1182:
  ```c
  ob_pc_serial_init(config->path, "su", (PCI_BASE_ADDR_1 | 0ULL) << 32, 0x3f8ULL, 0);
  ```
  This constructs the `su` node under EBus. `ob_pc_serial_init` itself is in
  `drivers/pc_serial.c`: it builds `device-name`, `device-type=serial`, a
  `reg` property (`(base+offset)` as two 32-bit cells + `SER_SIZE=8`), an
  `interrupts` property (hardcoded to `1` under `CONFIG_SPARC64`), binds
  `open`/`close`/`read`/`write` methods, and sets `/aliases/ttya` to this
  node's full path. **This is the entire node-construction surface for the
  hypothesis space** — nothing else constructs this node.
- **A real `sun4u`-targeted kernel is already staged, no download needed**:
  `~/Downloads/sol-nv-b59-sparc-dvd-iso.iso` (Solaris Nevada build 59, SPARC,
  3.88GB). Confirmed via `strings -a` against the raw ISO (macOS has no UFS
  mount driver, so this substitutes for a mount-and-`find` pass): package
  manifest contains the literal entry `platform/sun4u/kernel/unix=sparcv9/unix`
  (SUNWcakr package, sun4u kernel binary), not just incidental string
  mentions. 1872 `sun4u` string hits vs 847 `sun4v` hits total in that image.
  Two smaller build-134 OpenSolaris images (`osol-dev-134-ai-sparc.iso`,
  `textinstall-134-sparc.iso`) also confirmed to carry `/platform/sun4u/`
  trees.
- **The Solaris 10 sun4v donor is NOT a usable oracle for this specific
  question** (established in prior discussion): it uses `qcn` (a paravirtual
  Niagara console), never attaches `su` at all, so it cannot show the
  su-specific device-tree contract. The oracle must be a system that
  genuinely uses `su` — which the sun4u kernel itself provides via its own
  known driver source (illumos-gate still carries `usr/src/uts/sun4u/io/su.c`
  or equivalent as read-only reference, even though the SPARC kernel BUILD
  tooling was removed from illumos-gate master in 2024 — the source text
  itself is still there to read).
- **This project's existing test harness pattern is directly reusable**:
  `tests/lib/vm.sh` (`vm_run`, `vm_boot_to_login_script`, clean-shutdown
  fragments), `tests/lib/lock.sh` (per-resource locking so tests can't
  collide), `tests/run-all.sh` (aggregate runner), all built around `expect`
  scripts driving QEMU's serial console via `-nographic`, with `spawn`,
  `set qpid`, and SIGTERM-based clean shutdown. The sun4u harness in this
  spec should follow the identical shape, not invent a new one.
- **illumos-gate master's SPARC kernel build tooling was deliberately removed
  in 2024** (commit `689b930`, "remove SPARC kernel makefiles", 66,939 files
  deleted) — confirmed directly against live GitHub. The C/driver SOURCE is
  still present and readable, useful as reference material, but nothing in
  this plan depends on being able to COMPILE illumos-gate's sun4u kernel from
  scratch. The plan uses the already-built binary kernel from the b59 ISO.

## 2. Explicit non-goals

- Not attempting disk, networking, or multiuser boot in this phase.
- Not touching the Niagara/`sun4v` machine, `q.bin`, hsimd, or any file
  under the main project's Niagara-specific paths.
- Not attempting to build a SPARC kernel from source (illumos-gate, Tribblix,
  or otherwise) — the b59 binary kernel is used as-is.
- Not a general OBP-compatibility rewrite. One property/behavior mismatch at
  a time, smallest change first, exactly per the `what-if` doc's Phase 3
  discipline.

## 3. The oracle problem, solved concretely

Two oracles, used for different questions, neither requiring new
infrastructure beyond what's already staged:

**Oracle 1 — real `su` driver expectations, from SOURCE not a live system.**
Since no live genuine-Sun-firmware `sun4u` reference machine exists in this
project (the Solaris 10 donor is sun4v/`qcn`-only), read the `su` driver
source directly. It is present in illumos-gate (read-only, build tooling
absent but text intact) at (illumos-gate master, current commit — verify path
still current, since files have moved before): `usr/src/uts/sun4u/io/su.c` or
`usr/src/common/io/serial/su.c` depending on gate revision — LOCATE THIS
EXACT PATH as step 0 of Phase 1 below, do not assume the path from memory.
This tells us precisely which device-tree properties/`compatible` strings/
`reg` layout the driver's `attach()` routine actually inspects before binding
— the authoritative ground truth for what OpenBIOS must produce, independent
of any live system.

**Oracle 2 — does the actual b59 kernel attach, given OpenBIOS's CURRENT
(unmodified) output?** This is the empirical falsification loop: boot b59
against stock OpenBIOS, observe exactly how it fails (same "console
disappears" symptom already documented, or something different — RE-VERIFY,
do not assume the prior `what-if` observation used this exact kernel/media).

## 4. Test-Driven Development structure

Following this project's own TDD-flavored discipline (RED/GREEN test names
already used in `tests/`, e.g. `test-disk-writes-persist.sh` documented as
"FAILS on stock QEMU; target for patch"), every phase below produces or
extends an automated test BEFORE any OpenBIOS source is touched, and the test
must demonstrably go from FAIL to PASS as the sole measurable outcome of each
patch.

### New test tree (proposed, mirrors `tests/` layout)

```
tests/sun4u/
  lib/
    vm-sun4u.sh          # sun4u-flavored vm_run: -M sun4u, points at b59 media,
                          # tracks OpenBIOS build under test via QEMU_BIN
    obp-probe.sh          # non-boot Forth-level property/node dump helpers
  test-openbios-boots-b59-kernel.sh    # RED first: does OpenBIOS even reach kernel entry
  test-su-node-shape.sh                # normalized property dump vs oracle-1 expectations
  test-su-attaches.sh                  # THE central test: console alive past su attach
  test-linux-regression.sh             # any OpenBIOS change must not break existing Linux/BSD boot
  test-netbsd-regression.sh            # ditto, if NetBSD/sparc64 media is available
  fixtures/
    su-oracle-properties.json          # ground truth extracted from illumos su.c source read
  run-all-sun4u.sh                     # aggregate runner, mirrors tests/run-all.sh
```

### Phase 0 — RED: reproduce and pin the current failure as an automated test

Goal: an automated, repeatable test that FAILS today in exactly the documented
way, so every later change has a concrete regression target.

1. `tests/sun4u/lib/vm-sun4u.sh`: a `vm_run`-style wrapper, but for
   `-M sun4u` and the b59 ISO. Reuse `tests/lib/lock.sh` verbatim (same
   locking primitive, different resource name e.g. `sun4u-test-<pid>`).
   Boot with plain stock OpenBIOS first (whatever ships with the pinned QEMU
   version already vendored in this repo under `qemu/roms/openbios/`).
2. `test-openbios-boots-b59-kernel.sh`: expect script that spawns QEMU,
   waits for the OBP `ok` prompt, issues `boot cdrom` (or the correct
   boot-device token for this media — VERIFY exact syntax against b59's own
   documented boot procedure, do not assume `boot disk` from the Niagara
   harness applies unchanged), and asserts that SOME kernel-loading evidence
   appears (e.g. "SunOS Release" banner, or the exact string the `what-if`
   doc says appeared) BEFORE asserting anything about console survival past
   that point. This test should PASS today — it's establishing the known-good
   baseline, not the blocker.
3. `test-su-attaches.sh`: expect script that continues past kernel entry and
   asserts EITHER a login prompt appears (full pass) OR that output visibly
   stops (documents the current failure precisely — capture the exact last
   line seen and how long before timeout, as a fixture for comparison). This
   test is EXPECTED TO FAIL today. Record its current failure signature
   verbatim in a checked-in fixture file (`fixteres/known-failure-b59.log`)
   so future runs can diff against it and detect if the FAILURE MODE changes
   (e.g. a different, new failure appearing after a change, vs the same one
   persisting) — this project's own `test-reboot-obp-intact.sh` precedent
   ("weak AND flaky" per `CURRENT-STATE.md` Known gaps #4) is a cautionary
   example of a test that doesn't actually pin down real state; do not repeat
   that mistake here — assert on the EXACT captured console bytes, not a
   loose substring.
4. `test-linux-regression.sh` / `test-netbsd-regression.sh`: establish
   PASSING baselines against stock OpenBIOS for whatever non-Solaris guest
   media is available (search this project's staged ISOs — `Downloads/` —
   for anything NetBSD/Linux-sparc64 capable; if none exists, this phase
   should ALSO include acquiring/verifying one, since regression protection
   against Linux/NetBSD is explicitly called for in the `what-if` doc's
   Phase 3 discipline and cannot be skipped).

**Exit criterion for Phase 0**: all tests run automatically via
`run-all-sun4u.sh`, `test-openbios-boots-b59-kernel.sh` and the regression
tests PASS, `test-su-attaches.sh` FAILS with a precisely captured, fixture-
pinned failure signature. This is the RED baseline.

### Phase 1 — Capture the reference contract (Oracle 1, source-based)

1. Locate the exact `su` driver source file and its `attach()`/`probe()`
   routine in illumos-gate (read-only; note exact file path and commit hash
   read, since the gate has moved files around and this must be reproducible).
2. Extract, into `fixtures/su-oracle-properties.json`, the exact set of
   device-tree properties/values the driver's attach path inspects: expected
   `compatible` strings (if any — some drivers match by node name, others by
   `compatible`), expected `reg` cell count/encoding, `interrupts` shape,
   and whether it reads `/aliases/ttya` or resolves the console purely via
   `/chosen/stdout` `ihandle`->phandle resolution (this determines whether
   `pc_serial.c`'s `/aliases/ttya` write, quoted above, is even on the
   relevant path at all, or whether `/chosen` handling elsewhere in
   `openbios.c`/`init.fs` matters more).
3. Write this extraction as a checked test
   (`test-su-node-shape.sh`, non-boot, Forth-level): boot ONLY to the OBP `ok`
   prompt (no `boot` command issued), use OBP's own `dev` /
   `.properties` Forth words interactively (scripted via expect) to dump the
   CURRENT `su` node's properties as OpenBIOS constructs them today, and
   assert equality against the oracle fixture. This test is EXPECTED TO FAIL
   at whichever property first diverges — that divergence IS the diagnosis,
   discovered mechanically rather than by guessing among the doc's six
   candidate hypotheses (node name, `compatible`, `reg`, `ranges`,
   `interrupts`, `ttya`/ihandle wiring).

**Exit criterion for Phase 1**: `test-su-node-shape.sh` exists, runs
automatically, FAILS, and its failure output names the SPECIFIC property that
differs from the oracle — this is the diagnosis, produced by a test rather
than by inspection alone.

### Phase 2 — GREEN: minimal targeted patch

1. Make the SMALLEST edit to `pc_serial.c` (or, if Phase 1 shows the mismatch
   is actually in `pci.c`'s EBus/`ranges` construction rather than the serial
   node itself, edit there instead — do not assume the fix lives in
   `pc_serial.c` just because that's where the node is built) that makes
   `test-su-node-shape.sh` pass.
2. Rebuild OpenBIOS (this repo already has a working sparc64 QEMU+OpenBIOS
   build process, per `README.md`'s existing patch/build instructions —
   reuse it, do not invent a new build path).
3. Re-run the FULL Phase 0 regression suite (`test-linux-regression.sh`,
   `test-netbsd-regression.sh`) before touching Solaris again — a change
   that breaks Linux/NetBSD boot is reverted immediately, full stop, per the
   `what-if` doc's explicit rule.
4. Re-run `test-su-attaches.sh`.

**Exit criterion for Phase 2**: `test-su-node-shape.sh` passes,
`test-linux-regression.sh`/`test-netbsd-regression.sh` still pass
(unchanged), and `test-su-attaches.sh` either (a) passes outright — console
survives, milestone 2 from the `what-if` doc's Success Criteria achieved — or
(b) fails with a DIFFERENT, NEW failure signature than the Phase 0 baseline,
which means progress was made and the loop repeats at Phase 1 for the next
divergent property. If (c) the SAME failure signature persists unchanged,
the hypothesis was wrong; revert and pick the next candidate from the
doc's list.

### Phase 3 — Iterate

Repeat Phase 1 -> Phase 2 for each newly-exposed mismatch, exactly per the
`what-if` doc's Phase 4 ("Fill runtime gaps incrementally"). Each iteration:
one property/behavior hypothesis, one test, one patch, full regression suite,
before moving to the next. Stop and reassess (per the doc's own "Stop
Conditions") if a change repeatedly reveals a NEW broad class of
incompatibility rather than narrowing toward milestone 2.

## 5. Automated harness — concrete mechanics

Extending `tests/lib/vm.sh`'s pattern rather than replacing it:

```bash
# tests/sun4u/lib/vm-sun4u.sh (sketch, not yet written)
QEMU_SUN4U="${QEMU_SUN4U_BIN:-$PWD/qemu/build/qemu-system-sparc64}"
B59_ISO="${B59_ISO:-$HOME/Downloads/sol-nv-b59-sparc-dvd-iso.iso}"

vm_run_sun4u() {
    local script_body="$1"
    # NOTE: sun4u wants a real -cdrom / IDE-attached ISO, NOT pflash like
    # Niagara -- VERIFY this against actual sun4u machine args before
    # assuming; do not copy the Niagara pflash invocation blindly.
    expect -c "
set timeout $BOOT_TIMEOUT
spawn \$env(QEMU_SUN4U) -M sun4u -cdrom \$env(B59_ISO) -nographic
set qpid \$exp_pid
$script_body
"
}
```

**Open question flagged, not assumed**: whether `sun4u` boots this ISO via
`-cdrom` (a real IDE-attached CD-ROM device, since `sun4u` — unlike Niagara —
has genuine IDE per the `what-if` doc's hardware inventory) or some other
attach method. Niagara's `-drive if=pflash` convention does NOT apply here;
CONFIRM the correct sun4u invocation empirically as literally the first
sub-step of Phase 0, before writing any test that assumes a specific command
line.

**Non-boot OBP-level testing** (`obp-probe.sh`): a way to reach the `ok`
prompt WITHOUT issuing `boot`, so Phase 1's property-dump tests don't pay a
~full kernel boot's time cost per iteration. Since OpenBIOS reaches `ok`
quickly (this is firmware-level, not a full guest OS boot), this should be
fast — seconds, not the minutes a full Niagara VM boot costs per
`tests/lib/vm.sh`'s generous 180s `BOOT_TIMEOUT`. This speed difference is
important: Phase 1 iteration should be CHEAP, and the harness should
exploit that rather than always paying for a full Solaris boot per
`what-if`'s own "Tests before full boots" principle.

## 6. Risks specific to this plan

- **The `su` driver source path in illumos-gate may have moved or been
  restructured** since whatever revision the b59-era driver actually matches
  (b59 predates the 2024 SPARC-makefile removal by roughly a decade-plus) —
  reading CURRENT illumos-gate source as the oracle risks reading a DIFFERENT
  driver revision than what's actually running in the b59 kernel. Prefer, if
  obtainable, source contemporaneous with build 59 specifically (OpenSolaris/
  Nevada's own historical source snapshots, if archived) over current
  illumos-gate, and flag any divergence found.
- **The Forth-level non-boot property dump (Phase 1) requires the SAME
  OpenBIOS session model the doc's own "preserve visibility" section
  discusses** — verify `dev` / `.properties` are the correct interactive
  Forth words for this OpenBIOS build (words vary across OpenBIOS versions)
  before scripting against them; do not assume word names from generic
  IEEE-1275 documentation without checking this repo's actual OpenBIOS
  source/`Documentation/` tree.
- **b59/OpenSolaris-134 are development-era builds** — expect their OWN bugs
  independent of the OpenBIOS question, and be prepared to distinguish "our
  firmware fix didn't work" from "this particular development build has an
  unrelated bug" — cross-check against BOTH staged sun4u-capable images
  (b59 and build-134) if one behaves confusingly.
- **Regression suite coverage is only as good as available non-Solaris
  media** — if no NetBSD/Linux-sparc64 image is staged, acquiring one is a
  real prerequisite, not an optional nice-to-have, since it's the only
  guard against silently breaking currently-working guests while chasing
  Solaris compatibility.

## 7. Definition of done for this spec's scope

`test-su-attaches.sh` passes reliably (run it multiple times — flakiness
itself is a finding, per this project's own experience with
`test-reboot-obp-intact.sh`) against the b59 kernel, with
`test-linux-regression.sh`/`test-netbsd-regression.sh` unchanged-passing, and
every property change that got there is captured in git history as a
sequence of small, individually-justified OpenBIOS patches — not a single
large diff. This achieves Milestone 2 from `what-if-we-went-the-other-way/
README.md`'s Success Criteria list ("The su driver attaches and console
output continues") and is the natural stopping point for this spec; Phases 4
("Fill runtime gaps") and 5 ("Exercise native storage") from that doc are
follow-on work, out of scope here.
