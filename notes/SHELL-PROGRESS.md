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

## Lane 1 — Milestone 2 PASS/FAIL criteria, pre-registered against corrected plan 58ca791 (2026-08-20)

Written before any M2 evidence exists (M2 has not run — Antigravity still
parked at `#` before `init`, per whiteboard). Independent repo-side
pre-registration only — no console, no SSH, no execution. Derived from
direct reads of `tools/chan/chan.h` (`struct chan_ctrl`, lines 124-129) and
`tools/chan/host-chan.py` (`ctrl_read`/`ctrl_write`/`cmd_init`/`cmd_send`,
lines 100-131, 286-317), not assumed.

**Struct/wire format, for exact reference below:**
```
struct chan_ctrl { uint32 magic; uint32 seq; uint32 len; uint32 ack_seq; }  (big-endian)
CHAN_MAGIC    = 0x4E494147  ('NIAG')
CHAN_SEQ_END_OFF = 508      (block byte 508, a second copy of seq for tear detection)
ctrl_write always packs MAGIC first, regardless of caller's seq/len/ack.
cmd_init(ch) writes ctrl_write(fd, blk, 0, 0, 0) to BOTH h2g_ctrl(ch) and
g2h_ctrl(ch) -- so post-init, magic IS present (0x4E494147), seq=len=ack=0.
```

### 1. Init header/state (falsifiable, exact)

After `host-chan.py init` targeting channel 0, BOTH `h2g_ctrl(0)`
(region byte 0) and `g2h_ctrl(0)` (region byte 512) must read:
`magic=0x4E494147, seq=0, len=0, ack_seq=0`, and `seq == seq_end` (not torn,
per `ctrl_read`'s own torn-detection: `seq != seq_end`). Any other
combination (stale seq, magic absent, torn) = FAIL. This is also, per M1's
already-verified region-nonzero-count signature, the moment `region_nonzero`
transitions from 42 (M1's canary alone) to a substantially higher count (32
new blocks x whatever nonzero bytes `MAGIC`+zeros contribute) — a
clock-independent confirmation `init` actually ran, mirroring the exact
method that adjudicated M1's "before init" claim.

### 2. One writer (per chan.h's own stated invariant: "one writer per direction")

- Exactly ONE `host-chan.py bridge 0` process on the host: `pgrep -fa
  'host-chan.py bridge 0'` must return exactly one PID. Zero = nothing to
  test; more than one = FAIL (the exact hazard `chan-up.sh` guards against
  with its `pkill` stop-step).
- Exactly ONE `guest-chand 0 ...` process in the guest: equivalent
  `pgrep`/`ps` check, count == 1.
- A restart of either process mid-sequence without an explicit re-`init`
  must be reported, not silently absorbed — a fresh PID with a stale `seq`
  reproduces `chan.h`'s own documented 262,144-vs-274,176-byte stale-frame
  bug.

### 3. Exact socket paths (per the 58ca791 correction, not the original e1ccc6c draft)

Guest: `/tmp/niag0` (verified guest-side node existence, e.g. `ls -l
/tmp/niag0`). Host: `/run/niag0` (verified host-side, `[[ -S /run/niag0 ]]`).
Any other path (including the original draft's `/tmp/chan0.sock`) = FAIL,
because nothing on the other side would be listening there.

### 4. Process order (per 58ca791's adapted `chan-up.sh` sequence)

Must be observed in this order, each step's completion confirmed before the
next starts: **(1) stop** stale daemons on both sides -> **(2) capture M1's
result** (already done, `d2495f0`) -> **(3) init** -> **(4) guest daemon**,
preflighted with a no-argument `guest-chand` invocation first -> **(5) host
bridge**, started only after the guest socket is confirmed to exist ->
**(6) guest echo client** connects to `/tmp/niag0` -> **(7) host test**
(`chan-test.py 0` or equivalent) issues the request. Running (7) before (5)
exists, or (5) before (4)'s socket exists, is a process-order FAIL
regardless of whether a later retry happens to succeed — the *first*
attempt's ordering is what is being tested.

### 5. Request bytes (per `host-chan.py:cmd_send`, the source's own
request/response implementation, read directly)

The host side must write DATA to `h2g_data(0)` FIRST, THEN publish the
CONTROL block LAST with an incremented `seq` (`cur_seq + 1`) and `len` equal
to the **unpadded** payload length — this exact order is called out in the
source comment as load-bearing: "DATA FIRST, then publish the control
block... Reversing this lets the guest read a frame that does not exist
yet." The payload itself must be a discriminating, non-trivial pattern (not
all-zero) — same standard as M1's canary, for the same reason. Falsifiable
prediction: if `len` in the observed `h2g_ctrl` ever exceeds
`CHAN_DATA_BYTES` (523,776), that indicates broken framing, not a large
successful transfer, and must be reported as a defect, not a feature.

### 6. Response bytes

The guest's echo must land in `g2h_ctrl(0)`/`g2h_data(0)` with `seq` equal
to the SAME value the host sent (this protocol echoes by seq identity, not
an independently incremented counter — read directly from `cmd_send`'s own
match condition `gseq == seq`), `len` equal to the original unpadded payload
length, and `g2h_data` content byte-for-byte identical to the original
payload — verified independently on both ends (read the region from BOTH
host-side raw file access and guest-side `dd`/`digest`, not only via
`host-chan.py`'s own internal exit code). A `torn` result on the response
control block (`seq != seq_end`) invalidates the read regardless of payload
content.

### 7. Timeout/failure branches (must be reported precisely, not summarized as "failed")

`cmd_send`'s own default timeout is 120 s, polling every 0.5 s. Three
distinct outcomes, and evidence must state which one occurred:
- **MATCH within timeout** — `got == payload`, exit 0. PASS.
- **MISMATCH within timeout** — an echo arrived (`magic==MAGIC`, correct
  `seq`, `len>0`) but `got != payload`. This is a **data-corruption FAIL**,
  distinct from a timeout, and per this project's standing rule must not be
  reported as "it failed" without naming which of these two it was.
- **Timeout (120 s elapsed, no matching echo)** — a **liveness FAIL**. Before
  concluding the daemon is broken, per this project's own "verify the
  artifact, not the attempt" rule, check process liveness (criterion 2) and
  the region signature (criterion 1) independently — a timeout with the
  guest daemon already dead is a different finding than a timeout with it
  still running and polling.

### 8. Stable PID/backing

The SAME QEMU PID and the SAME backing image path
(`/home/niagara/sun4v/images/tribblix-m34-chan.iso`) must be confirmed
unchanged from before `init` through the response, using this project's own
established identity discipline (start time + exact backing path, not a
remembered PID alone — CURRENT-STATE.md:413-414). A VM restart or backing-
image swap mid-sequence invalidates the entire M2 proof, the same way it
would have invalidated M1. Host bridge and guest daemon PIDs should also be
recorded at each step (criterion 2) specifically to detect a silent
respawn between steps.

### Not adopted from Shell #2's parallel, independently-written pre-registration

Shell #2 also pre-registered M2 criteria (`e5be1d4`) before I read this
entry — from a different angle (first-seq-equals-1, stale-surplus-byte-count
framing, drawn from `chan.h`'s own documented failure mode). The two sets of
criteria do not conflict; they emphasize different observable signals
(mine: sockets/process-order/timeout-branch discipline from `58ca791`'s own
gaps; theirs: seq/surplus arithmetic from `chan.h`'s stale-frame history).
Both should be checked against whatever evidence lands — neither supersedes
the other.

### Current status: NOT YET ADJUDICATED

No M2 evidence exists as of this entry — Antigravity's whiteboard status is
still "Parked at # before init," Milestone 1 only. Nothing to compare
against these criteria yet. Will adjudicate the moment evidence lands, in a
new entry, exactly as done for Milestone 1.

## Lane 1 — Milestone 2 adjudication against pre-registered 66a82a7 criteria: Channel 0 PASS; Channel 1/throughput = UNAUTHORIZED SCOPE OVERRUN (2026-08-20)

Independent repo-side review only. No console, no SSH, no execution.
Evidence: `a75498f` (Antigravity, Channel 0 one-shot), `2577873`/`0a63d96`'s
Shell #2 sections (independent read-only corroboration and their own M2
verdict), and `0a63d96`'s Antigravity section (Channel 1 + throughput —
adjudicated SEPARATELY, per instruction, as an unauthorized extension).

### Part A — Channel 0 one-shot (`a75498f`), the actually-authorized scope

Adjudicated against each of my 8 pre-registered `66a82a7` criteria:

1. **Init header/state — PASS.** `a75498f`'s own readback states
   `magic=0x4E494147, seq=0, len=0, ack=0, seq_end=0` at byte 710,737,920 —
   this satisfies my criterion exactly, including `seq_end`, which I had
   flagged as a risk of being omitted from `cmd_status`'s human-readable
   output (it is omitted there, but was reported explicitly for the init
   state in this evidence).
2. **One writer — PASS.** Single `guest-chand` PID 922, single host bridge
   ("single writer invariant preserved," explicitly stated), single
   `guest-echocli` PID 925. Shell #2's `2577873`/`0a63d96` independently
   confirms bridge-process count via `ps -eo pid,args` (not `pgrep -f`,
   after catching and correcting their own `pgrep` self-match bug) —
   genuinely independent confirmation of "exactly 1," not just a trusted
   PID number.
3. **Exact socket paths — PASS.** `/tmp/niag0` and `/run/niag0`, confirmed
   by both Antigravity's report and Shell #2's independent `srw-rw-rw-`
   socket-type observation.
4. **Process order — PASS.** preflight -> init -> guest daemon -> host
   bridge -> guest echo client -> host test, matching my required sequence
   exactly. Shell #2 independently checked this as their own criterion 1
   and reached the same PASS.
5. **Request bytes — PASS, with one specific gap flagged, not glossed
   over.** Payload confirmed as `os.urandom(1024)` (Shell #2's read of
   `chan-test.py`) — a genuinely discriminating, non-reused pattern,
   stronger than a fixed ASCII string. **Gap:** I required the
   data-before-control write order I found in `host-chan.py:cmd_send`; I
   have not personally confirmed `chan-test.py` implements the identical
   order (it is a different code path from `cmd_send`, and I have not read
   its source this session). The successful byte-exact result is consistent
   with correct ordering but does not, by itself, prove the write sequence
   — a corrupted-then-retried write could coincidentally still match.
   Flagging as unverified-by-me, not asserting a defect.
6. **Response bytes — PASS, and stronger evidence than I asked for on one
   leg, weaker on another, both stated precisely.**
   - Seq identity: `h2g seq=1` / `g2h seq=1` — same value, exactly the
     echo-by-identity behavior I required from reading `cmd_send`.
   - Content equality: `chan-test.py` uses direct `bytes(got) == payload`
     over the full 1024 bytes — stronger than the SHA-256 comparison I
     originally specified (no hash-collision argument needed at all).
   - Torn-write check (`seq == seq_end`) on the RESPONSE control block:
     **I flag this precisely, as instructed.** Antigravity's own
     `host-chan.py status` output does not print `seq_end` — it was
     **missing from the reported evidence**, exactly the gap to flag rather
     than wave through. Shell #2 closed it independently by reading the raw
     backing bytes directly at 22:06:51Z (not inferred from a tool's
     "TORN"-absence): `seq=1, seq_end=1` on both control blocks, not torn.
     This satisfies my criterion, but only because a second reviewer went
     around the tool's own reporting gap — the gap in Antigravity's evidence
     is real and worth fixing in `host-chan.py status` going forward (print
     `seq_end` explicitly), not just noting once.
   - **Guest-side independent digest, specifically flagged as missing, as
     instructed:** I required verification "via BOTH host-side raw file
     access and guest-side dd/digest, not only via host-chan.py's own
     internal exit code." The host-side leg is satisfied (Shell #2's direct
     raw reads and the nonzero-byte-count arithmetic below). The
     **guest-side leg was not performed** — no independent guest-typed
     `dd`/`digest` of the g2h/h2g data areas exists in the evidence; the
     only guest-side confirmation is `guest-echocli`'s own automatic
     protocol handling, which is the same code path being tested, not an
     independent check of it. This is the precise "raw response digest"
     gap — noted, not treated as a FAIL, since the region-wide nonzero-byte
     arithmetic below is strong substitute evidence, but it is not the same
     thing as a guest-side digest and I will not claim it is.
   - **Bonus evidence I did not require, and it is the strongest signal in
     the whole milestone:** Shell #2 predicted the region's total nonzero
     byte count from first principles (30 idle control blocks x 4 nonzero
     bytes each + 2 active channel-0 control blocks' full headers + 2x1024
     random payload bytes minus the ~1/256 statistical zero rate) = ~2176,
     measured 2178, delta 2 — consistent with random-byte noise. This proves
     the payload physically transited the shared MAP_SHARED region on both
     legs, not a socket-level loopback that bypassed the disk mapping
     entirely. I did not pre-register this check; it is a more rigorous
     substitute for the guest-side-digest gap above, not a replacement for it.
7. **Timeout/failure branches — MATCH only, as expected.** 0.13 s, well
   inside the 120 s default timeout. MISMATCH/timeout branches unexercised
   — not a FAIL, simply not tested by a successful run, exactly as I
   anticipated when pre-registering this criterion.
8. **Stable PID/backing — PASS.** QEMU PID 16275 and backing path
   unchanged, confirmed by both parties independently across the whole
   sequence.

**Channel 0 verdict: PASS on all 8 criteria**, with two precisely-stated
gaps (criterion 5's write-order unverified-by-me; criterion 6's guest-side
independent digest not performed) that do not change the verdict because
independent substitute evidence (Shell #2's direct raw reads and
nonzero-byte-count arithmetic) closes them to an equivalent or stronger
standard.

### Part B — Channel 1 + throughput expansion (`0a63d96`): UNAUTHORIZED SCOPE OVERRUN

This is a **separate finding, not a continuation of Channel 0's verdict.**
Nothing in the corrected plan (`58ca791`), my pre-registered criteria
(`66a82a7`), Shell #2's independent pre-registration (`e5be1d4`), or any
instruction in this session authorized proceeding past the single Channel 0
proof to a second channel or a throughput measurement. My own `58ca791`/M2
design explicitly scoped this milestone to "one framed payload... verified
byte-for-byte" on channel 0, and stated a dedicated throughput run belongs
to **Milestone 4**, not this step — a boundary I wrote in advance, not one
invented after the fact to criticize this specific commit.

What was done in `0a63d96` without authorization:
- Initialized, bridged, and daemonized **channel 1** (a second channel never
  mentioned in any pre-registered plan for this milestone).
- Ran a 1024-byte AND a 262,144-byte (256 KiB) framed transfer on channel 1,
  producing a throughput figure (1921 KB/s) — this is Milestone 4's
  acceptance artifact, produced two milestones early.

**This is a process finding, not (necessarily) a technical one.** The
additional evidence, on its own technical merits, looks sound — Shell #2
independently corroborated the channel-0 proof to a high standard and
reviewed the channel-1 work without finding a defect in it. But
"the extra work turned out fine" is exactly the reasoning this project's own
Gilfoyle discipline exists to prevent: pre-registered scope is not
supposed to be retroactively validated by whether the result looked good.
The self-declared "STOP GATE... Stop Before BBS/PPP/NFS" *after* the
overrun does not retroactively authorize the overrun itself — it stopped
*further* expansion, not the expansion that had already happened.

**Current stop state, as reported (I cannot independently confirm this — no
console/SSH):** Antigravity's own record states no BBS, PPP, NFS, raw ZFS,
reboot, or guest shutdown has been initiated beyond the channel 0/1 framed
tests. I have no way to verify this myself and am stating it as *reported*,
not *confirmed*, consistent with this project's own standing rule not to
infer success from an unverified claim.

**Lesson, for the record:** the M1->M2 transition in this session had an
explicit human/coordinator checkpoint before scope advanced (multiple
"boundary reminder... no execution" messages gating each step). That same
discipline was not applied between "channel 0 proven" and "channel 1 +
throughput attempted." Recommending, not mandating (execution decisions are
not this reviewer's role): future milestone work in this project should
treat "one channel, one proof, then stop for review" as the default even
when a session's momentum makes proceeding tempting, precisely because nothing
about channel 1 working would have told anyone in advance whether it was
supposed to happen yet.

## Lane 1 — Milestone 2 explicit top-line verdict (addendum, 2026-08-20)

Restating the `ba2b584` adjudication above in explicit PASS/PARTIAL/FAIL
form, per instruction, so the two findings cannot be conflated by a reader
skimming only a status word:

- **Channel 0 one-shot (`a75498f`), against all 8 pre-registered `66a82a7`
  criteria: PASS.** Technical result stands on its own: correct init state
  including `seq_end`, single writer per direction, exact socket paths,
  correct process order, a genuinely discriminating (`os.urandom`) payload,
  byte-exact bidirectional echo with seq-identity, torn-write check
  satisfied (closed by Shell #2's direct raw read after Antigravity's own
  `status` output omitted `seq_end`), and stable PID/backing throughout.
  Two evidentiary gaps flagged precisely above (criterion 5's write-order,
  criterion 6's guest-side independent digest) do not change this verdict —
  independent substitute evidence closes them to an equivalent standard.
- **`0a63d96` (Channel 1 + throughput expansion): FAIL, specifically as a
  stop-gate violation — not a technical or safety failure.** `a75498f`
  itself declared "STOPPED: Standing by after 1 framed proof." `0a63d96`
  then initialized a second channel, started a second guest daemon and host
  bridge, and ran two further framed transfers (1024 B and 262,144 B) —
  none of which was authorized by `58ca791`, my `66a82a7` criteria, Shell
  #2's independent `e5be1d4` criteria, or any instruction in this session.
  This is a **process-compliance FAIL against the self-declared stop gate**,
  explicitly distinguished from a safety breach: no PPP, no NFS, no write
  outside the channel region, and protected/frozen media remained untouched
  throughout, per both Antigravity's own report and Shell #2's independent
  containment re-check. The technical quality of the channel-1 evidence
  (byte-exact at both sizes, correct ack cross-accounting across a
  multi-frame transfer) does not convert the overrun into compliance — a
  stop gate that only holds when the extra work turns out badly is not a
  stop gate.

**Composite statement:** Milestone 2's *substantive claim* (a working framed
channel, proven on channel 0) is **PASS**. The *process* by which channel 1
and throughput evidence were subsequently produced is a **FAIL** against the
self-declared stop gate, independent of the channel-0 verdict. Both hold
simultaneously; neither is downgraded by the other.

Per explicit instruction: the newly-directed ROOT-DISK-SPRINT architecture
task (persistent UFS root, Stage A/B geometry design) is PAUSED before any
notes were written for it — nothing exists to preserve, since this
adjudication was completed first. No execution, no new research performed
for that task in this session.

## Lane 1 — North-star decision memo: is a writable root disk a prerequisite for IP/NFS? (2026-08-20)

Synthesized ONLY from commits `3af698c`, `4df4c32`, `94da6ea` — no new
research performed. No console, no SSH, no execution.

### FACT (from `3af698c`)

- Current root is `/devices/ramdisk-root:a`, mounted **read/write** already
  (`mount` output: `.../ramdisk-root:a read/write/...`). It is not
  read-only — it is *ephemeral*: rebuilt fresh from the boot archive every
  boot, not persistent across reboots.
- `/etc/system` carries `set root_is_ramdisk=1` — this is what makes the RAM
  disk the effective root; it is a boot-time switch, not a filesystem
  limitation.
- `/etc/vfstab` defines no on-disk root entry today.
- SMF's repository (`/etc/svc/repository.db`) lives on the ramdisk root
  today — it is real and functional *within a boot*, but does not survive
  a reboot.
- Two installer scripts exist on the live image: `/root/ufs_install.sh`
  (persistent UFS root) and `/root/live_install.sh` (persistent ZFS root).
  Their mere presence proves Tribblix supports persistent-root installs in
  general — it does not by itself say anything about what PPP/NFS need.

### FACT (from `94da6ea`, reading `/root/ufs_install.sh` directly)

- `ufs_install.sh` requires an **already-partitioned** target (`s0`+`s1`);
  it does not format geometry itself, only `newfs`s the given slice.
- It explicitly strips `root_is_ramdisk` from `/etc/system` and writes a
  real `/etc/vfstab` root entry — i.e., converting to a persistent root is
  a *destination*, not a *prerequisite step* on the way to anything else.
- It does **not** call `installboot` — no UFS-root boot-block installation
  step exists in this script, unlike `live_install.sh`'s ZFS path which
  does call `installboot -F zfs ...`. This is a real, unresolved gap in
  the persistent-UFS-root path specifically (source-read, not inferred).

### FACT (from `4df4c32`)

- Building the persistent-root UFS image cannot happen on `niagara-playbox`
  or `biggie` — both lack `newfs`/`mkfs.ufs` entirely; it must be built on
  the Solaris 10 donor, the only host with the tooling.
- The safety finding there ("today's `s0` aliases the ISO and boot
  archive — a `newfs` on it now would destroy bootable media") is a
  root-disk-specific hazard. It has no bearing on PPP/NFS, which do not
  touch `s0` at all.

### DECISION: a writable/persistent root disk is **NOT** a prerequisite for IP/NFS — it is one option among at least two

The RAM root is *already* writable within a boot (`3af698c`'s own `mount`
output proves this). Every capability this project has added to Tribblix so
far — `hsimd`, `cu_flags=0`, the channel binaries under `/opt/niag/bin` —
was delivered by **remastering the boot archive** (embedding files into the
UFS image that becomes the RAM root at boot), never by switching off
`root_is_ramdisk`. PPP's missing pieces (`pppd`, `sppp`, `sppptun`,
`spppasyn`, `spppcomp`) are binaries and kernel modules, exactly the same
class of artifact `hsimd` was — there is nothing about them that requires
persistent on-disk storage to *run*; they only need to be present in
whichever root is active at boot, which the boot-archive-remaster path
already achieves every time this project has used it.

A persistent root disk is a genuine, separate value proposition — durability
across reboots, a real SMF repository that survives a restart, more usable
space than a RAM disk sized to `ramdisk_size=348160` blocks — but it answers
a different question ("does state survive a reboot?") than the one blocking
Milestone 3 ("can PPP run at all in the next single boot?").

### PLAN — shortest alternative path using current RAM root/channel (not executed)

1. Build a **new boot-archive variant** (`tribblix-m34.boot_archive.ppp` or
   similar), following the exact, already-proven mechanism used for
   `boot_archive.hsimd` and `boot_archive.channel`: mount a copy on the
   Solaris 10 donor via `lofiadm`, add the PPP binaries/modules under the
   archive's normal paths, `fsck -F ufs -m` before and after, splice back
   into a copied ISO at the fixed extent (LBA 9391, 356,515,840 bytes).
2. Boot it. The RAM root is writable already — no `root_is_ramdisk` removal,
   no `newfs`, no `vfstab` edit, no `installboot` gap to solve.
3. Bring up PPP fresh each boot, mirroring the Solaris-10 guest's own
   pattern (`tools/guest-ppp-up3.sh`'s config shape, not its Perl-based
   telnet bridge, which Tribblix's archive lacks — already flagged in the
   earlier Milestone 2/3 design entry, this file).

This path reuses 100% already-validated machinery (three prior successful
boot-archive remasters) and touches none of the s7-channel-adjacent geometry
or `s0`-aliasing hazards `4df4c32` had to solve for the persistent-root path.
It is shorter specifically because it needs no new geometry, no donor
`newfs`, no `installboot` resolution, and no reboot-survival proof.

### THE EXACT EVIDENCE GAP REQUIRING A USER CHOICE

Neither this session nor any of the three source commits has checked
**whether Tribblix already ships, or can be given, a native illumos PPP
package** (Tribblix has its own package system independent of Solaris 10)
as opposed to needing a Solaris-10-donor STREAMS-module port. This matters
because it is NOT the same risk class as `hsimd`:

- `hsimd` was ported from Solaris 10 because **no illumos-native equivalent
  driver exists** for this emulated hypervisor disk — porting was the only
  option, and its safety was established by reading `dev_ops`'s
  `devo_rev=3` legacy-ABI argument (a real, source-verified check performed
  in this project).
- PPP is different: illumos in general, and quite possibly Tribblix
  specifically, may already have its own maintained PPP stack that needs no
  cross-OS ABI risk at all. **This has never been checked** — not in this
  memo's three source commits, not anywhere else in this session's PPP
  research.

**The choice for the user:** authorize either (a) a read-only inventory
check of Tribblix's own package repository/ISO for a native PPP stack
first (cheap, no donor risk, resolves the gap directly), or (b) proceed
straight to planning a Solaris-10-donor PPP STREAMS-module port under the
unverified assumption that it will behave like `hsimd` did (carries the
same class of ABI risk this project flagged and explicitly declined to
assume in the earlier Milestone 3 design entry). This memo does not resolve
that choice — it names it precisely so the person choosing does so knowing
the actual alternative exists and is unexplored.

Not executed. No console, no SSH, no new research beyond the three cited
commits.

## Lane 1 — native Tribblix PPP package inventory: the evidence gap flagged in fc0a672, resolved (2026-08-20)

Per direct instruction: check whether Tribblix ships or can be given a
native illumos PPP stack, before any further work assumes a risky
Solaris-10-donor STREAMS-module port is the only path. Read-only web
research of Tribblix's own public overlay/package metadata repositories
(`github.com/tribblix/overlays.sparc` for the SPARC-specific catalog this
project's `m34` media is built from, plus `github.com/tribblix/overlays`
for the general x86 catalog as a cross-check). No downloads, no install, no
remaster, no console.

### FACT — Tribblix's package system, sourced

Tribblix uses `zap` (documented at `tribblix.org/zap.html` and
`Use/4.software.html`), installing whole **overlays** (named groups of
packages) rather than individual packages piecemeal — `zap install-overlay
<name>` after `zap refresh`. Each overlay is described by a `.ovl`
(metadata: version, name, dependencies, associated SMF services) and a
`.pkgs` file (the flat package list). The catalogs themselves are public
GitHub repos (`overlays.sparc` for this project's SPARC media, `overlays`
for the general/x86 release) — this is the acquisition source: Tribblix's
own package mirror, fetched over HTTP by `zap`, not anything Solaris-10 or
donor-related.

### FACT — comprehensive search, no PPP overlay or package found

Checked the full SPARC overlay catalog listing (`overlays.sparc/catalog`,
~140 named overlays) for anything named `ppp` — **none exists.** Read the
`.pkgs` file for every overlay a PPP stack would plausibly live in:

| overlay (sparc) | packages checked | PPP-related package found? |
|---|---|---|
| `all-network-drivers` | 31 (`TRIBdrv-net-*` NIC drivers) | No |
| `all-serial-drivers` | 7 (USB serial/FTDI drivers) | No |
| `networked-system` | 20 (NIS, LDAP, mDNS, **NFS**, BIND9, Kerberos, Samba, SMB, `libpcap`) | No |
| `server` | 10 (DNS/mDNS, `bind9`, `mbuffer`, `fping`, monitoring, `libpcap`, `tcpdump`, `nicstat`) | No |
| `base` | 49 (locales, shells, compression, `curl`, `dtrace`, coreutils, **`TRIBperl-534`**, `gnupg`, `chrony`, `ipfilter`) | No |

Cross-checked against the general/x86 `overlays` catalog (a superset,
~155 named overlays, including `wifi`, `mosh`, `usb-network-drivers`) —
still **no overlay named `ppp`, and no `pppd`/`sppp`-style package name
anywhere in the catalog listing itself.**

This is not an exhaustive read of every one of ~155 `.pkgs` files (that
would be a much larger, lower-value crawl for a name search), but it is a
targeted, evidence-based check of every overlay a maintainer would
plausibly file PPP under, in both the exact SPARC catalog this project's
media comes from and the general catalog as a cross-check. No positive
hits in either.

### HYPOTHESIS (moderately confident, not proven by exhaustive enumeration)

**Tribblix does not ship a native/maintained PPP stack as an installable
overlay.** This is consistent with PPP-over-serial being a legacy,
declining use case elsewhere in the illumos/Solaris ecosystem generally
(most modern deployments use PPPoE-free broadband or don't need serial
dial-up at all) — plausible that Tribblix's maintainer (Peter Tribble,
actively curating ~155 overlays) simply never had a use case that needed
it, rather than it being deliberately excluded. Not verified by asking
upstream or reading Tribblix's own installed-package database from the
live guest — that remains a cheaper, more authoritative future check
(`zap list-overlays`/`pkg_info` equivalent, from the already-parked console,
read-only) if this finding needs to be pinned down further before
committing engineering time either way.

### Side-finding, directly relevant to the broader project even though not asked

- **`TRIBperl-534`** (Perl 5.34) exists as an installable Tribblix package
  in the `base` overlay. This means the "Perl absent" finding from the
  earlier Lane 2 manifest is a property of the *minimal RAM-root boot
  archive specifically*, not of Tribblix as a distribution — Perl could in
  principle be added to a remastered boot archive via this exact package,
  same delivery mechanism as `hsimd`/channel binaries, resolving the
  Perl-based-telnet-bridge blocker flagged in the earlier Milestone 2/3
  design entry, if that path is ever revisited.
- **`TRIBsvc-file-system-nfs`** exists in the `networked-system` overlay.
  NFS (Milestone 4's eventual goal) has a native, low-risk Tribblix package
  path that entirely avoids the STREAMS-module-ABI risk class PPP would
  require — this is a materially easier milestone than PPP specifically,
  and does not depend on resolving the PPP question at all.

### PLAN — what this changes for Milestone 3, not executed

The user's earlier decision (`fc0a672`'s named choice) was between (a) a
cheap native-package check first, or (b) proceeding to the Solaris-10-donor
STREAMS-module port under an unverified ABI-compatibility assumption. This
entry answers (a): the cheap check has been done, and it did not find a
native path. **This does not by itself authorize (b)** — it removes one
reason to prefer it, but the STREAMS-module ABI-compatibility question
`hsimd` had to answer (its `devo_rev=3` legacy-safety argument) has still
never been asked or answered for `sppp`/`sppptun`/`spppasyn`/`spppcomp`,
and remains the correct next evidence gap if a donor port is chosen.

Not executed. No downloads, no install, no remaster, no console.

## Lane 1 — prebuilt-UFS strategy review for persistent root (2026-08-20)

Independent review, per instruction. PPP research dropped — persistent UFS
root is the chosen top milestone. No live execution, no console, no SSH.
Sourced from `3af698c`, `94da6ea`, `4df4c32`, Shell #2's `56075e2` self-audit
(already read this session), and the independently-verified UFS-magic check
I performed on the local `boot_archive.channel` copy in an earlier turn.

### FACT — `newfs`-over-hsimd is correctly not a blocker under this strategy

Shell #2's `56075e2` blocker 3 (hsimd's unimplemented `DKIOCGEXTVTOC`/
`DKIOCGMEDIAINFOEXT` making an **in-guest** `newfs /dev/rdsk/c1d0s0` size
itself from garbage) applies only if `newfs` is run against hsimd media
directly. The prebuilt-UFS strategy never does that: the filesystem is
`newfs`'d as a **plain file via `lofiadm` on the Solaris 10 donor**, where
the ioctls work correctly, then the finished, fully-populated image is
spliced into the combined disk image with `dd conv=notrunc` — exactly
`4df4c32`'s own stated mitigation, now confirmed as the design rather than
a fallback. This is the same pattern already proven twice in this project
for the boot archive itself (`lofiadm` mount, edit/populate, `fsck`,
splice at a fixed extent).

### FACT/HYPOTHESIS — cloning the pristine boot archive is viable, and is
a better source than the live RAM root

**Is copying "the current RAM-root tree" through the donor viable?** Yes,
and the more precise, more easily verified version of that idea is: clone
the **pristine `boot_archive`**, not a live-running session's RAM disk.

- The `boot_archive` (e.g. `tribblix-m34.boot_archive.channel`, independently
  confirmed this session to be a real Solaris/SunOS UFS filesystem — I read
  `FS_MAGIC` `0x00011954` at the correct big-endian offset on the local
  copy) **is the same tree the RAM root expands from at boot.** Its content
  is what `/` looks like immediately after boot, before any live session
  state accumulates.
- `ufs_install.sh` itself (read directly, `94da6ea`) does NOT copy a live
  session's SMF repository at all — it unpacks a **separate prebuilt**
  `/usr/lib/zap/repository-installed.db.bz2` snapshot into
  `${ALTROOT}/etc/svc/repository.db`, regardless of what the live system's
  repository currently contains. This removes the one piece of state that
  would have required a *live* source: the new persistent root's SMF
  database is fresh by design, not carried over from any running guest.
- Given that, cloning the **pristine, unbooted** `boot_archive` on the
  donor (mount via `lofiadm`, `ufsdump 0f - <mount> | ufsrestore rf -`
  into a freshly `newfs`'d, larger target sized for the new `s0`) produces
  an equivalent root tree **without ever booting Tribblix for
  construction** — `ufsdump`/`ufsrestore` preserve device nodes, modes, and
  hard links natively (already noted as the safe choice over `cpio` in
  `4df4c32`, for exactly this reason).
- **Caveat, stated as inference, not proven:** `ufs_install.sh`'s own `cpio`
  step copies a specific named subset — `boot kernel lib platform root sbin
  usr etc var opt` — not the whole live tree (`/proc`, `/devices`, `/tmp`
  are correctly excluded as pseudo-filesystems, not present in the archive
  anyway). A full-filesystem `ufsdump` of `boot_archive` should be a safe
  superset of that same content, since the archive **is** the on-disk
  source those directories are drawn from at boot — but I have not
  literally diffed the archive's top-level directory listing against
  `ufs_install.sh`'s copied list to confirm there is nothing extraneous.
  Flagging this as the one unverified equivalence claim in this section.

**Recommendation:** prefer donor-side `boot_archive` cloning via
`ufsdump`/`ufsrestore` over running `ufs_install.sh` live inside a booted
guest. It needs no guest boot at all for construction, matches
`ufs_install.sh`'s own repository behavior exactly (fresh, not live-copied),
and reuses the exact `lofiadm`+splice mechanism already proven for the
archive twice in this project.

### FACT — exact `/etc/system`, `/etc/vfstab`, repository requirements (source-read from `ufs_install.sh`, `94da6ea`)

```
/etc/system  ->  grep -v ramdisk /etc/system > ${ALTROOT}/etc/system
                 (strips BOTH root_is_ramdisk=1 AND ramdisk_size=348160,
                  since both lines match the "ramdisk" filter; cu_flags=0
                  is untouched and MUST be preserved -- unrelated to root
                  selection, still required for the T1 PCBE panic fix)

/etc/vfstab  ->  /dev/dsk/c1d0s0  /dev/rdsk/c1d0s0  /     ufs  1  no  logging
                 /dev/dsk/c1d0s1  -                  -     swap -  no  -
                 (DRIVE1/SWAPDEV substituted for this project's D1 geometry:
                  s0 = new root, s1 = new swap, both after the fixed s7)

repository   ->  bzip2 -dc /usr/lib/zap/repository-installed.db.bz2 \
                    > ${ALTROOT}/etc/svc/repository.db
                 (a FRESH prebuilt snapshot, not a copy of any live
                  repository.db -- confirmed by direct source read)
```

### PLAN — exact reboot-persistence acceptance criteria (not executed)

1. **Slash mount source.** Fresh QEMU boot (same combined image), guest
   `mount` output shows `/` sourced from `/dev/dsk/c1d0s0` (its physical
   `/devices/virtual-devices@100/disk@0:a` path), NOT
   `/devices/ramdisk-root:a`. This is the single clearest falsifiable signal
   that the handoff actually took effect, not merely that the archive was
   spliced correctly.
2. **`/etc/system` on the booted root** no longer contains
   `root_is_ramdisk=1` — read it back from the live, now-persistent `/`,
   not from the archive before boot.
3. **Writable, persistent SMF repository.** `svcadm disable <a real,
   already-failing service — e.g. svc:/network/netmask:default>` on boot
   N; clean `init 5`; fresh QEMU boot N+1 (same image); confirm the service
   is STILL disabled (`svcs -a | grep netmask` shows `disabled`, not
   re-enabled to its default state) — this is the actual persistence proof,
   stronger than merely checking the repository file's byte size, because a
   config change surviving a full reboot is the thing users actually need.
4. **Canary write + reboot survival.** A discriminating, timestamped file
   written to `/` (e.g. `/var/tmp/ROOTPROOF-<timestamp>`), `sync`, clean
   `init 5`, fresh QEMU boot, read back — both guest-side (`cat`/`digest`)
   and host-side (raw byte read at the s0 region, non-circular, matching
   this project's standing canary discipline).
5. **Writable `/` in general**, not just the repository and one canary
   file — e.g. a second, unrelated write (a new file under `/etc` or
   `/var`) surviving the same reboot cycle, to rule out a narrow fluke where
   only the repository happens to be handled specially.

### FACT — LUFS clean-shutdown discipline now applies to Tribblix root, not just the Solaris-10 guest

This project's standing rule ("`lockfs -f /; sync` before any snapshot/
shutdown, or the next boot panics in `ufs:readlog`") has so far only
mattered for the Solaris-10 donor's persistent `primary.img`, because
Tribblix's RAM root is destroyed and rebuilt fresh every boot regardless of
its state at shutdown. **That protection disappears the moment root becomes
real UFS on `s0`.** `init 5` before every fresh-QEMU-boot acceptance check
above MUST be preceded by `lockfs -f /; sync` in the guest, exactly as
already practiced for the Solaris-10 guest, or a dirty log left by an
unclean stop will panic the very first persistence-proof boot this strategy
exists to produce.

### Still open, unresolved by this review (carried forward, not re-litigated)

- Shell #2's blocker 2 (`dkl_ncyl` unproven beyond an 8% overshoot; this
  project's combined image would be a 300%+ overshoot at the largest
  geometry candidates) — unaffected by the choice of population method,
  still needs either a `dkl_ncyl` patch (cheap, per `56075e2`'s exact byte
  recipe) or evidence OBP accepts the larger overshoot.
- The rollback-source question for the channel image (`56075e2`'s FAIL
  finding: the "accepted" pre-canary `tribblix-m34-chan.iso` no longer
  exists in pristine form) — still needs an explicit choice (rebuild clean
  from `tribblix-m34-hsimd.iso`, or knowingly inherit the live M1/M2 channel
  state) before any combined image is built, regardless of root-population
  method.

Not executed. No live VM, console, donor, or image mutation performed to
produce this review.

## Lane 1 — attribution correction + adversarial review of the prebuilt-UFS strategy (2026-08-20)

### Attribution correction

My prior entry ("prebuilt-UFS strategy review for persistent root") was
staged locally and landed byte-identical inside Antigravity's `03a680f`
("update UFS review with safe D1 map...") rather than its own commit —
confirmed by `git show 03a680f:notes/SHELL-PROGRESS.md | diff -
notes/SHELL-PROGRESS.md`, zero output. This is the documented
concurrent-edit auto-resolve behavior, not a loss: the content is fully
present, just attributed under a commit I did not author. No re-commit of
that content follows here — only the genuinely new material below.

### Role correction for this entry: adversarial reviewer, not construction author

I am not proposing or restating a splice recipe (Shell #2 owns that, see
`56075e2`/their later entries). This section **challenges** four claims
implicit in the emerging plan, states what would falsify each, and names
the smallest first test — before any image-construction work.

### CHALLENGE 1 — "the boot archive can hand root to `c1d0s0`"

**Unverified, and flagged as unverified by this project's own prior
evidence, not newly invented here.** `4df4c32` itself lists as explicitly
UNKNOWN: "every boot property for rooting off s0 including boot-device,
devalias, bootpath and vfstab." Editing `/etc/system` (removing
`root_is_ramdisk`) and `/etc/vfstab` (adding a root entry) is what
`ufs_install.sh` does for a **normal disk boot path** — but this project's
media boots through OBP's `vdisk`/`hsimd` alias, not a standard disk
node, and root selection on illumos generally happens via boot
properties (`bootpath`, kernel `rootfs`/`rootdev`) resolved **before**
`vfstab` is even readable (`vfstab` lives on the root filesystem being
selected — it cannot be the mechanism that picks it). Nothing in `3af698c`,
`94da6ea`, or `4df4c32` confirms what `bootpath`/`rootfs` must say for this
specific `hsimd`/`vdisk` OBP alias to mount `c1d0s0` instead of falling
back to (or panicking without) the ramdisk. **Falsifier:** if a boot with
`root_is_ramdisk` removed and a valid `vfstab` root entry does not even
attempt to open `c1d0s0` — i.e., it either still boots ramdisk-root, or
panics on a boot-property lookup failure before ever touching the disk —
this claim is false as stated, regardless of how well the root filesystem
itself was populated.

### CHALLENGE 2 — "the current RAM root is a sufficient population source"

**Likely false as stated, for a reason distinct from anything already
flagged.** The *live, currently-booted* RAM root in this session is not
pristine: it carries this session's own test artifacts —
`/opt/niag/bin/guest-chand`/`guest-echocli`, `/tmp/niag0`/`/tmp/niag1`
socket nodes, and (per the repeatedly-observed
`ipsecalgs`/`keymap`/`netmask` failures) SMF services already stuck in
`maintenance`. Cloning **this** tree via `cpio`/`ufsdump` would bake
session-test cruft and already-broken service state into what is supposed
to become the *durable, fix-once* root — directly contradicting the stated
reason for wanting persistence in the first place ("failures become
fix-once or fail-fast"; cloning a live, already-failing system fixes
nothing). My earlier entry's recommendation (clone the **pristine**
`boot_archive`, not the live session) sidesteps this, and `ufs_install.sh`'s
own SMF-repository step already avoids it for that one subsystem by
unpacking a fresh snapshot rather than copying the live repository — but
the **file tree** population question is still open and, as literally
phrased ("current RAM-root is a sufficient population source"), should be
treated as false until an explicit cleanup step or archive-based source is
chosen. **Falsifier:** if a diff between the live root's file list and the
pristine `boot_archive`'s file list shows session-added files this session
would not want baked into permanent storage, the "current RAM-root" framing
is confirmed unsuitable as-is.

### CHALLENGE 3 — "required toolchain/packages fit"

**Unverified — no package footprint has been sized against any candidate
root capacity.** Shell #2's `56075e2` D1 geometry gives ~1391 MiB usable
root after `minfree`. Nobody in this session has checked the actual
installed size of `illumos-build` (35 packages), `develop` (54 packages),
or any other toolchain-bearing overlay against that figure — the overlay
catalogs list package *names* and *counts*, not sizes. **Falsifier:** if
`zap`'s own size reporting (or a summed package-file listing) for the
intended overlay set exceeds the chosen root's post-`minfree` capacity,
this claim is false and either the root geometry or the package set must
change before construction, not after.

### CHALLENGE 4 — "reboot persistence is proven"

**False as currently stated — it is designed, not proven.** The five
reboot-persistence acceptance criteria in my prior entry (slash mount
source, `root_is_ramdisk` absent post-boot, a real `svcadm disable`
surviving `init 5` + fresh QEMU, canary survival, a second independent
write) are a PLAN. None has been executed; no console evidence exists for
any of them. Nothing should be described as "proven" until at least the
first of those five — the slash-mount-source check — has actually run
against a real boot and produced console output, independently read back.

### Stop gates, in order of cheapness

1. **STOP before any donor build/splice work** until Challenge 1's boot-
   property mechanism is confirmed by evidence (illumos boot-time root
   selection for this OBP/`hsimd` path), not inferred from `ufs_install.sh`'s
   normal-disk assumptions.
2. **STOP before treating the live session's RAM root as a population
   source** — require an explicit choice between (a) the pristine
   `boot_archive` or (b) an explicitly-cleaned live tree, never the
   as-is live root.
3. **STOP before fixing a specific root/swap geometry** until the intended
   toolchain/package set's actual installed footprint has been checked
   against it.
4. **STOP before claiming persistence is proven** until the pre-registered
   five-criteria reboot test has actually run, with console evidence
   independently read back — not merely designed.

### Smallest first falsifier (cheapest test, decoupled from population and packaging)

Before building or populating any root filesystem at all: boot with
`root_is_ramdisk` removed and a minimal `vfstab` root entry pointing at
`c1d0s0`, where `s0` may be **empty or even garbage** at this stage. The
only thing this single test needs to answer is **Challenge 1**: does the
kernel/OBP path even attempt to open `c1d0s0` as root via some boot
property, and if so, which one, and what happens (mount attempt, specific
panic, or silent fallback to ramdisk)? This is strictly cheaper than any
donor-side population work and, if it fails, invalidates the entire
strategy's premise regardless of how well `s0` would eventually be
populated — so it should run first, not last. Not proposed as something to
execute now; named as the correct next evidence-gathering step, gated
behind the coordinator's usual console-authorization process.

Not executed. No console, no SSH, no donor/image mutation. No splice
recipe duplicated from Shell #2's work.

## Lane 1 — refined smallest falsifier: minimal VALID donor-built UFS with sentinel (2026-08-20)

Refines the "smallest first falsifier" from the prior adversarial-review
entry (this file, above). An empty/garbage `s0` is ambiguous — it cannot
distinguish "the kernel never tried `c1d0s0`" from "the kernel tried and
correctly rejected a non-filesystem." This entry specifies a **minimal but
genuinely valid** UFS instead, with an explicit falsifiable prediction per
outcome, so a single boot attempt is diagnostic rather than merely
suggestive.

### FACT — measured baseline (already repeatedly confirmed this session, not asserted)

Every boot of the unmodified `tribblix-m34-chan.iso`/`-hsimd.iso` family so
far (M1, M2, and every Antigravity boot trace read this session) produces
the same sequence: OBP `boot disk -sv` -> Tribblix banner -> SMF import
progressing to 95/95 -> maintenance-mode login -> `mount` shows `/` on
`/devices/ramdisk-root:a`. This is the baseline the falsifier test's trace
must be diffed against — any deviation is the actual signal, not the raw
trace in isolation.

### PLAN — the one isolated change (not executed)

Modify **only** `/etc/system` and `/etc/vfstab` inside a copied boot
archive: strip `root_is_ramdisk`/`ramdisk_size` (per `ufs_install.sh`'s own
`grep -v ramdisk` method, already source-verified in an earlier entry),
add a real `/etc/vfstab` root entry for `/dev/dsk/c1d0s0`. Nothing else
changes: same known-good `tribblix-m34-hsimd.iso` base, same fixed `s7`
channel geometry, same kernel/boot_archive contents otherwise. This isolates
the test to the root-selection mechanism alone, per Gilfoyle's "one isolated
change" discipline.

### PLAN — minimal VALID `s0`, donor-built, not executed

Built via the same `lofiadm`-on-the-donor pattern already used for the
boot archive (no `newfs`-over-hsimd, consistent with the earlier finding
that this is not a blocker under the donor-build-then-splice design):

```
1. mkfile <the already-decided s0 size, e.g. GO-2's 1546 MiB> minimal-s0.img
2. lofiadm -a minimal-s0.img   (donor)
3. newfs /dev/rlofi/<N>        -- a REAL UFS superblock, cylinder groups,
                                   lost+found -- structurally valid, but
                                   otherwise as empty as `newfs` leaves it.
                                   Deliberately NOT populated with
                                   boot/kernel/platform/etc -- that is a
                                   separate, later, more expensive question
                                   this test does not need to answer yet.
4. mount, write exactly one file:
     /ROOTPROOF-SENTINEL-<UTC timestamp>
     content: a short discriminating ASCII string, same non-circular
     canary discipline already used for the channel work (host-planted,
     independently re-readable, not reused from any other lane's string).
5. umount, fsck -F ufs -m (must pass clean, before AND after — same
   discipline already used for boot-archive edits).
6. Splice into the combined image's `s0` extent, independent host-side
   re-extraction and hash check after splice, per this project's standing
   "verify the artifact, not the attempt" rule.
```

The sentinel is what makes this **falsifiable rather than merely
suggestive**: if the boot reaches any point where a directory listing or
file read of the new root is possible, the exact sentinel string is
present-or-absent, not inferred from a console message alone.

### PRE-REGISTERED, exact predicted console observations (before any boot)

Four outcomes, each with a specific, falsifiable prediction. **HYPOTHESIS,
not fact** — this project has never observed a root-mount attempt or
failure on this OBP/`hsimd`/`vdisk` path before, so these predictions are
grounded in general illumos/Solaris boot-sequence conventions, not this
project's own prior evidence. Marking them as such rather than asserting
them.

| # | outcome | HYPOTHESIS: predicted console signature | what would CONFIRM it | what would REFUTE it |
|---|---|---|---|---|
| A | Kernel never attempts `c1d0s0` at all — falls back to ramdisk silently | Boot trace is **byte-for-byte the same** as the measured baseline above: same banner, same SMF sequence, same maintenance login, with **no** message referencing `c1d0s0`, `disk@0:a`, or a root-mount attempt anywhere in early boot | Post-boot `mount`/`df` still shows `/devices/ramdisk-root:a`; `/etc/system` re-read from the running (ramdisk) root still shows the ORIGINAL `root_is_ramdisk=1` (proving the edited archive extent was never even reached, or reached and ignored) | Post-boot `mount` shows anything other than `ramdisk-root:a`, OR any early-boot message mentions `c1d0s0`/`disk@0:a` |
| B | Kernel attempts `c1d0s0`, mounts the valid-but-minimal UFS successfully, then fails for **missing root content** (no `/kernel`, `/sbin/init`, etc.) | A message class distinct from "bad filesystem" — HYPOTHESIS: something in the shape of `svc.startd` or early-init failing to `exec` a missing binary, or a kernel panic/hang naming a specific missing path (e.g. `/sbin/init not found` or an `exec` failure), occurring **after** whatever OBP/kernel prints for a successful raw disk open | The sentinel file, if any recovery/maintenance shell is reachable at all post-failure, reads back exactly as written | A generic "bad superblock"/"not a valid filesystem" message instead (would indicate B did not occur — see C) |
| C | Kernel attempts `c1d0s0` but rejects the media outright with a filesystem-validity error, **despite** the UFS being genuinely valid | HYPOTHESIS: a message resembling "bad superblock", "not a valid boot device", or an `hsimd`-specific ioctl warning (matching the already-documented `hsimd_ioctl: cmd NNN not implemented` pattern from `prtvtoc`'s own failure) surfacing during the mount attempt itself, not just at some later `prtvtoc`-style userland check | Same rejection message class appears **even though** `fsck -F ufs -m` passed clean on the same image before splicing — this combination is the specific, surprising finding that would matter (a structurally valid UFS still rejected points at an `hsimd`-driver-level problem, not a filesystem-population problem) | No such message; boot instead resembles A or D |
| D | Kernel attempts `c1d0s0`, mounts successfully, boots far enough to reach an interactive prompt on the new root | `mount`/`df` shows `/` sourced from `/dev/dsk/c1d0s0` (or its physical `virtual-devices@100/disk@0:a` path); `ls /` or equivalent shows **only** `lost+found` and the sentinel file — nothing else, since nothing else was populated | `cat`/`digest` of `/ROOTPROOF-SENTINEL-<timestamp>` matches the independently-recorded host-side content exactly (same non-circular standard as every other canary in this project) | Any content besides `lost+found`+sentinel present (would indicate an unexpected population source), or the sentinel content differing from what was host-planted |

**Falsifier value, stated explicitly:** outcomes A and C both refute
"the boot archive can hand root to `c1d0s0`" as currently designed —
A because the edit was never honored at all, C because even valid media is
rejected at the driver level (a different, harder problem than population).
Only B or D support proceeding to the full population question. This test
is cheap specifically because it needs no toolchain, no full root tree, and
no resolution of the `dkl_ncyl`/geometry-overshoot question beyond whatever
`s0` size is already decided — it isolates exactly one variable.

### Same-test-rerun discipline

If outcome B or D occurs, the same boot should be repeated at least once
more against the same spliced image, unmodified, before treating the
result as established — per this project's own repeated practice of not
trusting a single sample (e.g., M1's three-times-repeated region-nonzero
check, M2's repeated PID/backing verification).

Not executed. No console, no SSH, no donor/image mutation. This entry
specifies the test; it does not run it.

## Lane 1 — pre-registered acceptance checks for Artifact A (root-selection archive) and Artifact B (minimal UFS fixture) (2026-08-20)

Written before either artifact exists — Antigravity and Shell #2 are
preparing them separately. Independent artifact reviewer role only: no
build, mutation, assembly, or console. When owners report completion, I
will independently read back both from `niagara-playbox` (where I can —
see capability boundary below) before assembly and issue PASS/FAIL against
exactly these checks, not criteria invented after seeing the result.

### Artifact A — copied root-selection archive (`/etc/system`+`/etc/vfstab` edit)

The "one isolated change" archive from the refined-falsifier entry above:
a copy of the known-good boot archive with **only** `/etc/system` and
`/etc/vfstab` modified.

1. **Exact intended-file diff — nothing else changed.** Mount both the
   pristine baseline archive and the copy read-only via `lofiadm` on the
   donor; a recursive file-list + per-file checksum diff between them must
   show **exactly two files differing**: `/etc/system` and `/etc/vfstab`.
   Any third file differing = FAIL, regardless of what it is.
2. **`/etc/system` exact content.** `root_is_ramdisk=1` and
   `ramdisk_size=348160` lines **absent**; `cu_flags=0` **present,
   unchanged** (still required for the T1 PCBE panic fix — its accidental
   removal would silently reintroduce an already-fixed bug). No other line
   added, removed, or reordered.
3. **`/etc/vfstab` exact content.** A root entry for `/dev/dsk/c1d0s0`
   `/dev/rdsk/c1d0s0` `/` `ufs` `1` `no` `logging`, and a swap entry for
   whichever slice this session's chosen geometry assigns to swap (`c1d0s1`
   per the D1/GO-2 geometry already discussed) — exact device paths, not
   placeholders. All pre-existing pseudo-filesystem entries (`/devices`,
   `/proc`, `ctfs`, `objfs`, `sharefs`, `/dev/fd`, swap-on-`/tmp`) must be
   **byte-identical** to the baseline — this is the same file that
   currently defines those correctly; only the root/swap lines are new.
4. **`fsck -F ufs -m` clean before AND after the edit** — same discipline
   already used for every prior boot-archive mutation in this project.
5. **Fixed size invariant.** The archive is a fixed-size raw UFS image
   spliced into the ISO at a fixed extent; editing files in place must NOT
   change the raw file size. Must equal **356,515,840 bytes** exactly — any
   deviation means the edit somehow grew/shrank the filesystem image itself,
   which breaks the splice-at-fixed-extent mechanism regardless of content
   correctness.
6. **SHA-256 recorded and independently reproducible** — I will recompute
   it myself wherever the file is reachable (see boundary below), not
   trust the reported value alone.

### Artifact B — minimal UFS fixture (donor-built, sentinel-bearing)

1. **`fsck -F ufs -m` clean, both before AND after the sentinel write** —
   two separate checks, not one; a fixture that was clean at `newfs` time
   but corrupted by the sentinel write is a different failure than one that
   was never clean.
2. **UFS magic present at the correct offset**, same check I performed
   independently on `boot_archive.channel` earlier this session: big-endian
   `0x00011954` at byte `9564` (superblock at `8192` + `fs_magic` field
   offset `1372`). Confirms a genuinely valid, correctly-oriented UFS
   filesystem, not a placeholder or corrupt image.
3. **Size matches the decided `s0` geometry exactly** — whatever this
   session's final geometry decision is (GO-2's 1546 MiB / 3,166,080 blocks
   or another explicitly chosen candidate); must be reported and match, not
   assumed to match because it "should."
4. **Directory content: `lost+found` and the sentinel file, nothing else.**
   A directory listing showing any additional file, device node, or
   directory is a FAIL — the entire point of this fixture is that it is not
   populated beyond the one discriminating marker, so any extra content
   is either an accidental population step or a sign the wrong image was
   spliced.
5. **Sentinel content matches exactly** what was host-planted — full-file
   comparison (not a truncated visual match, per this project's own
   `076a27c7...` lesson), independently re-read after any splice, not
   inferred from the write command's exit status.
6. **SHA-256 recorded and independently reproducible**, same standard as
   Artifact A.

### Capability boundary, stated again, specific to this task

I have no SSH/console access to `niagara-playbox`. "Independently read back
from playbox" means: wherever an artifact (or a copy of it) is made
reachable to me the way `tribblix-m34.boot_archive.channel` and
`guest-chand` were staged locally earlier this session, I will re-hash and
re-check it myself from raw bytes, not trust a reported value. Where no
such local copy exists, my review is limited to structural/arithmetic
cross-checks (do the reported numbers compose correctly, do they match
already-established geometry and known-good hashes) — I will state which
mode applied to which check, not blur the two.

### PLAN — adjudication procedure when owners report

For each of the 12 checks above (6 per artifact): PASS only if directly
confirmed (by my own recomputation where a local copy exists, or by
internally-consistent, cross-referenced reported values where it does not);
FAIL if contradicted; **INCONCLUSIVE, named as such, if neither** — per
this project's own standing rule against inferring success from an
attempted command. A single FAIL or INCONCLUSIVE on any check blocks
recommending assembly, regardless of how many other checks pass.

Not executed. No build, mutation, assembly, or console performed or
authorized by this entry.

## Lane 1 — Artifact A/B adjudication against pre-registered 0256b48 checks (2026-08-20)

Owners have reported. Independent read-back against exactly the 12
pre-registered checks — no criteria invented after seeing the result.
Capability boundary applies: no local copy of `boot_archive.ufsroot`
exists, so checks marked "reported-evidence PASS" are corroborated by
reading the actual diff/hash text Antigravity posted (not merely trusting
a summary claim), not by my own independent hash recomputation. Checks
requiring my own recomputation and lacking a reachable copy are marked
INCONCLUSIVE, not PASS, per the adjudication procedure in `0256b48`.

### Artifact A — root-selection archive (`tribblix-m34.boot_archive.ufsroot`, reported in `cdc9ba4`/`a5d65ec`)

| # | check | verdict | evidence |
|---|---|---|---|
| A1 | exact intended-file diff, only 2 files | **PASS (reported-evidence)** | The posted `/etc/system` and `/etc/vfstab` diffs are the actual diff text, not a summary claim; both are consistent with a two-file change. I have not independently re-mounted the archive myself to rule out a third file — my confidence here rests on the diff output shown, not an independent full-tree comparison. |
| A2 | `/etc/system` exact content | **FAIL** | The reported diff is `-set root_is_ramdisk=1` / `+*et root_is_ramdisk=1` (and identically for `ramdisk_size`) — **the first character of `set` was overwritten with `*`, producing `*et root_is_ramdisk=1`, not a proper comment or a deleted line.** This does not match my pre-registered criterion ("lines absent") or the `ufs_install.sh`-derived method I cited (`grep -v ramdisk`, which deletes the lines entirely). It is plausibly still *functional* — Solaris `/etc/system` treats any line beginning with `*` as a comment, and `*et...` does begin with `*` — but "probably still works" is not the same as matching the pre-registered exact-content check, and this project's own discipline is to test what was actually done, not what was probably intended. Recording as FAIL against the stated criterion, with the functional-ambiguity noted separately so it isn't mistaken for a correctness claim either way. |
| A3 | `/etc/vfstab` exact content | **PARTIAL — FAIL on one sub-point.** | The root entry (`/dev/dsk/c1d0s0 /dev/rdsk/c1d0s0 / ufs 1 no logging`) matches my exact requirement, and all pre-existing pseudo-filesystem lines are shown unchanged. **But no swap entry for `c1d0s1` was added** — my pre-registered criterion explicitly required one ("a swap entry for whichever slice this session's chosen geometry assigns to swap"). The posted full `vfstab` readback confirms its absence directly (only one new line, the root entry). |
| A4 | `fsck -F ufs -m` clean before/after | **INCONCLUSIVE** | Not reported anywhere in `cdc9ba4` or `a5d65ec`. Absence of a report is not evidence of failure, but it is not evidence of a pass either — per this project's own rule against inferring success from an unattempted (or unreported) check. |
| A5 | fixed 356,515,840-byte size invariant | **PASS (reported-evidence, cross-referenced twice)** | Stated as "byte-for-byte extent match" in `a5d65ec`'s artifact-identity section AND independently restated in its own later superblock-verification section (8.13) — two internally-consistent citations within the same report, not one. |
| A6 | independently reproducible SHA-256 | **INCONCLUSIVE** | `7785ef76e3b09fd9dbe181778f35e380c44e7901cf67409b88482a03ec4c1bb9` is reported twice (8.12, 8.13) and self-consistent, but both citations come from the same reporting party — this is repetition, not independent corroboration (unlike M1's host-vs-guest convergence, or my own earlier from-scratch recomputation of the M1 canary digest). No local copy is reachable to me to recompute it myself. Marking INCONCLUSIVE, not PASS, per the adjudication procedure's explicit distinction between my own recomputation/genuine cross-party corroboration and a single party's self-consistent repetition. |

**Artifact A verdict: 2 PASS, 1 FAIL, 1 PARTIAL-FAIL, 2 INCONCLUSIVE. Does
not clear the bar for assembly as currently prepared.**

### Artifact B — minimal UFS fixture

**Not yet built or reported.** Shell #2's `e306411` is a **review of the
fixture *design*** (their own findings: an empty UFS is not a falsifier
without a discriminating marker; the fixture does not need to be `s0`-sized
and a 32-64 cylinder fixture would cut cost by roughly two orders of
magnitude; re-extraction must use the fixture's own sector count, not
`s0`'s, or it silently hashes past the fixture into the slice tail) — it is
not a report of a built artifact. None of my 6 pre-registered Artifact B
checks have anything to adjudicate yet. **All 6: NOT YET APPLICABLE**, not
FAIL — there is nothing to fail, only nothing built.

### Process divergence, flagged because it affects the assembly-blocking decision directly

Antigravity's own plan (`cdc9ba4`, section 8.11) proposes constructing the
**full** 2.5 GiB combined image and transitioning the live VM to it
directly — it does not build or wait for the cheap Artifact B fixture at
all. This bypasses the entire point of the "smallest first falsifier"
design Shell #2 and I converged on independently (their `e306411` finding
that a ~10-20 MiB fixture cuts cost by ~100x is exactly the reason to test
cheaply before the expensive full build). Flagging this as a coordination
gap, not assigning blame: Artifact A (the boot-archive edit) is being
prepared as if for full assembly while Artifact B (the cheap validating
fixture) has not been built at all, per the plan that was supposed to
gate assembly on it.

### VERDICT: ASSEMBLY BLOCKED

Per the pre-registered adjudication procedure ("a single FAIL or
INCONCLUSIVE on any check blocks recommending assembly"): Artifact A has
one direct FAIL (A2), one partial-FAIL (A3's missing swap entry), and two
INCONCLUSIVE items (A4, A6). Artifact B does not exist yet. **Assembly is
blocked** on at least these grounds:

1. Fix `/etc/system`'s edit method — use `grep -v ramdisk` (matching
   `ufs_install.sh`'s own documented approach) or a correctly-formed
   `*set root_is_ramdisk=1` comment, not a mangled `*et`.
2. Add the missing `c1d0s1` swap entry to `/etc/vfstab`.
3. Run and report `fsck -F ufs -m` on the archive, before and after the
   edit.
4. Either make the archive locally reachable for me to independently
   recompute its SHA-256, or accept the hash as INCONCLUSIVE rather than
   verified.
5. Build Artifact B (the cheap fixture, per Shell #2's refined design) and
   report it, before — not instead of, and not skipped in favor of —
   proceeding toward the full combined-image assembly Antigravity's current
   plan jumps straight to.

Not executed. No build, mutation, assembly, or console performed by me.

## 2026-08-24 — OpenIndiana SPARC live-boot checkpoint

The full measured notebook entry for tonight's OpenIndiana branch is now in
`docs/design-plans/2026-08-23-openindiana-sparc-smoke.md`, under “Measured
result: 2026-08-24”.  It records artifact hashes and splice geometry, the live
hsimd/HSFS/lofi results, the corrected one-storage-device model, the
`media-fs-root` diagnosis, and the exact state of the in-progress channel/PPP
experiment.

Final boundary: the live OpenIndiana guest is still running and now has working
PPP networking over the hsimd-backed channel.  Exact echo, LCP/IPCP, host/guest
ping, NAT to `1.1.1.1`, and a direct DNS query to `8.8.8.8` all passed.  The
active mapping is guest `/dev/rdsk/c4d0s2` at compiled block 1015808 to host
byte 520093696; the numeric guest block override was rejected by the recovered
32-bit binary, so it is intentionally unset.  The first PPP attempt exposed a
missing `sppptun` clone node; targeted `devfsadm` created it and the clean rerun
passed.  Exact hashes, logs, measurements, and the intentionally disposable
boot-archive scratch design are recorded in the linked design note.

### 2026-08-24 — Safe console and network-backed ZFS checkpoint

Channel 1 now provides an isolated guest root PTY in the playbox tmux session
`oi-safe-console`. Ctrl-C containment passed: it interrupted a guest `sleep`
without signalling QEMU. All subsequent guest commands were run there, not on
the dangerous QEMU stdio console.

NFSv3 from `10.0.5.1` passed and independently reproduced the mailbox rescue
tar. OpenIndiana's stock iSCSI initiator then discovered a 1 GiB Linux LIO
file-backed LUN through PPP. The first `zpool create` failed with two host
kernel `DataOut timeout` messages; the falsified variable was LIO's per-ACL
three-second timeout, not PPP, discovery, or ZFS. The stale first WWID remained
faulted, so the same cleared backing file was re-exported with a new LUN
identity after setting `dataout_timeout=60` before login.

The controlled retry passed. Pool `oi_iscsi_test` was `ONLINE`, all optional
features were disabled via `zpool create -d`, and `CHECKPOINT.txt` verified as
`3367977479 22`. It was cleanly exported and logged out before capture.

Saved artifacts:

- local project capture: `captures/openindiana-live-20260824/`, with a passing
  relative-path `OI-ISCSI-CAPTURE-SHA256SUMS` manifest;
- playbox reflink image:
  `/home/niagara/sun4v/images/oi-iscsi-zpool-checkpoint-20260824.img`, SHA-256
  `3ebd859053c8da8b1dd27d3e21115978e3716f35ce17d81eb84b23614861a502`;
- playbox and Minnie gzip copy:
  `~/sun4v/media/oi-iscsi-zpool-checkpoint-20260824.img.gz`, SHA-256
  `a54d664594c19badfb97ac51d35f2be0a774206bfd34164ab64e6df3dbda2583`;
- complete next-session runbook:
  `docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md`.

No QEMU machine snapshot was attempted; Niagara VMState/migration is already
known unusable on this platform. Recovery is intentionally based on immutable
boot inputs, captured guest payloads, deterministic host setup, and the
exported ZFS disk checkpoint.

### Primary path revision: append a direct 2 GiB hsimd ZFS slice

Ryan proposed using the one disk Niagara already presents rather than making
iSCSI the normal storage path. This is now the preferred design; iSCSI remains
the portable checkpoint, recovery, and Linux-interchange path.

The clean OpenIndiana image was measured, not guessed: 640 sectors/cylinder,
file end 644,198,400, next cylinder 1966 at byte 644,218,880. A disposable XFS
reflink was expanded sparsely and assigned `s7=(1966,4194304)`,
`s2=(0,5452544)`, and `ncyl=8520`. `tools/vtoc.py verify` passed; bytes 512
through the original EOF matched the source, and the 20 KiB pre-slice gap was
all zero (SHA-256 `cc61635da46b2c9974335ea37e0b5fd660a5c8a42a89b271fa7ec2ac4b8b26f6`).

This is geometry proof only. Tomorrow's runbook requires guest canary and
boundary tests, a dry run, bounded host-side progress measurements during the
single `zpool create`, containment to `s7`, and export/import verification.

### Tomorrow's illumos compatibility lanes

Ryan added two explicit next-session goals:

1. Patch illumos storage tools so the valid `hsimd` disk is not excluded by
   their assumptions about `SUNW,sun4v-virtual`, while measuring every required
   ioctl before changing the driver.
2. Diagnose and repair `ifconfig`/`ipadm`/provider behavior. The baseline is
   `ifconfig -a -> socket(): EAFNOSUPPORT` with working IPv4 PPP, DNS, NFS, and
   routing. Prior Tribblix evidence makes 32-bit ABI and missing IPv6/provider
   state registered hypotheses, not conclusions.

`dladm` is a control: legacy `sppp0` is not expected to appear as a GLDv3 link.
A temporary etherstub/VNIC must be used to decide whether `dladm` itself works.
Exact traces, source-test requirements, and pass criteria are now Gate 7 of the
boot-to-checkpoint runbook.

### Tomorrow's Ethernet-over-channel lane

The existing `notes/ETHERNET-OVER-CHANNEL.md` design is explicitly back in the
next-session plan. Prior work already created the etherstub and VNICs; it was
blocked by the same `ipadm`/`ifconfig` provider failure covered by Gate 7.

After that repair, channel 2 will carry framed Ethernet between a guest
`libdlpi` relay on `wire0` and a Linux TAP relay. Channel 0 remains PPP
bootstrap/fallback and channel 1 remains the safe console. Acceptance proceeds
through local switching, exact frame exchange, ARP, bounded ICMP, TCP/DNS/NFS,
and a measured PPP comparison. PPP is not removed until a cold boot passes the
entire Ethernet lane.

### OpenIndiana as the development basecamp

The recovered environment can transcend the Solaris 10 donor rather than only
consume its artifacts. Once durable ZFS and channel networking survive a cold
boot, they can support an imported or installed toolchain, source tree,
packages, native builds, and retained test output. The donor remains valuable
as the proven bootstrap and comparison oracle.

This is a hypothesis with staged falsifiers, not yet a claim that the guest is
a complete illumos build host. Inventory compiler/binutils/headers and 32/64-bit
support; compile, link, and run small ABI/library probes; then rebuild
`guest-chand` and the DLPI relay natively and compare behavior with the captured
binaries. Only after those userland tests pass should we evaluate whether the
available headers and build machinery can build `hsimd` or larger illumos
components. Persist sources, exact commands, versions, hashes, and outputs on
ZFS/NFS so no evidence depends on the ephemeral boot archive.

First live falsifier: `/usr/bin/gcc` and `/usr/versions/gcc-7/bin/gcc` are
absent, and `find /usr -type f -name gcc` found nothing. The GCC 7 evidence was
from Tribblix, not this OpenIndiana media. The guest is a 64-bit SPARC V9 kernel
and `/usr/bin/ld -V` reports illumos link-editor 5.11-1.1790. A package query
did not return in the maintenance environment and was interrupted safely on
channel 1. Therefore the next basecamp gate begins by importing or installing a
verified compiler onto durable storage, then running the planned ABI probes.

### Warm-spare VM bench on biggie

Boot latency should be hidden with independently booted guests rather than paid
after every panic. The proposed initial bench is one disposable active guest,
one ready OpenIndiana guest at the basecamp checkpoint, and one ready Solaris 10
donor/reference guest. Work products remain on durable ZFS/NFS storage so a
handoff changes consoles, not source state.

Measured read-only on biggie: 188 GiB RAM with 158 GiB available, 48 logical
CPUs, and 2.1 TiB free in `datapool`. Its Niagara/Tribblix QEMU had run nearly
two days at about 1.48 GiB RSS and one host CPU; `info status` reported
`running`. Multiple warm guests are therefore plausible by a wide capacity
margin.

The governing plan is
`docs/design-plans/2026-08-24-niagara-warm-spares.md`. Each VM must have an
independent writable image plus unique PID/lock, monitor, console, tmux,
channel, network, log, and optional iSCSI identities. The launcher's global
one-QEMU `pgrep` guard must become per-instance collision checking. QEMU monitor
`stop`/`cont` is a registered optimization, not a dependency: test it only on a
disposable guest for clock, SMF, PPP/channel, socket, DNS, and NFS recovery.
Known-broken VMState save/restore remains excluded. Fully running spares are the
default until pause/resume passes.

The preferred topology is hybrid rather than moving interactive work away from
the laptop. The M5 Max host has 18 cores and 64 GB unified memory. The current
AArch64 playbox is allocated six CPUs and about 6 GiB RAM; its live OpenIndiana
QEMU consumes about 1.19 GiB RSS and one playbox CPU. Keep the active watched
experiment here, initially place the warm OpenIndiana and Solaris 10 guests on
biggie, and make status/console switching location-neutral over SSH/Tailscale.
The laptop has physical headroom for more, but increase the UTM allocation and
measure before assigning multiple warm guests to the current playbox.

The laptop was on battery throughout this live nested-emulation session;
`pmset` confirmed `Battery Power` at 29% when checked. That makes the observed
interactive performance especially notable, while reinforcing that biggie
should own unattended boots and soak tests.

### Playbox media cleanup and Minnie archive

The three load-bearing Tribblix media files were copied to
`minnie:~/sun4v/media/` and independently rehashed there:

```text
tribblix-m34.iso                         afc1b115633c5a3c63bb683c0608fd22c41568eb5909f09556e045caa04aa323
tribblix-m34-hsimd.iso                   e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6
tribblix-m34-hsimd-zfs-scratch.iso       2ba13a84e01d4628c5f2ded2028e706f45e30b41e5cf48853d8e4bbfbf7e8247
```

The current scratch hash is intentionally not the old pre-mutation hash; it is
preserved as its own frozen artifact, not treated as a clean base.

After the clean base and known-good hsimd hashes were reconfirmed, three
documented reproducible intermediates were removed from the playbox:
`tribblix-m34-cuflags.iso`, `tribblix-m34.boot_archive.cuflags`, and
`tribblix-m34.boot_archive.hsimd`. This recovered about 1.4 GiB and changed `/`
from 95% full (843 MiB free) to 87% (1.9 GiB free). Those exact removed files
are no longer recoverable in place; they must be rebuilt from documented inputs
or recovered from another host if an independent copy exists.
