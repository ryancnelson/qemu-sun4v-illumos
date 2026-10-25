# Solaris/OpenBIOS/QEMU backlog

Coordinator: Codex Mac app. Delegate through Maestri Maestro, not directly
to its helpers. Work is useful only when it advances a gate or resolves a
specific uncertainty. Each task needs a hypothesis, falsifier, evidence,
acceptance criteria and an isolated owner. No busywork or duplicate builds.

## Active

- Maestro macapp-sun4u-001: principled OpenBIOS available-map fix; Kestrel
  implementation, Flint tests, Mica independent review, Trellis native test.
  Acceptance: failing baseline and passing unmodified B134512MiB boot/input,
  plus range/overflow/canonical-hole tests and unchanged allocation policy.
- Mac app: browser firmware execution using completed qemu-wasm build.
  First failure: single-thread TCG lacks Wasm TLS initialization; test
  thread=multi with oneCPU and all other inputs fixed. Require prompt,
  arithmetic3, device tree, serial path and responsive UI.
- Mac app: native run136 IDE installation target reached maintenance mode
  while preparing text-install media. Installation is NOT proven.

## Ready for Maestro as current owners become free

1. **Review CI outcome detection.** Read-only review of current harness:
   panic, maintenance mode, host OOM, timeout and cancellation must produce
   distinct outcomes and preserve evidence. Provide patch/tests in isolated
   directory; no CI push or edits to Mac-app-owned staging. Success: fixture
   tests prove each failure is detected and normal prompt is not rejected.
2. **Diagnose disk/media enumeration regression.** Compare diskless135 pass
   and IDE-target136 failure. Read immutable logs and B134 boot scripts;
   identify media selection assumptions versus actual device enumeration.
   No guest interaction without explicit ownership transfer from Mac app.
   Success: testable cause with precise script/location and falsifier, then
   a scoped candidate experiment, not a speculative disk-size change.
3. **Native same-fork control plan.** Define minimal native build of pinned
   qemu-wasm source0ef7b4e and guest tests that distinguish SPARC/QEMU faults
   from Wasm backend faults. Reuse existing build/source artifacts. Plan
   first; request coordination before expensive builds. Success: exact
   reproducible commands and endian/64-bit/trap/CASX test expectations.
4. **Browser disk strategy.** Design worker-compatible chunked read-only ISO
   plus persistent writable overlay, drawing on qemu-wasm and Infinite Mac
   primary sources. Avoid loading the ISO into MEMFS with the1792MiB heap.
   Success: concrete existing APIs/code reuse, memory budget, integrity and
   crash-recovery tests. No new implementation in active browser harness.
5. **Firmware regression matrix.** After candidate fix:512,1024,1088,1536MiB,
   low auto allocation unchanged, positive high claims, canonical holes and
   non-SPARC behavior. Run only bounded owned guests; integrate via Mac app
   Woodpecker review. Success: provenance and separate pass/fail per gate.
6. **Reproducible Wasm CI packaging.** Review completed build recipes, pinned
   Emscripten3.1.50/dependencies/submodules, checksums/licenses and import
   contract. Propose isolated CI patch; no external pushes. Success: rebuild
   inputs documented and artifact set cannot silently mix versions.

## Dependency-gated

- Fix browser runtime errors before ISO/OS boot experiments.
- Resolve disk/media discovery before installer target selection.
- Install only to verified disposable disk; then cold boot WITHOUT ISO,
  writable-root test, networking and reboot as separate gates.
- Test reduced RAM only after firmware fix, not by silently editing kernel.
- Benchmark hot-block JIT and browser memory only after correctness gates;
  report measured wall time/heap and repeatability, not anecdotal speed.

Maestro may assign ready read-only review/design tasks when useful. Existing
macapp-sun4u-001 scope remains authoritative: no external pushes/PRs, changes
to main checkout/browser harness, or takeover of run136 without handoff.
