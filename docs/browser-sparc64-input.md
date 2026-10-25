# Browser firmware harness and input regression

`tools/browser-sparc64/` contains the existing firmware-only harness, pinned
xterm5.3/xterm-pty0.10.1 vendors and their license/provenance files. Compiled
QEMU/Wasm/firmware payloads are not added. The included README/ACCEPTANCE record
their historical sequence; the later v2 acceptance supersedes early failure text.

Runtime artifacts must match `ASSET-SHA256SUMS`: Wasm424346e4, JSce661d5b,
worker74f89b30 and run132 firmware1341c419. Do not substitute native topology
firmware or mix artifact versions. Import the already-built matching JS/Wasm/
worker using `bash import-artifacts.sh EXISTING_V2_DIRECTORY`, copy the existing
run132 firmware as `assets/openbios-sparc64.patched`, then run
`sha256sum -c ASSET-SHA256SUMS`. No new build is needed.

Run `python3 tools/browser-sparc64/serve.py --port 8091`; open loopback8091.
Keep512MiB/oneCPU/thread=multi/no disk/network. Start and observe the prompt.
Direct typing `1 2 + .` must return3, `dev / ls` must list devices, and command
form `dev /pci@1f,0/pci@1,1/ebus@1/su@14,3f8 pwd` must return that path.
Save console evidence. Reload/stop releases the Wasm runtime.

Actual2026-10-25 Chrome replay reproduced doubled direct input before the fix.
Recorded event stacks show xterm `_keyDown` and `_keyPress` each emitting the
same character. The public onKey/custom-keypress guard rejects only the second
matching event after confirmed keydown handling. It does not deduplicate serial
strings, repeated keydowns or paste. Exact reviewed implementation/test bytes
are preserved; vendor code is unchanged. Direct arithmetic/tree, repeated11,
focused printablepress7 and command-form serial path passed after correction.
Use PinchTab `focus --css .xterm-helper-textarea` before standalone press:
clicking that hidden textarea failed, yielding a separately preserved negative
control stack-underflow. Physical keyboards, full IME and other browsers were
not tested. `?inputDiagnostics=1` is bounded128records and disabled by default;
firmware-only diagnostic use, not credentials.

CI: `python3 scripts/validate-browser-assets.py` hashes source/vendors, runs
10Node tests and2binary-independent HTTP tests with a60second total deadline.
It does NOT launch Wasm/browser/guest, load disks, build firmware or establish
runtime acceptance. The existing asset-job image installs/reports Node via its
existing apt toolchain mechanism; existing firmware/native validators remain.
For all3HTTP tests, first import the pinned firmware, then run
`python3 tools/browser-sparc64/test_server.py`.

Small before/after console, event traces, screenshot and test logs are preserved
under `artifacts/browser-input-20261025/`. Original browser evidence under
`notes/evidence/browser-sparc64-20261024/` is untouched. Solaris/browser disk/
network boot and native installed-OS acceptance remain separate milestones.
