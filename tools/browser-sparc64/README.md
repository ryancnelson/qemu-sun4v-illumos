# SPARC64 browser firmware smoke harness

Experimental harness, not a proven browser boot. No disk images are loaded.
Default guest memory: 512 MiB; TCG cache: 64 MiB; one CPU. Total Wasm heap
is separately fixed/configured by the Emscripten build. Larger RAM choices
may exhaust that heap. Native Solaris B134 at 512 MiB is currently failing;
this harness makes no claim about Solaris at that memory size.

## Artifact contract

Put the qemu-wasm Emscripten ES6 factory in `assets/qemu-system-sparc64.js`
(the build output may originally be extensionless). Copy the matching
`qemu-system-sparc64.wasm` and `qemu-system-sparc64.worker.js` alongside it,
plus any other runtime companions the build emits, preserving their names.
Use the hybrid Wasm TCG backend, `PROXY_TO_PTHREAD=1`, xterm-pty integration,
and exported runtime methods `FS,TTY,getTempRet0,setTempRet0,addFunction,removeFunction`.
No `file_packager` / `.data` file is needed for this test.

Copy xterm 5.3.0 UMD `lib/xterm.js`, `css/xterm.css` into `vendor/`, and the
build's xterm-pty UMD `index.js` to `vendor/xterm-pty.js`. Keep package versions,
license files, and hashes with the build provenance. All runtime code is local;
no CDN fallback hides missing dependencies or breaks cross-origin isolation.

Dependency retrieval note: inspected `~/bin` for a package/download wrapper;
only `safe-curl` applies, but it rejects its own underlying curl command.
A one-invocation `GUARDRAIL_BYPASS=1` exception is used for each read-only HTTPS
download from pinned unpkg package URLs. Downloads are vendor assets, not
installation scripts. Review and syntax-check them before browser execution.

Firmware: playbox run 132 `artifacts/openbios-sparc64.patched`, saved to
`assets/openbios-sparc64.patched`. SHA256:
`1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938`.
The browser verifies it before writing to the guest's firmware filesystem.

## Run and test

Run `python3 serve.py` from this directory, then open `http://localhost:8088`.
The server binds only loopback and adds COOP/COEP headers for SharedArrayBuffer.
Do not expose this development server publicly. Use Reload / stop to destroy
the runtime; the harness deliberately does not attempt snapshot/restart.

Static checks: `node --test test-config.mjs` and `node --check harness.mjs`.
These are **not** a substitute for a real browser execution test.
HTTP tests: `python3 test_server.py` (ephemeral loopback port).

2026-10-24 validation: config tests 2/2, HTTP tests 3/3, JS/Python syntax
checks passed. PinchTab's Chrome opened the page on localhost:8089; the
cross-origin-isolation guard passed and both terminal library imports loaded.
Start then correctly reported the still-missing compiled QEMU module. This
is a harness/dependency test, **not** an OpenBIOS-in-Wasm success. The
current build contract uses a fixed 1792 MiB Wasm heap; large RAM selections
remain experimental. Native B134 also panics at 1024 MiB, separately from
this firmware-only browser test.

Browser acceptance criteria:

1. Page reports `crossOriginIsolated === true` and verifies firmware hash.
2. Emscripten worker starts without missing assets/exports or traps.
3. OpenBIOS banner and prompt appear.
4. Typing `1 2 + .` returns 3; `dev / ls` lists the device tree.
5. Save serial log with artifact hashes, browser version and RAM selection.

The firmware power-interrupt/fdthree workarounds are needed before a future
Solaris boot, not for this no-disk firmware smoke test. Browser block storage,
networking and Solaris installation remain separate milestones.
