# Mica independent v3 native acceptance review

Verdict: PASS for the scoped native 512MiB early installer boot/input gate, with independently replayed sizing and contemporaneous translation/available consistency. No blocker found in these supplied raw captures. This does not establish installation, installed operation, browser execution, every RAM size, or complete IEEE1275 address-space compliance.

Read actual candidate-v3 capture.log, console.log, harness.log, statuses and Docker inspect artifacts beneath /tmp/macapp-sun4u-001-trellis-evidence/. Reviewed analyze-v3.py/v3-analysis.txt but did NOT rely solely on their decoded node labels or summary. Own independent offline verifier saved at /tmp/macapp-sun4u-001-mica-v3-replay.py; ran with ~/bin/safe-bash. No guest commands, new run, source edits, build or Docker execution.

## Raw verification and exact B134 consumer

Decoded the 23-record pre-sizing available property directly from captured raw bytes pointed to by entry o0; count matched entry o1. Verified all22 CPU pair/gap register captures against those bytes. Verified breakpoint PCs entry0x10136a0, translations0x1016bd0 and before-kmem640x1016f20.

Independently read captured raw 8-byte global0x1846620, yielding head0x1960600. Followed raw32-byte linked nodes using +0 address,+8 size,+0x10 next,+0x18 prev. Checked no cycles, valid back-links and null termination:22 nodes. These offsets come from earlier exact B134 copy_memlist disassembly, not guessed contemporary illumos layout. Decoded all166 translation records by captured pointer+24*i; one mapping starts below0x1000000 and is skipped by exact B134 import predicate. All165 checked translations are disjoint from contemporaneous available intervals. This is STRONGER than exact B134 address_in_memlist's full-containment predicate and rules out containment for each remaining-page suffix checked during import.

Both old failing MMIO translations remain present with exact TTEs:

|VA|Bytes|TTE|
|---|---|---|
|0xfffce000|0x2000|0x800001fe0200201e|
|0xfffd0000|0x2000|0x800001fe0200601e|

The entire [0xfffce000,0xfffd6000) arena is excluded from BOTH pre-sizing and contemporaneous available sets. Relevant available intervals end at0xfffce000 and resume at0xfffd6000. This fixes the concrete v2 inconsistency without dropping the real device translations. All available intervals are page-aligned, positive, sorted, disjoint and end at or below exclusive0x80000000000; canonical hole/upper space are not advertised.

High claims are visible as gaps. Kmem reservation excludes [0x70000000000,0x70000c00000) and tail resumes at0x70000c00000 through0x80000000000. Actual effective kmem64 mapping span is narrower, [0x70000000000,0x70000942000). The distinction matters: the estimator counts reserved gaps, not only actually mapped pages. There are144 high translation records at/above0x30000000000, and all relevant entries are disjoint from the CURRENT list. Newly allocated hblk pool at0x30000dde000 is excluded from that list; its earlier pre-sizing availability was legitimate chronology, not an inconsistency.

## Observed versus predicted

|Quantity|Independent calculation|Raw observation|
|---|---|---|
|Pre-sizing available count|23 records|entry o1=23|
|Allocated pages from inter-record gaps|27601|estimator return o0=27601|
|hblk1 request|input155|pool-request i3=155|
|hblk8 request|3493 (recursive contributions3451,17 plus2+23)|pool-request i2=3493|
|Pool allocation|0x10e000 =1105920 bytes|pool-request i1=0x10e000|
|Actual hblk8 capacity|floor((1105920-155*88)/312)=3500|raw pool capacity3500 at both captures|
|Usage at translation entry|not predicted|raw used0|
|Usage before kmem64|3085 distinct64KiB mapping blocks after existing nucleus exclusions|raw used3085|
|Effective kmem64 page code|small-page expectation|before-kmem64 i3=0 (8KiB)|
|Additional kmem64 blocks|149|not directly captured after mapping|
|Post-kmem64 usage|3234 predicted|NOT captured|
|Post-kmem64 spare capacity|266 predicted|NOT captured|

Sizing replay follows exact B134 consumer: sum ceil(gap/8192), add ceil(nhblk1*88/8192), recursively budget hblk8 blocks/own pages, add2 plus available count, page-round total bytes. No architectural-hole subtraction applies because no available entry reaches upper canonical space. Verified exact input values against register captures, not just arithmetic copied from summary.

The3085 block replay excludes initial nucleus entries at0x1000000 and0x1800000 as in prior binary-correlated analysis. It agrees exactly with raw pre-kmem usage. Existing baseline observed capacity3185/pre-kmem3084; v3 observed capacity3500/pre-kmem3085. The larger pool itself adds one mapping block. Do not promote predicted3234 into measured post-kmem state. Kmem64 span needs149 additional blocks, so modeled demand is safely below capacity; full gate supplies separate runtime evidence that import/kmem takeover completed.

## Gate and provenance

Raw console contains keyboard selection, language selection7, `User selected: English`, and `Configuring devices.`; no panic or observed maintenance marker. Harness log emits SUN4U_OPENBIOS_BOOT=PASS; capture and harness exit-status files both0; capture has detach OK. No installation inference from later pseudo-device messages.

Read container-started.json: -M sun4u,-m512,-smp1,-vga none,serial ttya,CD-ROM original ISO; HostConfig.Memory2147483648 and NanoCpus1000000000. Evidence hash manifest records candidate4bb44a805d3d1cfb3b3150189b5d4f828d2b086b19ccc5eecce9570316532ecb, unchanged ISOc1ac3fb8bae47d4b8421d7a5506a33b05b1189c9ba731e0e560f78b140f228e0, capture scriptcd8b86065a47c9b8c8fc66da70f04d86fe89f2089fd7b25a77e8be7c14be7388 and gate978c87590a12989a0d33d8a655d1ec9dd30259e5bd5607f4cb6da7a9ff664102. These manifest claims were read from preserved owner evidence; this review did not reconnect to guest or rehash remote firmware/ISO. Full build provenance remains Kestrel/Maestro responsibility.

Independently hashed local raw evidence:

- capture.log: efaf803d8a720120debbb57f785ae3bb965fcbf0715c0ba8e506164182800465
- console.log: c0c13f08c54c568c83f90ed292cb2dec04573246f2e9f22485e963189cd28253
- harness.log: 4417c5acf5c39110d2e777cbadbd67c5c218fc988174377e2d5c9e1ad177f1d9

Remaining limitations: usable physmem and post-kmem pool index not captured; no native cross-RAM/non-SPARC matrix; no generic fix for upper-canonical reporting, release refresh or all map-without-claim paths. Current same-time disjointness is concrete evidence for this executed run. CI outcome-hardening review is separate and its base patch remains blocked; it does not invalidate the explicitly inspected preserved native logs or authorize any new guest. Mac app owns next media guest after Trellis.
