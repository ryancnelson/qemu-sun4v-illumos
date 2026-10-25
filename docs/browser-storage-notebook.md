# Project notebook: browser unique-sector storage control

Task002 storage evidence, 2026-10-25. Integrated from the reviewed Flint draft; existing NEVADA notes are unchanged. Trellis owns runtime; Kestrel owns allocator diagnostics.

## Actual progress

**SIX_READ_STORAGE_CONTROL_PASS_NOT_BOOT_OR_ALLOCATOR_PROOF**, completed in the same Trellis-owned run. All six64-byte captures match their requested offsets; all five seeks returned0 and all six reads returned40hex. Raw console documents first close, nonzero reopen fef85db0, second close and free-mem returning normal prompts. Saved A–F binaries were independently compared with frozen image slices for this revision. No resend or restart.

Final configuration from result.json: sun4u, guest512MiB,1CPU, tcg tb-size64/thread=multi, no VGA/display/monitor/network, serialstdio, auto-boot?false, readonly raw IDE CD index0. Prepared firmware/Wasm pins below remain the recorded input identities.

**Timing negative:** E's initial snapshot was incomplete and its decoder failed closed; empty E-compare.txt is not a PASS artifact. A later read-only snapshot verified the already-issued E bytes before F. Owner authorized F continuation in the same session; E was not resent. This demonstrates that an early snapshot can be incomplete, not a storage short-read or proven runtime fault. It establishes no fixed wait duration or general completion-timing guarantee.

Final evidence: browser-sector-control-trellis/evidence/result.json and raw-console.txt. Raw SHA256 b0459ffa21bb0688e705597c7ada6131abbcb331372000ce6759000ad352bc05 independently verified. Earlier preparation.json status PREPARED_NOT_EXECUTED is historical preparation metadata, superseded by this actual result. Historical A-only draft SHA256 c76356e3352421cecb80d9c800be89aa938f7ad065b45c29ab925516d39dfac1.

|Block|Requested offset(hex)|Length(decimal)|Operation|Actual|
|---|---:|---:|---|---|
|A|0|64|seek/read|PASS|
|B|100|64|distinct first-sector offset|PASS|
|C|7e0|64|cross-sector|PASS|
|D|820|64|sequential after C; no seek|PASS|
|E|800|64|close/reopen then seek|PASS|
|F|7fc0|64|last64 bytes|PASS|

## Inputs and host evidence

Frozen32768-byte image has16 sectors of2048 bytes and is not bootable. Each32-byte record contains S4U2SENT, absolute offset BE64, sector BE32, slot BE32 and8 SHA256-derived bytes. All32705 overlapping64-byte windows differ. This distinguishes wrong-offset256 and sector-alias2048 returns that the old repeating00..ff image could hide. One-byte uniqueness is not promised.

Mica independently approved8/8 host tests including uniqueness, wrong-offset/sector-alias, truncation/extra/corruption and bounds. check_contract.py statically verifies six command offsets/bytes, cursor progression, two open/close lifetimes, five seeks/six dumps and end bound. These tests do not execute firmware.

Prepared firmware1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938; Wasm424346e400e987381270ab05472a1dd123212f20c4dc3dd478d9f4c41a2a1155; storage source37466aa140b02683ac0b7c0ec2fd0b5ace19d5cff94cf76d8fbfa6f9eaa4dd76. Native1537670b is distinct and untouched. Preparation pins do not replace final runtime configuration evidence.

## Reproduction contract

Authorized by /tmp/macapp-sun4u-002-next-diagnostic-2018.md: one reviewed control, Trellis sole runtime owner. This draft does not request another run. Use the frozen image in the separate readonly IDE_CD configuration. Exact observed path is /pci@1f,0/pci@1,1/ide@3/ide@0/cdrom@0; no cdrom alias assumed.

Transcript below is INTERACTIVE: send only through the next CHECK, verify, then continue. Never paste/load it as an unattended script. CHECK comments are external hard gates, not executable assertions. All numbers are hex:40=64decimal,800=2048decimal. seek is low-cell then high-cell0 and must return0, supported by exact132 deblk_seek. Each read must return40hex; compare all64 decoded bytes at the requested offset before the next operation.

Stop on zero allocation/handle, error/trap, missing output, nonzero seek, unexpected/short read or byte mismatch. Preserve evidence; no blind cleanup through failed or closed handles. A reopened handle may reuse the same numeric value. Total read384 bytes; maximum end8000hex; no EOF/boot/write.

```forth
\ OWNER INTERACTIVE: one block at a time; NEVER paste whole file.
\ Every CHECK is a hard external gate; stop on any mismatch/error/trap.
hex
800 alloc-mem dup . constant s2buf
\ CHECK buffer nonzero; otherwise STOP.
" /pci@1f,0/pci@1,1/ide@3/ide@0/cdrom@0" open-dev dup . constant s2h1
\ CHECK handle nonzero; otherwise STOP.
\ BLOCK A requested absolute offset 0x0; length 0x40 (64 decimal).
0 0 " seek" s2h1 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block A at REQUESTED offset; otherwise STOP.
\ BLOCK B requested absolute offset 0x100; length 0x40 (64 decimal).
100 0 " seek" s2h1 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block B at REQUESTED offset; otherwise STOP.
\ BLOCK C requested absolute offset 0x7e0; length 0x40 (64 decimal).
7e0 0 " seek" s2h1 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block C at REQUESTED offset; otherwise STOP.
\ BLOCK D requested absolute offset 0x820; length 0x40 (64 decimal).
\ NO SEEK: successful C advanced position from 0x7e0 to 0x820.
s2buf 40 " read" s2h1 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block D at REQUESTED offset; otherwise STOP.
s2h1 close-dev
\ CHECK normal prompt, no error; first handle is now closed.
" /pci@1f,0/pci@1,1/ide@3/ide@0/cdrom@0" open-dev dup . constant s2h2
\ CHECK new handle nonzero; may numerically equal old handle.
\ BLOCK E requested absolute offset 0x800; length 0x40 (64 decimal).
800 0 " seek" s2h2 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h2 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block E at REQUESTED offset; otherwise STOP.
\ BLOCK F requested absolute offset 0x7fc0; length 0x40 (64 decimal).
7fc0 0 " seek" s2h2 $call-method .
\ CHECK seek returns 0 before read.
s2buf 40 " read" s2h2 $call-method .
\ CHECK read returns 40 HEX before dump; otherwise STOP.
s2buf 40 dump
\ CHECK all 64 decoded bytes against expected.json block F at REQUESTED offset; otherwise STOP.
s2h2 close-dev
\ CHECK normal prompt, no error.
s2buf 800 free-mem
\ END storage control only; no boot command.
```

Decode only64 payload bytes from each dump, excluding address/ASCII columns, retaining raw console. Do not infer expected offset from the returned embedded tag. Exact golden bytes are in sector-control-flint/expected.json.

From task002 root, using owner-decoded captures:
```sh
python3 sector-sentinel-flint/sentinel.py verify capture-A.bin --offset 0x0 --length 64
python3 sector-sentinel-flint/sentinel.py verify capture-B.bin --offset 0x100 --length 64
python3 sector-sentinel-flint/sentinel.py verify capture-C.bin --offset 0x7e0 --length 64
python3 sector-sentinel-flint/sentinel.py verify capture-D.bin --offset 0x820 --length 64
python3 sector-sentinel-flint/sentinel.py verify capture-E.bin --offset 0x800 --length 64
python3 sector-sentinel-flint/sentinel.py verify capture-F.bin --offset 0x7fc0 --length 64
```

## Interpretation limits

This six-read success establishes only these partial/offset/sequential/reopen operations in this configuration. It would not prove bootability, every EOF behavior, generic allocator health or every loader path.

The separate frozen1MiB ISO-prefix -H experiment failed with Wasm OOB and no H-halt marker. Owner/DWARF source correction maps the g_malloc0 caller to core.c708 req=g_new0(IDEBufferedRequest,1), constant44-byte metadata, NOT later payload blk_blockalign(iov->size). Transfer size and truncation are not established causes. Kestrel owns allocator diagnostics; no additional replay or investigation is initiated here.

Exact132 source snapshot boot-media-flint/boundary/exact132-sources.json SHA2566eb55f7a82472ef188940f9b2c71054201693f5df984965b03155945c3a79e06 supports seek contract. Earlier real-C boundary tests contain backend stubs and are separate from browser runtime. No native guest/checkpoint, fixture, media, shared notes or runtime changes by Flint.

## Exact evidence hashes

Paths relative to work/maestro-sun4u-002. Runtime evidence belongs to Trellis and was read-only. Final result/raw hashes and all six captures are included; this draft does not alter runtime evidence.

- sector-sentinel-flint/sentinel-32k.raw — 52fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5
- sector-sentinel-flint/sentinel.py — e0dae80917f2b6d2240342a5e56c41821997bdc9c8ceaeec7c621b3a189a72a5
- sector-sentinel-flint/test_sentinel.py — add0f7abc9ee694e04d85069512e741c71c0f092a1cea0c372635fea390bccac
- sector-sentinel-flint/manifest.json — 926a1f430308d54be1a6c2d1ca10b651f6378389d64df598961d063802b36dad
- sector-control-flint/storage-control.fth — 1f20843b749c8fc3651ac633ccfc8a942d7abc6ba412c8bedf1aa431118ac698
- sector-control-flint/expected.json — 8aa3988f3e5e124156229d0b748019d58a5581ea3e0306f8641c881a5478eb71
- sector-control-flint/check_contract.py — b797bbf73bc21e874c26bfc828e7a0ee434d223b11696f78a20d177494e3e196
- browser-sector-control-trellis/preparation.json — 004bf30a915cab97059ccaf07feec3f4267c7fba0a06a0d8b1b76fb89b3311f0
- browser-sector-control-trellis/evidence/A-page.txt — aa1cfb3102d22eda13405008cbcd73ffb1ced0ba52b1d1b18f82b9a8b203dad6
- browser-sector-control-trellis/evidence/A.bin — 462ea30f611f4bd60db39ba27b4916c4958af7b59d3146e7c07144e4b7135d6c
- browser-sector-control-trellis/evidence/A-compare.txt — d70f4de33f7e2c14b2af66c8fb3deee4f3d363cdf5dd7643bc96b90e2294ee62
- browser-sector-control-trellis/evidence/result.json — 73d0def3a37f7263a8fb504eb5d2143a3d31e342b9123e3ca1b54a2ea7fcbd6e
- browser-sector-control-trellis/evidence/raw-console.txt — b0459ffa21bb0688e705597c7ada6131abbcb331372000ce6759000ad352bc05
- browser-sector-control-trellis/evidence/E-page.txt — 928cdd8478476226845e9d6f28464d1fcee6ceb17fa7c299a1541c90d3f2fcb8
- browser-sector-control-trellis/evidence/E-compare.txt — e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
- browser-sector-control-trellis/evidence/E-later-page.txt — 0d4933e5b5040b9993b7f1bfd97b86efea96f28600c1b1cf4613d25d80be3753
- browser-sector-control-trellis/evidence/E-later-compare.txt — ba7b844e78a3260c500d3ea0b9286cd1f4b7f0f5813fb86731aaa97265453c61
- browser-sector-control-trellis/evidence/final-page.txt — e85388d95f5de80d9b74ba0bffac75b1364acdaa4390eb9fa5261de41016b9ad
- browser-sector-control-trellis/evidence/B.bin — 01ad438696be1ba5712af6a4277280d8272d7ff28b29c0c10e9f9de8dcaf6ed0
- browser-sector-control-trellis/evidence/C.bin — 3ba29599f2233f652930c73b83afc4603209bcc37982956f2eecbc6110b1380c
- browser-sector-control-trellis/evidence/D.bin — a749fedbee84c271ec4d9d6ea175afe07831ef0cc2b7139367681b1b0c4230c6
- browser-sector-control-trellis/evidence/E.bin — d204cc784c63b6c52b2757b1427e38c7f48f39729b70b8036514cf32095c7533
- browser-sector-control-trellis/evidence/F.bin — ce76a60b4d5eadf4a97f1799e2411b13ab2c54be899e97dbf0fb318252490c51

## Source packaging revision

Separate storage-integration-flint/tools/browser-sparc64/sentinel handoff regenerates exact assets/sentinel-32k.raw in private temporary scratch; no binary bundled. Existing validator can invoke python3 /src/tools/browser-sparc64/sentinel/check.py with /src read-only. Exact manifest bytes and image pin verified;8/8 host tests plus static contract PASS. Node harness tests need their own writable private harness copy and generator output into its assets directory, not /src; Codex owns that integration. No new workflow/runtime/allocator work. Negative controls include wrong-offset/sector aliases, truncation/extra/corruption, invalid bounds and overwrite refusal. No CI pass claimed.

## Repository reproduction and preserved evidence

Run `python3 scripts/validate-browser-assets.py` for host validation. The packaged generator and interactive contract are in `tools/browser-sparc64/sentinel/`. For manual writable-checkout setup: `mkdir -p tools/browser-sparc64/assets` then `python3 tools/browser-sparc64/sentinel/sentinel.py generate tools/browser-sparc64/assets/sentinel-32k.raw`. Existing output is refused, never overwritten. The raw console, result, six 64-byte captures, and E timing-negative snapshots are preserved under `artifacts/browser-storage-20261025/` with SHA256SUMS. Historical work paths above identify original provenance; not all intermediate pages are repackaged. No new browser run is part of this integration.
