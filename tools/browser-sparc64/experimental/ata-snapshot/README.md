# Experimental ATA snapshot control

This separate page preserves the production harness, its default no-media mode, and `?storage=sentinel` ATAPI control unchanged. This page defaults to no media too; only `?storage=snapshot-sentinel` selects the fixed32KiB ATA snapshot experiment. No arbitrary image, path or QEMU argument is accepted. RAM must be512MiB when selected; oneCPU/run132 firmware and baseline v2 artifacts remain pinned.

From the repository root, generate the existing fixture if absent:
```
python3 -B tools/browser-sparc64/sentinel/sentinel.py generate tools/browser-sparc64/assets/sentinel-32k.raw
node --test tools/browser-sparc64/test-config.mjs tools/browser-sparc64/test-terminal-input.mjs tools/browser-sparc64/test-storage.mjs tools/browser-sparc64/experimental/ata-snapshot/test-observation.mjs tools/browser-sparc64/experimental/ata-snapshot/test-overlay.mjs
```
The generator refuses overwrite; verify an existing fixture instead. Fixture SHA25652fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5. Host tests use real `node:crypto` webcrypto when the global is unavailable. No browser/guest runs in these tests.

With existing v2 assets imported using the ordinary importer, use existing loopback server:
```
python3 tools/browser-sparc64/serve.py --port 8088
```
Open `http://localhost:8088/experimental/ata-snapshot/?storage=snapshot-sentinel`. This manual invocation is not a CI step. The top is `media=disk,snapshot=on,readonly=off`; QEMU's source-supported snapshot branch opens the raw backing read-only and creates a writable temporary qcow2 top. The experiment creates only the required MEMFS `/var/tmp`; it does not patch QEMU permissions or supply real media.

Prelaunch validation reads the actual MEMFS backing and holds QEMU main with a run dependency until its pinned hash succeeds. Failed validation keeps launch held. After the reviewed reads, click **Capture actual backing after reads**, then **Save console log**. The one-shot observer requires the same main FS object/node/inode, a still-open read-only QEMU backing stream, and the actual backing hash. It records matching `/var/tmp/vl.*` stream metadata separately. A replaced node, missing backing stream, writable backing, size/hash failure or oversized stream inventory is failure, not acceptance. An observer's transient stream cannot satisfy the QEMU-stream check because it is closed.

Use the independently reviewed gated command contract804abb30698d648d9c9d5335bd5cc383299104761dc25a6916a883c6ada8ce36 (`overlay-contract-flint/enumeration-read.fth` in task003 evidence). Never paste it whole. Enumerate ide@0 then disk@0; stop if actual topology differs. Open exact `/pci@1f,0/pci@1,1/ide@3/ide@0/disk@0`, allocate800hex bytes, seek0/read40hex/dump64bytes, verify exact requested bytes, then seek800hex/read40/dump and verify. Nonzero allocation/handle, seek0, read40 and completed prompt are hard gates. Close/free only after successful checks. No write/boot/EOF commands are authorized by that contract.

Recorded predecessor runtime,2026-10-25 21:10–21:12UTC: ATA startup/enumeration/two64-byte reads and observed backing endpoint preservation PASS. Actual MEMFS pre/post inode21/hash52fa9b2c; read-only backing fd12 and writable temporary fd13 observed. Raw SHA2562de0e7e28f6240400a2871b0932534c0ad0f6829efc3eed30a9d8f30f85ceca4; task evidence `work/maestro-sun4u-003/overlay-runtime-trellis/evidence/runtime-result.json`, report `/tmp/macapp-sun4u-003-overlay-runtime-trellis.md`. The relocated integration is host-tested, not another browser acceptance run.

**Writes, isolation under writes, durability and browser OS boot: NOT TESTED.** Temporary fd metadata is not a directly inspected block graph or overlay payload. This control neither diagnoses nor fixes the separate Wasm allocator failure. No compiled runtime, firmware, real ISO or generated fixture is included here. Source contract argv/pins are retained in `fixed-config.json`; historical producer status fields describe that source contract, not current acceptance.
