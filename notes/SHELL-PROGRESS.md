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
python3 ~/niag-proj/tools/vtoc.py set ~/sun4v/images/tribblix-m34-chan.iso 7 2169 33280
python3 ~/niag-proj/tools/vtoc.py verify ~/sun4v/images/tribblix-m34-chan.iso
```
(`vtoc.py set` is the only path in this project's tooling that calls
`fix_checksum()` — verified in the earlier ZFS-doc reconciliation,
`tools/vtoc.py:77-87` — so the label write above is the one that actually
recomputes the checksum; `verify` after it only confirms.) Slice length in
blocks: 52 cyl × 640 sectors/cyl = 33,280 blocks, matching the byte math
above (33,280 × 512 = 17,039,360). **CORRECTED 2026-08-20**: this entry
originally stated 34,112 blocks, an arithmetic slip (52×640 was mistyped) that
does not match 52×640=33,280 and does not satisfy 34,112×512=17,825,024 ≠
17,039,360. A slice built with 34,112 blocks would extend 832 sectors
(425,984 bytes) past the intended image end — this is the exact defect
Antigravity caught and corrected in the live build (099f366f..., replacing
the earlier 2b801bff... artifact). Confirmed independently here from the
repo's own arithmetic, not from their report.

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

## Lane 1 — independent review of Shell #2's transfer/build evidence (2026-08-20)

Scope, per explicit instruction: source/destination size+SHA, boot-archive vs
channel-image identity, VTOC start/extent, known-good hash unchanged. No
transfer, build, or console work performed. Where I had a locally-present
artifact I hashed it myself rather than trusting the whiteboard's stated
value — that is the only way this counts as independent readback rather than
re-reading the same claim twice.

### FACT — two artifacts independently re-hashed on this machine, both EXACT matches

I did not create, copy, or move these files; they already existed locally at
review time and I only read/hashed them.

1. **`/tmp/tribblix-m34.boot_archive.channel`** — `stat -f%z` = 356,515,840
   bytes; `shasum -a 256` =
   `2417a500e0ae900307612d13ad7b287c57f41c3772dc126ecee9e850ed59c912`.
   Matches the whiteboard's claim for BOTH the donor-side
   `/export/solaris/tribblix-m34.boot_archive.channel` and the "Mac /tmp"
   copy, exactly, on both size and hash. This is a genuine independent
   confirmation, not a re-quote — I ran `shasum` myself against a file I did
   not place there.
2. **`/tmp/guest-chand-tribblix`** — size 12,838 bytes; SHA-256
   `baa7bd2798a414cf7f774f83588fdb132b857f86f5a189ade65f7e1440baffc9`;
   `cksum` = `1454951726 12838`. All three independently computed values
   match the whiteboard's donor-side claim for
   `/export/solaris/tribblix-chan-build/guest-chand` exactly (size, SHA-256,
   AND the POSIX cksum triplet — three independent checksums in agreement,
   not one). `file` confirms `ELF 32-bit MSB executable, SPARC32PLUS, ...
   dynamically linked ... not stripped`, matching the claimed "SPARC32PLUS"
   target exactly.

### FACT — boot-archive content sanity-checked against the claim, not just its hash

`strings` on `boot_archive.channel` contains `guest-chand`, `guest-chand.c`,
`guest-echocli`, `guest-echocli.c`, and — significantly — the literal env-var
names `NIAG_CHAN_DEV` and `NIAG_CHAN_GUEST_BLK` introduced by `88b3e98`
(verified against `tools/chan/chan.h` in the prior geometry-reconciliation
entry above). This is real evidence the archive contains the channel
binaries built against the current runtime-configurable `chan.h`, not stale
binaries from an earlier protocol version. I could NOT confirm the exact
claimed path `/opt/niag/bin` (no UFS mount tool available on this machine to
list the filesystem tree) — `strings` proves presence of the binaries and
their build provenance, not their installed path. Flagging this as the edge
of what I could verify, not confirming the path claim.

### FACT — boot-archive vs channel-image identity, not conflated

`boot_archive.channel`'s SHA-256 (`2417a500...`) differs from both previously
documented boot-archive variants: `.cuflags` = `3ae66e65...` and `.hsimd` =
`6d42e684...` (HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:447, :490). Confirms this is
a genuinely new, distinct archive — not an accidental re-tag of an earlier
one. Separately: **no channel ISO exists yet.** Antigravity's own Gate 2 on
the whiteboard is explicitly "OPEN (awaiting Shell #2 publication of ...
dedicated channel ISO ... with exact SHA-256)" — so the boot-archive artifact
reviewed here and the eventual 727,777,280-byte channel ISO (per the
geometry reconciled in commit `26ce736`) are correctly two different,
not-yet-conflated artifacts at two different completion states. There is
nothing to review yet on the ISO side beyond the geometry already checked.

### FACT — UFS filesystem magic present at the correct offset (partial substitute for fsck, which I cannot run here)

Read raw bytes at file offset 9564 (superblock at 8192 + `fs_magic` field
offset 1372, the classic BSD/SunOS UFS1 layout): `00 01 19 54`, i.e. big-endian
`0x00011954` = the Solaris `FS_MAGIC` constant. Correct byte order for a
SPARC (big-endian) UFS image. This is NOT equivalent to the claimed
`fsck -F ufs -m` pass (I have no UFS fsck/mount tool on this machine) but is
independent evidence the file is a plausible, correctly-oriented UFS image,
not corrupt or byte-swapped.

### HYPOTHESIS (flagged, not confirmed) — truncation-size near-collision

The whiteboard records a previously-truncated playbox transfer at **127,434,752**
bytes. THE-TRIBBLIX-HSIMD-STORY.md:152-153 and
HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:454 record an *earlier, different* truncated
transfer at **127,426,560** bytes — a difference of exactly 8,192 bytes (16
sectors). Both are plausibly independent incidents from different sessions
(this project has hit this transfer-truncation bug more than once), and nothing
here says otherwise. Flagging the near-coincidence only because Gilfoyle
discipline says a suspiciously round difference deserves a note, not because
I have evidence of a mix-up. Not investigated further — out of scope (no
access to the deleted `.part` file to compare).

### NOT VERIFIABLE FROM HERE — stated as a boundary, not glossed over

- **"Known-good hsimd archive/ISO untouched."** I have no local copy and no
  SSH/console access to `niagara-playbox`. I cannot independently confirm
  this claim's hash is unchanged; I can only note that no command in any
  reviewed evidence targets `tribblix-m34-hsimd.iso` for a write, consistent
  with (not proof of) the claim.
- **The "fresh transfer... to `chan-archive-xfer-20260820.tmp`"** mentioned
  on the whiteboard is explicitly incomplete by its own admission ("exact
  size/hash required before promotion") — nothing to verify yet; noting it
  is still open, not silently dropping it.

### PLAN / outcome

No corrections needed to Shell #2's transfer/build claims — both artifacts I
could independently re-hash matched exactly (size, SHA-256, and for the
binary, `cksum` too), and the archive's content and UFS magic are consistent
with the claim. The only open items are ones Shell #2's own record already
flags as open (the in-flight `chan-archive-xfer-20260820.tmp` transfer and
the not-yet-published channel ISO) — not new findings from this review. No
transfer, build, or console action taken.

## Lane 1 — Milestone 1 PASS criteria, pre-registered before evidence lands (2026-08-20)

Gilfoyle discipline: written BEFORE any Antigravity evidence exists for this
milestone, so it cannot be shaped to fit a result. Independent repo-side
review only — no console, no SSH, no edits to Antigravity's or Shell #2's
files. If evidence contradicts a criterion below, that is a FAIL regardless
of how the milestone is reported elsewhere.

**Milestone claim under test:** one host-write/guest-read canary byte proven
on the dedicated channel image at the reconciled geometry (`26ce736`,
arithmetic-corrected `aed36a0`): absolute host byte **710,737,920**, guest
LBA **0** on `/dev/rdsk/c1d0s7`.

### PASS criteria (all required; any single failure = FAIL)

1. **Backing image identity, verified before trusting anything else.**
   `/home/niagara/sun4v/images/tribblix-m34-chan.iso` must be exactly
   **727,777,280 bytes**, SHA-256 **must be independently recomputed at
   review time**, not copied from a prior report — expected to match the
   corrected Gate-2 value `099f366f528f375888ca008f399f9685d931daaf3100bf52ad269c38eca2f6b1`
   (superseding the defective `2b801bff...` build). If the hash differs from
   this AND no coherent explanation is given (e.g. a further corrected
   rebuild with its own new recorded hash), that is a FAIL on identity, not
   a detail to wave through.
2. **Host canary bytes/hash/offset, fully specified, not just "a byte
   changed."** The write must be:
   - at absolute host byte 710,737,920 exactly (not "near" it),
   - exactly one aligned 512-byte sector (`dd bs=512 oseek=1388935... ` no —
     block-relative: `oseek=$((710737920/512))`, i.e. `oseek=1388160`,
     `conv=notrunc`, never a bare single byte or an unaligned write),
   - a distinct, discriminating, non-circular pattern — MUST NOT be
     all-zero, MUST NOT be the known zero-hash-colliding value already
     retired in this project (`076a27c7...`, the SHA-256 of 512 zero bytes),
     and MUST NOT reuse the string `HSIMD-ZFS-CANARY-20260820` (that string
     is the OTHER, frozen ZFS-scratch artifact's identity marker — reusing
     it here would make the two lanes' evidence indistinguishable by
     content, defeating the artifact-identity safety rule this project
     already adopted for this exact reason),
   - independently host-side re-read (a second `dd`/`od` after the write,
     not inferred from the write command's exit status — "verify the
     artifact, not the attempt," this project's own standing rule).
3. **Guest command and output, exact.** Must be
   `dd if=/dev/rdsk/c1d0s7 bs=512 iseek=0 count=1` — `iseek=`, never
   `skip=`, per this project's own measured 254s-vs-0.1s finding
   (CURRENT-STATE.md:674-686). Output must be byte-identical to the
   independently-verified host-side write in criterion 2, with both sides
   computed separately (this is the non-circularity standard this project
   has enforced since the `076a27c7...` false-positive).
4. **No channel-protocol `init` before this guest read.** `chan.h` documents
   this exact hazard verbatim: "STARTUP ORDER IS LOAD-BEARING. Run
   `host-chan.py init` BEFORE starting either daemon... an init underneath a
   running daemon leaves it holding a stale seq and the peer then replays a
   leftover frame as new" — MEASURED there: a 262,144-byte transfer came
   back 274,176 bytes due to wrong ordering. This milestone is a raw
   `dd`-based single-block proof (chan.h's own "Route A" per Shell #2's Lane
   2 manifest), not a daemon-protocol run, so `host-chan.py init` and
   `guest-chand` MUST NOT have executed at all before this read — if either
   ran first, the control-block/seq framing could overwrite or reinterpret
   the plain canary and the read is no longer a clean proof of raw
   host-write/guest-read, whatever byte it happens to return.
5. **Post-proof artifact/VM state, itemized:**
   - Image size unchanged at 727,777,280 bytes (the canary is an in-place
     512-byte overwrite, not an append/truncate).
   - SHA-256 of bytes `0..1,048,576` (Sun label + image head) unchanged from
     the pre-canary baseline in criterion 1 — proves the write didn't drift
     backward into the label.
   - SHA-256 of the boot-archive extent (`byte 19,232,768`, length
     `356,515,840`) unchanged — proves the write didn't drift forward into
     the archive.
   - The write touched **only** its targeted block: the immediately
     preceding and following 512-byte blocks (guest LBA -1 is out of range /
     N/A since this is LBA 0; guest LBA 1) must be reported, and if
     non-zero/non-baseline, that is a FAIL (multi-block overwrite).
   - VM/console state explicitly recorded: alive-and-parked or
     cleanly-halted, with **no** Ctrl-C/Ctrl-D per this project's standing
     single-console-ownership rule (CURRENT-STATE.md:398-411).
   - `tribblix-m34-hsimd.iso` (the pristine source of this dedicated image)
     hash independently reconfirmed unchanged — must still be
     `e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6`.
   - `tribblix-m34-hsimd-zfs-scratch.iso` (the frozen, unrelated artifact)
     untouched — no command in the evidence trail should reference it at all
     for this milestone.

### Capability boundary, stated again

I have no SSH/console access to `niagara-playbox`. I can verify: internal
arithmetic consistency of any reported numbers, cross-references against
already-committed project facts and repo source (`chan.h`, `vtoc.py`), and
logical consistency of the evidence trail (do the claimed pre/post states,
offsets, and commands actually compose into a valid proof). I CANNOT
independently recompute a hash of a file I cannot read. Where evidence
depends on a remote byte I cannot see, my review will say so explicitly
rather than rubber-stamp it.

## Lane 1 — Milestone 2/3 design (framed channel, PPP/NFS, throughput/persistence), NOT EXECUTED (2026-08-20)

Design only, prepared while Antigravity is on the boot path for Milestone 1.
No VM, console, donor, image, or boot-archive mutation performed to produce
this. Derived from repo source (`tools/chan/*`, `88b3e98`'s exact diff) and
Shell #2's Lane 2 manifest (`notes/SHELL-2-PROGRESS.md`), cited by line, not
re-derived from memory.

### FACT — exact reusable assets, source-verified

- **`tools/chan/chan.h`** (canonical framing, `88b3e98` "PORTABLE PLACEMENT"):
  16 channels × 1 MB, `NIAG_CHAN_DEV`/`NIAG_CHAN_GUEST_BLK` (guest),
  `NIAGARA_IMG`/`NIAG_CHAN_HOST_BYTE` (host).
- **`tools/chan/guest-chand.c`** (diff read directly): now reads
  `NIAG_CHAN_DEV` and `NIAG_CHAN_GUEST_BLK` from the environment at startup
  (falls back to `DEV_DEFAULT="/dev/rdsk/c0t0d0s3"` / `CHAN_GUEST_BLK` if
  unset) — confirmed by reading the actual `getenv()` calls added in
  `88b3e98`, not assumed from the commit message.
- **`tools/chan/host-chan.py`**: `NIAG_CHAN_HOST_BYTE` env override
  (`int(..., 0)`, decimal or `0x`), and — already present *before* `88b3e98`,
  confirmed by reading `host-chan.py:59-68` — `NIAGARA_IMG` is a **plain-path
  override** specifically documented for "hosts with no ZFS at all... the
  portable target (Ubuntu on arm64)" i.e. exactly `niagara-playbox`. Full
  invocation for the dedicated channel image:
  `NIAGARA_IMG=/home/niagara/sun4v/images/tribblix-m34-chan.iso NIAG_CHAN_HOST_BYTE=710737920 host-chan.py init`.
- **`guest-chand`/`guest-echocli` binaries**: already cross-built SPARC32PLUS,
  staged under `/opt/niag/bin` in the verified channel boot archive
  (independently re-hashed by me, `9ee9fb6`: SHA-256
  `baa7bd2798a414cf7f774f83588fdb132b857f86f5a189ade65f7e1440baffc9`,
  12,838 bytes). Usage string found via `strings`: `guest-chand <channel
  0..%d> [socket-path]`.
- **`tools/chan/chan-test.py`**: existing test-harness pattern already
  proven for the Solaris-10 lane (`test-exchange-channel`, PASS,
  CURRENT-STATE.md:15) — reuse its round-trip/checksum methodology, not its
  hardcoded Solaris-10 constants.
- **`tools/exchange.sh`**: the FAT32/pcfs bidirectional exchange tool
  (`test-fat-exchange`, PASS) — a DIFFERENT, filesystem-based channel, not
  reusable for Tribblix (no pcfs mount path established there), but its
  "verify both directions independently" discipline is the pattern to copy.

### FACT — critical sequencing hazard, source-verified (from Shell #2's read of `host-chan.py:cmd_init`)

`host-chan.py`'s `cmd_init` writes a zeroed control block to **exactly two
blocks per channel** — `h2g_ctrl(ch)=cbase(ch)+0`, `g2h_ctrl(ch)=cbase(ch)+1`
— for all 16 channels: blocks `{0,1},{2048,2049},...,{30720,30721}`, 32
blocks / 16,384 bytes total, and never touches data blocks. Consequence,
already worked out in `notes/SHELL-2-PROGRESS.md:1018-1062`: **any canary or
proof byte at region byte 0 (= channel 0's h2g control block) is destroyed
the instant `host-chan.py init` runs.** My own pre-registered Milestone 1
criteria (this file, above) already required "no init before the guest
read" for exactly this reason — this section confirms that requirement was
correct and explains *why* in full, not just as an assertion.

**Consequence for the M1 -> M2 transition, stated explicitly:** Milestone
1's raw canary at region byte 0 is *expected* to be overwritten the moment
`host-chan.py init` runs to start Milestone 2. That is correct, by design —
Milestone 1 only had to prove offset/addressing, not durability — but it
means M1's proof artifact should be captured (host+guest readback recorded)
BEFORE M2 begins, since it cannot be re-read afterward without redoing M1.

### PLAN — Milestone 2: framed guest-chand/host-chan echo proof (NOT EXECUTED)

**AMENDED 2026-08-20 (review correction).** The original version of this
section initialized and started `guest-chand` but never started the host
bridge process `chan-test.py` and `guest-echocli` both require, and used a
non-default guest socket path. Corrected below by reading `tools/chan/chan-up.sh`
(the project's own canonical bring-up script) and `tools/chan/host-chan.py`'s
`cmd_bridge`/`guest-chand.c` header directly, not assumed.

**Socket-path correction.** `guest-chand.c:3` documents its own default:
`guest-chand <channel 0..15> [socket-path]     default /tmp/niag<ch>`.
`host-chan.py:cmd_bridge` (`:163-164`) defaults to `sockpath = f"/run/niag{ch}"`,
and `chan-up.sh`'s own printed summary confirms the convention: "host
`/run/niag0`.. guest `/tmp/niag0`..". The prior draft's guest socket
`/tmp/chan0.sock` was a non-default, unmatched path — nothing on the host
side would have been listening there. Corrected to the project default,
`/tmp/niag0` (guest) / `/run/niag0` (host) for channel 0, since there is no
reason to deviate and every consumer (`guest-echocli`, `chan-test.py`) is
built expecting the default.

**Order, preserved from `chan-up.sh`'s own enforced sequence** (its header
comment: "ORDER IS LOAD-BEARING... 1. stop every daemon on both sides 2. THEN
init 3. THEN guest daemons 4. THEN host bridges"), adapted here because
`chan-up.sh` itself drives steps 1/3 over `telnet`, which does not exist yet
on Tribblix (no IP — that is Milestone 3, not this one). Console-driven
equivalents substituted where `chan-up.sh` assumes IP:

1. **Stop.** Guest: confirm no stale `guest-chand` is running
   (`pkill -9 guest-chand 2>/dev/null; sleep 1`, console-typed — `chan-up.sh`
   does this over `telnet`, unavailable here). Host: confirm no stale bridge
   (`pkill -f 'host-chan.py bridge' 2>/dev/null`).
2. **Capture Milestone 1's result first** (see pre-registered criteria
   above) — this step's `init` destroys that evidence by design.
3. **Init.** Host:
   `NIAGARA_IMG=/home/niagara/sun4v/images/tribblix-m34-chan.iso NIAG_CHAN_HOST_BYTE=710737920 python3 tools/chan/host-chan.py init`.
4. **Guest daemon, with a preflight check first.** Run
   `NIAG_CHAN_DEV=/dev/rdsk/c1d0s7 NIAG_CHAN_GUEST_BLK=0 /opt/niag/bin/guest-chand`
   with **no arguments** first — the usage string
   (`usage: guest-chand <channel 0..%d> [socket-path]`) prints and exits
   before the binary opens the device or a socket, so this is a safe
   dynamic-linker/argument-parsing smoke test. Only if that succeeds:
   `NIAG_CHAN_DEV=/dev/rdsk/c1d0s7 NIAG_CHAN_GUEST_BLK=0 nohup /opt/niag/bin/guest-chand 0 /tmp/niag0 > /var/tmp/chand0.log 2>&1 &`,
   then confirm with `ls -l /tmp/niag0` that the socket node exists before
   proceeding.
5. **Host bridge — the step the original draft omitted entirely.** Exactly
   ONE bridge process for channel 0, with the SAME image/offset environment
   the `init` call used (must be exported/inherited, not re-typed
   inconsistently):
   `NIAGARA_IMG=/home/niagara/sun4v/images/tribblix-m34-chan.iso NIAG_CHAN_HOST_BYTE=710737920 nohup python3 tools/chan/host-chan.py bridge 0 > /tmp/niag-bridge0.log 2>&1 &`.
   Verify **one writer**: `pgrep -fa 'host-chan.py bridge 0'` must return
   exactly one PID before continuing — `chan-up.sh` itself treats a
   duplicate bridge as the same class of hazard as a stale `init` (one
   writer per direction is a hard invariant, chan.h:65-66 and
   host-chan.py:154). Verify socket existence: `[[ -S /run/niag0 ]]`.
6. **Guest echo client**, only after both sockets above are confirmed to
   exist: run `guest-echocli` against the guest socket, `/tmp/niag0` (not
   the channel device directly) — echocli is documented as `guest-chand`'s
   companion client in the same archive.
7. **Host test.** `sudo python3 tools/chan/chan-test.py 0` — this is the
   step that actually requires the host bridge from step 5 to be up; running
   it before step 5 would fail against a socket that was never created,
   which is the exact gap this amendment closes.
8. Verify byte-for-byte, both directions, independently computed each side —
   mirroring `test-exchange-channel`'s already-proven methodology, not
   asserting success from exit status.
9. Record throughput at this stage only as a byproduct, not a gate — chan.h's
   own measured ceiling (~4000 single-block hypercalls/sec, ~2 MB/s at
   `bs=512`, chan.h:34) sets the expectation; a dedicated throughput run is
   Milestone 4, not this step.

**Missing/unverified before this can run:** whether `guest-chand`'s dynamic
linker actually resolves at runtime in the Tribblix RAM root — Shell #2's
Lane 2 manifest marks `libsocket`/`libnsl` presence as **REPORTED, not
independently confirmed** (SHELL-2-PROGRESS.md:970-978); step 4's
no-argument preflight call is exactly the check that resolves this before
any device or socket is touched.

**Correction to my own M3 framing, found while reading `guest-chand.c` for
this amendment, not chased further (out of scope for this focused fix):**
`guest-chand.c`'s header comment states "PPP over this channel measured
133-384ms against 26-46ms over the console" — i.e. IP-over-channel is NOT
the untested zero-prior-art hypothesis the Milestone 2/3 design section
above called it; it has apparently been measured before, on a machine/lane
this note does not identify. Flagging this contradiction for whoever next
touches the M3 section — it is not resolved here.

### PLAN — Milestone 3: PPP + IP (BLOCKED, needs its own remaster — not a natural next step)

**FACT, not hypothesis: the entire PPP kernel stack is absent from the
Tribblix boot archive.** Shell #2's Lane 2 manifest, reported (not yet
independently confirmed by either of us):
`pppd`, `sppp`, `sppptun`, `spppasyn`, `spppcomp` **absent**
(SHELL-2-PROGRESS.md:977-978, :990-992: "Milestone 3 (PPP/TCP-IP) is not
reachable on this archive at all. It needs its own remaster and should not
be sequenced as if it followed automatically from a working channel.")
Confirmed I have found no contradicting evidence anywhere else in this
repo.

**This is a different and harder problem than the hsimd port**, and the
existing hsimd precedent does NOT transfer automatically:
`sppp`/`sppptun`/`spppasyn`/`spppcomp` are STREAMS kernel modules, not a
single legacy `dev_ops`-rev-3 leaf driver. hsimd's safety argument
(THE-TRIBBLIX-HSIMD-STORY.md / HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:233-254:
`devo_rev=3` short-circuits the illumos `dev_ops` size check) has **not**
been redone for any PPP module, and STREAMS module ABI stability across a
Solaris-10-to-Tribblix-illumos gap is an open question this project has not
investigated at all. Treat "port Solaris 10's PPP binaries the way hsimd was
ported" as an unverified HYPOTHESIS, not a proven recipe — do not schedule
work assuming it will work the same way.

**Existing Solaris-10-side reference** (what to reuse for CONFIG shape only,
not binaries): `tools/guest-ppp-up3.sh` (read in full this session) —
exact working sequence: mount pcfs staging slice, start a Perl mini-inetd
for telnet (`guest-pinetd.pl` — **also blocked**, Perl is absent from the
Tribblix archive per the same Lane 2 finding), verify `/etc/default/login`
allows root, then hand the console to
`pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff <peer-ip>:<local-ip> nodetach debug`.
The **PPP-over-console handoff pattern itself** (this exact `pppd` invocation
shape, plus the "everything needing the console happens BEFORE `pppd` takes
it over" ordering discipline, `guest-ppp-up3.sh:3-4`) is reusable design once
Tribblix has a working `pppd`; the Perl-based telnet bridge is not (no Perl).

**Missing dependencies for Milestone 3, complete list, nothing assumed present:**
1. `pppd` binary, plus `sppp`, `sppptun`, `spppasyn`, `spppcomp` kernel
   modules — absent, confirmed (reported evidence, not yet independently
   verified by either Shell #2 or me).
2. STREAMS module ABI compatibility check against Tribblix's illumos kernel
   — not started; this is new work, not a reuse of the hsimd analysis.
3. A getty/login-over-serial replacement for the Perl mini-inetd (Perl
   absent) — needs either a statically-linked C alternative (same cross-build
   pattern already proven for `guest-chand`) or Tribblix's own SMF
   `inetd`/`telnetd` made to work (this project's Solaris-10 side needed the
   Perl workaround specifically because SMF's inetd was `offline`; Tribblix's
   own SMF state for this has not been checked at all).
4. `/etc/default/login` and PPP `/etc/ppp/options` equivalents inside the
   Tribblix boot archive — not present, need to be authored, not copied
   verbatim (Solaris 10 and Tribblix `/etc` layouts are not guaranteed
   identical).
5. IP addressing scheme: reuse the already-working Solaris-10 numbering
   (`10.0.5.15`/`10.0.5.1`, `guest-ppp-up3.sh:43`) is safe to propose since
   it's a private point-to-point link with no observed conflict with the
   channel region (channel work never touches host networking), but this is
   a **naming choice**, not a dependency — flagging it as decided-by-reuse
   rather than blocked.

**Alternative worth naming, not adopted:** an IP tunnel built entirely in
userspace over the now-working `guest-chand`/`host-chan.py` framed channel
(SLIP/PPP-over-channel instead of PPP-over-serial-console) would sidestep
the STREAMS-module-porting problem entirely and would not consume the sole
serial console. This is a HYPOTHESIS with zero prior work in this project —
noting it as a lower-risk alternative worth a design discussion before
committing engineering time to the STREAMS-module route, not as a
recommendation to build it now.

### PLAN — Milestone 4 (NFS mount) and throughput/persistence gates (brief, correctly gated behind M3)

NFS client presence is REPORTED present in the Tribblix archive (Lane 2
manifest), but an NFS mount requires working IP first (M3) — there is
nothing to design here yet beyond noting the existing Solaris-10 reference
point (`10.0.5.1:/export/solaris` mounted at `/share`,
HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:89-92) as the shape to imitate once M3
lands. Throughput/persistence gates (bytes, elapsed time, MiB/s, and a
reboot-survives-mount check) are correctly sequenced last and depend on
both M2 (channel) and M3/M4 (IP+NFS) — no new design content until those
land; premature detail here would be speculation, not a plan.

Not executed. No console, no SSH, no VM/image/donor/boot-archive mutation.

## Lane 1 — Milestone 1 FINAL VERDICT, adjudicated against pre-registered criteria (05d2fc9): PASS (2026-08-20)

Independent repo-side review only. No console, no SSH, no execution, no M2
work. Evidence obtained from current whiteboard content and commits
(`4fa940c`, `7a1c633`, `e05bfa0`, `f28d909`, `0231463`), cross-checked
against my own from-scratch computation, not copied from any single agent's
verdict.

### Independent computation, not trusted from any report

Before comparing anything, I derived the expected digest myself:

```python
canary = b"HOSTPROOF-20260820T212724Z-CANARY-BYTE-01\n"   # 42 bytes
block  = canary + b"\x00" * (512 - len(canary))            # zero-padded to 512
sha256(block) = 7e12ea47ab7f1aba1d902c9b84f2bea41b35f93579a27051670e628a65cc9403
```

This matches, byte for byte:
- the host-side value Shell #2 measured three times independently
  (21:47:44Z, 21:49:21Z, 21:59:11Z — identical each time) via
  `dd bs=512 skip=1388160 count=1 | sha256sum` against the live backing file;
- the guest-side value reported in this task's evidence,
  `dd if=/dev/rdsk/c1d0s7 bs=512 iseek=0 count=1 | digest -a sha256` =
  `7e12ea47ab7f1aba1d902c9b84f2bea41b35f93579a27051670e628a65cc9403`.

Three independently-derived values (mine from first principles, host `dd`,
guest `dd`+`digest`) agree exactly. This is not a single source repeated —
it is the non-circular standard this project has required since the
`076a27c7...` false-positive.

### Adjudication against each of my five pre-registered `05d2fc9` criteria

1. **Backing image identity.** PARTIALLY independently verifiable, and I
   say so rather than paper over it: I have no SSH/console access and
   cannot recompute the *whole-image* SHA-256 myself — that remains a
   capability boundary, stated in `05d2fc9` in advance. What I CAN and did
   verify: the pre-canary whole-image hash (`099f366f...`) was the
   already-accepted Gate 2 value; the post-canary image hash
   (`a5c7dc8f...`) is a *different, expected* value because the canary
   write itself changed 42 bytes — that is not a discrepancy, it is the
   predicted consequence of criterion 2's write. The *targeted region's*
   hash was independently re-measured three times by a different reviewer
   using a from-scratch host command, and I independently reproduced the
   expected value by computation rather than by trusting either their
   number or the guest's. **Sub-verdict: PASS, with the whole-image-hash
   limitation stated, not hidden.**
2. **Host canary bytes/hash/offset.** PASS. Offset exactly 710,737,920.
   One aligned 512-byte sector (`oseek=1388160`, matches
   `1388160*512=710737920` exactly). Content is discriminating ASCII
   (`HOSTPROOF-20260820T212724Z-CANARY-BYTE-01`), not all-zero, not the
   retired `076a27c7...` zero-hash collision, and — checked specifically,
   since I required it explicitly — does NOT reuse the frozen ZFS-scratch
   lane's `HSIMD-ZFS-CANARY-20260820` string, preserving the artifact-
   identity separation this project adopted for exactly this reason.
   Independently re-read host-side three times, not inferred from a write
   exit status.
3. **Guest command and output, exact.** PASS. The command used —
   `dd if=/dev/rdsk/c1d0s7 bs=512 iseek=0 count=1 | digest -a sha256` —
   matches my pre-registered requirement exactly: `iseek=`, not `skip=`;
   output is byte-identical (full SHA-256, not a visual/terminal-rendered
   match) to the independently-verified host value in criterion 2.
4. **No channel-protocol `init` before this guest read.** PASS, proven
   without relying on either side's clock — exactly as I required. The
   discriminator is `host-chan.py cmd_init`'s own structural behavior
   (source-verified by me in an earlier entry, this file): `init` writes
   `NIAG`-magic control blocks and inflates the region's nonzero-byte count
   well past 42. Region nonzero was still exactly **42** and block 0 still
   carried **no `NIAG` magic** at three separate post-read checks
   (21:47:44Z, 21:49:21Z, 21:59:11Z). Since this count spans the *entire*
   17,039,360-byte channel region, not just neighboring blocks, it is
   strictly stronger evidence than my own criterion 5 sub-check demanded
   (which only asked about the immediately adjacent block) — nothing
   anywhere in the region besides the 42 planted bytes has changed.
5. **Post-proof artifact/VM state.** PASS on every itemized sub-check I
   required: region-wide nonzero count unchanged at 42 (supersedes and
   satisfies the narrower neighbor-block check I originally specified);
   known-good `tribblix-m34-hsimd.iso` hash reconfirmed unchanged
   (`e98d3a5e...`) multiple times across the whiteboard's shared facts; the
   frozen `tribblix-m34-hsimd-zfs-scratch.iso` reconfirmed untouched; VM
   state explicitly recorded as alive-and-parked at a `#` prompt with **no**
   Ctrl-C/Ctrl-D ("STOP GATE ENFORCED... Cleanly parked at # prompt"). I did
   not independently re-verify the boot-archive-extent hash
   (`2417a500...`) or the `0..1,048,576`-byte invariant myself at this
   specific moment — relying on Shell #2's and Antigravity's repeated
   reconfirmations of these same invariants throughout this session, which
   is consistent with, not a substitute for, independent verification; flagging
   as the one sub-item I did not personally re-derive.

### Not independently verifiable by me, stated plainly

- `guest-echocli`'s reported SHA-256 (`e41e6c419783885bc2f3af9143340bb7cb3b236069831bdeb8e50ff2109ccfa1`)
  — I have no local copy of this binary (only `guest-chand`, hashed in an
  earlier entry). Irrelevant to the M1 verdict itself (echocli is an M2
  asset, not used in the raw-`dd` canary proof), noted for completeness.
- Whole-image SHA-256 of the live, post-canary `tribblix-m34-chan.iso` — no
  SSH/console access; relying on the targeted-region cross-verification
  above instead, as stated in criterion 1.

### VERDICT: MILESTONE 1 — **PASS**

All five pre-registered `05d2fc9` criteria are satisfied. The one
capability-boundary caveat (whole-image hash, criterion 1) does not change
the verdict: the specific claim under test — a host-planted, discriminating,
non-circular byte proven readable by the guest at the correct offset before
any channel-protocol initialization — is independently established by three
separately-derived digests in agreement, clock-independent ordering proof,
and full-region integrity confirmation. This assessment was reached from my
own pre-registered criteria and my own from-scratch digest computation, not
by adopting another agent's verdict, though it agrees with Shell #2's
independent `f28d909` conclusion — convergent, not copied.

No M2 execution performed or authorized by this entry.
