# Browser acceptance record

Use actual observations. A compiled binary, loaded page, initialized runtime,
or firmware banner alone is not an interactive firmware success.

## Preflight

- Record qemu-wasm source commit, local patches and Emscripten version.
- Record build flags, Wasm heap size, JS/Wasm/worker SHA256 digests.
- Import one matching artifact set with `import-artifacts.sh`; never mix builds.
- Record browser/version, host and time; preserve serial output verbatim.
- Serve on loopback with `serve.py`; confirm no missing modules or isolation error.
- Default test: 512 MiB guest, 64 MiB TB, one CPU, no disk/network.
- Firmware digest must match the harness's checked run-132 digest.

## Distinct gates

1. **Runtime:** worker begins executing without a Wasm trap or abort. Runtime
   initialization status alone does not demonstrate that firmware has run.
2. **Firmware output:** recognizable OpenBIOS banner and prompt.
3. **Input/execution:** enter `1 2 + .` then Enter; capture the returned `3`
   separately from terminal echo and a following usable prompt.
4. **Machine tree:** enter `dev / ls`; capture the root listing, then use
   `dev /pci@1f,0/pci@1,1/ebus@1/su@14,3f8` and `pwd` to verify our repaired
   path, recording any errors rather than correcting firmware ad hoc.
5. **Responsiveness:** controls/terminal remain responsive; Save console log
   works. Note observed latency; do not turn an anecdotal time into a benchmark.

If a gate fails, retain first error and exact artifacts; compare against native
same-fork QEMU before blaming SPARC translation. Do not add an ISO or change RAM,
firmware and backend together to make the failure disappear.

## Results so far

2026-10-24: static configuration 2/2, HTTP 3/3; pinned terminal libraries load in
Chrome with isolation enabled. Start currently fails fetching the absent QEMU
module. Gates 1–5 remain **unexecuted** until the compiled artifacts are imported.

## Out of scope for this gate

Solaris at 512 MiB, installed boot, disk persistence and guest networking.
Native B134's hblk8 exhaustion at 512/1024 MiB is a separate known defect.

## First compiled-artifact runtime tests (2026-10-24)

PinchTab listed and controlled actual Chrome tab
A23419EC82F865229902328BCFB6083F at http://localhost:8089/. Navigation,
click, snapshot and page text work. JS evaluation returned403 (disabled);
do not claim that capability works or enable it silently.

Imported matching artifacts from work/qemu-wasm-sparc64-artifacts:
Wasm SHA256b831215cd3ad850a7035b1234afc2870d2ca38ae4a0ec05db337d6e20da10849.
Initial512MiB/oneCPU/thread=single run initialized runtime, then worker
TypeError: Cannot read properties of undefined (reading 'tb_ptr_ptr').
Code inspection found init_wasm32 called only in mttcg_cpu_thread_fn.

Changed only thread=single to thread=multi (still one guestCPU), with a
configuration regression test observed failing before/passing after.
Next actual browser run advanced to generated Wasm CompileError:
function#2 i64.sub[1] expected i64, found i64.gt_u of type i32 @+859.
No OpenBIOS banner or usable prompt observed; firmware boot remains FAILED.
Screenshot browser-failure-v1.png preserves visible failure.

Source hypothesis: tcg_wasm_out_sub2 emits a comparison producing i32 borrow,
then i64_sub without extending it. Build owner tasked with executable
red/green Wasm tests and a minimal correction. Await fresh artifact set;
do not mix or overwrite original artifacts.

## v2 firmware success (2026-10-24)

Wasm424346e400e987381270ab05472a1dd123212f20c4dc3dd478d9f4c41a2a1155
includes missing i32-to-i64 borrow extension in tcg_wasm_out_sub2. Source-
linked regression: original emitted Wasm fails validation; patched emitter
passes24 arithmetic/alias cases. Same firmware/512MiB/oneCPU/thread=multi.

Actual Chrome produced OpenBIOS banner and0> prompt. PinchTab direct type
and printable press actions doubled characters, so those do not establish
working keyboard automation. Added a normal Serial command field and button
using xterm5.3's paste API. First attempted Terminal.input was unavailable;
console errors identified this harness mistake, then corrected to paste.
No eval permission change was made.

Verified via form fill/click and serial output:
- `1 2 + .` -> `3 ok`, new prompt.
- `dev / ls` -> actual root device listing including memory, virtual-memory,
  pci@1f,0 and SUNW,UltraSPARC-IIi, new prompt.
- `dev /pci@1f,0/pci@1,1/ebus@1/su@14,3f8 pwd` -> matching serial path and ok.
- Save console log produced ~/Downloads/sparc64-openbios-console.txt,
  copied to browser-v2-console.txt; screenshot browser-v2-pass.png.

Gates1–5 PASS through command-form input. Direct automated terminal typing
remains a separate bug. No Solaris boot, disk, network or performance claim.
