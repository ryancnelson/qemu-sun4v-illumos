# Trellis — native validation preparation

Status: READY, awaiting explicit validation-go with candidate artifact from Codex. No guest started. Sole diagnostic guest owner: Trellis. No new agents, CI, browser, pushes, or run136 access. Main checkout, existing evidence and original harness remain read-only.

## Verified inputs

Read task in full, command-guardrails and maestri skills, HBLK-CAPTURE-RESULT.md, HBLK-DECISIVE-TEST.md, analyze-sizing.py, capture-sizing.py, NEVADA-RESUME-20261024.md, diagnostic and current boot harness, and main build recipe. Ancestor AGENTS checks found none on relevant local workspace/data paths or Biggie home/devel; repository-level search found none for main repo.

Playbox live hashes:
- run132 firmware: 1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938
- original B134 ISO: c1ac3fb8bae47d4b8421d7a5506a33b05b1189c9ba731e0e560f78b140f228e0
- Docker image ID: sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f
- /usr/bin/qemu-system-sparc64: 902dc13a3dbc23a6057cd8f98109632fcbf11ad80a2ad6e0934f48b8b8305d40
- Original diagnostic harness and byte-identical isolated gate.sh: 978c87590a12989a0d33d8a655d1ec9dd30259e5bd5607f4cb6da7a9ff664102

QEMU digest was measured by a short-lived hash-only container with --cpus 1 --memory 2048m, no guest execution. ISO and baseline firmware read directly with sudo sha256sum. Image inspected with docker image inspect.

Playbox disk free: /mnt/disk-images 9.5GiB; root 5.1GiB. No disk or ISO copies needed. Source HEAD af97fd7af5e7c18f591a7b987291d3db4ffb28b5; existing modified files arch/sparc64/tree.fs, config/scripts/switch-arch, drivers/pci.c left untouched.

Main repo HEAD 2b66321a11365a483bf49f7852bfa0d7916e507f.
Build recipe SHA256 331421512532a070347f6f16b2851f5ea4aa99c0058b1f5a3bfcc1db34c4018b.
Existing patch hashes: 0001 081a01794255214efc6a5fb44f53e7ab0a80252419c3b7e85a57bd315e88c216; 0002 f85f0e4d95d0b99244545aff479790b245c65a837e32a04b5a314ad6808d8910.
Recipe pins source HEAD, applies those two patches, switch-arch sparc64, EXTRACFLAGS=-fno-stack-protector make, and rejects stack-canary TLS loads. Candidate provenance must include additional patch, final artifact hash, build output and source identity.

Offline replay executed unchanged: OBSERVED_EVIDENCE_ASSERTIONS_PASS=7; estimator 25131 pages, requested3167, capacity3185, low2987/high97 blocks, pre-kmem used3084. This is existing evidence, not a new baseline boot.

## Isolated evidence and exact commands (NOT EXECUTED)

Local /tmp/macapp-sun4u-001-trellis-evidence/gate.sh; playbox /mnt/disk-images/woodpecker/macapp-sun4u-001-trellis/gate.sh. Both hashes match above; bash -n passes. Root-owned parent required sudo mkdir of only this new directory followed by ownership assignment to niagara.

After validation-go only, commands below run on playbox via ~/bin/safe-bash SSH wrapper. Candidate artifact path and expected digest must arrive with go; verify sha256sum before invoking. Baseline and candidate are SEQUENTIAL, never concurrent. Use the single owned container name macapp-sun4u-001-trellis-guest. Preserve its inspect/logs before stop and remove only that stopped owned container before next run. No debugger mutation, kernel patch, disk creation or installation choices.

```bash
base=/mnt/disk-images/woodpecker/macapp-sun4u-001-trellis
mkdir "$base/baseline"
sudo env SUN4U_RAM_MIB=512 SUN4U_KEEP_CONTAINER=1 SUN4U_CONTAINER_NAME=macapp-sun4u-001-trellis-guest bash "$base/gate.sh" /mnt/disk-images/woodpecker/sun4u-openbios-132/artifacts/openbios-sparc64.patched "$base/baseline" >"$base/baseline/harness.log" 2>&1
# Save exit status immediately; capture even on failure:
sudo docker inspect macapp-sun4u-001-trellis-guest >"$base/baseline/container-final.json"
sudo docker logs macapp-sun4u-001-trellis-guest >"$base/baseline/docker.log" 2>&1
sudo docker stop -t 5 macapp-sun4u-001-trellis-guest
sudo docker inspect macapp-sun4u-001-trellis-guest >"$base/baseline/container-stopped.json"
# Confirm stopped, then remove ONLY this container to reuse its name.
sudo docker rm macapp-sun4u-001-trellis-guest

# CANDIDATE is exact artifact path from validation-go, with verified hash.
mkdir "$base/candidate"
sudo env SUN4U_RAM_MIB=512 SUN4U_KEEP_CONTAINER=1 SUN4U_CONTAINER_NAME=macapp-sun4u-001-trellis-guest bash "$base/gate.sh" "$CANDIDATE" "$base/candidate" >"$base/candidate/harness.log" 2>&1
# Same capture/stop sequence, substituting candidate for baseline.
```

The diagnostic harness is unchanged from prior experiment: -M sun4u, -m512, -smp1, --cpus1, --memory2048m, serial ttya, VGA/display disabled, ISO and firmware read-only mounts. Preserves power interrupts deletion and fdthree rename. Original keyboard46/language7/English/Configuring devices assertions remain intact. It includes a dormant GDB socket; no debugger attached. It preserves owned guest on failure for evidence collection using KEEP_CONTAINER=1. Its panic detector is older than current main harness: independently inspect complete console for any panic before declaring pass. Its hash-only preflight container is not resource capped; it executes only sha256sum and exits, no guest. Guest itself is capped.

Capture exit status, raw console, harness, Docker logs, inspect before/after stop, firmware/ISO/harness/log hashes. Recheck immutable inputs after test. Copy evidence to local isolated directory; retain remote raw evidence. Stop ONLY owned guest. Candidate artifacts/logs not yet available, so runtime verdict PENDING.

## Hypothesis / falsifier / verdict criteria

Hypothesis: candidate reporting coverage includes missing high virtual allocations and restores sufficient hblk sizing at512MiB. Baseline should reproduce nucleus hblk exhaustion. Candidate passes only with original keyboard46, language7, English, Configuring devices and absence of panic; early MMU progress alone insufficient. Panic, timeout, missing gate, hash mismatch or resource-control mismatch is failure/blocker, not success. A pass establishes early native installer boot/input only, not installed operation or a formal cross-architecture firmware contract. If one-total-guest interpretation is desired, use immutable seven-assertion baseline evidence and execute candidate only; default is one concurrent guest with sequential control per task text.

Next: Codex must send explicit validation-go and artifact path/hash/provenance. No guest launches until then.

## Refinement — supersedes baseline launch plan above

User refinement accepted: use existing baseline/replay; do NOT launch redundant baseline. Candidate-only diagnostic guest, approval hold until candidate hash AND this plan reviewed. Adapted own capture-candidate.py from read-only capture-sizing.py: removed exhaustion breakpoint and wait; detach immediately after before-kmem64 read. Socket operation timeout reduced from900 to180 seconds. Original source unchanged. Python compile check passes.

Exact capture sequence: hardware execution breakpoint at0x10136a0; capture o0 pointer/o1 count and count*16 available bytes; remove breakpoint. Capture all count-1 CPU-loaded entry/gap pairs at0x10136e8/0x10136fc (supports E14 virtual-read fallback). Capture estimator return at0x10196c8, pool request at0x101979c, translations at0x1016bd0, effective page size and pool used/capacity at0x1016f20. Every reached breakpoint removed before next one. Finally send D to detach and let original harness finish gate. No register or guest memory writes, no kernel perturbation. RSP commands limited to g/m/Z1/z1/c/D. Do not use old exhaustion-waiting script.

Candidate command replaces prior one with SUN4U_WAIT_DEBUGGER=1:
```bash
base=/mnt/disk-images/woodpecker/macapp-sun4u-001-trellis
# CANDIDATE assigned only to approved artifact; compare its sha256sum first.
mkdir "$base/candidate"
sudo env SUN4U_RAM_MIB=512 SUN4U_KEEP_CONTAINER=1 SUN4U_WAIT_DEBUGGER=1 SUN4U_CONTAINER_NAME=macapp-sun4u-001-trellis-guest bash "$base/gate.sh" "$CANDIDATE" "$base/candidate" >"$base/candidate/harness.log" 2>&1
# While harness waits at WAITING_FOR_DEBUGGER_MARKER, independent SSH command:
sudo python3 "$base/capture-candidate.py" "$base/candidate/debug.sock" "$base/candidate/debugger-ready" >"$base/candidate/capture.log" 2>&1
```

Run harness asynchronously; helper sets marker only after first breakpoint acknowledged. It captures before-kmem64, removes breakpoint and detaches; harness continues keyboard46/language7/English/Configuring devices. Capture expected under180s per debugger operation; harness gate timeouts remain original. If helper fails/timeouts with a possible live breakpoint, capture failure logs/inspect and stop ONLY own guest, do not claim success or attempt unreviewed state changes. Successful capture must contain detach OK and all expected labels. Preserve full raw RSP register/memory evidence, not merely summaries. Reconstruct candidate available list/gaps and compare estimator/pool-request to arithmetic, using actual candidate count and request values; existing analyzer has hardcoded baseline addresses/count expectations so is NOT a candidate validator. Quantify coverage of high VA claims and pool capacity vs pre-kmem usage. A gate pass lacking usable causality capture is a limited boot result, not full acceptance.

Adapted capture SHA256: 48bc24604d591d7e72aecb6d92086d557b80e87dc3f961d6179de2d847c5f5af. Exact original gate SHA256: 978c87590a12989a0d33d8a655d1ec9dd30259e5bd5607f4cb6da7a9ff664102. No runtime execution yet.

## Codex plan approval received

Codex reviewed and approved the exact candidate-only plan: unchanged gate, read-only hardware execution breakpoints through before-kmem64, remove breakpoints/detach, then full original input gate. Existing baseline sufficient. Approval is for plan only: HOLD remains until explicit validation-go supplies candidate artifact/hash. No guest has started. Only Trellis-owned guest may be operated. No guest register or memory writes will be performed. Original/adapted capture and gate hashes recorded in /tmp/macapp-sun4u-001-trellis-evidence/prelaunch-script-hashes.txt. Candidate artifact hash and final source/patch provenance remain pending; record and verify before launch.

## Transport robustness review correction

Preserved capture-candidate-v1.py locally and on playbox with SHA256 48bc24604d591d7e72aecb6d92086d557b80e87dc3f961d6179de2d847c5f5af. Current capture-candidate.py SHA256 dc9e74fcc238a6472a4bafe917b1c1b3cd9c2f5eb87059f8e2523f84fb0faaed. recv_exact now raises explicit EOFError on an empty receive during preamble, body, or checksum; checksum consumes exactly two bytes despite split reads and is verified. Five fake-transport tests pass: preamble EOF, body EOF, checksum EOF, mismatch, fragmented valid checksum. Syntax compile passes. An intermediate generation had a shell-quoting syntax error; it was never executed against a guest and was replaced with the compile-checked version.

External total deadlines are REQUIRED additions to the previously documented launch commands: harness runs as `sudo timeout --signal=TERM --kill-after=10s 2100s env SUN4U_RAM_MIB=512 SUN4U_KEEP_CONTAINER=1 SUN4U_WAIT_DEBUGGER=1 SUN4U_CONTAINER_NAME=macapp-sun4u-001-trellis-guest bash "$base/gate.sh" "$CANDIDATE" "$base/candidate"`; capture runs as `sudo timeout --signal=TERM --kill-after=5s 600s python3 "$base/capture-candidate.py" "$base/candidate/debug.sock" "$base/candidate/debugger-ready"`. Existing redirections remain as above. Playbox /usr/bin/timeout verified present. Thus capture bounded600s plus5s escalation, harness bounded2100s plus10s escalation, independent of180s per-operation socket timeout. Timeout/EOF/checksum error => failure evidence capture then stop only owned guest; no attempt to resume a possibly breakpoint-stopped guest. No guest memory/register writes. No guest started. Candidate v2/hash and final review pending; launch hold remains.

## Candidate artifact ready — NOT validation-go

Candidate supplied: /mnt/disk-images/woodpecker/macapp-sun4u-001-kestrel/artifacts/openbios-sparc64.candidate
Expected SHA256: a9c8162f7c2edf62c1fbcb38d9b308c43eae7f01aeb62aa41f54366ec4d94a6d.
Codex reports final common35138356… passes121 64-bit and119 mixed-width tests, recorded host toolchain provenance, linked reporting hook returns1<<43, TLS check passed. These are supplied build results, not independently reproduced here; full source hash/provenance still to record from final artifact report. Hardened capture hash dc9e74… and external timeout plan approved. Final Mica signoff and explicit validation-go remain pending. No guest started.

Exact candidate harness command on playbox after go only (run asynchronously and save exit status):
```bash
base=/mnt/disk-images/woodpecker/macapp-sun4u-001-trellis
CANDIDATE=/mnt/disk-images/woodpecker/macapp-sun4u-001-kestrel/artifacts/openbios-sparc64.candidate
printf "%s  %s\n" a9c8162f7c2edf62c1fbcb38d9b308c43eae7f01aeb62aa41f54366ec4d94a6d "$CANDIDATE" | sudo sha256sum -c -
mkdir "$base/candidate"
sudo timeout --signal=TERM --kill-after=10s 2100s env SUN4U_RAM_MIB=512 SUN4U_KEEP_CONTAINER=1 SUN4U_WAIT_DEBUGGER=1 SUN4U_CONTAINER_NAME=macapp-sun4u-001-trellis-guest bash "$base/gate.sh" "$CANDIDATE" "$base/candidate" >"$base/candidate/harness.log" 2>&1
printf "%s\n" "$?" >"$base/candidate/harness-exit-status.txt"
```
Separate SSH command once WAITING_FOR_DEBUGGER_MARKER appears:
```bash
base=/mnt/disk-images/woodpecker/macapp-sun4u-001-trellis
sudo timeout --signal=TERM --kill-after=5s 600s python3 "$base/capture-candidate.py" "$base/candidate/debug.sock" "$base/candidate/debugger-ready" >"$base/candidate/capture.log" 2>&1
printf "%s\n" "$?" >"$base/candidate/capture-exit-status.txt"
```
All prior ownership, capture/stop-only-own-guest, raw evidence, no memory/register writes and original gate requirements remain. Initial digest check must succeed before mkdir/launch; orchestrator enforces sequential success, not blind execution of all displayed lines.
Live read-only preflight: candidate digest independently matches a9c8162f7c2edf62c1fbcb38d9b308c43eae7f01aeb62aa41f54366ec4d94a6d. Free space remains9.5GiB data/5.1GiB root. Launch commands prepared only; not executed.

## VALIDATION-GO received; candidate running

Explicit go received with final Mica no-source-blocker review. Exact common source SHA256 supplied:3513835600a784cecbaa36e15ffdf82eba6ea844cd0919dcf4590eca7412db01;121/121 64bit,119/119 mixed-width,+2 hook link checks reported. Candidate, ISO, unchanged gate, hardened capture and Docker image hashes reverified immediately before launch. Harness additionally verifies actual QEMU digest before its guest launch. Started exactly one owned candidate guest macapp-sun4u-001-trellis-guest with approved2100s external harness timeout. WAITING_FOR_DEBUGGER_MARKER observed; capture launched with600s external timeout. No baseline guest. No guest memory/register writes. Runtime verdict pending.

# Final candidate result — FAIL, preserved separately

Tested ONLY artifact a9c8162f7c2edf62c1fbcb38d9b308c43eae7f01aeb62aa41f54366ec4d94a6d. No revisions or replacement artifacts in this evidence. No further guest authorized. Stopped container retained, NOT removed: macapp-sun4u-001-trellis-guest. Raw evidence local /tmp/macapp-sun4u-001-trellis-evidence/candidate and remote /mnt/disk-images/woodpecker/macapp-sun4u-001-trellis/candidate. Full local evidence SHA256 manifest: /tmp/macapp-sun4u-001-trellis-evidence/EVIDENCE-SHA256SUMS.

Observed panic: `panic - kernel: sfmmu_map_prom_mappings: inconsistent translation/avail lists`, followed by EXIT and OpenBIOS prompt. Original gate never reached keyboard selection. Harness exited1 with PANIC_DETECTED. Capture reached entry, all21 gap pairs, estimator return, pool request, and166 translations. It then waited for before-kmem64; that breakpoint was never reached. Because the guest had already panicked, captured raw logs/inspect and stopped only owned guest. Capture exited1 with ConnectionResetError upon owned guest stop; this is a teardown consequence, not the cause of kernel panic. No detach was reached. No guest register/memory writes were issued; hardware execution breakpoints only. A pending before-kmem64 breakpoint was terminated with the owned guest, no attempt to resume or mutate it.

Container state from retained stopped inspect: Running=false, Status=exited, OOMKilled=false, ExitCode=0 (QEMU termination, not boot success). Started2026-10-25T03:01:08.859788797Z; Finished2026-10-25T03:02:28.481131489Z. Memory2147483648 bytes, NanoCpus1000000000, QEMU -m512 -smp1 -M sun4u. Serial ttya, no VGA/display, no install disk. Before/after inspect, raw console/capture/harness/Docker logs and exit statuses retained.

Post-run immutable hashes unchanged: ISO c1ac3fb8bae47d4b8421d7a5506a33b05b1189c9ba731e0e560f78b140f228e0; tested firmware a9c8162f7c2edf62c1fbcb38d9b308c43eae7f01aeb62aa41f54366ec4d94a6d. Gate978c87590a12989a0d33d8a655d1ec9dd30259e5bd5607f4cb6da7a9ff664102; capture dc9e74fcc238a6472a4bafe917b1c1b3cd9c2f5eb87059f8e2523f84fb0faaed. QEMU/image pins previously recorded and gate enforced both before launch.

## Actual sizing and causal limits

Pre-sizing available pointer0xfef6d008,count22 (baseline8). Raw352 bytes captured twice identically. CPU-loaded pair/gap registers independently agree with every entry/gap. Estimator return27597 (0x6bcd), baseline25131. Requested hblk8=3491 (0xda3), hblk1=155 (0x9b), allocated bytes1105920 (0x10e000), pointer0x30000dde000. Offline arithmetic reproduces live request/bytes, iterations3450+17 plus2+22. Computed capacity3500 from rounded bytes and hblk1 storage; NOT directly read actual capacity, since before-kmem64 was never reached. No claim about actual pre-kmem64 usage.

Candidate list now covers high virtual claims through0x80000000000. This supports that reporting coverage changed sizing as intended, but runtime inconsistency falsifies acceptance of this artifact. The exact cause of panic remains unproven. Translation snapshot is later than available snapshot; overlaps caused by subsequent allocation are legitimate possibilities. Do not label every overlap a firmware inconsistency. In particular pool allocation at0x30000dde000 occurred after sizing. Full22 entries and all overlap intervals follow from independently replayed raw capture. Candidate analyzer source /tmp/macapp-sun4u-001-trellis-evidence/analyze-candidate.py; output candidate-analysis.txt. This is separate from unchanged baseline analyzer and assertions.

Build provenance snapshots retained as build-FINAL-SHA256SUMS and build-source-sha256.txt. Exact source hashes: common3513835600a784cecbaa36e15ffdf82eba6ea844cd0919dcf4590eca7412db01; header0d82a6a1c61ac241079a7da296c6a1f3f1c23a4c6dbd1ff639076140a9957480; sparc64 source37d660e88f12bf41e823ab8cc7ca69e892f6acf51a27b6068256edcac97ab33a. Candidate patch efb0a6f33abc91fd3ed978eb6e60e025c64daf71fbe8007fb173eea2093e6f94; complete-source patch8bcbe62b62463465f3d28be9a99286f2ccd10c9fcf73915a125f395412633d83. Host tests/reviewer acceptance do not override this runtime failure.

## Exact replay output

AVAILABLE count 22
0x0 0x1000000 end 0x1000000
0x1400000 0x2000 end 0x1402000
0x1436000 0x3ca000 end 0x1800000
0x1c80000 0x4a380000 end 0x4c000000
0x4c2aa000 0x3d56000 end 0x50000000
0x5018c000 0xe74000 end 0x51000000
0x5c6a8000 0x13958000 end 0x70000000
0x700c4000 0x8eea8000 end 0xfef6c000
0xff000000 0xd00000 end 0xffd00000
0xfff00000 0x2ff00102000 end 0x30000002000
0x30000036000 0xc000 end 0x30000042000
0x30000074000 0xe000 end 0x30000082000
0x300000d6000 0x30000 end 0x30000106000
0x3000022a000 0x2a000 end 0x30000254000
0x30000266000 0x3c000 end 0x300002a2000
0x300003ba000 0x10000 end 0x300003ca000
0x30000400000 0x800000 end 0x30000c00000
0x30000d30000 0x30000 end 0x30000d60000
0x30000d6c000 0x4000 end 0x30000d70000
0x30000d8c000 0x38000 end 0x30000dc4000
0x30000dde000 0x3ffff222000 end 0x70000000000
0x70000c00000 0xffff400000 end 0x80000000000
ESTIMATOR 27597 POOL_REQUEST 3491 BYTES 1105920 ARITHMETIC_CAPACITY 3500 iterations [3450, 17]
TRANSLATIONS 166
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0x2000 0x800000 [('0x2000', '0x802000')]
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0xfffce000 0x2000 [('0xfffce000', '0xfffd0000')]
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0xfffd0000 0x2000 [('0xfffd0000', '0xfffd2000')]
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0x30000036000 0x2000 [('0x30000036000', '0x30000038000')]
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0x30000038000 0x2000 [('0x30000038000', '0x3000003a000')]
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0x30000dde000 0x10e000 [('0x30000dde000', '0x30000eec000')]
TRANSLATION_OVERLAP_WITH_EARLIER_AVAILABLE 0x30000eee000 0x2000 [('0x30000eee000', '0x30000ef0000')]
NOTE earlier sizing list may legitimately differ after pool allocations; overlap alone is not proof of panic cause
CANDIDATE_REPLAY_PASS
110:/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|/-\|panic - kernel: sfmmu_map_prom_mappings: inconsistent translation/avail lists
112:EXIT

Failed artifact preserved independently under /tmp/macapp-sun4u-001-trellis-evidence/failed-artifact-provenance, including stripped/unstripped binaries, candidate/complete/base patches, build recipe/log, source/toolchain manifests. All11 entries of FINAL-SHA256SUMS verified OK on local copies. Future builds cannot overwrite this evidence. No new guest; retained stopped container remains available for read-only inspection.

## Next capture v3 prepared — no guest, pending review/go

Preserved tested v2 as capture-candidate-v2.py (dc9e74fcc238a6472a4bafe917b1c1b3cd9c2f5eb87059f8e2523f84fb0faaed). Failed raw evidence and firmware remain unchanged. Proposed v3 is separate file /tmp/macapp-sun4u-001-trellis-evidence/capture-candidate-v3.py, SHA256 cd8b86065a47c9b8c8fc66da70f04d86fe89f2089fd7b25a77e8be7c14be7388. Not launched or installed as active capture.

Read exact B134 unix offline with host gdb-multiarch, no target attached. Unix SHA2561cfa9322a08b4cd6ffaa9a1c748907fedd90ae051a40b8a71a906c47cc8dbd25. `info address virt_avail`:0x1846620, no debug type metadata. Checker disassembly at0x1016d3c loads8-byte pointer from that address;0x1016d4c calls overlap checker with o0=head,o1=translation current VA,o2=remaining size (delay slot). Exact copy_memlist/memlist_find disassembly establishes32-byte node, address0,size8,next16,prev24, all8-byte big-endian. Raw disassemblies/check-symbol output retained; no reliance on modern source type alone. Static self-target call at0x1016d4c is unresolved relocation in file, not claim of actual recursion.

V3 reads global and bounded linked list at existing0x1016bd0 translations entry stop, before resume, making it contemporaneous with captured translations. Logs raw bytes and decoded nodes; validates exact read length, next alignment, cycle/count limit256, previous links, nonempty list, nonzero size and64-bit endpoint bounds. Additional pool48-byte read at same stop allows direct capacity capture even if checker panics before-kmem64. No added breakpoint, register/memory write, or changed gate. Retains hardened RSP, external timeout requirements, later before-kmem64 detach. Failed required list read => explicit failure, not silently using stale pre-sizing list. Python compile plus5 mock-list checks pass (valid,cycle,prev,overflow,empty). Pending Mica layout confirmation and Codex exact script review then new explicit go. No new guest.

## Flint runtime addendum received; native hold unchanged

Read /tmp/macapp-sun4u-001-flint-runtime.md in full. Flint independently reports actual-v2-init/real-map_io SAME-TIME counterexample: VAfffce000 andfffd0000,size2000,PA1fe02002000/1fe02006000,mode1e remain available. Actual v3 architecture source SHA7dd74a6d3703d2741cbfde872cfe7011f86bcd414786fe463d54adbbea249a68 reserves virtual I/O arena[fffce000,fffd6000) before inherited boot maps, and real-C lifecycle excludes mappings while preserving autofeffe000, original two-I/O allocation order, and no additional physical claim. Common remains3513835600a784cecbaa36e15ffdf82eba6ea844cd0919dcf4590eca7412db01. Source/test/log/executable manifest located under work/maestro-sun4u-001/tests/runtime-counterexample/SHA256SUMS-runtime. These are Flint host lifecycle findings, not Trellis native proof or independently repeated tests. Frozen failed v2 native artifact/raw evidence unchanged. V3 firmware build and final independent review pending; no validation-go, no new guest. Maestro positively reviewed capture v3; pending independent confirmation is not bypassed.

## Mica independent capture-v3 confirmation completed

Mica confirms exact B134 virt_avail0x1846620 is u64 list head;32-byte nodes with address/size/next/prev offsets0/8/16/24 from copy_memlist; capture point0x1016bd0 correct. Capture-v3 review complete, no blocker. Approved script hash remains cd8b86065a47c9b8c8fc66da70f04d86fe89f2089fd7b25a77e8be7c14be7388. No guest launched. Final firmware-v3 independent review/build artifact hash and explicit validation-go still required.

## Explicit checkpoint HOLD
All native/build/new work paused at safe boundary by Ryan/Codex request. Exact session/process/status checkpoint saved to /tmp/macapp-permissions-trellis.md. No Maestri callback, no configuration changes, no process stops. Await supported resume and release of hold.

## V3 VALIDATION-GO — running

Ryan explicitly released coordinated hold and authorized one v3 run. Exact resumed thread01a170e2-5ae5-7c70-a979-efa6147dc018 / terminal242FD388-271E-45B0-9607-4C528AB55B24 verified; actual Codex command includes --no-daemon --ask-for-approval never --sandbox danger-full-access resume same UUID. Saved /tmp/macapp-permissions-trellis-verified.md. No config changes.

Preflight candidate4bb44a805d3d1cfb3b3150189b5d4f828d2b086b19ccc5eecce9570316532ecb, ISOc1ac3fb8…, gate978c8759…, capture-v3cd8b8606…, image56dac302… all match exact approved hashes. Gate independently verifies QEMU902dc13a… before launch. Free data9.4GiB/root5.1GiB.

ACTUAL guest start2026-10-25T03:28:21.440000202Z; container macapp-sun4u-001-trellis-v3-guest, ID2344f0905f76ed746c679b81be521dff2192c32d583a32e53320b2bfe3cca8ac. Fresh remote evidence /mnt/disk-images/woodpecker/macapp-sun4u-001-trellis/candidate-v3. One guest only,512MiB/1CPU/2GiB,2100s+10s harness,600s+5s capture. WAITING_FOR_DEBUGGER_MARKER observed, reviewed capture-v3 launched. Same-time virt_avail/translations/pool before before-kmem64/detach and original gate. No register/memory writes. Failed v2 guest/evidence retained untouched. Runtime result pending.

V3 capture completed with detach OK and exit0. Replay passes:165 checked translations disjoint from SAME-TIME virt_avail; I/O arena excluded. Direct pool capacity3500, translations-entry used0, before-kmem64 used3085. Effective page code0, kmem64[0x70000000000,0x70000942000),149 additional64KiB hblk spans; predicted post-kmem3234,margin266 (post-kmem counter NOT CAPTURED). Guest passed former panic points; original gate still pending. No guest writes.

# V3 FINAL VERDICT: PASS_FULL (512 MiB original native boot/input gate)

Exactly one authorized v3 guest ran. No second guest. Start2026-10-25T03:28:21.440000202Z, stop2026-10-25T03:31:41.702083045Z; macapp-sun4u-001-trellis-v3-guest ID2344f0905f76ed746c679b81be521dff2192c32d583a32e53320b2bfe3cca8ac. Preserved stopped container: Running=false, Status=exited, OOMKilled=false, ExitCode=0. Capture exit0 and harness exit0. v2 stopped container and all failed evidence remain intact. Mac app owns next1088/index0 media replay; Trellis performs none.

## Acceptance evidence

Full raw final bundle LOCAL /tmp/macapp-sun4u-001-trellis-evidence/candidate-v3/; REMOTE /mnt/disk-images/woodpecker/macapp-sun4u-001-trellis/candidate-v3/. Includes console.log, capture.log, harness.log, docker.log, container-started.json, container-inspect-running.json, container-final.json, container-stopped.json, container-id.txt, capture-exit-status.txt, harness-exit-status.txt, immutable-after.sha256, original harness SHA256SUMS. Supporting replay script analyze-v3.py and output v3-analysis.txt in local evidence root; independent preserved v3 build/firmware provenance in v3-artifact-provenance/ (all10 FINAL-SHA256SUMS entries verified). Final V3-ACCEPTANCE-SHA256SUMS manifest covers v3 bundle, replay, exact capture/gate and v3 provenance. No socket files copied.

Console lines266: keyboard prompt and46;279: language prompt and7;280: User selected: English;281: Configuring devices. Harness SUN4U_OPENBIOS_BOOT=PASS and original pcipsy/ebus/su path assertions. Full console screened for panic/maintenance/hblk exhaustion: none. Hardware breakpoint capture completed before input gate and explicitly logged detach OK. No guest register or memory writes. Only original keyboard/language choices sent, no installer disk or later choices. Docker verifies Memory2147483648/NanoCpus1000000000 with QEMU-m512/-smp1; all pinned controls retained.

## Causality results

Actual pre-sizing list23 entries, current checker list22 entries. All sizing pairs/gaps verified against CPU registers. Estimator27601pages, recursive request3493 hblk8 and155 hblk1,1105920bytes (0x10e000), requested pointer0x30000dde000. Arithmetic iterations3451+17 plus2+23 reproduce exact request/bytes. Direct capacity3500 matches prediction. At translations entry used0; before-kmem64 used3085. All166 translations captured;165 at/above0x1000000 subject to B134 checking are disjoint from contemporaneous virt_avail. Low direct map excluded according to checker semantics. I/O arena[0xfffce000,0xfffd6000) excluded from both snapshots. All ranges sorted, positive, nonoverlapping and within[0,0x80000000000).

Effective kmem page code0 (8KiB), base0x70000000000/end0x70000942000. Translation-derived imported hblk set count3085 equals actual pre-kmem usage. Kmem span149 additional64KiB hblk records; predicted post-kmem3234,margin266. Post-kmem counter NOT CAPTURED; this is prediction supported by completed gate, not a direct final counter measurement. Usable physical page count NOT CAPTURED. Complete exact lists and replay follow in v3-analysis.txt.

Hypothesis supported for this512MiB original gate: reporting high allocations increases sizing vs baseline25131/request3167/cap3185, while I/O arena exclusion prevents the v2 same-time inconsistency; actual v3 sizing yields enough small-page capacity and full original input success. Broader RAM matrix, installation, installed boot, browser execution and universal Open Firmware contract remain untested here. Mica independently reviewing raw capture; this report records Trellis replay, not an assumed completed external review.

## Exact immutable post-run hashes

- Firmware4bb44a805d3d1cfb3b3150189b5d4f828d2b086b19ccc5eecce9570316532ecb
- ISOc1ac3fb8bae47d4b8421d7a5506a33b05b1189c9ba731e0e560f78b140f228e0
- Capturecd8b86065a47c9b8c8fc66da70f04d86fe89f2089fd7b25a77e8be7c14be7388
- Gate978c87590a12989a0d33d8a655d1ec9dd30259e5bd5607f4cb6da7a9ff664102

All match preflight. QEMU902dc13a3dbc23a6057cd8f98109632fcbf11ad80a2ad6e0934f48b8b8305d40 and image sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f enforced by unchanged gate. Source common3513835600a784cecbaa36e15ffdf82eba6ea844cd0919dcf4590eca7412db01; arch7dd74a6d3703d2741cbfde872cfe7011f86bcd414786fe463d54adbbea249a68; exact patch/source/toolchain manifest retained in v3-artifact-provenance.

V3 acceptance manifest SHA25624015cca83bacff322b156dcb29981147bd380f3f701cf7087de5b953f8339d0; all29 listed files verified OK. Final report saved. No second guest or housekeeping dependency.
