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

The next test infrastructure supports an explicit hash-pinned, read-only QEMU
binary override without changing the runtime image. Host and in-container
hashes plus loader smoke are required before target/guest creation. The fixed
SUN4U_CMD646_B134_COMPAT boolean defaults0;1 requires that override and an
advertised boolean x-b134-status-compat property. Only its fixed -global argv
pair is allowed. Nineteen fixtures pass independently; default trace failure
handling also retains14/14 fixture coverage with the override helper present.

Exact Ubuntu source1:8.2.2+ds-0ubuntu1.18 has CMD646/core bytes matching the
previously inspected upstream files. First rebuilt baseline linked, but owner
loader test in pinned image exited127 for absent libcurl.so.4. No guest was
launched. Optional dependencies are being aligned consistently in baseline and
candidate; compilation alone is not accepted as runtime readiness.

Both CURL-disabled builds completed with identical configuration/toolchain.
Baseline SHA21bd3ec9b31833e0a48419e6f878ce9a1b0edf0d95c05bba4e27b9fedcd4f148;
candidate SHA1d5d578dd82a402be1a56d1eb52b29d59e50e7c4674a571a0ac4e3505e3e5abe.
Frozen files reside at playbox
/home/niagara/devel/macapp-sun4u-001-cmd646-compat/artifacts/.
Both pass owner loader smoke in pinned image; candidate property help reports
x-b134-status-compat boolean defaultfalse. Static dependency audit reports
16libraries and no missing libraries for either. Native guest behavior pending.

Reviewed candidate source e049fc70b179d75f0f79218efc369ca1ad86cd6b690cbb61caf08e8ef469daa0,
compat-only patch3a46bd147fa2158d5dceb181df1dd3308abb540641035120f140a224f6415f21;
separate ack-only dependency806842be34741f187d2aac4d431db7e27a52785124f3bbc6e7144047e4dfcbe6.
198checks pass,10,000 OFF transitions match ack-only,29blocker checks pass.
ExperimentalON retains pending status separately from live IRQ and explicitly
rejects migration/snapshots; no hardware-fidelity or migration-support claim.

Next control: candidate binary OFF,baseline132firmware,1088MiB,freshIDE8GiB,
traceOFF,guest/maintenance preservationON. Following ON run changes only the
compatibility boolean (and uses its own fresh target). CandidateOFF includes
the separate ack-only correction, not pristine Ubuntu; OFF/ON isolates the
experimental retention policy within the same binary.

Run141 candidate-OFF completed MAINTENANCE21 with repeated "Interrupt not
seen after set_features" followed by maintenance during media preparation. This reproduces
the control failure; it is not an installation success. Console and outcome
are retained under notes/evidence/run141-cmd646-off-20261024. Owned container
73ab7524447495a616ff7c8189b7fa92cc6d405eaf99a88b7adb705b16499166
was live/non-OOM at capture. Next CI changes only compatibility0->1 with a
fresh target. Both runs are visible via read-only X11 :0 log followers.
Native paused fixture independently passed OFF acceptance and ON explicit
migration/snapshot rejection; diskless load rejection does not prove pre_load.

Run142 compatibilityON reached snv134 installer menu, media mounted, CI boot
gate PASS0. Read-only format inventory confirms c2t0d0, DEFAULT geometry
16642 cylinders/16 heads/63 sectors, dad0 under the expected IDE controller.
Installation is NOT complete: launching text-install fails target discovery at
slice_info.py80, str(tgt_slice.offset * tgt_slice.geometry.blocksz), with
SystemError: Negative size passed to PyString_FromStringAndSize. Full traceback
captured through console from /tmp/install_log. Guest remains alive in root
shell for diagnosis, no reboot. Standalone Python2.6 str(0), str(512), and
str(8589934592) all pass, narrowing but not excluding numeric-runtime issues.

Minimal reproducer: str(0L), repr(0L), hex(0L), decimal formatting of0L,
and str(1L-1L) fail; str(1L),str(-1L),str(512L) pass. Actual slice offset
equals0L and converts to int0; block size512L. This is independent of labeling.
Root tested process-local slice_info.str=lambda v: '0' if v==0 else str(v),
without touching builtins or guest files. DiskInfo then succeeds with2slices;
0L/1L/-1L/512L/2**64 give exact expected strings, nonzeros match originals.
Within that interpreter, sys.argv=['/usr/bin/text-install'] and execfile of
that path launch installer with override. Disk screen accepts8GiB (minimum3.2,
recommended5.2). Selected whole fresh c2t0d0, slice0 rpool8GiB, UTC, no network,
hostnameopensolaris, userniagara. Temporary credentials held outsideGit in
local run142-credentials.private mode0600, never commit them.
F2 Install accepted; observed Preparing disk2%. Installation/coldboot still
unproven. Guest clock unexpectedly displayed Nov12 in syslog after installer
time-setting despite accepted Oct25 UTC screen; preserve as separate anomaly.

Heartbeat05:59Z: installer remains99% Completing transfer process, not success.
Target allocation2.4GiB; writes2501762560/29970operations/298flushes unchanged
across sampled05:39/05:49 checks. Small reads continue, not progress proof.
Unsigned pkcs11_softtoken skip warning is observed, not proven fatal/causal.
No OOM; host cgroup near2GiB with historical max events, but bounded samples
showed no current PSI/reclaim growth. No resource change or reset performed.
Two HMP register snapshots resolve via exact archive unix to idle+72 at
0x105f69c; callback0x10617f0 generic_idle_cpu is retl;nop. Independent review
confirms sampled kernel idle, not continuous idle or specific wait cause.
Read-only targeted process/wait-channel introspection feasibility delegated
through Maestro; requires proven exact layouts, no guessed offsets/guest pause.
Coldboot harness completed and independently16/16 mock-tested; remains frozen,
unlaunched pending actual installation completion and clean disk closure.

2026-10-25 recovery: Ctrl-Z recovered the existing parent root shell without
stopping QEMU. Live stacks established install-finish waiting on pkg child,
with pkg in do_multi_select/pollsys and guest IPv6 SYN_SENT. Install log proves
transfer, installboot and initial boot archive completed; current task was
remove_specific_packages. Exact child2022 was uninstall SUNWslim-utils.
Historical in134 source and selected runtime lines show cached manifests may
still trigger intent HTTP HEAD; not yet proof this was the exact request.
Host SLIRP/netns had no corresponding IPv6 flow, so host firewall rejection
was rejected at preflight. No network/firewall changes made.

Both SIGINT and SIGTERM are ignored by actual pkg children. Root chose explicit
failed-task recovery, not graceful cancellation: HUP to verified child2022,
then foreground resume. Log records removal failed with status1; parent then
started2084 for system/install/text-install. Verified argv, same pollsys wait,
and ignored INT/TERM/default HUP independently for2084; HUP sent to that child
and original installer resumed. No VM restart/disk reset or concurrent pkg
writer. Finalizer outcomes and target cleanup must be inspected before repair.
Original installer failure must remain recorded even if target is repaired.
Raw pstack headers contain credential hashes; do not commit raw console logs.

Finalization then finished: 1/23 Python ICT tasks failed (the one package-removal
task accounts for both children). Final bootadm returned, snapshot Succeeded,
root-pool-ready Succeeded. UI correctly reported Installation Failed. F9 exit
returned root shell; no original installer/package/finalizer writers remained.
beadm showed opensolaris, Active R, unmounted,2.28GiB. bootfs is
rpool/ROOT/opensolaris. beadm mount opensolaris /a succeeded; df verifies exact
dataset at/a. Both packages remain installed: SUNWslim-utils0.134 and
system/install/text-install0.133(textinstall publisher).
First narrow repair trial uses existing pkg with connection/low-speed timeout5
and retry/error count1. No publisher settings changed and no shim applied yet.

Subsequent recovery experiments: timeout-only real uninstall still waited in
pollsys; terminated isolated child2207. Dry-run2259 worked locally and fg exit0.
Six runtime source hashes exactly matched reviewed pkg5 in134. Reviewed
process-local advisory shim1389fd81 (8/8 host tests) was transferred with exact
hash and mounted-target probe; native2319 still reached network wait. No repair
success claimed; terminated isolated2319, no remaining image writers. Diagnostic
shim8834313e is preserved for later observation, not deployed in this boot.

Root chose separate disk-boot experiment with both cleanup packages retained.
Unmounted BE; rpool ONLINE, zero read/write/checksum errors. Explicit export was
busy (recorded failure), then halt synced filesystems. Exact kernel mapping
proved PC0x104e384=prom_exit_to_mon+44, terminal self-branch after PROM call.
QEMU monitor quit; original container exited0,OOMfalse. Offline qemu-img info:
8GiB,no backing,dirtyfalse,corruptfalse. qemu-img check: no errors.
Preserved reflink copy install-before-coldboot.qcow2 beside original. Both SHA256
b08d18fb255d0121999735ac146ef5f8fcf2e80335f0ed17e64936793338e69f.
Original offline identity64785:138422282:2496659456. No saved-machine restore.

Coldboot harness9ae6db99 launched unchanged with actual clean-shutdown/exclusive
checks. Evidence on playbox /mnt/disk-images/woodpecker/sun4u-coldboot-142-20261025.
Only installed disk, firmware132, candidateON,1088MiB; NO ISO. Initial OpenBIOS
prompt reached. X11:0 window 'B134 disk-only OpenBIOS boot' tails exact console.
This is known-imperfect installation boot test, NOT clean installer success.

FIRST ACTUAL DISK-ONLY BOOT FAILED BEFORE KERNEL: verified disk alias
/pci@1f,0/pci@1,1/ide@3/ide@0/disk@0; existing power-interrupt and fdthree name
workarounds applied successfully. boot disk -v loaded4168-byte FCode at0x4000,
then EvaluatingFCode raised exception0x30 PC0xffd0f454 NPC0xffd0f458 and stopped.
Container81c895e8831ed91a0749010319c9d59f253333f8d174a2657befef6a77dff8df.
No Solaris kernel/root mount reached. Root is stopping only that owned container
and preserving evidence/backup. Maestro team redirected to exact firmware fault
mapping, installed ZFS bootblock/OpenBIOS interface, and regression/patch review.

First coldboot container is now stopped. Harness outcome was exit2,
UNVERIFIED_SESSION_END/client0, not boot success. Exact firmware132 symbol
mapping identifies PCffd0f454 as unalignedlongread+12, first ldub[%o0],%g1.
Trap0x30 is data-access exception, not the alignment trap0x34. Original operand
and MMU fault status were not captured; the exception printer clobbers o0.
No root-cause claim or speculative firmware patch is justified yet.

Immutable backup extraction confirms a4168-byte first-stage FCode bootblock
at sector1, with nested ZFS FCode offset0x80000/length8192. Checksum mismatch
is recorded but loader ignores checksum, so it is not established causal.
Next experiment: same disk/firmware/QEMU/RAM with isolated local Unix debugger
and monitor sockets, capture pre-fault operand and Forth context. Root owns
native run; Maestro workers own instrumentation, exact breakpoint plan,
bootblock analysis, and independent review. Preserve frozen original harness.

Asset validation commit20df935 pushed to Gitea and GitHub branch
codex/sun4u-coldboot-asset-validation. Root verified all existing workflow
branch filters exclude this branch; new push/manual workflow runs only pinned
offline asset tests, never guest/install actions. Local20/20tests passed.
Woodpecker outcome pending. This validation cannot establish installed boot.

Woodpecker143 failed correctly: pinned fixtures existed in the working tree but
were ignored/untracked, so clean checkout could not find coldboot.py. Root added
only the five explicitly pinned assets in commit ed25b51; reran20/20 locally,
pushed both remotes. Woodpecker144 SUCCESS. This closes the clean-checkout gap;
installed coldboot remains NOT_TESTED by this workflow and failed in native run.

Second native boot used instrumentationce340d43, same firmware/QEMU/disk/RAM.
X11 window B134 instrumented disk boot showed actual console. GDB hardware
breakpointffd0f454 caught first unaligned-l@ before execution: operand o0=4,
ForthPCffe0d0d0,dstackcnt14,rstackcnt57. Saved full dictionary(524288bytes),
data/return stacks and register log BEFORE advancing. Single-step reproduced
exception30 at samePC; handler clobbered o0 as expected. Root monitorquit then
closed exact owned containerdfc8c0b5, exit0/OOMfalse; harness2UNVERIFIED, notPASS.
Saved artifacts work/b134-resume/coldboot-debug1 and playbox
/mnt/disk-images/woodpecker/sun4u-coldboot-142-debug1.

Concrete firmware bug candidate: table.fs comments out two FCode entries after
0x249(/x*), shifting later64-bit tokens by2. Nested ZFS x0= uses token0x251
(xlsplit), but saved compiled dictionary calls XTffe0d528 named xwflips. Its
buffer dereference explains why a numeric value becomes address4. Exact132
table hash7691a6aae98da1de270304071791dbb3e34fb30372790a1ff21d86b68fd0d9d2.
Team independently validating full mapping and preparing isolated two-entry
restoration, failing-before regression, candidate firmware build. No fixed
native result yet. Preserve original132 firmware and installed-disk backup.

THIRD DISK BOOT REACHED B134 KERNEL. Candidate firmware SHA256
0fe3be7270fe52e64085c690b05474e0063f9d184c35a3dd7d15406a15e38343, isolated132
build differs in table.fs only; Mica independently approved source/tests/build.
Native token251 compared equal to xlsplit and executing it on0 returned0 0.
Same installed disk/QEMU candidateON/1088MiB/noISO: boot disk -v progressed
through ZFS reads, loaded unix/genunix/platmod/UltraSPARC-IIi, printed
SunOS Release5.11 Version snv_134 64-bit. Previous FCode trap is resolved in
native replay. Startup/rootmount/login not yet verified; retained cleanup
packages and original installer failure still recorded. X11 visible window
B134 corrected FCode disk boot, evidence sun4u-coldboot-142-tokenfix1.

Fix/regressions committed dcf3a2b on validation branch, both remotes pushed.
Woodpecker145 SUCCESS: original20mocktests plus4token-contract groups. Tests
cover20slot mapping, unchanged non64 assignments, actual extracted0251 token
and seven numeric x0= cases, six xlsplit values. Source interpreter tests are
not falsely presented as native execution; separate live token test above is.

Next observed blocker after kernel entry: disk/ide no-major-number warnings for
PROM nested path, then uata0 attachment, spa_import_rootpool error5, root mount
panic. /chosen bootpath remains /pci@1f,0/pci@1,1/ide@3/ide@0/disk@0;
zfs-bootfs=rpool/56. Historical actual installer target is dad0 at uata0 target0
lun0, /pci@1f,0/pci@1,1/ide@3/dad@0,0 (c2t0d0s0), NOT sd (CD target2).
This supports a boot-path normalization hypothesis, not label corruption.
Third VM monitor stats98,626,560readbytes/zero writes; exact monitorquit closed
container e50a974b exit0/noOOM, harness2UNVERIFIED. Rootask1 fresh same-pin VM
now runs boot disk -av to observe actual interactive path-selection behavior.
No speculative -B syntax, disk label writes or device-tree mutation performed.

ROOTASK1 FAILS WITH EFFECTIVE OVERRIDE: kept displayed /etc/system, retire_store,
zfs defaults; actual physical-root prompt received verified dad@0,0:a path.
Error now quotes that direct path, proving propagation. WARNING can't bind
driver for boot path appears after kernel banner but before PCI attachment; no pcipsy/simba/
uata/dad reports (unlike original nested-path run). Error5 alone does not prove
bad labels; team tracing exact driver-binding warning and archive/preload path.
Current rootask1 rebooted to OpenBIOS; no full boot/login yet. Native logs saved
under work/b134-resume/coldboot-rootask1. No further guessed path substitution.

Reusable firmware build integration committed b7ea868, both remotes; CI146
SUCCESS (20mock+4token+5build-wiring groups). Recipe includes existing0003 plus
new0004; its future output is NOT assumed byte-identical to isolated132 tokenfix
artifact. Original native CI still uses its prior132 selection, not silently
updated to this candidate. Build artifact/provenance bundle committed61a9439.

ROOTDEBUG1: same fixed firmware/disk/QEMU/1088MiB, no ISO, boot disk -av.
Read-only GDB observer verified swapgeneric text base12feef8 using live code.
Correction to initial team analysis: implementation descriptor18192d8+0 is
12ff42c; +18 is zero/error fallback, not the active implementation slot for
flags10. Physical descriptor reads and exact common-dispatch trace corroborate.
No guest memory/register mutations or forced returns were used.

Default nested PROM path returned PROM nodeffffffffffe325e0 and matched
devinfo30000d3c2a0 at first load_bootpath_drivers call. Driver loading emitted
disk/ide no-major and reprompted. At this SECOND prompt owner supplied native
/pci@1f,0/pci@1,1/ide@3/dad@0,0:a. Its PROM lookup returned-1/dip0; final
loadrootmodules returned0, rootfs183e028 held exact native path. Continuing
restored pcipsy/simba/uata attachment, but still no dad attachment and ZFS label
error5/rootpanic. This falsifies pathname substitution alone as sufficient.
It does not establish bad disk labels or missing archive members. Next isolate
native device lookup/open/read error and dad preload/attachment requirements.
Evidence on playbox: sun4u-coldboot-142-rootdebug1/{console.log,gdb.log}.

ROOTDEBUG2C isolates failure BEFORE disk open/read. Same two-input path sequence;
live boot-driver observations show disk/ide no-major, successful canonical
modloadonly returns uata38/simba40/pcipsy41/rootnex24, no forceload callback hit
in this interval. Some entry names inaccessible due TLB residency; canonical
names were readable at returns. No dad-loading inference beyond observed routes.
Actual rootconf call validated fsop122a5c0 -> genunixbase10cef18 and live vfsops
mount1372b14 -> ZFSbase1303fe0; bootstrap instruction checks all passed.
Rootlabel entry path exact dad@0,0:a, devidNULL. resolve_pathname return at
1129e20 was-1, then ldi_open_by_name returned19 at135eab8, and rootlabel itself
returned19 at133349c. Thus this invocation never attempted label reads; upper
spa_import_rootpool error5 masks device-resolution failure. Next question is
why the dad device/minor cannot resolve, not label corruption or I/O timing.
VM currently paused at rootlabel return for bounded further inspection.

Launch accounting: rootdebug2 refused invalid2400 deadline before any container;
rootdebug2b lacked local writable PTY and was stopped at firmware before boot.
rootdebug2c uses a writable PTY and is the actual diagnostic run. No rollback or
disk edits; checksum before launch remained b08d18fb... after rootdebug1 zero
writebytes. Logs saved locally under coldboot-rootdebug2c. Prior evidence/notes
commit2ddc7c2 pushed both remotes; Woodpecker147 SUCCESS.

Rootdebug2c completed the same expected rootpanic, then exact monitor quit;
container55100dde exited0/noOOM. Its final logs/outcome are preserved. The
resolution evidence commit35b23af was pushed to both remotes.

ROOTDEBUG3 separate prekernel failure: identical pins, but GDB attached earlier
while firmware loading (stopped in udelay) with hardware breakpoint104e5c4.
Console failed after claim va10a3b60 size19, Exception30 PCffd276b8/NPCffd276bc.
Exact candidate symbol is memcpy+24, raw opcodec42a0001; handler registers are
not original fault operands. No data writes were made by debugger. Saved logs
in coldboot-rootdebug3; exact quit container708c501c exit0/noOOM. No attribution
to GDB yet: rootdebug4 repeats same boot WITHOUT attachment until kernel prompts
to test that variable. Main root-resolution diagnosis remains separate.

ROOTDEBUG4 (no early GDB) reached kernel successfully. Attached only at physical
root prompt; same natural two inputs. Revalidated module bases/instructions.
Bounded component observer: pci@1f,0, pci@1,1, ide@3 all succeeded; actual IDE
child30000d3ca38. Paused before dad lookup: pm_pre_config0, dad@0,0 flags4080.
Custom callback target7be0b5b4 was actually selected, not generic wrapper path.
Following only actual instruction branches: helper1207dd0 ->600104e1200,
flags+e8=60001, callback+108=0 and+1c8=0; tail7be0b254 chose fallback with
flags14084, then1116a38 and verified genericdevi_config_one11142c4.

At generic pre-attach45688, candidate60010445498 NONNULL; name dad@0,0, unit0,0.
Thus matching disk child exists. Actual i_ddi_attachchild1110230 returned-1 at
caller1113f1c. Candidate major23hex (35 decimal), current state3, rawflags150=0.
Exact live code attempts configuration tostate6 and on failure unconfigures to3.
Currently stopped before caller handles failure, considering explicitly marked
diagnostic same-frame retry with deeper probe/attach breakpoints; NOT performed
yet. No guest data/register writes to date. This is attachment failure, not
missing-path/label-read evidence. Current saved logs coldboot-rootdebug4.

SUBSEQUENT ROOTDEBUG4 CONTROLLED RETRIES (not pristine replay): owner chose two
same-frame diagnostic reexecutions of existing CALL1113f14/delay1113f18, changing
only PC/NPC after recording original1113f1c/1113f20 and child/state/flags. Full
rollback/idempotence was NOT established; no result is accepted as cold-boot
repair proof. No forced success, driver data patch or persistent disk change.
Retry1: devi_probe110f86c driver-hold returnNULL for same dad candidate, before
actual hardware-driver probe call. Returned-1 normally. Current devnames table
verified live by exact instructions: dad major35, name dad, flags1 (84maskclear),
devcnt241hex. Retry2 captured actual modload('drv','dad'), composed drv/dad;
loader1261b90 returnedNULL at126131c with explicit errorout2 (ENOENT). Thus this
diagnostic failure is driver acquisition, before disk probe, not disk I/O.
Next minimal cold test under review: add compatible='dad' to existing firmware
disk node (preserve name/methods/alias) to induce early preloading through the
verified ddi_binding_name fallback. No property edit performed yet. A later
full cold boot is required even if this hypothesis succeeds diagnostically.

ROOTDEBUG4 completion: terminal rootpanic returned to OpenBIOS, debugger detached,
exact monitor quit. Blockstats: rd_bytes98681344, wr_bytes0, wr_operations0.
Final logs retrieved. Naming correction:110f86c is probe_node after ndi_hold_driver,
not actual devi_probe. Outer loader ENOENT does NOT establish archive absence or
which inner loader stage failed.

DADCOMPAT1 fresh coldboot: same pinned QEMU/firmware/disk/1088MiB, no ISO.
Read-only OpenBIOS inspection confirmed my-self0, exact nested disk path, name
disk/device_type block/reg0, and compatible ABSENT. Added only transient property
using `" dad" encode-string " compatible" property`; readback length4, bytes
64 61 64 00. Existing name/methods/aliases unchanged. Same power/fd workarounds,
boot disk -av. Visible X11 window B134 dad early preload cold boot. Hypothesis:
ordinary compatible binding selects dad and load_parent_drivers fallback requests
it before boot services quiesce. Require actual early load/attach/root evidence;
property echo alone is not success. No persistent firmware/disk patch.

DADCOMPAT1 ACTUAL SUCCESS THROUGH ROOT LABEL AND USERSPACE: current sg live
instructions corroborated (descriptor page unreadable, no descriptor reread
claimed). Flint/Mica-reviewed observer captured early dad major35 modloadonly
return38, SUCCESS. ide still no-major, so same second physical-root prompt was
answered native dad@0,0:a. Exact bootstrap revalidated gb/zb live this boot.
probe_node110f86c for major35 returned nonNULL devops18fc938; console dad0 attached
at uata0 target0lun0. ldi_open_by_name return135eab8 was0. Rootlabel return133349c
was0 with nvlist600104f1f28. Guest continued naturally: Hostname opensolaris,
dump on /dev/zvol/dsk/rpool/dump, Configuring devices. ROOT MOUNT/USERSPACE reached.
No register/data mutation, forced returns or same-frame retries in this boot.
Only transient compatible property differed from natural control; debugger
breakpoints observational. Login/SMF completion still pending. Do not kill or
roll back this now-mounted writable root. Original offline backup preserved.

Evidence/notes through prior run committed05c67cc both remotes; Woodpecker149
SUCCESS (existing artifact validation, not this native success). New live evidence
will be saved separately. Team preparing minimal durable property patch/test and
separate remaining double-prompt/rootpath strategy, not claiming unattended boot.
