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
