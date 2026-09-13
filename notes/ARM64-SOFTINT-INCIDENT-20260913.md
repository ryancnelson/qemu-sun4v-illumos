# ARM64 Niagara incident, 2026-09-13

## Scope and method

Ryan authorized evidence capture, debugging and iteration on the running
`oi-arm-sep12` container. Do not terminate its `--rm` container before exporting
the evidence and guest disks. No QEMU migration or unrestricted HMP client.

Asked `~/bin/librarian` for Gilfoyle and read the complete local
`~/devel/gilfoyle/SKILL.md` and memory reference. Follow discovery → one
falsifiable hypothesis → discriminating test → record result. Its init found
no configured orgs and exited 1; mem-write found no initialized personal KB.
Record evidence here instead of configuring unrelated observability systems.

## Observed before intervention

- Native ARM64 image `localhost/sparc64-qemu-openindiana-20g:arm64-smp-local`.
- QEMU source archive revision `049affb20df67162cf58deeaf74d5ad4b83cbdc3`,
  project build worktree base `5cad53a`.
- Guest reported two online CPUs. Console/channel output stopped together at
  approximately 2026-09-13 02:20:30 UTC, at 39,760 KiB of a GCC tarball download.
- QMP responsive and running; host vCPU threads 56 and 57 executing, main loop
  polling. No panic in console or QEMU error log.
- Guest unix extracted with existing iso-extract.py and Sleuth Kit from the
  immutable installer boot archive; SHA256
  `300e2b11956675686a6864bbc398eff96ab0202017e7a996e2804c995807294c`, matching
  the project's previous installed-kernel inventory.
- PCs `0x1044074` and `0x104407c` resolve to `cpu_halt`; caller
  `0x106e7b0` resolves to `idle`. Other samples enter hv_cpu_yield firmware.
- CPU0 stick comparator remains `255845200000` (`0x3b918ff080`), enabled,
  qtimer expiration `-1` (not queued), softint `0`. CPU1 comparator and queued
  expiration advance over repeated samples.
- Running binary's `stick_irq` uses atomic OR to set bit `0x10000`.
  `helper_set_softint` and `helper_clear_softint` use ordinary ARM64 load,
  modify, store on the same field. This establishes a possible lost update,
  NOT that this interleaving caused this particular incident.
- Added host-container diagnostic packages gdb, SPARC binutils, file and
  Sleuth Kit. No guest packages installed. GDB inspections detach explicitly.

## Capture

`tools/capture-softint-incident.py` is a one-incident tool with validated target
PID and fixed QMP allowlist. It captures three live samples, then pauses via
QMP, captures host core (including guest RAM), copies writable disks, firmware,
binary, kernel and logs, and resumes in finally. Core is sensitive: private
directory and umask 077; do not publish it.

First attempt at 02:34:14 saved a live sample but GDB Python incorrectly included
`end`; detach succeeded, script aborted before QMP pause. Removed the stray
Python token and reran at 02:34:38 UTC.

## Hypothesis H1 / planned discriminating test

H1: Loss of CPU0's system-timer wakeup is sustaining the freeze.
After verified capture, reassert only CPU0's STIMER bit and interrupt request,
with vCPUs stopped under GDB, then detach. Record exact pre/post values.
Disproof: no resumed comparator scheduling or guest/channel progress after
the wakeup is consumed. Support: comparator re-arms and guest I/O resumes.
This tests the sustaining condition, not the origin of the missing bit.

H2 (only if H1 supported): non-atomic guest softint updates race the timer
thread. Establish a deterministic lost-update regression against actual helper
code, then test atomic update patch through the existing ARM64 image workflow.
Do not equate a race in source with a proven historical interleaving.

## H1 result: supported

All exported top-level artifact checksums passed at
`/var/tmp/niagara-softint-20260913T023438Z` on the Mac. The capture is private
and approximately 25 GiB on the Mac (sparse disk copies expanded in transport).

At 2026-09-13T02:38:05.340715Z `probe-softint-wakeup.py` validated CPU0's
unchanged comparator, absent timer and zero softint, then set only softint
`0x10000` and CPU_INTERRUPT_HARD `2` while GDB had all host threads stopped.
Detached without reset or inferior function calls.

Within the following sample, the console printed new download progress and
processed pending Ctrl-C, returning to `/jack/toolchain-downloads` prompt.
CPU0 comparator became `0x6d33c231c0`, qtimer expiration `2345099000000`, and
softint returned to zero. Missing timer wakeup was the sustaining condition.
The historical lost-update interleaving remains unrecorded; H2 needs a test.

## H2 regression / patch

`scripts/test-softint-atomic.py` extracts the actual three helper bodies from
the pinned source. It injects the timer OR at do_modify_softint entry, after
the update argument has been computed but before the old implementation stores
it. This is a deterministic interleaving, not a probabilistic load test.

Unpatched source: seven ordinary-semantics cases pass; timer-arrival during set
fails (0x8 vs 0x10008), timer-arrival during clear fails (0 vs 0x10000).
Patch 0007: all nine pass. Set and clear use atomic fetch-or/fetch-and; full
register writes use exchange. Notification uses the atomic operation's old
and new values rather than rereading shared state to infer whether it changed.
Added regression to the existing appliance Dockerfile before the QEMU build.

Edits are isolated on `codex/softint-race-debug` in the existing ARM64 build
worktree. Main checkout and published images remain unchanged.

## Shutdown complication and recovery

Podman VM has 3.5 GiB RAM and no swap; simultaneous full guests risk OOM.
Issued guest `sync; shutdown -y -g0 -i0` intending to halt then preserve a clean
disk before testing. Returning to firmware instead reached MAXTL (TL6, traps
0x32, firmware PCs f0243430 and 410768); QEMU exited and --rm removed the
container and anonymous volume before a post-shutdown copy could be taken.
Captured tmux transcript as `shutdown-console.txt` in the exported evidence.

No original container is left. Verified pre-intervention core and full disk
copies remain on the Mac. Recovery uses that paused, crash-consistent snapshot,
not a claimed clean shutdown image. No guest configuration or toolchain
installation was performed between capture and shutdown; resumed curl and
pending Ctrl-C were the only workload progress. The missing most-recent disk
state must not be represented as preserved.

Named recovery volume: `oi-arm-softint-preserved-20260913`. Restore original
immutable assets from the existing embedded bundle and replace root/NVRAM with
the verified capture. Keep this volume separate from the writable trial clone.

Recovery disk SHA256 verified after transfer:
`266dae08016df8e317ab5c779961853b5ea88ccc7eb4fff1159d331cd1c27ad5`;
NVRAM SHA256 `e1cf2fe5626d9c69b1ef62f90ab035f5f5761b7f7e62c6de744782ac6aebe47a`.
Writable trial volume is `oi-arm-softint-trial-20260913`.

## Patched runtime validation

Final local image `localhost/sparc64-qemu-openindiana-20g:arm64-softint-test`,
ID `cb9935b2df30112577b321efcd251603d2da2baab2a92336d7865e34f6eb4801`.
Built via existing ci-self-contained-oci.sh build. Console/network/cache/
OpenBoot/SMP policy gates, nine helper cases, source and binary TLB gates pass.
Compiled ELF is aarch64 and set/clear/write call respectively
`__aarch64_ldset4_acq_rel`, `__aarch64_ldclr4_acq_rel`,
`__aarch64_swp4_acq_rel`.

Added opt-in `NIAGARA_DEBUG_GDB=1` to entrypoint; local private
`/state/gdb.sock` only, no TCP listener. Default remains disabled.
Booting `oi-arm-softint-test` (no --rm) on the writable trial clone with this
option enabled. Existing smoke-login and guest-command workflows are used.

### First boot failed / next discriminating test

Installed gdb-multiarch in the trial container and attempted gdbstub preflight
during boot. Target description was rejected; forcing sparc:v9 inherited little
endian and printed byte-swapped PCs. Detached. Second attempt loaded the matching
Solaris unix and forced big endian, but target description was again rejected
and connection did not yield valid state. These samples are NOT usable guest
architectural evidence. The boot ended at OpenBoot with
`ERROR: /packages/cpio-file-system: Last Trap: Fast Data Access MMU Miss`.

Exported full /state and inspect JSON. H3: debugger attachment during early boot
contributed to the failure. Test: restart same container/image/volume without
any debugger attachment until login. If the same failure recurs, H3 loses support.
No change to atomic patch, firmware, NVRAM source or disk in this comparison.

Retry without debugger attachment reached automatic login. distpool is ONLINE;
guest resolver config survived (nameserver 8.8.8.8, hosts files dns). Existing
self-smp had a false-pass: /usr/bin/psrinfo missing and subsequent mpstat masked
the failed awk assertion. Corrected to /usr/sbin/psrinfo and && mpstat, added
policy assertions, and reran successfully. Both CPU0 and CPU1 online.

self-network passed bring-up and BBS but failed host-container ping with
`exec: Operation not permitted`; do not count the full suite as passed. Guest
ping to 10.0.5.1 and DNS getent for dlc mirror pass. Preserve user's resolver
settings rather than forcing the suite's different expected nameserver.

Guardrail exception: single-invocation GUARDRAIL_BYPASS=1 for the existing
guest-command wrapper containing native illumos curl. The host ~/bin wrapper
does not exist inside the guest; actual guest download is the workload under
test. No bypass for host service/API operations.

Final metadata-complete image is
`d0c9a1f83239ab97134f3b5328a28f9cde708f8a63344aadce2e7faca057c9cb`.
Running trial and final image QEMU binaries have identical SHA256:
`714022d0fd75814de20178b889d1bec11f68258be9f7cc6a69fe59ba84ae1f8e`.
The final metadata-only rebuild updates both OCI labels and runtime manifest
to include 0007, without changing the tested emulator binary.

Resumed GCC download from saved 33.62 MiB. It passed the original 83-second
failure point and exceeded 173 MiB of additional transfer at 183 seconds.
Full-transfer and native-compiler validation still pending at this entry.

Full download subsequently completed with guest-command rc0, including sysroot:

- GCC tarball SHA256: `7c2193369b0f6accd56c4fc5cacc3cd175e387b20ed942b13a1e710a6c7ee038`
- Sysroot SHA256: `753ca4b2e24a2a2c3d3ac5de3a590c6b1a106f8fe5cbd89f78f70f80431cb027`

No timer reinjection or debugger attachment during this workload. Proceeding
with the existing OPENINDIANA-NATIVE-GCC13-TOOLCHAIN notes for extraction and
native C compile/run, also providing a further CPU/disk workload check.

## Release implementation update

The maintained private CI branch `codex/cross-arch-golden-volume` at
`89baac8` already provides seed assembly, clean-shutdown freezing, two cold
boots per native architecture, and gated multiarch publication. The release
worktree `/var/tmp/qemu-sun4v-release` extends that implementation on
`codex/softint-dualarch-release`. The competing draft orchestration was
discarded; its files were never published. AMD64 build execution moves to
Biggie because ec2cicd has only 1.5 GiB free on Docker's filesystem.

The local working guest subsequently cold-booted successfully with the
8 GiB Podman VM (`recovery-8gb-boot.log`). GCC extraction resumed there.
The private checkpoint volume and OCI archive remain separate from the
clean-source public release.
