# Dad plus topology firmware — R2 build PASS

Artifact /mnt/disk-images/woodpecker/firmware132-dad-topology-kestrel/artifacts/openbios-sparc64.candidate
SHA2561537670b70680bfe286969a6e246142aff29ab13cd90405d1787a601295e9a5e,1593408bytes.
Unstripped sibling .nostrip SHA25656e4e493019d80a58dea462d1e8e25cc3d2fd7b298e11dced47cd8cc11d0db50,2173904bytes.
No VM, installed disk access, deployment or native acceptance claimed.

Full exact frozen e235 source copied into NEW isolated firmware132-dad-topology-kestrel/openbios; all688 tracked files pinned, full non-Git copy content compared. Only copied generated objects/config removed for initial build. Inherited original132 tree.fs/pci.c/switch-arch changes plus tokenfix and dad-compatible are preserved. No0003 available-ranges change. Frozen e235 tree rehashed unchanged after build; candidate688files match final manifest and ONLYdrivers/ide.c differs. Underlying Git commit af97fd7af5e7c18f591a7b987291d3db4ffb28b5 is intentionally dirty; full base/final patches saved.

Final source042e902414b127471adfdbbe53932d53b67c0952d24d03e55412ec5a5788bab6.
Final patch vs e23503be4b55e5634c5a816208b01482432a22bf4d6e20285b7814f648ca62582064, localr2/topology-on-dad.patch, remote topology-on-dad-r2.patch.
Mica scoped source and declaration approvals relayed by owner; no other source alteration.

R1 source9f7578e7 and patchdb62c961 compiled under mocked constructor fixture but real firmware FAILED: missing DECLARE_UNNAMED_NODE metadata for new table. Preserve r1-failed/ remote with original source/log/manifests; original local source and64-case evidence remain. This is a genuine fixture limitation, not a successful R1 build.
R2 adds exactly DECLARE_UNNAMED_NODE(ob_ide_sun4u_ctrl,0,sizeof(int)), same existing controller flags/instance size. Declaration-only patch1888fc0f18c4e94bd3bc7ea06f5388fa2da0d09e80b9aef30ac7ed72228e270a. New test_bindings.py uses actual pinned bindings.h macros and actual method table, confirms R1 compile failure for flags_/size_ and R2 compile/runtime metadata PASS. Header18ea4ea328235a5fd139fd955012c0408318a0b39bb075da0ca6f852f41e0ec8; test64c9b64981e12cf6094ad89a691ebba9fd281e64a7f83790bc032c90f2372a52.

R2 real constructor64/64 ASan/UBSan cases PASS: allATA, mixedCD, emptyATAPI presence, ATAPI floppy/optical/disk, missingfirstchannel, emptycontroller, SPARC64/nonSPARC, absent/empty/list/dad compatible. Checks ancestry/regcells/targetlun/drivepointer/I/O mapping and compatible preservation. Existing constructor BIND stub remains recording-only; separate actual-macro regression closes metadata gap. Hardware probes/firmware services are host stubs; no actual Forth stack roundtrip/ATAPI I/O/native boot claimed.
Frozen replay verified using replay-tests.py: copies only named fixture bytes into fresh writable temporary tree and runs actualmacro +64cases without touching frozen inputs. Use this entrypoint; original fixtures generate files beside themselves. frozen-replay.log preserved.

Proven host GCC13.3/Make4.3/toke1.0.2 recipe reused, max-j2. R2 incremental build reused configured object tree, omitted switch-arch rerun only; EXTRACFLAGS=-fno-stack-protector preserved. build-r2.log/build-r2-exit0, configs, executable/package toolchain pins, disassembly/symbols/nostrip/dictionaries saved. Established stack-canary TLS pattern check passed, not exhaustive compiler assurance.

Local fullbundle /Users/ryan/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/firmware132-dad-topology-kestrel
Remote evidence manifest FINAL-SHA256SUMS SHA3f092a689812e7d96f3af232972729167ddc5534686cfa7ac540f5e7063b4796, all copied entries independently verified.
Final HANDOFF-MANIFEST.json SHAdf503e3c2bbd1f18d51e3f05a22a8f69c4add8f97be6ed65942c16278fa7a00a.

Scope CONFIG_SPARC64, not a runtime sun4u-model test. Only nonempty controllers whose PRESENT drives are all ATA disks flatten into direct dad children with controller-local targets and two-cell ESP-equivalent codecs. Any present ATAPI/other media keeps complete legacy tree; empty controllers/nonSPARC retain legacy. Absent-only dad property preserved on eligible ATA leaves in either shape. Probing-before-publication SPARC timing and current_channel diagnostics caveat retained. Owner later A/B must validate actual codec/path/alias/open/slice/OS semantics; diskless CD suppression prerequisite previously proven, no installed topology boot by helper.
