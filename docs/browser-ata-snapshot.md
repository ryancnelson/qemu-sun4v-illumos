# Browser disposable ATA snapshot control — reviewed task003

On 2026-10-25, one baseline-browser run passed **startup, disk enumeration, two exact reads, and observed backing endpoint preservation**. **WRITE, isolation under writes, durability and browser OS boot are NOT TESTED.** This is recorded runtime evidence, not a new execution or a CI result for the integration revision.

## Actual run

Trellis started at21:10:31UTC and captured at21:12:41UTC; the browser was subsequently reloaded idle. The fixed configuration used512MiB/oneCPU, no network,32KiB synthetic sentinel only, baseline v2 QEMU/Wasm and run132 firmware. Firmware enumerated disk@0. Two seeks returned0 and two reads returned40hex; all64 bytes at each requested byte offset0 and800hex matched. Close/free completed.

The actual MEMFS backing was hashed before and after:32768bytes, SHA25652fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5, same filesystem and node21. Post-run stream metadata identified fd12 /sentinel.raw inode21 flags557056 as read-only and fd13 /var/tmp/vl.IMPMX3 inode35 flags557058 as writable. These are observations of streams, not independent inspection of the QEMU block graph. The temporary filename/inodes/FDs are historical, not reproduction constants.

Unchanged endpoints do not rule out transient writes; no guest write occurred. The result's historical name BACKING_INVARIANCE_PASS must be read with this endpoint-only limitation.

## Reproduction inputs and commands

Use [fixed-config.json](../artifacts/browser-overlay-20261025/fixed-config.json) for exact argv and pins. Its original runtime_status=NOT EXECUTED BY FLINT and write_status=NOT TESTED are preserved historical author/scope metadata; actual runtime is [runtime-result.json](../artifacts/browser-overlay-20261025/runtime-result.json). Runtime was performed by Trellis, not Flint.

The ordinary drive option is `file=/sentinel.raw,format=raw,if=ide,index=0,media=disk,snapshot=on,readonly=off`. Supported isolated preRun creates `/var/tmp` using `mod.FS.mkdirTree('/var/tmp')`, verifies the fixed image before injection, and holds main until the actual injected backing hash check succeeds. The reviewed harness observes the same live FS/node through read-only streams; hashing only a fetched Uint8Array would be insufficient. Trellis owns the separately integrated implementation; this document adds no arbitrary-path/argv facility.

The existing generator is `tools/browser-sparc64/sentinel/sentinel.py`. In an owned writable checkout/scratch, create its assets directory then run:
```sh
python3 tools/browser-sparc64/sentinel/sentinel.py generate tools/browser-sparc64/assets/sentinel-32k.raw
```
Require32768 bytes and the pin above; output overwrite is refused. CI must generate in private scratch, not read-only /src. This package contains no raw fixture, ISO, firmware or Wasm binary. Baseline artifact acquisition/import remains the established project workflow.

Follow the [reviewed interactive command transcript](../artifacts/browser-overlay-20261025/enumeration-read.fth) one CHECK at a time: enumerate controller and ide@0 children, require disk@0, allocate800hex bytes, open the exact path, seek/read/dump at0 and800hex, close/free. Require nonzero allocation/handle, seek0/read40hex and all requested64 bytes against [expected.json](../artifacts/browser-overlay-20261025/expected.json). Do not paste the whole transcript, use an alias, infer offset from a tag, or continue after error/short/missing output. No write/boot/EOF command is included. The existing sentinel verifier can compare decoded payloads at these requested offsets; no new runtime is requested by this notebook.

## Why snapshot routing works and writes remain blocked

Bounded [source proof](../artifacts/browser-overlay-20261025/source-proof.txt) identifies exact source paths, lines and whole-file hashes. QEMU source HEAD0ef7b4e2814b231705d8371dd7997f5b72e70baf: block.c4060 saves top read-only=off, deletes original read-only and applies COW inheritance;1390 defaults backing read-only=on;4220 creates temporary qcow2. create_tmp_file substitutes /tmp with /var/tmp. Generated baseline JS initializes /tmp but not /var/tmp; normal mkdirTree resolves that prerequisite without permission-check changes.

Run132 OpenBIOS has two independent write blockers. ide.c opens deblocker then interposes disk-label; disk-label.c179 dlabel_write consumes addr/len and returns-1 without forwarding. The underlying IDE method table has read-blocks but no write-blocks. is-deblocker relays a write method, but its cached parent writer is absent; do_readwrite returns-1 before I/O. ATA write_tasklet/write_registers names concern command-register programming, not a disk-data writer.

Seek only updates position (low/high cells;0 success), not durability. IDE close closes the deblocker, which frees its buffer. No registered flush or ATA FLUSH CACHE was found on the reviewed paths. These are exact source-checkout findings, not a new firmware binary trace. No negative-write trial, port bypass, injected code or firmware patch was attempted.

## Pins, evidence and review

- Wasm424346e400e987381270ab05472a1dd123212f20c4dc3dd478d9f4c41a2a1155
- JSce661d5b351ba929f9ffd51cfa1568fb4a41b04d0d70c4731fc72254e25c23c9
- Worker74f89b30f18ccc23eeb9153b5db55648fd59e62daaf32f69c99829dfbcc4347a
- Firmware1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938
- [Raw console](../artifacts/browser-overlay-20261025/raw-console.txt):2de0e7e28f6240400a2871b0932534c0ad0f6829efc3eed30a9d8f30f85ceca4
- [Runtime result](../artifacts/browser-overlay-20261025/runtime-result.json):16c1d8491325a96d2e134d0a5f45b8d914ad54c6e133d7d0dff38f98bd6364a3

Mica independently reviewed source/config,20 host tests, actual argv/pins, raw backing observations, access-mode masks and requested-offset bytes. [Actual review](../artifacts/browser-overlay-20261025/actual-runtime-review.json) is preserved. No identical-byte runtime/test review was repeated to prepare this package. [SHA256SUMS](../artifacts/browser-overlay-20261025/SHA256SUMS) pins packaged evidence. [Provenance](../artifacts/browser-overlay-20261025/provenance.json) maps copied files to the untouched work archive; not every intermediate page/full source file is packaged.

No write/readback, write isolation, persistence/durability, real-disk support, large-image feasibility, browser loader/kernel/OS boot or allocator-correctness claim. Native sessions/checkpoint/baseline artifacts remain untouched. Task002CI164 PASS is historical and does not establish task003 integration CI. Kestrel's allocator lane remains platform-blocked/unconfirmed and unchanged; this control neither replaces nor bypasses it.
