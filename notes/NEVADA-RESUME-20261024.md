# Nevada B134 resumption — 2026-10-24

Objective: install B134 on a disposable disk and cold-boot it with generic
QEMU sun4u and OpenBIOS, using Woodpecker for repeatable gates.

Recovered Woodpecker repository 2 runs 55, 58, and 67 from the controller's
read-only database. All passed. Run 67 commit is 5aee07f599; its source was
recovered from Biggie's existing Git object database. The private CI branch
subsequently added only documentation in 8baadcb.

The saved run67 artifacts on playbox passed their original SHA256 manifest:
firmware f56f9a3d8da8521f82ec162f4fe3cb5b1ae0d478da69e8aab551aa56ffd8d2f9.
The pinned workbench image is still present with the expected image ID.
Playbox was initially offline; Ryan started it on the MacBook Pro.

The original acceptance boundary is keyboard selection, language selection,
and Configuring devices. It does not prove installation or installed boot.
The harness deletes the power node's interrupts property and renames fdthree
before booting. Preserve those operations in the control experiment.

This isolated branch changes only the Woodpecker branch selector for the first
replay. Existing Tribblix graphics edits on Minnie remain untouched.
Replay first; then add a private installation disk and extend the gates to
installer completion, cold disk boot, writable root, networking, and reboot.
Do not report any of those later gates as passed without console evidence.

Before installation, check real disk allocation: playbox currently has 9.5 GiB
free on its 70 GiB data filesystem and 5.1 GiB free on its root filesystem.

## Baseline replay and browser-oriented RAM experiment

Run 132 reached SUN4U_OPENBIOS_BOOT=PASS at 1536 MiB: keyboard and
language selection followed by Configuring devices. Installation remains unproven.
Its rebuilt firmware differs from run 67; do not claim byte-identical recovery.

Ryan requested a 512 MiB trial, with Infinite Mac as a browser-port reference.
The harness retains 1536 MiB as its default; this CI trial explicitly selects
512 MiB and logs the selection. Keep the container limit at 2048 MiB to avoid
confounding guest-memory reduction with host process limits. The existing
acceptance gate is unchanged. A pass proves early installer boot/input only,
not sufficient memory for installation, installed operation, or WebAssembly.

Infinite Mac references:
- https://github.com/mihaip/infinite-mac
- https://blog.persistent.info/2025/03/infinite-mac-os-x.html

Its README documents worker-separated emulation and chunked disk images.
Its cores include PearPC, DingusPPC, and Previous, not QEMU. Study and reuse
applicable worker/disk/persistence patterns; separately validate a SPARC64
QEMU WebAssembly CPU execution backend. Native 512 MiB testing comes first.

The Infinite Mac OS X post documents pure-interpreter PearPC/DingusPPC
optimization and explicitly points to https://github.com/ktock/qemu-wasm
as an encouraging QEMU browser port. Evaluate this existing work before
inventing a new backend; SPARC64 compatibility has not been established.

## 512 MiB diagnosis; next trial 1024 MiB

Run 133 panicked: `no nucleus hblk8 to allocate`. Reproduced with the exact
run132 firmware in `/mnt/disk-images/woodpecker/b134-hblk-512-control`.
An instrumented 1536 MiB control using that same firmware passed the original
boot/input gate. Docker reported no OOM kill for the initial failing run.

B134 kernel symbols were read from its own boot archive, mounted read-only.
Debugger inspection found nucleus_hblk8 index=len=3185, hblk1 index=2,len=157,
and hblk_alloc_dynamic=0 at failure. segkmem_lpszc=0 at 512 MiB versus 3 at
1536 MiB; segkmem_lpminphysmem=0x40000000 (1 GiB).
The failure breakpoint at 0x1032d98 caught vaddr=0x70000650000, inside kmem64
(base=0x70000000000, end=0x70000942000). The translation list needs 3084
distinct small-page hme blocks before kmem64; another 101 blocks exhaust
the pool exactly at this address. Startup budgets kmem64 in larger-page
records but the below-1-GiB heap setting makes its remapping consume small-
page records instead. This is early mapping-pool sizing, not host OOM.

Diagnostic artifacts are in playbox's woodpecker/b134-hblk-* directories;
512-mappings.log and 512-failure.log were also captured on the laptop.
A RAM-only extra-128-records experiment was started, but Ryan redirected
work to simply trying 1 GiB before its result was established. No ISO or
on-disk kernel patches were made. CI now explicitly selects 1024 MiB;
the harness retains its 1536 MiB default. Passing at exactly 1 GiB still
requires testing: installed RAM and kernel usable-page accounting differ.

Run134 at 1024 MiB also produced the same nucleus_hblk8 panic (not host OOM).
Filed project issue: http://biggie:3000/ryan/niagra-qemu-solaris-project/issues/2.
Independent review: the small-page policy is the trigger, but ownership of
the accounting defect is unresolved. The post-panic boot_virtavail only
covers low virtual addresses, omitting coverage of high heap/kmem64 claims;
size_virtalloc cannot count allocations outside supplied range coverage.
Capture the list at the sizing breakpoint before asserting the precise
kernel-vs-firmware contract violation. A constant pool increase is only a
diagnostic experiment, not the proposed production fix.

Tooling note: no Gitea-specific service wrapper was found. safe-curl itself
was blocked by its raw-curl check, so its documented per-invocation
GUARDRAIL_BYPASS=1 exception was used with .netrc authentication for issue
lookup/creation. No credentials were printed.

Run134 debugger confirmation: physmem@0x1810f18=128185 pages, or
1001.4453125 MiB at 8192 bytes/page. segkmem_lpszc@0x181621c=0;
segkmem_lpminphysmem@0x18125b8=0x40000000. Thus 1024 MiB configured
still leaves usable physmem below the large-page policy threshold.
The exact source of all excluded pages was not independently measured.

Ryan authorized parallel browser-port work: isolated Emscripten SPARC64
build on Biggie, local serial browser harness, and independent backend/
performance review. Use qemu-wasm's hybrid interpreter/Wasm TCG backend;
keep these experiments separate from the known native baseline.

## Controlled 1088 MiB trial

Hypothesis: 1088 MiB configured RAM leaves usable physmem above 1 GiB,
enabling segkmem large pages and avoiding the observed hblk8 exhaustion.
Falsifiers: usable physmem remains below threshold; lpszc remains zero;
or the same panic occurs with large pages. Installer boot/input success
alone is evidence for a workaround, not proof of defect ownership or repair.
Reuse exact run132 firmware SHA256
1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938;
hold ISO, QEMU image, CPU count and console commands fixed. CI verifies
the copied firmware digest rather than rebuilding it. Harness now detects
panic before accepting a prompt and preserves failed container inspection.
Local regression tests cover prompt acceptance, panic precedence, timeout.
Gilfoyle discovery found no configured observability environments; evidence
is scoped to CI artifacts, serial logs, and explicit debugger measurements.

Run135 (09377de), at device attachment after the former panic point:
RSP reads physmem `m1810f18,8=00000000000212df` (135903 pages,
1061.7421875 MiB); `m181621c,4=00000003` (large pages);
`m18125b8,8=0000000040000000` (1 GiB threshold);
`m1820800,18=0000000000000c200000000000000cba0000030000e8c000`
(hblk8 used3104, capacity3258). Detached successfully. These support the
threshold workaround; installer input acceptance was still pending at
measurement time. Run134 had been marked killed by CI but its panicked
container remained CPU-active; stopped that exact container, retaining
its metadata and all run artifacts.

Run135 subsequently emitted `SUN4U_OPENBIOS_BOOT=PASS`: keyboard46,
language7 accepted, `User selected: English`, `Configuring devices.`
Thus1088 MiB passes the original boot/input gate with exact run132 firmware.
This does not establish installation, cold disk boot, browser execution,
or repair of the below-threshold hblk sizing defect.

Next independent gate: attach a fresh private8GiB qcow2 as IDE index0,
keeping1088MiB and pinned firmware. Host preflight found9879764KiB free,
above9GiB needed for full virtual capacity plus1GiB reserve; qemu-img8.2.2
is present in pinned image. Source tests cover opt-in defaults, invalid
options, existing target refusal and insufficient space. Original gate
remains unchanged. After it passes, observe120seconds and explicitly keep
the guest for interactive inspection; no automatic installer decisions.
Disk discovery must be observed in guest before selecting an install target.

## OpenBIOS source correlation (not yet a tested firmware fix)

Read exact run133 source checkout: `include/arch/sparc64/ofmem_sparc64.h`
defines OFMEM_VIRT_TOP=0xff000000. `libopenbios/ofmem_common.c`
ofmem_claim_virt_ accepts fixed-address (!align) claims using is_free/add_entry
without the automatic allocation max bound. ofmem_update_translations emits
MMU available only through ofmem_arch_get_virt_top()-1; its range walker
breaks when r->start>=top_address. This code path is consistent with the
measured low-only sizing list despite imported high-VA mappings. A firmware
repair must distinguish automatic-allocation policy from property coverage;
blindly raising OFMEM_VIRT_TOP changes both and is not a validated fix.
Canonical-address holes, range overflow and terminal free-range accounting
need explicit tests before proposing a permanent change.

## Maestri and first browser execution

Task macapp-sun4u-001 delegated through /tmp/maestro-handoff.md to existing
Maestro Codex and Kestrel/Flint/Mica/Trellis. They own isolated firmware
implementation/tests/review/native validation, no main-branch edits or pushes.
Prioritized follow-on queue is local work/MAESTRI-BACKLOG.md. A10-minute
thread heartbeat checks useful progress and assigns through Maestro.

qemu-wasm pinned0ef7b4e built successfully with Emscripten3.1.50; original
Wasm SHA256b831215cd3ad850a7035b1234afc2870d2ca38ae4a0ec05db337d6e20da10849.
Provenance in local work/qemu-wasm-sparc64-artifacts/BUILD-PROVENANCE.txt.
Actual Chrome test via PinchTab at localhost8089: navigation/click/text and
screenshot verified; eval403 disabled, not enabled. Runtime initialization
does NOT mean guest success. First thread=single test errored on undefined
__wasm32_tb.tb_ptr_ptr. Source initializes that state only in MTTCG path.
Changing only to thread=multi, still oneCPU/512MiB, advances to generated
Wasm CompileError: function2 i64.sub operand expects i64 but i64.gt_u
produces i32. tcg_wasm_out_sub2 lacks borrow-width extension before high-half
subtraction; executable regression and candidate rebuild are in progress.
No OpenBIOS browser prompt yet. Preserve original artifacts as negative case.

Native run136 added fresh8GiB IDE index0 disk, then entered maintenance mode
during text-install image preparation before keyboard gate. This is a new
failure distinct from hblk exhaustion; disk/media enumeration is a hypothesis,
not yet established. Installer completion and disk boot remain unproven.

Browser v2 now PASSES firmware/input gates: WasmSHA256
424346e400e987381270ab05472a1dd123212f20c4dc3dd478d9f4c41a2a1155,
same firmware/512MiB/oneCPU/thread=multi. Missing borrow width conversion
fixed; actual source-emitted Wasm regression fails before, passes24 cases
after. OpenBIOS banner/prompt, arithmetic1 2 + . ->3, root tree listing and
repaired su@14,3f8 path all observed in Chrome. Raw saved console SHA256
de431def836369163ac776e88d3d5ee499f91efa7617f01d24bb98964ccb9a17.
PinchTab direct typing duplicates characters; normal form fill/click feeding
xterm.paste works. Its eval endpoint remains disabled. Browser OS/disk/network
boot and direct automated keyboard correctness remain unproven.

## Native firmware v3: 512 MiB boot gate passed

The first expanded-available firmware (v2) failed native validation because
the dedicated I/O arena was mapped but not reserved in virt_range. The v3
patch reserves that architecture-defined virtual arena at initialization,
without reserving physical RAM or changing automatic allocation policy.
It also separates the lower-canonical reporting ceiling from allocation limits.

V3 firmware SHA256:
4bb44a805d3d1cfb3b3150189b5d4f828d2b086b19ccc5eecce9570316532ecb.
Candidate patch SHA256:
cc3251e0a55578e5350d97c9a805ea00821a5d499e1e794cddcffa98173b70c5.
The exact patch is retained as patches/openbios/0003-sparc64-available-ranges.patch.

Trellis launched the fresh native guest at 2026-10-24 20:28:21 PDT, with
512 MiB guest RAM, one CPU and a 2 GiB container cap. Read-only capture
reached before-kmem64 and detached. The actual console then passed keyboard,
English and Configuring devices; harness emitted SUN4U_OPENBIOS_BOOT=PASS.
This is the diskless installer boot/input gate, NOT installation or disk boot.
No guest memory/register patch was used. Failed v2 evidence remains preserved.

Captured pool capacity is 3500; pre-kmem64 usage is 3085. The predicted
post-kmem64 usage is 3234 (not a captured post-kmem64 counter). The capture
analysis reports 165 checked translations disjoint from contemporaneous
virt_avail, including exclusion of the I/O arena. Raw evidence is under
playbox /mnt/disk-images/woodpecker/macapp-sun4u-001-trellis/candidate-v3.

The next controlled CI replay retains baseline run132 firmware and 1088 MiB
with a fresh 8 GiB IDE index0 target to identify the run136 media-service
failure without mixing firmware changes. It will preserve a live maintenance
guest explicitly for service-log diagnosis. Default failure cleanup remains
unchanged; maintenance must still return failure, never PASS.

## Run137: media failure isolated; next SCSI comparison

Woodpecker137 (874e6d9) reproduced run136 with baseline firmware1341c419,
1088MiB and fresh8GiB IDE index0 disk. Corrected harness returned
MAINTENANCE/21 and retained the live guest, not a false PASS. Root maintenance
login with the install image's empty password succeeded. Before discovery,
read /etc/svc/volatile/system-filesystem-root:media.log (the expected
/var/svc/log path was absent): FATAL Unable to access media, exit95.
/.volumeid is OpenSolaris; mnttab has neither CD nor /usr mounted.
listcd returned0 with NO rows. prtconf-vD shows uata bound but no instance or
minor nodes; firmware IDE disk/CD children exist. Explicit device-path ls
repeated set_features interrupt warning and found no /devices IDE directory.
Thus failure is CD/controller discovery, not wrong-first-disk selection or
lofi mounting. Exact uata failure cause remains under source investigation.

Saved raw console, pre-interaction failure snapshot, container metadata and
outcome under notes/evidence/run137-media-20261024. Stopped ONLY owned run137
container after capture; retained container and untouched fresh target.

Next controlled experiment changes only target bus to LSI53C810/SCSI disk;
IDE CD, baseline firmware,1088MiB and disk size stay unchanged. Actual pinned
QEMU device-help confirms lsi53c810/scsi-hd. Exact B134 aliases bind glm to
pci1000,1 and its SPARCV9 module is present. Baseline OpenBIOS does NOT enable
its existing LSI driver, so this trial tests kernel discovery/media recovery,
not installed disk boot. Separate isolated firmware enablement is underway.
New SUN4U_INSTALL_BUS defaults to ide and rejects unknown values. Tests
first failed on ignored invalid bus, then passed exact IDE/SCSI arguments.

Run138 (ed3e91d) failed before boot: QEMU reported no free slot on its default
root PCI bus; harness correctly recorded CONTAINER_EXITED/25. Actual pinned
QEMU qtree with CPU paused (-S) shows reserved root pci, built-ins on pciA,
and empty pciB. Corrected controller argument to bus=pciB,addr=1. A real
paused instantiation of controller plus scsi-hd succeeded and exited0; the
existing empty138 disk was mounted readonly with snapshot=on, no CPU execution.
This closes the CLI/device-instantiation gap that device-help alone missed.
Run139 will repeat with explicit pciB placement and a fresh disk.

## Run139 result: installer menu reached, target rejected

Run139 (586e399) passed the CI boot/input gate and reached the snv_134
installation menu with baseline firmware and 1088 MiB. Moving the target
off IDE recovered CD/media discovery. However glm rejected PCI1000:0001:
"Symbios PCI device (1000,1) not supported", followed by config init and
attach failure. In the installer shell, `format < /dev/null` reported
"No disks found!" and returned1. No installation or disk writes were selected.
Raw console and CI snapshots are retained in the run139 evidence directory.

Exact glm disassembly distinguishes ordinary810 from810A through revision
bit0x10. Stock895a device0012 is also rejected. Binding aliases were not
enough to establish supported attachment. Frozen experimental OpenBIOS LSI
enablement is therefore not an accepted installation solution.

The primary next experiment is a pinned-runtime IDE replay with existing
QEMU register trace events. Source tests reproduce pending-status loss
after normal ATA STATUS, before B134's second controller poll. Hardware
documentation does not yet prove the required latch lifetime. A separately
reviewed MRDMODE W1C/block-write correction fixes documented alias defects
but is NOT predicted to fix this B134 failure; do not stack it into the
diagnostic baseline. Trace collection must be bounded and incomplete traces
must not be reported as negative evidence.

During preparation, the Mac exit node intercepted the UTM local subnet.
An SSH ProxyCommand using `nc -b bridge100` confirmed playbox and run139
remained healthy, without reboot. User authorized local-network access and
then disabled the exit node; ordinary routing still lacked UTM's /24 route.
Connectivity recovery is separate from guest storage diagnosis.

Restored only the missing local 192.168.64.0/24 route via bridge100. Ordinary
SSH and Biggie's CI-to-playbox SSH then worked. Run139 was stopped after
capture, retained (38e95c61cfde480bbadfabe44e4a46f878138b57fc09e5ddca37ad674f9267f4),
OOMfalse. No playbox reboot or saved-VM restore occurred.

Pinned trace backend smoke: ten seconds of firmware only,128MiB,no disk or
OS, auto-boot false, PCI read/write events and timestamped log backend.
Exited0 and produced481 complete records/31493bytes. Raw trace and serial
are at playbox /tmp/macapp-trace-backend.4pfwVf and locally in
work/b134-resume/trace-backend-smoke. This verifies the actual trace backend;
it is not the B134 failing sequence. Next CI replay keeps baseline firmware,
1088MiB and IDE8GiB target, enables the seven-event trace, and disables live
guest preservation so trace collection can terminate and be validated.

Trace integration checks:10 helper unit tests,7 shell integration tests,
14 independent full-harness fixtures,3 console smoke cases, and IDE/SCSI
option tests pass on root staging. Stop errors now trigger incomplete status,
stopping is verified by exact container ID, and a watcher nonzero exit cannot
be hidden by failure to write its marker. 64MiB is a polling stop threshold,
not a hard allocation cap; overshoot is reported. The unmodified IDE failure
is expected to fail CI (maintenance), while retaining trace evidence.

## Run140: real controller transition captured

Commit90d81fa, pinned baseline firmware/QEMU,1088MiB,fresh IDE8GiB.
Run stopped with TRACE_INCOMPLETE/27 at the64MiB trace threshold after131.15s,
before the guest reached its eventual maintenance warning. Threshold observation
was67280867bytes (172003overshoot); final stopped file67302187bytes/633551lines.
SHA256 ad83fa56689621fae3b8de8cd722feb99069490ba3e54ae27a177fa6b628bb16
matches the host capture and local copy. Container a5b6dc0e2638f154a46dcf2a87e1a26270b75469b765af58a624a692f4976621
is stopped, OOMfalse. This is incomplete capture, NOT a guest boot success.

Positive sequence survives intact: line469467 writes SET FEATURES0xef with
features03/count42 after device/head e0 on bus0xca2d96014600. Line469468 reads
cmd646-ide01:03.0 CFR0x50 as0x4. Lines469469/470 read normal ATA Status0x50
on the same bus/device. Line469471 rewrites device/head e0; line469472 reads
CFR0x50 as0x0, followed by repeatedzero reads through capture end. There is
no intervening controller W1C in this observed transition. This matches the
source-derived second-poll compatibility hypothesis; direct IRQ levels and
original silicon semantics remain unobserved. No absence inference is made
from the truncated end. No larger baseline capture is required merely to
establish this positively observed sequence.

Offline parser independently executed:633551 selected records,1 SET FEATURES,
exit2 solely for owner-declared incomplete capture. Raw gzip retains all bytes;
large derived JSON timeline stays outside Git. Agents now use this evidence
for an explicitly opt-in compatibility candidate and controlled rebuilt A/B.
