# Read-only browser storage control

Generate the frozen 32768-byte sentinel with `python3 tools/browser-sparc64/sentinel/sentinel.py generate` at `tools/browser-sparc64/assets/sentinel-32k.raw`. Require SHA256 `52fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5`. No ISO or Wasm binary is included by this change.

Run `node --test tools/browser-sparc64/test-config.mjs tools/browser-sparc64/test-terminal-input.mjs tools/browser-sparc64/test-storage.mjs` after generating the fixture. These are host tests, not a browser run.

Use the existing loopback `serve.py` and v2 artifact importer. The default URL remains firmware-only, with no image fetch or drive. Explicit `?storage=sentinel` validates length/hash before MEMFS injection and attaches only a fixed raw read-only IDE CD-ROM. MEMFS remains mutable; QEMU's `readonly=on` enforces block read-only access. IDE hard-disk `readonly=on` was rejected before firmware and is not fixed by this feature.

For manual storage control, use Flint's reviewed interactive `storage-control.fth` and `expected.json` contract (hashes `1f20843b749c8fc3651ac633ccfc8a942d7abc6ba412c8bedf1aa431118ac698` and `8aa3988f3e5e124156229d0b748019d58a5581ea3e0306f8641c881a5478eb71`). Send one command through each CHECK, never the whole file. Its short-command sequence allocates `800` hex bytes, opens `/pci@1f,0/pci@1,1/ide@3/ide@0/cdrom@0`, seeks and reads `40` hex bytes at offsets `0`, `100`, `7e0`, sequential `820`, closes/reopens for `800`, then reads `7fc0`. Validate seek0/read40 and all64 decoded bytes at the requested offset before advancing. Close/free only after successful checks. No boot or EOF test.

Wait for the **current command's completed prompt and dump**, not a byte substring that may already exist in an earlier dump. The recorded run's E snapshot initially arrived early; the decoder stopped, a later read-only snapshot verified E, and owner authorized F continuation in the same session without resending E. Both snapshots remain evidence.

Recorded baseline: v2 Wasm `424346e400e987381270ab05472a1dd123212f20c4dc3dd478d9f4c41a2a1155`, run132 firmware `1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938`,512MiB/oneCPU. Six reads/384 bytes passed; raw console SHA256 `b0459ffa21bb0688e705597c7ada6131abbcb331372000ce6759000ad352bc05`. Durable source evidence: `work/maestro-sun4u-002/browser-sector-control-trellis/evidence/result.json`; report `/tmp/macapp-sun4u-002-browser-storage-trellis.md`. This integration revision is host-tested only; the recorded browser execution used its predecessor fixed-input configuration.

This proves those storage reads, not loader/kernel boot, allocator health, ATA behavior or large-media feasibility. The separate real1MiB `-H` loader trials still trap in Wasm. Default FS.writeFile copies the image; source buffer and MEMFS copy coexist in addition to the fixed1879048192-byte shared heap. No RSS/peak-memory claim. Allocator diagnosis remains a separate blocked lane; this patch neither retries nor replaces it.

See [the recorded storage notebook](browser-storage-notebook.md) and the packaged `tools/browser-sparc64/sentinel/` contract. CI uses temporary regeneration, not a committed raw image.
