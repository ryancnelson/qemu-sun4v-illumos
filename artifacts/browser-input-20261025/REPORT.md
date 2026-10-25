# Browser v2 rerun and terminal-input correction

Owner explicitly transferred browser_harness execution/edit ownership. Actual existing v2 browser firmware gates1–5 reproduced; direct automated typing bug reproduced and corrected in the harness. No QEMU/Wasm/firmware build, native guest access, shared CI/index edit, commit or push. Frozen fresh-serial handoff untouched.

Harness: `~/Documents/Codex/2026-08-23/run/work/browser-sparc64-harness`.
Evidence: `~/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/browser-retest-trellis`.

## Actual execution and result

Existing default PinchTab instance9868 returned503 `get targets: context canceled`. Left it untouched. Created own headless instance `inst_f666b52c`, port9871, using existing PinchTab executable (no install). Own tab `7C73CCFDAA8E3246E428ED53999A8155`. Existing `serve.py --port 8091` served unchanged compiled assets on loopback. New profile was auto-created with `pinchtab instance start --mode headless --port 9871`; initial named-profile request404 and stale remembered-tab404 preserved as setup limitations, not firmware failures.

Reproduction workflow:
```
python3 work/browser-sparc64-harness/serve.py --port 8091
pinchtab --server http://127.0.0.1:9871 nav http://localhost:8091 --new-tab --snap
# Click Start OpenBIOS, wait for banner, snapshot current terminal textbox.
pinchtab --server http://127.0.0.1:9871 type .xterm-helper-textarea '1 2 + .' --tab TAB
pinchtab --server http://127.0.0.1:9871 press Enter --tab TAB
```

Baseline actual output: `11 22 ++ ..` for one `1 2 + .` input. `console-before.txt` and `direct-before.txt` preserve it. After scoped correction, actual direct typing produces `1 2 + . 3  ok`, a new prompt, `dev / ls` root device listing, and repeated keys `11 . 11  ok`. Existing command form still produces repaired serial path `/pci@1f,0/pci@1,1/ebus@1/su@14,3f8 ok`. Save-console UI produced raw `console-after.txt` SHA256 `5ff80107f6d3526090ea54d736de722759ed4ef294178404b3b217d3fdb1f714`. Screenshot `browser-after.png` and page text retained. No Solaris/storage/network claim.

Printable `pinchtab press 7` also verified after explicitly focusing with `pinchtab focus --css .xterm-helper-textarea`: `7 . 7 ok`. Negative control retained: preceding `click .xterm-helper-textarea` failed hidden-element check; subsequent unfocused press sent no7, so ` .` caused firmware stack underflow. This is not silently removed: `console-final-with-focus-negative-control.txt` contains both that failure and corrected focused-press result. Use `focus`, not hidden-textarea click, for standalone press actions.

Reload/stop used at end to release this Wasm VM; snapshot shows Start enabled/Send disabled. Own loopback server/tab remain available for inspection; no browser VM left executing by this test. No existing profile/server stopped or configuration changed. Eval remains untouched/disabled.

## Concrete cause and minimal fix

Temporary opt-in `?inputDiagnostics=1` captures a bounded128 event/onData records. For one7, saved `input-stacks-before.txt` shows two xterm.onData emissions: first stack through xterm5.3 `_keyDown`, second through `_keyPress`. Thus duplicate bytes already exist before PTY/QEMU; not just double terminal echo. Browser keydown/keypress/beforeinput/input/keyup records are retained. Diagnostic `prevented` is captured via queued microtask from ancestor capture phase and is NOT proof of final event cancellation state.

Pinned vendored xterm source normally cancels handled keydown (`cancel(e,true)`), relying on browser not subsequently delivering its matching keypress. Observed PinchTab dispatch delivers both paths. Exact PinchTab internal implementation was not inspected; causality claim is bounded to recorded browser/xterm emissions.

New `terminal-input.mjs` uses only public `onKey` and `attachCustomKeyEventHandler`. It suppresses matching keypress only after xterm onKey reported that keydown, matching key/code/modifier signature. New keydown/keyup resets state; repeated keydowns, keypress-only/no-emitted-keydown, mismatched modifiers/code and composition events remain allowed. It never deduplicates raw strings or PTY data; paste remains unchanged. No vendored code modification or private-field hook.

Changed files only:
- `harness.mjs`: import/install keyboard guard and opt-in diagnostics.
- `terminal-input.mjs`: scoped guard.
- `input-diagnostics.mjs`: default-disabled bounded browser-event/onData diagnostics (firmware-only; do not enable for credentials).
- `test-terminal-input.mjs`: eight behavior regressions including baseline duplicate counterexample.

10/10 Node tests PASS (eight new plus two existing config); existing HTTP3/3 PASS; JS syntax checks PASS. Logs `unit-tests.log`, `http-tests.log`. Public-event fixture is not a complete browser/IME model; actual Chrome direct typing/repeated digits/printable press/form tests above independently exercise the fix. Physical keyboard, full international input/IME and other browsers remain untested.

## Frozen bytes and preservation

Patch `browser-input.patch` SHA256 `11ef1076dd7d9646dea16daab4b4dbef4c5bd3983954d5b7e49860296d162da7`.
Harness SHA256 `7cb73b94729b41ed491c6391dd8f1dad0b4b9a01333e14b0804b17a9249002ac`.
Guard SHA256 `98b808445ee6ea4daa50c4039a7bc70078c1af1e39f6c48ab26dbc57ff3f67e9`.
Tests SHA256 `9a59cb0148e59ea6ae134bd2add7a91a7819f82b7a508f8c1ffeffa33135aa73`.
Complete manifest/SHA256SUMS in evidence directory. Old harness/index/ACCEPTANCE copied there before editing; original ACCEPTANCE/index and old screenshots/raw logs remain unchanged.

Verified compiled inputs unchanged: Wasm424346e400e987381270ab05472a1dd123212f20c4dc3dd478d9f4c41a2a1155; JSce661d5b351ba929f9ffd51cfa1568fb4a41b04d0d70c4731fc72254e25c23c9; worker74f89b30f18ccc23eeb9153b5db55648fd59e62daaf32f69c99829dfbcc4347a; firmware1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938. Same512MiB/oneCPU/thread=multi. No native firmware1537670b substitution.
