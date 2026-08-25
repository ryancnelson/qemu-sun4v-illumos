# OpenIndiana on Niagara QEMU: performance notebook

Date: 2026-08-24

## Question

What limits OpenIndiana boot and development iteration speed under the Niagara
QEMU machine, and would more RAM, more playbox vCPUs, a ramdisk, or the original
memory-mapped `hsimd` arrangement materially improve it?

## Host topology

The execution stack for the interactive development VM is:

```text
Apple laptop
  UTM qemu-aarch64-softmmu, HVF accelerated
    niagara-playbox, AArch64 Linux, 6 vCPUs and 6 GiB RAM
      qemu-system-sparc64 -M niagara, TCG
        OpenBoot and OpenIndiana SPARC64 guest code
```

The outer UTM VM uses Apple hardware virtualization.  The inner SPARC64 VM is
necessarily TCG: QEMU translates SPARC guest code to AArch64 at runtime.  The
QEMU machine, device, MMU, and TCG implementation is native compiled C, but
OpenBoot and illumos execute as translated SPARC instructions.

The other active Niagara QEMU on biggie is also TCG.  It is an x86-64 build of
the same QEMU revision running on a 48-CPU Intel Xeon E5-2690 v3 host.  Its
vCPU thread was measured at 99.3% of one Xeon core.  Moving a SPARC VM between
playbox and biggie changes the TCG host backend and single-core performance; it
does not change the guest from TCG to native execution.

## Capacity measurements

During one active OpenIndiana guest boot:

- Laptop: 18 CPU cores, 64 GiB RAM, approximately 68% CPU idle.
- macOS memory pressure reported healthy, with 85% system-wide free percentage
  despite macOS using otherwise-idle RAM for cache and compression.
- UTM playbox process: approximately 8.5 GiB resident during the measurement.
- Playbox: 6 vCPUs, 5.8 GiB usable RAM, 4.2 GiB available, zero swap in use.
- Playbox remained approximately 83--84% CPU idle because the inner QEMU
  saturated approximately one vCPU.
- Inner QEMU used approximately 1 GiB resident for the 1 GiB SPARC guest.

Conclusion: neither laptop capacity nor playbox-wide CPU/RAM pressure is the
current bottleneck.  Additional playbox vCPUs will help concurrent host
services or a second guest, but will not proportionally accelerate a single
TCG vCPU.  Six GiB is sufficient for one 1 GiB SPARC guest.  Eight to ten GiB
would be useful only if playbox must run two guests concurrently.

## Recorded baseline boot

The valid baseline process was a completely fresh QEMU, not a reset or reused
post-panic process:

```text
QEMU start: 2026-08-24 22:45:28 UTC
PID:        3874
binary:     /home/niagara/niag-proj/qemu/build/qemu-system-sparc64
image:      OpenIndiana_Text_SPARC_12_2025.niagara-net-v1.fresh.iso
boot:       boot disk
```

The image was a new XFS reflink clone of the preserved net-v1 ISO.  The QEMU
command used the existing `MAP_SHARED` pflash/`hsimd` path.

At 2026-08-24 22:52:32 UTC, elapsed QEMU time `07:03`, the last console output
was still:

```text
OpenIndiana Hipster 2025.12 Version illumos-31d3d510d0 64-bit
os-io NOTICE: Disabling watchdog as watchdog services are not available
```

QEMU was using approximately 103% of one playbox CPU at that point.

Timestamped console capture began at elapsed `06:09`, so milestones after that
point have exact timestamps.  Earlier sampling bounds the kernel banner to
roughly the first minute, but does not provide exact line-by-line timestamps.
The logs at capture time were:

```text
/tmp/oi-baseline-console-timed.log
/tmp/oi-baseline-live.pidstat
```

## I/O evidence

`/proc/PID/io` showed one initial boot-archive read:

```text
read_bytes:  199602176
write_bytes: 0
```

After that read, repeated `pidstat` and `iostat` samples measured:

```text
QEMU reads:  0.00 kB/s
QEMU writes: 0.00 kB/s
QEMU iodelay: 0
playbox block-device utilization: effectively zero
```

The SPARC vCPU thread remained at approximately 94--95% CPU while disk traffic
was zero.  The QEMU main/device thread used another 13--14% CPU and performed
roughly 2,300--2,400 voluntary context switches per second.

Conclusion: a ramdisk, more page cache, or another mmap arrangement may reduce
the initial approximately 190 MiB archive load, but cannot materially improve
the multi-minute silent phase.  The current image is already memory-mapped and
the host has enough RAM to cache it.

## `perf` profile

The baseline was sampled at 99 Hz for approximately 70 seconds.  The capture
contains about 7,000 task-clock samples and lost zero samples.

Important results:

| Symbol/path | Measured share | Meaning |
| --- | ---: | --- |
| TCG vCPU thread | 91.7% inclusive | Work is overwhelmingly guest execution/MMU work |
| `tlb_flush_page_by_mmuidx_async_0` | 31.8% inclusive, 12.2% self | Repeated per-page TCG TLB invalidation |
| `tlb_flush_vtlb_page_mask_locked` | 20.0% inclusive, 19.9% self | Victim-TLB scans while holding the TLB lock |
| `replace_tlb_1bit_lru` | 33.1% inclusive | SPARC/Niagara TLB replacement caller |
| `helper_lookup_tb_ptr` | 15.5% inclusive, 4.6% self | TCG translated-block lookup |
| `get_physical_address` | 3.8% | SPARC MMU translation |
| `qht_lookup_custom` | 4.0% | Translation-block hash lookup |
| `tb_gen_code` | 1.3% | New translation generation is not the primary cost |
| `tcg_flush_jmp_cache` | 1.5% self | Jump-cache invalidation consequence |

The dominant actionable finding is a TLB invalidation storm, not translation
compilation and not storage I/O.

## Source cause and experimental optimization

`target/sparc/ldst_helper.c:replace_tlb_entry()` invalidates an existing SPARC
TTE by iterating over the complete mapping in 8 KiB `TARGET_PAGE_SIZE` steps:

```c
for (offset = 0; offset < size; offset += TARGET_PAGE_SIZE) {
        tlb_flush_page(cs, va + offset);
}
```

Each call takes the TCG TLB lock and can scan the victim TLB across MMU modes.
Large SPARC TTEs multiply that cost by every 8 KiB page in the mapping.

The experimental patch replaces that loop with QEMU's range API:

```c
tlb_flush_range_by_mmuidx(cs, va, size,
                          (1U << (MMU_PHYS_IDX + 1)) - 1,
                          TARGET_LONG_BITS);
```

For small mappings, the range helper retains page-level behavior.  For a range
larger than the TCG TLB, it performs a single full flush instead of repeatedly
locking and scanning for every guest page.

The reviewable patch is in:

```text
patches/0003-sparc-tlb-range-flush.patch
```

The ignored `qemu/target/sparc/ldst_helper.c` checkout contains the applied
working-tree version.  The file under `patches/` is the publishable artifact;
the ignored checkout is not part of the repository.

It compiled cleanly as a separate experimental binary.  The baseline binary
was restored after the build and the live baseline process was not changed.

```text
baseline:
  /home/niagara/niag-proj/qemu/build/qemu-system-sparc64
  SHA-256 7073119a7c2c15527cd93a315ccce30bafacb537228e049eafb4118b46b0a053

experimental:
  /home/niagara/niag-proj/qemu/build/qemu-system-sparc64.tlb-range
  SHA-256 bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b
```

## Console failure observations

These are separate correctness problems that also affect iteration cadence:

1. `boot disk -s` reaches `SINGLE USER MODE` and waits on a blocking tty read.
   The QEMU Niagara serial device currently has no IRQ wired, so serial input
   cannot wake that reader.  The keyboard and installer menus are responsive
   because those paths poll the console.
2. A previous normal boot panicked at trap level 1, trap type `0x41`, with the
   visible stack ending in `qcn:qcn_start+0x14`.
3. After that panic, the QEMU process returned to OpenBoot but retained invalid
   interrupt/UART state.  A subsequent boot reported `Last Trap: Level 14
   Interrupt`, and serial characters were lost or reordered.
4. Do not reuse a QEMU process after this class of guest panic.  Terminate it
   and start a new QEMU process from a fresh reflink test image.

## A/B validation procedure

- [ ] Use a fresh baseline boot and allow it to reach the keyboard prompt, installer
  menu, panic, or an explicitly chosen timeout.
- [ ] Preserve its final timestamped console and pidstat logs.
- [ ] Stop the baseline QEMU; never reset and reuse it after a panic.
- [ ] Create another fresh XFS reflink clone from the same preserved net-v1
  ISO.
- [ ] Launch `qemu-system-sparc64.tlb-range` with the identical machine,
  firmware, memory, monitor, and pflash arguments.
- [ ] Use normal `boot disk`, not `-s`.
- [ ] Record elapsed time to kernel banner, watchdog notice, device
  configuration, keyboard prompt, mounted live media, installer menu, channel
  shell, and any panic.
- [ ] Repeat the 99 Hz `perf` sample for the same interval and compare TLB
  invalidation shares.
- [ ] Compare QEMU CPU seconds as well as wall time.  A boot-time improvement
  without a correctness regression is required before retaining the patch.
- [ ] Run storage/ZFS/channel checks; a faster boot is not sufficient if stale
  TCG translations or incorrect MMU behavior appear.

## Preserved raw evidence

Snapshot directory:

```text
work/openindiana-perf-20260824/
```

| File | SHA-256 |
| --- | --- |
| `oi-fresh-boot.perf.data` | `b079d968f79d802ef8c4ebaab4e671432bca614389aa00fd00d2d914785a73dd` |
| `oi-fresh-boot.perf-report.txt` | `361103bf32465c866cf9a9e8a319f730a2d4203ca09a25662cccd4430a0dbeb1` |
| `oi-fresh-boot.pidstat` | `4ec7e2e70ab7bce92315e1755adafe44a024ae83b7d30a149db807d0405d287f` |
| `oi-baseline-console-timed.log` | `be97ac71ab085fe1142a55bc71bc774bfd771ab878cd3d208a4b287ca288e2df` |
| `oi-baseline-live.pidstat` | `4bcbf13c13a468479e72bab33f25a1c045fe0e0a4226cd2851c730604ede3c4e` |

The two baseline live logs are snapshots taken at 2026-08-24 22:52 UTC; their
playbox `/tmp` originals continue recording the active boot.

## Newly discovered current prior art

On 2026-08-24 we found Masa Murayama's newly published QEMU sun4v distribution
and source stack.  It materially changes the emulator baseline: it documents a
persistent Solaris 10u11 installation using multiple block-backed disks and
supports SMP, although its README explicitly says networking is not supported.

See `notes/MURAYAMA-QEMU-SUN4V-PRIOR-ART.md` for the source comparison and the
controlled evaluation plan.  The current instrumented boot was not disturbed.

## 2026-08-25 noninteractive ISO try 2

A fresh QEMU process (PID 6352) booted the fresh reflink candidate
`OpenIndiana_Text_SPARC_12_2025.niagara-net-v2-noninteractive.try2.iso` in
`openindiana-console:console` on the playbox.  This run used an isolated copy
of the firmware directory and the baseline QEMU binary.

Measured console checkpoints from QEMU start were:

- approximately 34 seconds: illumos kernel banner and watchdog notice;
- 1:20: still in quiet early kernel initialization, using one full host CPU;
- 2:47: the guest PC had moved from `0xff12e7a4` to `0xff26f020`, proving
  forward progress rather than the previously observed `hv_cpu_yield` loop;
- 3:36: hostname, root remount, device configuration, and
  `Preparing text install image for use`;
- 6:35: `hsimd` install media mounted, keyboard setup completed without an
  interactive keyboard or language prompt, and SMF service startup began.

This validates the immediate purpose of the same-length boot-archive patch:
the installer no longer blocks in `kbd -s` or `set_lang` waiting for a serial
interrupt that the current QEMU UART path cannot deliver.  It does not yet
validate installer disk discovery, channel getty wakeups, or networking.

## 2026-08-25 Murayama QEMU source-build baseline

Biggie was selected for the first source build because it has 48 x86-64 CPUs,
188 GiB RAM, and ample storage.  All five repositories were cloned and pinned;
the QEMU source was built at commit
`879fee341ad8307f8f0a0110b4a7dc6d6853d639` with:

```text
../configure --target-list=sparc64-softmmu --enable-debug
ninja -j24
```

The complete clone/configure/build interval was 7 minutes 9 seconds
(00:35:47Z through 00:42:56Z).  The build completed with `BUILD_RC=0` and
produced a 39 MiB x86-64 debug executable reporting
`QEMU 10.2.0 (v10.2.0-sun4v-0.2-dirty)`.  The `dirty` suffix is caused by
partially initialized optional ROM submodules; the pinned QEMU source tree
itself was not edited.

A firmware-only smoke run using the new binary and Murayama's published
`vm_test/hwconf` reached a live `{0} ok` prompt with 2 CPUs and 3072 MiB RAM.
It remains visible in Biggie tmux window `masa-sun4v-build:smoke`.  No disk or
Solaris donor VM was attached.

## 2026-08-25 install run: stale binary caught, range patch rebuilt

The first real install into `oi_hsimd` exposed a process failure in the test
harness: the range-flush source patch existed in the playbox checkout, but the
QEMU binary launched for the install had not been rebuilt after that edit.

Measured identities:

```text
active install QEMU PID: 340544
active executable build ID: c0ee601249d419310bb485d696b92eecad96b1f5
active executable timestamp: 2026-08-19 19:18:04 UTC
patched source timestamp: 2026-08-24 22:49:42 UTC
rebuilt executable build ID: 8ad4fe2ec3d93dc923149035727d48822575b64d
rebuilt executable timestamp: 2026-08-25 03:16:51 UTC
```

After the rebuild, `/proc/340544/exe` correctly showed the old executable as
`(deleted)`: the active process retains the old inode while the path now names
the patched binary for the next fresh launch.  `objdump` on the new binary
showed three direct calls from `replace_tlb_1bit_lru.isra.0` to
`tlb_flush_range_by_mmuidx` (at host text offsets `0x4751ac`, `0x475214`, and
`0x475288`).  This is the executable-level gate that was missing before the
install began.

Short host-GDB attachments did not find a blocked hsimd syscall or QEMU mutex.
The main loop slept in `ppoll`, the RCU thread slept on its event, and the vCPU
thread executed TCG.  One high-value sample caught:

```text
replace_tlb_entry
replace_tlb_1bit_lru
tlb_flush_page_by_mmuidx
guest pc=0x408afc npc=0x408b00 tl=1
```

Five subsequent samples spanned translated guest user code (`0x7af...`),
illumos kernel code (`0x107...`), the sun4v firmware region (`0x408...`), a
SPARC MMU fill, and emulated-clock service.  The guest was therefore executing,
but with directly observed MMU/TLB overhead; it was not one stationary host
spin or a host I/O wait.

The installer UI remained at 18% for more than ten minutes during
`Transferring Contents`, but the raw image allocation proved continued work:

```text
03:05:04 UTC  1,618,944 allocated 512-byte blocks
03:15:06 UTC  2,081,792 allocated 512-byte blocks (writes resumed)
03:18:29 UTC  3,292,056 allocated 512-byte blocks
03:23:02 UTC  4,309,280 allocated 512-byte blocks
```

OpenIndiana's transfer progress is derived from periodic `df -k /a`, not file
or byte completion, and can plateau during a cpio action.  Backing allocation,
QEMU PC samples, and host pressure are the independent signals for this run.
At 03:19 UTC the playbox still had 3.5 GiB available memory, essentially unused
swap, zero PSI memory pressure, zero I/O wait, and five idle host CPUs.

Mandatory next-run gates:

1. assert the full QEMU build ID before launch;
2. disassemble the replacement callsite and require the range helper;
3. boot only a raw reflink child of the preserved installed image;
4. initialize host mailbox controls before guest daemons and establish the
   independent channel shell before launching curses or other blocking UI;
5. collect identical `perf`/GDB samples and wall-clock checkpoints for an
   actual baseline-versus-range-patch comparison.

The old-binary run was terminated at 03:33:45 UTC after allocation stopped at
4,991,288 512-byte blocks for more than seven minutes.  Repeated GDB samples
still found the vCPU executing, predominantly across the firmware interrupt
region (`0x407000`-`0x40ac00`) and a small set of illumos kernel PCs near
`0x10124ec`; this was not evidence of useful installer progress.  F9 could not
be serviced while the foreground transfer was blocked.  Sending Ctrl-C through
QEMU's `-nographic` terminal terminated QEMU itself, so the resulting pool was
not cleanly exported.  The failed image was preserved as
`OpenIndiana_Text_SPARC_12_2025.install-6g.failed-old-c0ee6012.iso`.

The 30-second host perf capture and its resolved text report are preserved in
`work/openindiana-perf-20260824/`:

```text
9f90ebe819fc56778e72d00062eeee2dafc765c87524f723bebeecb6c5fc165f  oi-install-cpio-old-c0ee6012.perf.data
2f5f38dfc7281f0e65b1c49c972031c4e07eb285d0b4ca98293d113af611a69c  oi-install-cpio-old-c0ee6012.report.txt
```

During that specific plateau, the largest self costs were
`helper_lookup_tb_ptr` (13.10%), `tb_lookup` (7.21%), `cpu_exec_loop` (5.15%),
and `helper_ld_asi` (3.43%).  The replacement/TLB helpers were not statistically
dominant in this 30-second window.  Therefore the rebuilt range-flush patch must
be evaluated as an A/B result; this sample alone does not establish that it
will accelerate the cpio phase.

At 03:34 UTC the next boot began in `openindiana-console:console` with one
emulated CPU and verified live build ID
`8ad4fe2ec3d93dc923149035727d48822575b64d`.  Its raw reflink child is
`OpenIndiana_Text_SPARC_12_2025.install-6g.patched-8ad4fe2e.iso`; mailbox
control blocks were initialized at byte 644218880 before QEMU launch, both host
bridges were started exactly once, and a persistent `channel1` tmux window was
created before issuing `boot disk -s -v`.

## 2026-08-25 patched boot and startup-harness incident

The patched one-vCPU run reached these observed checkpoints:

```text
03:34:33 UTC  QEMU start / OpenBoot
03:35:16 UTC  single-user milestone announced
03:37:06 UTC  text-install image mounted
03:37:17 UTC  keyboard prompt (default 47 accepted)
03:40:20 UTC  SINGLE USER MODE maintenance prompt
03:40:40 UTC  primary root prompt and S99niagara completion
03:40:47 UTC  channel-1 SECOND_CONSOLE_OK proof
```

This was substantially faster through media mount than the earlier measured
old-binary boot, but it is not yet a controlled A/B: the image state and boot
path were not identical.  The range-flush patch therefore remains promising,
not proven by elapsed time alone.

The second console was real and bidirectional.  `/etc/rc2.d/S99niagara start`
returned zero and produced one guest-chand for channels 0 and 1 plus a channel-1
rootpty.  The independent pane printed root `id`, the OpenIndiana sun4v
`uname -a`, time, and helper PIDs.  This satisfied the mandatory console gate
before further work.

PPP/SSH did not satisfy their gates.  Repeated manual composition obscured the
existing CI path until the project librarian/recall material was consulted.
The applicable Gilfoyle loop is: pre-register one falsifiable hypothesis and
exact observables, run one disproof query, make one isolated change, rerun the
identical test, independently read back the result, and retain durable
artifacts.  `tools/tmux-run.sh` already exists specifically to avoid long
`tmux send-keys` corruption and must be used.

### Host zombie storm

The actual playbox `tools/chan/host-up.sh` differed from the project copy.  Its
pppd command contained:

```text
persist maxfail 0
```

During failed negotiation, host pppd PID 579344 accumulated many `[pppd]
<defunct>` children.  The previously observed `fork: Resource temporarily
unavailable` was the consequence of this live storm, not steady-state host
load.  A pre-storm snapshot showing only 308/15,277 user cgroup tasks did not
exonerate the rapidly changing process tree.

The parent pppd and waiting host-up processes were terminated.  All zombies
were reaped; the post-cleanup host state was zero zombies, about 261 processes,
and about 4.0 GiB available memory.  QEMU, both host channel bridges, and the
channel-1 guest shell remained alive.

The stale script is preserved on playbox as
`tools/chan/host-up.sh.zombie-storm-20260825` with SHA-256
`5305eee23ecfaa267e0a0c0626820617fee0d9e3d91edf407c18b2e3cf7d73a0`.
The deployed project copy has SHA-256
`0fbc4f8860df54df4decfe4eb49fee348c65b36fb745dadac46e9d452a0e4e29`;
it removes `persist maxfail 0` and adds the QEMU sync hook.

Two additional harness failures remain:

1. The sync hook counts sudo wrappers as QEMU processes and skipped SIGUSR2
   because it saw more than the one real worker.
2. `S99niagara stop` is not idempotent.  It does not reliably terminate/reap
   `guest-ppp-chan.pl` and `guest-rootpty.sh`; repeated stop/start produced
   duplicate rootpty helpers.

No further PPP run is valid until those two defects have checked regression
tests.  The current patched image inherited the unclean partial ZFS pool from
the failed old-binary install and is evidence only, not the next baseline.
