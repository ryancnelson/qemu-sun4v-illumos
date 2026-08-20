# Shell — progress notes (2026-08-20)

## FACT — assignment scope
Assigned: review the uncommitted `CURRENT-STATE.md` diff for factual accuracy
against `THE-TRIBBLIX-HSIMD-STORY.md`, `HSIMD-ZFS-VALIDATION-PROCEDURE.md`, and
the shared whiteboard. Strict TDD/Gilfoyle discipline: FACT/HYPOTHESIS/PLAN,
falsifiable checks, independent readback. No SSH, no console input.

## FACT — the reviewed diff landed mid-review
At review start, `git status` showed `CURRENT-STATE.md` and
`HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` modified (unstaged), branch ahead of
origin by 1 commit (`be680a8`). By the time review completed, another agent
(per whiteboard: Shell #2 / Codex) had committed that exact diff as
`dd252f0 docs: correct falsified s7 claims, add corrected Stage 4 matrix`.
Verified with `git show dd252f0:CURRENT-STATE.md | diff - CURRENT-STATE.md`
— byte-identical, zero diff output. Branch is now ahead of origin by 2
commits. No edit was made to either file during this window (collision
avoided by design: review only, no writes to actively-touched files).

## FACT — line-by-line verification performed (all against current CURRENT-STATE.md, tag #7BE0/#436C)

1. **SHA-256 math, independently recomputed, not asserted:**
   `sha256(bytes(512)) = 076a27c79e5ace2a3d47f9dd2e83e4ff6ea8872b3c2218f66c92b89b55f36560`
   (computed locally with Python `hashlib`). This exactly matches the digest
   CURRENT-STATE.md:229-231 attributes to the sector-37564 read, and the
   caveat at CURRENT-STATE.md:232 ("that digest is also the SHA-256 of 512
   zero bytes") is TRUE. The claim at line 233-234 that sector 0's digest
   (`77d82f36...`, line 228) "differs" from the zero-hash is also TRUE
   (`77d82f36... != 076a27c7...`). The discrimination logic in lines 232-238
   is internally sound: it rules out "hsimd always returns sector 0" but not
   "hsimd zero-fills any nonzero offset."

2. **Sector 37564 identity, independently recomputed:** CURRENT-STATE.md:229
   calls sector 37564 "the first sector of the embedded boot archive."
   `HSIMD-ZFS-VALIDATION-PROCEDURE.md` line 373 gives the boot-archive extent
   as `bs=2048 skip=9391` (ISO9660 LBA 9391). `9391 * 2048 = 19232768` bytes;
   `19232768 / 512 = 37564.0` exactly. Confirmed correct, not a rounding
   coincidence.

3. **s7 geometry arithmetic, fully recomputed independently:**
   - `2169 * 640 = 1388160` (sector) — matches CURRENT-STATE.md:342 and
     HSIMD-ZFS-VALIDATION-PROCEDURE.md:240.
   - `1388160 * 512 = 710737920` (byte) — matches line 342 and validation
     doc's "710737920".
   - `655360 * 512 = 335544320` bytes `= 320.0 MiB` exactly — matches line
     343.
   - `710737920 + 335544320 = 1046282240` — matches line 344 (image size) and
     the media table in HSIMD-ZFS-VALIDATION-PROCEDURE.md:205 (scratch ISO
     size, byte-for-byte).
   - Gap `710737920 - 710717440 = 20480` — matches line 346.
   - Full four-label offset table (CURRENT-STATE.md:353-358, L0-L3
     blank@/nvlist@/uberblock-ring) independently re-derived from ZFS's
     16K-blank/112K-nvlist/128K-uberblock-ring layout and the `size-512K` /
     `size-256K` L2/L3 convention: every one of the 12 numbers in the table
     checks out exactly.
   - Import-alias-hazard claim (line 360-364): s2 and s7 both end at the
     image's final byte, so their L2/L3 slots collide at 1045757952 and
     1046020096 — confirmed by the same arithmetic, not a new computation.

4. **Cross-doc consistency, CURRENT-STATE.md vs HSIMD-ZFS-VALIDATION-PROCEDURE.md:**
   - s7 contents block (CURRENT-STATE.md:291-296) matches the FACT section in
     HSIMD-ZFS-VALIDATION-PROCEDURE.md:256-287 (canary text, L0-L3 offsets,
     per-chunk nonzero-byte counts) field for field.
   - Uberblock-ring "42 nonzero bytes" (CURRENT-STATE.md:306-307) matches
     HSIMD-ZFS-VALIDATION-PROCEDURE.md:298.
   - H-A/H-B hypothesis pair (CURRENT-STATE.md:311-318) matches
     HSIMD-ZFS-VALIDATION-PROCEDURE.md's Stage-4 hang/crash framing (and the
     already-committed Stage 4 matrix in HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md).
   - No stale/uncorrected duplicate of the falsified "no canary write and no
     `zpool create`" claim survives anywhere else in the 1250-line file
     (checked with a full-file grep for `zpool create|no canary|not attempted`).

5. **Media hash cross-check:** `tribblix-m34-hsimd.iso` SHA-256 in
   CURRENT-STATE.md:241 (`e98d3a5e...a6a33cf6`) matches the media table row in
   HSIMD-ZFS-VALIDATION-PROCEDURE.md:204 exactly (marked KNOWN-GOOD,
   unmodified there too).

6. **Whiteboard cross-check:** "Verified: guest c1d0s7 first 10 sectors
   exactly match host backing bytes by SHA-256" and "Verified pre-write
   baseline: no committed uberblock magic in s7" both match
   HSIMD-ZFS-VALIDATION-PROCEDURE.md's Stage 2/3 section (digest
   `3b0765bd...`, guest and host computed independently, byte-identical) and
   the uberblock-scan finding respectively. No contradiction found.

## MINOR — non-blocking imprecision, not corrected

CURRENT-STATE.md:296 and the mirrored line in HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md
say "~54 KB total nonzero." The exact figure from
HSIMD-ZFS-VALIDATION-PROCEDURE.md:282-287 is 53974 bytes
(1154+19575+19575+12540+1130, checked by addition). That's 52.71 KiB (binary)
but 53.97 decimal KB — i.e. "~54 KB" is correct if KB means 1000 bytes (as
used loosely elsewhere for round numbers) and off by ~1.3 KiB if KB means
1024 bytes. Both docs otherwise use MiB (binary) for larger units, so the
convention is inconsistent but the value is defensible either way. Not worth
a commit on its own; flagging for whoever next touches that line.

## HYPOTHESIS status — none introduced by this review
This review made no new hypotheses; it only checked existing claims against
independently recomputed arithmetic and cross-document consistency.

## PLAN / outcome
No factual errors found in the CURRENT-STATE.md correction (commit `dd252f0`).
All checked arithmetic, hashes, and cross-document claims are internally
consistent and independently verifiable. No corrective commit made — there
was nothing incorrect to correct, and the target commit was already merged by
another agent before this review completed. Whiteboard `Shell` section and
`Shared facts` updated with the current commit ID and this outcome; see
whiteboard for the pointer back to this file.

## FACT — reconciliation pass on HSIMD-ZFS-VALIDATION-PROCEDURE.md (2026-08-20, follow-up)

Per explicit direction to reconcile this untracked doc after the CURRENT-STATE.md
review above. Ownership check performed before editing: sha256 of the file was
`2fd534fe16f0cf08872dfb780538ec58cfcb5e4e127ecc1b8ca97aa8f56731a9` when first
read and unchanged immediately before the edit (re-hashed, same value, `git
status` showed it untracked with no other agent claiming active writes on the
whiteboard). Edited PLAN section only; left every FACT section (Stage 2/3
console transcript, media hash table, s7 byte mapping, uberblock-scan results)
untouched.

Each correction below was independently verified before editing, not asserted:

1. **`tools/vtoc.py` source-verified (read the actual code, not assumed):**
   `cmd_verify` (lines 90-113) opens the device read-only and never calls
   `open(..., "r+b")` or `fix_checksum()`. Only `cmd_set` (line 77-87) does
   both. The doc's Stage 1 H2 comment claiming "re-run vtoc.py verify so the
   XOR checksum is recomputed" was FALSE — fixed to describe patch+recompute
   correctly and note the tool has no ncyl setter at all.
2. **prtvtoc gate removed from Stage 3**, matching THE-TRIBBLIX-HSIMD-STORY.md:298
   ("prtvtoc exposed another unsupported ioctl and reported an invalid VTOC")
   and the already-committed HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md's own
   "must not be a stop-gate" language. Did NOT invent an ioctl number: checked
   every documented unsupported-ioctl reference in the project (`0x4a4`
   CDROMREADOFFSET for HSFS mount, `0x760b` for fmthard/geometry) — neither is
   attributed to prtvtoc anywhere, so the fix states "no source pins this down"
   rather than fabricating a number.
3. **UFS-file-vdev diagnostic lane note added.** THE-TRIBBLIX-HSIMD-STORY.md:362-390
   and :496 establish this as a mandatory separate lane; the validation
   procedure previously never mentioned it. Added a note requiring it stay
   separate in "names and claims" per the story doc's own words, and flagged
   that whether `/share/tribblix-s7-ufs.img` on the Solaris donor was ever
   completed has not been re-verified.
4. **H1/HYPOTHESIS-list weighting corrected** to match the already-committed,
   more thoroughly evidenced H-A/H-B split in CURRENT-STATE.md (H-B hang
   directly observed = better supported; H-A crash-loss = circumstantial).
   The doc previously reversed this weighting ("most economical explanation"
   framing favored crash-loss).
5. **Safety bug fixed — most severe finding.** Stage 8 literally instructed a
   bare `zpool import` ("expect hsimdz listed"). CURRENT-STATE.md's
   already-committed Import-alias-hazard section is explicit that a bare
   import can bind `c1d0s2` instead of `c1d0s7` (their L2/L3 label offsets
   are byte-identical: 1045757952 and 1046020096, both independently
   recomputed by me in the earlier CURRENT-STATE.md review), destroying the
   Sun label and boot archive. Replaced with `zpool import -d <isolated-dir>`
   per the established rule.
6. **Stage 4 bare device name fixed** (new finding, not in the original
   instruction list, found while fixing #5): `zpool create -f hsimdz c1d0s7`
   used a bare device name; CURRENT-STATE.md's rule is "always name the vdev
   by full path `/dev/dsk/c1d0s7`, never bare `c1d0s7`." Fixed to match.
7. **Stage 6 mtime gate removed.** It required host mtime to "MUST advance"
   after `kill -USR2`. CURRENT-STATE.md's own committed text warns mtime
   advances on writeback/msync timing, not on store, and CURRENT-STATE.md's
   "How storage actually works" section documents independent background
   writeback (`dirty_expire ~30s`) that can move mtime for unrelated reasons.
   Replaced the gate with an explicit pointer to Stage 7's byte/hash readback
   as the actual proof.
8. **Stage 8 scrub-completion gate fixed.** The gate text already said "scrub
   completes with 0 errors" but the command list was a single
   `scrub ; status` pair with no poll loop — `zpool status` run immediately
   after `zpool scrub` starts typically reports `scan: scrub in progress`,
   not a completed result, so the literal commands didn't satisfy the stated
   gate. Added a poll-to-completion loop.

**Formatting bug self-caught and fixed:** my first pass at three of the
multi-line swaps dropped opening code fences (Stage-1 ncyl block boundary,
Stage 6, Stage 8) and a blank line before the `## PLAN` heading. Caught by
counting backtick-fence occurrences in the file (must be even) after editing —
found 47 (odd) before the fix, 48 (even) after. Re-read the affected ranges
and inserted the three missing fences plus the blank line.

**Whiteboard mishap and independent fix:** my first whiteboard post announcing
this reconciliation was run through `bash -c "... \`text\` ..."` and had its
own backtick-quoted code references silently stripped by shell command
substitution before reaching `maestri note edit` (confirmed: the bash tool's
own stderr showed `error: command not found: tools/vtoc.py:cmd_verify` etc. —
those were real, if harmless, local shell invocations of fragments of my own
message text, not commands run against the niagara host). Recovered by
re-extracting the exact posted (garbled) text via `maestri note read`,
substituting a corrected block, and re-posting through a Python
`subprocess.run([...])` argv list (no shell re-interpretation) instead of an
inline bash string. Independently confirmed by re-reading the note.

## PLAN / outcome — reconciliation
Applied all 8 corrections above to `HSIMD-ZFS-VALIDATION-PROCEDURE.md`'s PLAN
section (Stage 1, 3, 4, 6, 8, plus the HYPOTHESIS list and a new diagnostic-lane
note). Every FACT section, the 10-sector digest match, the unbounded-`digest`
ENOSPC finding, and the already-correct isolated-`-d` import language in
CURRENT-STATE.md were left untouched, as required. Committing this file plus
this note; not touching CURRENT-STATE.md, HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md, or
any console/VM state.

## FACT — hsimd ioctl source audit (PARKED mid-task, 2026-08-20, per Ryan pause/regroup)

Source: `hsimd.c` fetched from `github.com/artyom-tarasenko/hsimd/blob/master/hsimd.c`
(the exact upstream cited elsewhere in this project, e.g.
HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:556). `hsimd_ioctl()` (near end of file) is a
single `switch (cmd)` with exactly three implemented cases and one default:

1. **`DKIOCINFO`** — `(DKIOC|3)` per illumos `sys/dkio.h`. Allocates and fills
   a `struct dk_cinfo`, `ddi_copyout`s it, returns 0. Implemented correctly.
2. **`DKIOCGVTOC`** — `(DKIOC|11) = 0x040b`. Calls `hsimd_build_user_vtoc()`,
   which populates a real `struct vtoc` from the driver's cached label
   (`hsimd_p->hsimd_vtoc`/`hsimd_map`, read once at attach time by
   `hsimd_get_valid_geometry()`), `ddi_copyout`s it, returns 0. Implemented
   correctly — output IS initialized on success.
3. **`DKIOCGGEOM`** — `(DKIOC|1) = 0x0401`. `ddi_copyout`s the cached
   `hsimd_p->hsimd_g` (`struct dk_geom`), returns 0. Implemented correctly —
   output IS initialized on success.
4. **`default:`** — `cmn_err(CE_WARN, "hsimd_ioctl: cmd %x not implemented", cmd);`
   then falls out of the switch to the function's final `return (0);`. **The
   output buffer (`arg`) is never touched.** This returns SUCCESS (0) with
   whatever the caller's buffer already contained (zeroed, stack garbage, or a
   previous ioctl's leftover data) — not `ENOTTY`, not `EINVAL`. This is the
   exact same bug class already documented for HSFS's `CDROMREADOFFSET`
   (`0x4a4`) and `fmthard`'s geometry ioctl (`0x760b`) in
   THE-TRIBBLIX-HSIMD-STORY.md and CURRENT-STATE.md — now confirmed at the
   general dispatch level, not just those two call sites.

**Not implemented at all (falls into the false-success default):**
`DKIOCGMEDIAINFO` = `(DKIOC|42) = 0x042a` per illumos `sys/dkio.h`
(confirmed via illumos-gate/illumos-joyent mirrors, not this project's
source). Its argument is `struct dk_minfo` (logical block size +
capacity in blocks). Also unimplemented: `DKIOCGMEDIAINFOEXT`,
`DKIOCPARTITION`, `DKIOCSTATE`, `DKIOCREMOVABLE`, `DKIOCHOTPLUGGABLE`, and
anything else outside the three cases above — none were checked individually
beyond confirming they are not in the switch.

**FACT — the ENOSPC mechanism Codex asked to have cited:** `hsimd_strategy()`
(same file) checks `blk_no >= hsimd_p->label[slice_no].nblocks` and
`blk_no + (bp->b_bcount/DEV_BSIZE) > label[slice_no].nblocks`; either
violation sets `bp->b_error = ENOSPC; goto bad;`, which sets
`bp->b_resid = bp->b_bcount; bp->b_flags |= B_ERROR; biodone(bp);`. This is
the exact, now-cited source of the `ENOSPC` (28) seen throughout this
project (HSFS mount failure, the unbounded `digest` failure, and the
predicted EOF-boundary behavior) — it is a per-slice bounds check in the
strategy routine, unconditional on which ioctl (if any) preceded the read.

**HYPOTHESIS (unproven, PARKED — not carried further this session):**
`zpool create`'s device-open path (illumos `vdev_disk.c`, not yet read) is
expected to call `DKIOCGMEDIAINFO` to determine device capacity/block size
before writing labels. If so, hsimd's false-success/uninitialized-output
response would hand ZFS a garbage or zero capacity, which is a plausible
(not yet confirmed) contributor to the already-documented `zpool create`
hang (H-B) — but I did not reach `vdev_disk.c` before this task was paused.
This must be re-verified against the actual illumos zfs source before being
treated as anything more than a hypothesis; do not promote it to FACT/PLAN
in this project's docs without that read.

**Status: PARKED by explicit instruction, not completed.** No whiteboard
claim was ever made for this sub-task; no other agent was blocked. Not
committed as a doc correction because the vdev_disk.c confirmation step
never ran — recording here only as raw source-verified material for
whoever resumes it.

## Lane 1 — Solaris-10-to-Tribblix channel archaeology (2026-08-20, per Codex lane assignment)

Per whiteboard: "Owners: Shell = Lane 1 Solaris-10-to-Tribblix channel
archaeology... shortest evidenced path to one shared channel byte." Redirected
mid-task by Ryan to prioritize a concrete, immediately actionable deliverable
over broad dependency writeup. This section is a PLAN (not executed) — no
console input, no VM state touched, matching the standing constraint.

### FACT — two channel mechanisms exist in this project, and they are unrelated

1. **Serial-console chunk transfer** (used to bootstrap `hsimd`/`modload`/
   `add_drv` into the RAM-root Tribblix before it had any disk driver).
   Documented in HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:306-346 and
   THE-TRIBBLIX-HSIMD-STORY.md:136-163. No dedicated repo script exists for
   it — confirmed by grep across `tools/` for `base64`/`chunk`/`MIME::Base64`
   (only hits were unrelated `tools/chan/guest-dial.pl` and
   `tools/chan/host-bbs.py` buffer-chunking, not this protocol). It was
   ad hoc Perl/openssl one-liners run interactively over tmux, never
   committed as tooling. The project's own conclusion (HSIMD-TRIBBLIX-
   LIVE-BOOTSTRAP.md:914-916): this path is "too fragile and too expensive
   for binaries" and was **replaced** by the boot-archive-remaster path for
   anything beyond small ad hoc transfers. Its dependencies: an NFS export
   `10.0.5.1:/export/solaris` mounted at the Solaris-10 donor's `/share`
   (HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:89-92) staged the real SPARCV9
   `add_drv`/`modload` from `biggie` onto the donor; PPP is NOT part of this
   path at all — PPP is a Solaris-10-guest-only network feature
   (CURRENT-STATE.md:53-68) never used for Tribblix. No slice/offset layout
   applies — this channel is pure serial-console text, not disk I/O.
2. **Host-planted-byte disk channel** (`tools/chan/chan.h`, `P2-014`,
   "CANONICAL SOURCE OF TRUTH"). This is a real, already-validated
   (`test-exchange-channel`, PASS, CURRENT-STATE.md:15) host<->guest
   protocol for the **Solaris 10** guest: 16 independent 1MB channels in a
   16MB region at `CHAN_HOST_BYTE = 2667577344` (absolute byte in
   `primary.img`) / `CHAN_GUEST_BLK = 1015808` (block within `s3`), each
   with separate h2g/g2h control+data blocks (chan.h:74-113). This is the
   pattern to imitate, not reuse directly — Tribblix has no such
   pre-built region, and building one requires either the RAM-root's
   limited toolset or the boot-archive remaster path.

### PLAN — minimal one-byte host-write/guest-read proof for Tribblix (NOT EXECUTED)

Tribblix's only disk-backed, hsimd-attached, guest-readable media today is
`tribblix-m34-hsimd-zfs-scratch.iso` (the ZFS-scratch image). The plain
known-good `tribblix-m34-hsimd.iso` has no candidate region: its Sun label
declares `s0`..`s7` all as `cyl 0 / 1387520 blk` — i.e. every slice spans the
identical 677.5 MiB CD image (HSIMD-ZFS-VALIDATION-PROCEDURE.md:226), so
there is no guest-reachable byte on that image that isn't live boot content.

**Region chosen: `s7 + 150 MiB`** (offset within s7 = 157,286,400 bytes =
307,200 sectors; absolute host byte = 710,737,920 + 157,286,400 =
**868,024,320**; guest LBA on `/dev/rdsk/c1d0s7` = **307200**).

Why this is safe, cited, not assumed:
- **Sector-aligned automatically**: 150 MiB = 150 × 2048 × 512 bytes, so the
  offset is an exact multiple of 512 with no remainder arithmetic needed.
- **Provably zero today, not merely assumed.** CURRENT-STATE.md:279-296 and
  HSIMD-ZFS-VALIDATION-PROCEDURE.md:279-299 report an *exhaustive* byte scan
  of all of s7 that found exactly five nonzero chunks (`s7+0`, `+4MiB`,
  `+36MiB`, `+68MiB`, `+316MiB`) summing to exactly 53,974 bytes — a total I
  independently re-added in the earlier CURRENT-STATE.md review
  (1154+19575+19575+12540+1130=53974). `+150MiB` is not one of the five
  listed chunks and is nowhere near any of them (nearest neighbors are
  `+68MiB` and `+316MiB`), so by the completeness of that scan it is zero.
- **Does not touch existing forensic evidence.** The canary/labels/MOS
  residue at `+0/4/36/68/316MiB` are the only evidence for the H-A/H-B
  uberblock-loss investigation (see the reconciled HYPOTHESIS section,
  `HSIMD-ZFS-VALIDATION-PROCEDURE.md:312-326`) and the "no forensic copy...
  destroys the only txg=0 evidence" blocker on the whiteboard. `+150MiB` is
  far outside all of them.
- **Not a label region.** All four ZFS labels sit within 256 KiB of either
  end of the 320 MiB slice (`CURRENT-STATE.md`'s label table: L0/L1 near
  byte 0 of s7, L2/L3 near byte 320M); `+150MiB` is nowhere near either
  boundary.

**Exact host write + flush commands** (niagara-playbox, PLAN):
```
F=/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso
OFF=868024320                      # s7(710737920) + 150MiB(157286400)
# 1. Safety gate: re-verify zero before writing (do not trust the record blindly)
dd if=$F bs=512 iseek=$((OFF/512)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
# MUST print 1024 hex '0' characters (512 zero bytes). If not: STOP, do not write.
# 2. Host-planted marker, one aligned 512-byte sector (never a bare single byte,
#    per this project's established raw-disk-block discipline)
printf 'HOSTPROOF-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" | \
  dd of=$F bs=512 oseek=$((OFF/512)) conv=notrunc
# 3. Force writeback (documented durability point, not proof by itself —
#    CURRENT-STATE.md's own caution: mtime is a hint, not evidence)
kill -USR2 <qemu pid>
# 4. Independent host-side readback of what was actually written
dd if=$F bs=512 iseek=$((OFF/512)) count=1 2>/dev/null | head -c 32
```

**Exact guest read command** (Tribblix maintenance shell, one line, matching
the project's proven `iseek=` discipline — HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md's
measured 254s-vs-0.1s finding, CURRENT-STATE.md:674-686):
```
dd if=/dev/rdsk/c1d0s7 bs=512 iseek=307200 count=1 2>/dev/null | head -c 32
```
Gate: guest output byte-identical to the host-side write in step 2/4 above —
independently computed on both sides, matching this project's own
"matching checksum can prove nothing [if asserted from one side]" standard
(THE-TRIBBLIX-HSIMD-STORY.md:162-165).

**Reverse direction (guest-write/host-read)** is already proven non-novel:
this is exactly the existing `HSIMD-ZFS-CANARY-20260820` result at `s7+0`
(guest-written, host-read-back) — already FACT, not part of this PLAN.

**Rollback source.** NOT `tribblix-m34-hsimd.iso` (that image has no `s7` at
all — irrelevant to this test). The correct rollback for the live scratch
image is the forensic copy already verified before Stage 4, per Codex's
whiteboard blocker note: `/home/niagara/sun4v/images/scratch-forensic-20260820.iso`,
sha256 `17e39e63f4f1f59e6532dcd71a49289b41a40d4cf6a89c440b3d017855316617`,
"matched SHA-256... before Stage 4." If step 2 above is ever mistakenly run
against the wrong offset, restore from that forensic copy, which predates
this proof and postdates the existing canary/label evidence.

**Not executed.** This is a design/citation deliverable only — no SSH, no
console input, no VM state was touched to produce it. Actual execution
(steps 1-4 above, plus the guest read) requires the console operator
(Antigravity, per the whiteboard's single-writer rule) or explicit
authorization, and should re-run the P5/P6 invariants
(`CURRENT-STATE.md:372-374`: sha256 of bytes `0..1048576` and of the
boot-archive extent) before and after, per this project's own standing
discipline.

## Lane 1 — geometry reconciliation vs Shell #2, s7+150MiB retired (2026-08-20)

Per Ryan's coordinator decision: geometry conflict resolved in favor of
Shell #2's dedicated-image proposal. Scope of this entry, per explicit
instruction: independent verification of commit `88b3e98` and the geometry/
artifact-identity claim only. No ioctl work (that thread is frozen ZFS
material, not on the channel critical path, and is not reopened here).

### FACT — commit `88b3e98` verified

`git show --stat 88b3e98` = "chan: make disk placement configurable for
Tribblix", touching `tools/chan/chan.h` (+20/-3), `tools/chan/guest-chand.c`
(+26/-6), `tools/chan/host-chan.py` (+5/-1). Read `chan.h`'s new "PORTABLE
PLACEMENT" block directly (lines 18-31): it defines runtime overrides
`NIAG_CHAN_DEV`, `NIAG_CHAN_GUEST_BLK` (guest), `NIAGARA_IMG`,
`NIAG_CHAN_HOST_BYTE` (host), and states the required identity explicitly:

```
NIAG_CHAN_HOST_BYTE = slice_absolute_byte + NIAG_CHAN_GUEST_BLK * CHAN_BLK
```

This is real, already-committed infrastructure — not a proposal.

### FACT — Shell #2's dedicated-slice geometry independently re-derived, matches exactly

Recomputed from scratch (not copied from their note), using the same
1-head/640-sector/512-byte geometry already verified project-wide:

```
s7 start:  cylinder 2169 * 640 sectors/cyl        = sector 1,388,160
                                                   = byte   710,737,920
gap from known-good ISO end (710,717,440):          20,480 bytes (no overlap,
                                                     same proof as the ZFS-scratch s7)
s7 length: 52 cylinders * 640 * 512                = 17,039,360 bytes
new image total size:  710,737,920 + 17,039,360    = 727,777,280 bytes
new image in sectors:  727,777,280 / 512           = 1,421,440  (matches claimed s2 size)
```

**52 cylinders confirmed as the true minimum**, not merely accepted:
`chan.h`'s `CHAN_REGION_BYTES` requires 16,777,216 bytes (16 MiB) for the 16
channels x 1 MiB. 51 cylinders = 51×640×512 = 16,711,680 bytes — **65,536
bytes (64 KiB) short**. 52 cylinders = 17,039,360 bytes — 262,144 bytes
(256 KiB) of slack, cylinder-alignment overshoot only, not fat to trim
further without breaking VTOC cylinder alignment.

**Identity check, per `chan.h`'s own formula:** with `NIAG_CHAN_GUEST_BLK=0`
and `slice_absolute_byte=710,737,920`: `710,737,920 + 0*512 = 710,737,920 =
NIAG_CHAN_HOST_BYTE`. Holds exactly. Shell #2's proposed values are
arithmetically correct.

### PLAN — the safety distinction is artifact identity, not offset (Ryan's framing, confirmed against the record)

`710,737,920` is **the same absolute byte** as the ZFS-scratch image's `s7`
start (CURRENT-STATE.md:342, HSIMD-ZFS-VALIDATION-PROCEDURE.md:240-244) —
same cylinder/geometry math, because both images derive from the same
base label. That byte currently holds the live `HSIMD-ZFS-CANARY-20260820`
canary and an L0 ZFS-label nvlist header **only in
`tribblix-m34-hsimd-zfs-scratch.iso`** — the artifact this project has
already frozen to preserve H-A/H-B evidence. It holds nothing (does not
exist at all — the file is 710,717,440 bytes) in the pristine
`tribblix-m34-hsimd.iso`.

**Binding rule, stated explicitly per Ryan's instruction:**
`88b3e98`'s `NIAG_CHAN_DEV=/dev/rdsk/c1d0s7` / `NIAG_CHAN_HOST_BYTE=710737920`
combination is valid **only** when the backing image is a **separate,
freshly copied** channel archive derived from `tribblix-m34-hsimd.iso`
(sha256 `e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6`)
with its own new `s7` per the geometry above. The identical byte offset
paired with `tribblix-m34-hsimd-zfs-scratch.iso` is a **different, unsafe**
target — it would write into the exact state the freeze exists to protect,
and a later `zpool create` on that artifact would destroy the channel data
too. Same numbers, two artifacts, only one of which is safe. Do not conflate
them by offset alone.

### RETIRED — my earlier `s7+150MiB` proposal (this file, above)

Explicitly retracted, not merely superseded by better math: it was designed
against the live `tribblix-m34-hsimd-zfs-scratch.iso` specifically because
that was the only hsimd-attached, guest-reachable media that existed at the
time. Per Ryan's coordinator decision, channel work now targets a *separate*
dedicated image, so that entire proposal — region, rationale, and its
"provably zero via the nonzero-byte scan" justification — no longer applies
and MUST NOT be executed. The zero-byte-region problem it solved does not
exist on a freshly created image: new space produced by extending a copy is
zero by construction, not by scan-and-hope.

### Exact commands for the dedicated-image channel (PLAN, NOT EXECUTED)

Image does not yet exist. This records the exact sequence for whoever builds
it — no console work, no transfer performed here.

**Build (host, niagara-playbox, PLAN):**
```
cp ~/sun4v/media/tribblix-m34-hsimd.iso ~/sun4v/images/tribblix-m34-chan.iso
sha256sum ~/sun4v/images/tribblix-m34-chan.iso
# expect e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6 (pre-truncate)
truncate -s 727777280 ~/sun4v/images/tribblix-m34-chan.iso
python3 ~/niag-proj/tools/vtoc.py set ~/sun4v/images/tribblix-m34-chan.iso 2 0 1421440
python3 ~/niag-proj/tools/vtoc.py set ~/sun4v/images/tribblix-m34-chan.iso 7 2169 34112
python3 ~/niag-proj/tools/vtoc.py verify ~/sun4v/images/tribblix-m34-chan.iso
```
(`vtoc.py set` is the only path in this project's tooling that calls
`fix_checksum()` — verified in the earlier ZFS-doc reconciliation,
`tools/vtoc.py:77-87` — so the label write above is the one that actually
recomputes the checksum; `verify` after it only confirms.) Slice length in
blocks: 52 cyl × 640 sectors/cyl = 34,112 blocks, matching the byte math
above (34,112 × 512 = 17,039,360).

**Host-side channel-region proof write + flush (PLAN):**
```
F=~/sun4v/images/tribblix-m34-chan.iso
OFF=710737920                       # = NIAG_CHAN_HOST_BYTE, guest block 0
dd if=$F bs=512 iseek=$((OFF/512)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
# expect all-zero (fresh space, zero by construction of truncate/extend -
# not asserted from a scan, proven by how the file was created)
printf 'CHAN-PROOF-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" | \
  dd of=$F bs=512 oseek=$((OFF/512)) conv=notrunc
kill -USR2 <qemu pid>               # msync durability point, not proof by itself
dd if=$F bs=512 iseek=$((OFF/512)) count=1 2>/dev/null | head -c 32
```

**Guest-side read (Tribblix, PLAN, `iseek=` per this project's measured
254s-vs-0.1s discipline):**
```
NIAG_CHAN_DEV=/dev/rdsk/c1d0s7 NIAG_CHAN_GUEST_BLK=0 \
  dd if=/dev/rdsk/c1d0s7 bs=512 iseek=0 count=1 2>/dev/null | head -c 32
```
Gate: guest output byte-identical to the host readback above, both computed
independently — the same non-circular standard used throughout this project.

**Rollback source for this NEW image:** `tribblix-m34-hsimd.iso` itself
(sha256 above) — the copy is disposable and derived from it; rollback is
"discard the copy," not a forensic restore, because nothing pre-existing is
overwritten (the appended region is virgin space, not reused evidence).

### Disqualified alternatives (checked and rejected, with reason)

| alternative | disqualified because |
|---|---|
| `s7+150MiB` on the ZFS scratch (my retired proposal) | wrong artifact — targets the frozen evidence-bearing image, not the new dedicated one |
| Any offset on `tribblix-m34-hsimd-zfs-scratch.iso`, including `710737920` itself | same byte already holds live canary/L0-nvlist evidence in that specific artifact; a future `zpool create` there would also destroy it |
| 51-cylinder (or smaller) dedicated slice | arithmetically 65,536 bytes short of `chan.h`'s 16 MiB `CHAN_REGION_BYTES` requirement (verified above) |
| Reusing Solaris-10's `CHAN_HOST_BYTE=2667577344` on the Tribblix image | wrong image entirely — that offset is near the end of the 2,684,354,560-byte `primary.img`, far past this ~728 MB Tribblix image; already flagged as the wrong-image case Lane 2 identified |
| bare `c1d0s7` / `zpool`-style bare device references | violates this project's established full-path device-naming rule (`/dev/dsk/c1d0s7` / `/dev/rdsk/c1d0s7`, never bare) |
| `s0`/`s1`/`s3`..`s6` on either image | all map to the read-only ISO region, not free space, on both the known-good and any derived image |

Not executed. No SSH, no console input, no VM state touched, no artifact
built or transferred.
