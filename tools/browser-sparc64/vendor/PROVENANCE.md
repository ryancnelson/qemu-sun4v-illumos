# Pinned browser terminal dependencies

Retrieved 2026-10-24 from unpkg, matching upstream qemu-wasm's xterm 5.3.0
example and Dockerfile's xterm-pty 0.10.1 pin. JavaScript syntax checks passed.
License texts are included alongside the assets.

| Local file | Source | SHA256 |
| --- | --- | --- |
| xterm.js | https://unpkg.com/xterm@5.3.0/lib/xterm.js | f0aea0f75f48559013ae6643c2479dd737d26da42d5524e6d2b70915ae6523c7 |
| xterm.css | https://unpkg.com/xterm@5.3.0/css/xterm.css | 832f3f2c603b43ad4351ff04970150cc7a873014276db126a6065c6dd81e4872 |
| xterm-pty.js | https://unpkg.com/xterm-pty@0.10.1/index.js | d242a568a3b1ef487ede00e10108edbc4b9fd93de12db0ef694c9b81e691c649 |

xterm-pty is the upstream bundled UMD terminal adapter, not a remote service.
It supplies `openpty()` and translates terminal input/output through Emscripten's
PTY library. It does not fetch the emulator or firmware.
