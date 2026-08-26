# Basecamp Evidence Note — hsimd VERSION_1 Native Build/Link Session

Generated: 2026-08-25T14:15Z. Evidence-only anchoring record. No VM/harness mutation was performed to produce this note.

## 1. Native link command (Aggie-reviewed, exact-rule PASS)

```
/usr/bin/ld -z type=kmod -N misc/cmlb -o /tmp/hsimd.v1 /tmp/hsimd.o /tmp/hsimd_asm.o
```
Run natively inside the candidate OpenIndiana guest (isainfo -kv: 64-bit sparcv9 kernel modules; ld -V: Software Generation Utilities - Solaris Link Editors 5.11-1.1790 (illumos)). rc=0.

Key finding: `-z type=kmod` sets the `SUNW_KMOD` dynamic-section tag; it does NOT replace `-dy`. The earlier failed attempt (`-r -dy -ztype=kmod -N misc/cmlb`) failed because `-z type=kmod` and `-d` (`-dy`) are mutually incompatible on this `ld` version (`ld: fatal: -z type=kmod and -d are incompatible`). The corrected, working invocation omits `-dy` and `-r` entirely.

## 2. Source object provenance (SHA/cksum chain)

| Object | SHA-256 (biggie, cross-compiled) | cksum (POSIX, host+guest, byte-identical) | Size |
|---|---|---|---|
| hsimd.o | 9da981e0fb903e007cdcacb7109c0abf01e69d410e44634995d895a2a13630f9 | 3506647269 | 28224 |
| hsimd_asm.o | e2406e4a9dcd6d0c62d814623de931cab34845e168cb5e8ae51f9325c99b0a9d | 451947053 | 776 |

Both compiled on biggie via `sparc64-linux-gnu-gcc-13` cross-toolchain against an isolated git worktree pinned to illumos commit `31d3d510d0d442d3e0ff619d2c80269ab236be55` (sparse-checkout: `usr/src/uts` full tree, widened progressively from `common`→`sparc`+`sun4v`→`sun`→full `uts` as header gaps were discovered). Source `hsimd.c` SHA `b7af2cba8ba12c8ecd5cd6355d8cffb3b18bb1cc9ae06feb7f076f596fbe1167` (Murayama VERSION_1 candidate, unmodified) except one reviewed one-line cast fix (`*result = (void *) instance;` → `*result = (void *)(uintptr_t) instance;`, chosen from a 263:20 majority-idiom count in `common/io` at the exact target commit) — patched copy SHA `1aadce86da1dfa6f23875254c8863ee196b0e62bd6eadf0c5e8fa55f0e18da2b`.

Transfer path: biggie → local transit (`/tmp/*.transit`, deleted after use) → niagara-playbox NFS staging dir `/home/niagara/nfs-oi/hsimd-link-staging-20260825T133600Z/` → guest `/tmp/` via existing candidate NFS mount. Hashes verified identical at every hop.

## 3. hsimd.v1 (linked module) — cksum/size and gate results

- **cksum: 2051293035, size: 28808 bytes** — identical on guest `/tmp/hsimd.v1` and host staging copy after transfer.
- `elfdump -e`: ELFCLASS64, ELFDATA2MSB, ELFOSABI_SOLARIS, EM_SPARCV9, ET_REL — correct SPARC64 relocatable/kmod form.
- `elfdump -d`: **NEEDED misc/cmlb** present; **SUNW_KMOD 0x1** present.
- `elfdump -s`: `_init`/`_info`/`_fini` all defined; **hsimd_tg_getinfo** defined at offset 0x12a4 (VERSION_1 dispatcher, matches source `.o` exactly); **hv_disk_read**/**hv_disk_write** both defined (resolved by the merge, offsets 0x1d28/0x1d40); 8 `cmlb_*` symbols correctly remain UNDEF (resolved at module-load time via the NEEDED `misc/cmlb` dependency — expected, not a defect); 67 total UNDEF entries, all NOTY (no-type), no unexpected FUNC-type unresolveds.

No modload, add_drv, boot-archive injection, or reboot performed at any point.

## 4. NFS transient-export defect (root-caused, fixed)

The harness's own `exportfs -i -o rw "$GUEST_IP:$NFS_EXPORT_DIR"` call (used for every rehearsal's transient per-run NFS ACL) produces Linux `exportfs -i`'s in-memory-only DEFAULT flags: `sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash`. This differs from the long-lived, genuinely-proven-working primary client entry (10.0.5.15/32): `...,rw,insecure,no_root_squash,no_all_squash`. The `secure`+`root_squash` combination blocked the guest's root-owned NFS client (connecting from a privileged port, e.g. 1021) from completing/renewing its TCP session, causing an in-guest `digest`/read call to block indefinitely inside a hard-mount RPC retry loop (parked PC, non-advancing across repeated checks — not a crash).

**Proven fix**: `sudo -n exportfs -i -o rw,no_root_squash,insecure 10.0.7.15:/home/niagara/nfs-oi` — brings the 10.0.7.15 client's flags to exactly match primary's proven `rw,insecure,no_root_squash,no_all_squash`. A new TCP session (`10.0.7.1:2049 <-> 10.0.7.15:1021`) established within a 10-second zero-input watch window immediately after the fix.

**Recommendation for the harness** (not yet applied — flagged for future review): the `exportfs -i -o rw` call at line 1147 should explicitly include `,no_root_squash,insecure` to match primary's proven flags from the start, rather than relying on Linux's differing default.

## 5. `digest` hangs and `cksum` fallback — BANNED

**`digest` must never be run again in this environment, for any reason.** It was explicitly retired after repeated hangs and confirmed unreliable even on small local files; re-invoking it after retirement wasted a full recovery cycle. `cksum` (POSIX) is the sole approved verification tool going forward for this guest; for SHA-256 specifically, copy the file out (already-proven NFS/staging path) and hash it on the host with `sha256sum`.


The illumos/Solaris `digest -a sha256` command, when invoked over the serial guest-command helper against files under the affected export, blocked the shell indefinitely (multiple timeouts, 30-90s windows) — consistent with the NFS RPC-retry root cause above. Even after the export fix, a SEPARATE `digest` invocation against a purely local `/tmp` file also blocked the shell — indicating `digest` itself (not just NFS) has an unreliable/slow interactive behavior on this guest image, independent of the transport fix. **`cksum` (POSIX, standard utility) was used as the verification fallback for all subsequent byte-identity checks** and completed promptly and reliably in every case — recommended as the standard verification tool for this guest going forward, not `digest`.

## 6. Guest-only ETX recovery method (used twice, both times successful)

When the guest's foreground shell is wedged (no prompt returned within the `r0-guest-command.exp` timeout, confirmed via QEMU monitor `info status`=running and non-advancing `info registers` PC across repeated zero-input checks), the proven recovery is:
```
printf '\003' | socat - UNIX-CONNECT:<serial.sock>
```
This writes exactly one ETX (0x03) byte into the GUEST's own serial tty line discipline via a fresh, one-shot socat writer — data delivered into the guest, not a Ctrl-C sent to the outer/host terminal or QEMU process, and therefore cannot directly signal QEMU itself. The guest's own cooked-mode line discipline converts ETX to SIGINT for the wedged foreground process. Confirmed effective via an immediate follow-up `echo <marker>` probe returning cleanly both times this session. No Ctrl-C, Ctrl-D, or other host-side/console-level input was ever used.

## 7. Session artifact/state summary

### 7a. Harness/tooling defect: long guest commands need async job + host-side observability

`r0-guest-command.exp` blocks the serial connection for the full duration of one foreground command with a fixed `expect` timeout. For large transfers (e.g. copying the ~192MB boot-archive candidate over NFS, observed rate ~120-140KB/s in this environment, implying 20+ minutes for a full copy), this causes the wrapper to report a false "timed out" even though the underlying guest command is genuinely still progressing (confirmed via QEMU `info registers` PC advancing, and via directly watching the destination file's size grow host-side across repeated `wc -c` polls with zero serial input). Sending an ETX to interrupt what is actually a legitimate long-running copy is destructive (produces a truncated, unusable partial file) and must never be done reflexively on a timeout — only after independently confirming (PC static across repeated checks, AND file size not growing) that the command is truly wedged, not merely slow. The correct pattern for any future long guest operation: launch it as a backgrounded guest job (e.g. `nohup cp ... &` plus a short guest command that returns immediately), then observe completion entirely host-side via destination file-size stabilization (and ideally a sidecar "done" marker or final cksum written by the guest job itself), never via a single blocking foreground `expect` call with a fixed timeout.

### 7b. Two-phase boot-archive copy-back behavior (host↔guest, over NFS)

**First attempt** (fixed target filename `boot_archive.hsimd-v1-MUTATED-20260825T143500Z`): the guest `cp` was still genuinely in progress when a `r0-guest-command.exp` timeout occurred; one ETX was sent to recover the wedged shell (consistent with the proven recovery method), which killed the in-flight `cp`, leaving a truncated partial file (30801920 of 192595968 bytes). **This partial file was deleted** (not preserved — it was produced by an intentional recovery action, not an unexplained failure) before retrying.

**Second attempt** (same target filename, relaunched): the guest `cp` was again still genuinely in progress at the next `expect` timeout. This time, the target file was **renamed to `.partial-interrupted` while the guest's cp continued writing to it via its already-open file descriptor** — confirmed by watching the renamed file's size continue to grow steadily host-side (21725184 → 136708096+ bytes across multiple zero-serial-input checks, ~120-140KB/s), proving the rename does not disrupt an in-progress NFS write on an already-open handle. **No ETX was sent this time** — per corrected guidance, a growing file size is decisive proof of a legitimate, not wedged, transfer, and interrupting it would be destructive. This is the standing procedure going forward: never send ETX to a transfer whose destination file is still growing.

- All live VMs (primary R0 PID 709698, Retry #13 rehearsal PID 761173 — paused via monitor socket, never resumed — and the tlb-range candidate PID 771681) remained alive and untouched throughout every step of this session.
- Staging directory `/home/niagara/nfs-oi/hsimd-link-staging-20260825T133600Z/` (host, mode 0777 to accommodate the root-squashed-then-fixed guest client) contains: `hsimd.o`, `hsimd_asm.o`, `hsimd.v1` — all hash/cksum-verified at every hop.
- Header worktree `/home/ryan/devel/masa-sun4v/hsimd-version1-candidate/header-worktree-31d3d510` (biggie, isolated `git worktree`, detached at commit `31d3d510d0d442d3e0ff619d2c80269ab236be55`, sparse-checkout widened to full `usr/src/uts`) remains in place; the donor gate's main worktree (`/export/solaris/illumos-ppp-src`) was never modified (confirmed clean `git status` and unchanged sparse-checkout list at every checkpoint).

### 7c. Confirmed lifecycle root cause and fixes (code, not speculative)

**`tools/chan/host-chan.py` — bridge accept() deadlock on peer death with queued data**: `conn.send(sendbuf)`'s `except OSError` handler set `eof=True` but left `sendbuf` non-empty; the loop-exit condition `eof and not pending and not sendbuf` could then never become true, permanently stalling the bridge's single-client accept loop. **Fixed**: `sendbuf = b""` added in the same except block. Verified via a focused host-side regression test (positive: fix resolves the deadlock in 1 iteration; negative: reproducing the pre-fix code confirms it genuinely hangs — 167 iterations with no exit, `sendbuf` still full).

**`tools/chan/guest-ppp-chan.pl` — guest pppd exits when host PPP dies, instead of persisting**: the `exec('/usr/bin/pppd', ...)` argument list never included `persist`/`maxfail 0`, so a host-side link death (e.g. the LCP echo-timeout observed this session) caused the GUEST's own pppd to exit too, leaving nothing to answer a fresh host-side relaunch attempt — exactly matching the `LCP: timeout sending Config-Requests` failure observed when relaunching against a live guest whose own pppd had already exited. **Fixed**: added `'persist', 'maxfail', '0'` to the exec argv.

**Harness host pppd invocation** — pinned `lcp-echo-interval 0 lcp-echo-failure 0` on the host side (already had it on the relaunch attempt; now baked into the harness's own primary launch path) to prevent the original resource-starvation-induced echo-timeout (host pppd killing a healthy link because the guest was too busy with heavy I/O to answer LCP echoes in time).

**Payload tar re-staged**: `guest-ppp-chan.pl` changed size (2520→2552 bytes). **CORRECTION recorded**: an initial attempt overwrote the anchor `basecamp-r0-bootstrap.proven.tar` in place — a violation of the anchor invariant. Recovered without data loss: the untouched playbox copy (confirmed SHA `d3820b9eb2e8adff62dff30cdc13ca67c8b83f994dd3d2c2a6e33e857a0e807b`, 30720 bytes) was copied back to the local `.proven.tar` path and verified byte-identical; the harness's `PAYLOAD_SHA`/`PAYLOAD_SECTORS`/member-hash defaults were reverted to the exact original baseline values. A correctly-scoped candidate was then rebuilt from a FRESH extraction of the restored proven tar (`basecamp-r0-bootstrap.ppp-persist-candidate-20260825T161500Z.tar`, SHA `966918bd15dc27dc6fa81e60d16911526f4fbc77c2965286f2023f40a584cfcf`, 32768 bytes / 64 sectors), preserving `guest-chand`/`guest-echocli` byte-for-byte (confirmed via `cmp`) and all members' uid/gid (0/0) and mtime (Aug 24 17:00) except the one intentional content change to `guest-ppp-chan.pl` (diff: exactly the added `'persist', 'maxfail', '0',` line). The harness now supports `PAYLOAD_TAR`/`PAYLOAD_SHA`/`PAYLOAD_SECTORS`/per-member `PAYLOAD_SHA_GUEST_*` env-default overrides (same `${VAR:-default}` pattern as `ARC`/`QEMU`), so the candidate can be tested via explicit override without ever mutating the baseline defaults — verified via `bash -n`, default-resolution preflight, and explicit-candidate-override preflight, all PASSED. New harness script SHA: `1b2d1f3619db7ed7df1849090b5ba42de0dbbe85ace3342818100bc7baf2538e`. Harness NOT repointed to the candidate and not launched; awaiting Aggie PASS.

**10.0.7 PPP explicitly NOT recovered further** — preserved as evidence exactly as instructed. The guest's own pppd there had already exited (unpatched binary, no `persist`), and its single shell remains blocked in the uninterruptible NFS wait; no further action taken on that lane.

### 7d. Candidate tar `966918bd...` — INVALID-SOLARIS-TAR, never reuse or overwrite

**First 10.0.9 launch attempt (RUNDIR `basecamp-r0-rehearsal-20260825T160432Z`, QEMU PID 788318) FAILED CLOSED at elapsed 153-155s, rc=1.** Confirmed progress before failure: `GATES_REACHED=17`, dynamic HSFS device discovery correctly found `/dev/rdsk/c4d0s2` (not a hardcoded ID), DTrace exact-probe-count gate passed at elapsed 153s (72893 probes, matching the proven baseline), `/usr` mounted from a dynamically-assigned lofi node, and the pinned 32768-byte payload was extracted from the guest disk and verified byte-identical to the pinned `PAYLOAD_SHA` via `dd`. **Root cause, confirmed via replay.log**: Solaris/illumos `tar` rejected the archive: `tar: PaxHeader/guest-chand: typeflag 'x' not recognized, converting to regular file` (×3, one per member) → `rc=1`. The candidate tar (SHA `966918bd15dc27dc6fa81e60d16911526f4fbc77c2965286f2023f40a584cfcf`) was built with macOS `bsdtar`, which silently inserted PAX extended-header (`typeflag x`) entries — a format Solaris's own `tar` does not understand. The earlier judgment that macOS-provenance xattr warnings during preflight were "harmless" was **incorrect** — they were symptomatic of this real, launch-blocking incompatibility. **SHA `966918bd...` is marked INVALID-SOLARIS-TAR and must never be reused or overwritten.** Failed run/image/manifest preserved as evidence at `/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T160432Z` and `/home/niagara/sun4v/images/basecamp-r0-rehearsal-20260825T160432Z.iso` (fail-closed cleanup already ran; not touched further).

### 7e. IMMUTABLE ANCHOR — first fully green 10.0.9 run (retry #2, GNU-tar-fixed candidate)

**STATUS=PASS, RC=0, GATES_REACHED=27, ELAPSED_S=177.** Independently confirmed from `replay.log`: PPP link at elapsed 170s, NFS at elapsed 177s, DTrace `72893 probes (exact, in-guest assertion)`, `REPLAY PASSED` (FINAL_PASS) at elapsed 177s.

| Artifact | Path (niagara-playbox) | SHA-256 |
|---|---|---|
| Disposable image | `/home/niagara/sun4v/images/basecamp-r0-rehearsal-20260825T161311Z.iso` | `4e268ae0948e699b179f61d95decc7cb78f69241426842d7822f32148220dc9f` |
| Manifest | `/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T161311Z/manifest.env` | `73d153338fedb0d3621a0e45054b0cd480fad02237448fd1400cf28f6b0bc9fd` |
| Replay log | `/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T161311Z/replay.log` | `14996f35912245f6e8684ece9a4ad7ef076ae2af848e47895445ecaf5b4944e2` |
| pppd debug log | `/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T161311Z/pppd-debug.log` | `02bc56d05fca14a6e678c4a2238aa30d5565d095a1791c6e64105ecf6877cb47` |
| Candidate payload tar (GNU-tar, Solaris-compatible) | `/home/niagara/niag-proj-anchor-staging/basecamp-r0-bootstrap.ppp-persist-candidate-GNUTAR.tar` | `d347b37657da7ac45fd3e755619086d5e6ddaea6211fe130ad58466c83a9b6c1` |

**Immutable pinned inputs this run used**: `SRC_ISO_SHA=173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04`, `ARC_SHA=f334e542c0ba0ac35fea8bf8f6270f813e984727a6d5c77a3c6fda0906cee376` (unpatched baseline archive — this run did NOT use the reviewed hsimd VERSION_1 archive), `QEMU_SHA=bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b`, `PAYLOAD_SHA=d347b37657da7ac45fd3e755619086d5e6ddaea6211fe130ad58466c83a9b6c1`.

**Exact reproduction command:**
```
export QEMU=/home/niagara/niag-proj/qemu/build/qemu-system-sparc64.tlb-range
export QEMU_SHA=bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b
export PAYLOAD_TAR=/home/niagara/niag-proj-anchor-staging/basecamp-r0-bootstrap.ppp-persist-candidate-GNUTAR.tar
export PAYLOAD_SHA=d347b37657da7ac45fd3e755619086d5e6ddaea6211fe130ad58466c83a9b6c1
export PAYLOAD_SECTORS=60
export PAYLOAD_SHA_GUEST_PPP_CHAN=2b963b0caf1c2c3628ad17daee07f95697649b1dc3522140c6209424ef774ff6
export NIAG_REHEARSAL_HOST_IP=10.0.9.1
export NIAG_REHEARSAL_GUEST_IP=10.0.9.15
bash tools/basecamp-r0-cold-anchor.sh   # harness SHA 1b2d1f3619db7ed7df1849090b5ba42de0dbbe85ace3342818100bc7baf2538e
```

**VM state**: QEMU PID 789613, left RUNNING (not paused, not torn down) at your explicit instruction — preserved as-is alongside primary R0 (709698), Retry #13 paused (761173), and the tlb-range candidate (771681). No reboot, no serial input, no mutation performed on 789613 after PASS.

### 7f. Run `basecamp-r0-rehearsal-20260825T162639Z` — INVALID-ACTIVE-SCRIPT-OVERWRITE

**Root cause confirmed, not speculative.** This run failed at elapsed ~164-168s with `line 798: e: command not found`, immediately after reaching `MAINTENANCE_SHELL`. The failure was caused by an `scp` overwrite of the SAME staged script path (`/home/niagara/niag-proj-anchor-staging/ppp-persist-fix-20260825T160354Z/tools/basecamp-r0-cold-anchor.sh`) that the still-running bash process was actively reading from — `bash` reads script source incrementally as execution proceeds (not slurped whole into memory up front for a script sourced from a live file path), so overwriting the file mid-run shifted line offsets and caused a comment fragment/backtick sequence to be misinterpreted as an executable command (`e: command not found`). **This is a script-lifecycle defect, not a logic bug in the tmux-invariant code** — both tmux windows and the descent-proof assertion were already confirmed working correctly in this run's own log before the corruption hit. Marked **INVALID-ACTIVE-SCRIPT-OVERWRITE**; evidence (run dir, image, manifest, log) preserved untouched.

**Corrective action for future launches (in progress, tracked separately, NOT yet applied to the harness)**: each launch must first copy the harness + helper scripts into a uniquely named, immutable per-run release directory and execute THAT copy — never a shared mutable staging path that a subsequent edit could touch mid-run. A guard should reject any source SHA change while a run against that path is active. **No further QEMU launch will occur until this lifecycle defect is reviewed and fixed.**

**Staged path frozen, byte-for-byte, not touched further this session**: `/home/niagara/niag-proj-anchor-staging/ppp-persist-fix-20260825T160354Z/tools/basecamp-r0-cold-anchor.sh`, confirmed SHA `227d8ce109811f988c0eff995bd1c03d65330a9a830896b4afbce51cbd63e7b9` — this is the exact byte content used by the immediately-following run `basecamp-r0-rehearsal-20260825T163112Z`, which reached **STATUS=PASS** (confirmed: DTrace 72893 probes, PPP `10.0.12.1<->10.0.12.15`, NFS ACL, tmux session `r0-rehearsal-20260825T163112Z` with both `qemu-owner` and `replay` windows present and the descent-proof assertion passing, QPID 792557 left running for inspection per the harness's own design).

### 7f. Finalized hSIMD-v1 BIG-DISK candidate — verified, candidate + rollback anchors confirmed

Built on the dedicated 10.0.10 rehearsal lane (RUNDIR `basecamp-r0-rehearsal-20260825T164820Z`, QEMU PID 794288, STATUS=PASS/RC=0/GATES_REACHED=27 for the unmodified baseline boot, then module-mutated post-boot). Guest disk work: `hsimd.version0.orig` backed up inside the mounted UFS copy (`root:sys`, `0755`, 19576 bytes, cksum `851234025 19576`); active `/platform/sun4v/kernel/drv/sparcv9/hsimd` replaced with the reviewed `hsimd.v1` (`root:sys`, `0755`, 28808 bytes, cksum `2051293035 28808`).

| Artifact | Path (niagara-playbox) | SHA-256 / cksum |
|---|---|---|
| Finalized mutated big-disk archive | `/home/niagara/nfs-oi/hsimd-link-staging-20260825T133600Z/boot_archive.hsimd-v1-bigdisk-MUTATED-20260825T170500Z` | SHA `1851f98012407ddd088365ffa0577889829b6739999f0e5804eca480ab477467`, cksum `3268174943 192595968`, exactly 192595968 bytes |

Copy-back verified byte-identical between guest (`/tmp/ba-bigdisk.candidate`, cksum `3268174943 192595968`) and host finalized copy — exact match. RO-remount on the same VM confirmed: active `hsimd` cksum `2051293035 28808` (matches reviewed `hsimd.v1` exactly); rollback `hsimd.version0.orig` cksum `851234025 19576` (matches original VERSION_0 module exactly); both `root:sys` mode `0755`. Clean unmount/lofi-detach, no dangling mount state.

**Candidate and rollback anchors both independently verified before proceeding to the next rung**, per instruction. VM 794288 left running, untouched since verification (no reboot).

## 9. Planned 10.0.8 disposable boot-archive rehearsal — launch environment / test matrix / manifest template (NOT YET LAUNCHED)
### Launch environment (env-overrides on top of the now-patched harness, script SHA `f720811b82e83f22179639734447f4bd134ee827fc8eb72b65eb32589eb74442`)

```
QEMU=/home/niagara/niag-proj/qemu/build/qemu-system-sparc64.tlb-range
QEMU_SHA=bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b
ARC=<path to the finalized, RO-remount-verified mutated boot-archive candidate>
ARC_SHA=<whole-file SHA-256 of that same finalized candidate, computed after the copy-back completes>
NIAG_REHEARSAL_HOST_IP=10.0.8.1
NIAG_REHEARSAL_GUEST_IP=10.0.8.15
```
`SRC`/`SRC_SHA` remain the unmodified pinned defaults (`OpenIndiana_Text_SPARC_12_2025.iso.clean`, `173ade54...`) — the base ISO is never touched by this work; only `ARC`'s content changes.

### Pre-launch verification matrix (all must pass before launch)
1. Candidate boot-archive whole-file byte count == 192595968 (== `ARC_LEN_SECTORS * 512`) — the new size gate itself will also re-check this live at runtime, but confirm host-side first.
2. Candidate boot-archive whole-file SHA-256 computed and recorded (becomes the launch `ARC_SHA`).
3. RO-remount of the finalized candidate (fresh `lofiadm -a` + `mount -F ufs -o ro`) confirms: active `/platform/sun4v/kernel/drv/sparcv9/hsimd` has SHA `40201a31bb6b721975ae8ced12f22b1e6f620c8863d352ba411472e464a9a1a0`, cksum `2051293035 28808`; backup `hsimd.version0.orig` present with cksum `851234025 19576`; both files `root:sys`, mode `0755`.
4. `bash -n` + static `--preflight-only` on the patched harness (already done, PASSED, this turn).
5. Runtime `--runtime-preflight-only` on niagara-playbox, run WITH the new env-overrides set, confirming the new size gate reports `inputs OK` (not yet run — requires the finalized candidate + its SHA, both still pending the in-progress copy).
6. Primary R0 (709698), Retry #13 paused rehearsal (761173), and the tlb-range candidate (771681) all confirmed alive/unchanged immediately before launch — same standing invariant as every prior launch this session.

### Expected gate sequence (unchanged from every prior rehearsal, replayed against the new ARC content)
IMAGE_BUILT → preflight-no-collision → deploy/qemu-owner → OBP boot → maintenance shell → DTrace probe count → channel-echo framed gate → dynamic HSFS device discovery (`/usr/lib/fs/hsfs/fstyp` loop, unchanged) → lofi attach (dynamic node, unchanged) → PPP link (10.0.8.1↔10.0.8.15) → 4 required assertions (host→guest ping, guest→host ping, external ping, DNS) → transient NFS ACL add (now using the FIXED `rw,no_root_squash,insecure` flags from this session's other patch) → NFS mount → **new, driver-specific verification step (not yet coded): confirm the booted guest's own `/platform/sun4v/kernel/drv/sparcv9/hsimd` matches the same SHA/cksum as the pre-boot RO-remount check (proves the repackaged archive round-tripped through actual OBP boot correctly)** → FINAL_PASS.

### Manifest template (fields expected in `manifest.env` for this run, extending the existing schema)
```
RUNDIR=<basecamp-r0-rehearsal-<TS>>
QEMU_PID=<pid>
QEMU_PATH=/home/niagara/niag-proj/qemu/build/qemu-system-sparc64.tlb-range
QEMU_SHA=bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b
ARC_PATH=<finalized candidate path>
ARC_SHA=<finalized candidate whole-file SHA>
ARC_SIZE_BYTES=192595968
HOST_IP=10.0.8.1
GUEST_IP=10.0.8.15
GATES_REACHED=<int>
STATUS=<PASS|FAIL>
RC=<int>
MILESTONE_*_ELAPSED_S=<per-phase timings, same schema as Retry #13/candidate>
HSIMD_ACTIVE_SHA=<expect 40201a31...>
HSIMD_ACTIVE_CKSUM=<expect 2051293035 28808>
HSIMD_BACKUP_PRESENT=<true|false, expect true>
HSIMD_BACKUP_CKSUM=<expect 851234025 19576>
```

### Explicitly not yet done
- The candidate archive copy-back (host↔guest NFS transfer) is still in progress (155353088/192595968 bytes at last check, growing — legitimate, not interrupted) — no polling scheduled; will be checked again only after further code/documentation work, or on your instruction.
- No RO-remount verification of the finalized candidate has happened yet (blocked on the copy completing).
- No `ARC`/`ARC_SHA` values have been assigned for a real launch — placeholders above.
- No launch, no serial input, no guest interaction performed since the size-gate code review began.
- Harness patch (3 logical fixes + 1 size gate) sent to Aggie for final script PASS this turn, SHA `f720811b82e83f22179639734447f4bd134ee827fc8eb72b65eb32589eb74442`.
