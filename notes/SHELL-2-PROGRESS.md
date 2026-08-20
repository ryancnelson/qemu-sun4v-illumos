# Shell #2 progress — documentation audit and Stage 4 safety review

Agent: Shell #2 (Maestri canvas). Coordinator: Codex.
Scope of this note: local read-only review plus documentation corrections.
No SSH, no guest console input, no VM signalling was performed at any point.

---

## 2026-08-20 — session log

### FACT — what was reviewed

| file | lines read | state |
|---|---|---|
| `THE-TRIBBLIX-HSIMD-STORY.md` | 1-523 (whole) | tracked, clean |
| `HSIMD-ZFS-VALIDATION-PROCEDURE.md` | 1-419 (whole) | **untracked, another agent's artifact — read only, not edited** |
| `CURRENT-STATE.md` | 1-300, 218-296 | tracked; edited by me |
| `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` | 1-677 (whole) | tracked; edited by me, sole editor |

Repo baseline at session start: branch `master`, HEAD `be680a8`, working tree
clean except untracked `HSIMD-ZFS-VALIDATION-PROCEDURE.md`.

### FACT — arithmetic independently re-derived (not copied from the docs)

All s7 numbers follow from the Sun label geometry alone (1 head, 640
sectors/cylinder). Every figure below was recomputed locally and agrees with
the source documents:

```
s7 start   cyl 2169 * 640      = sector 1388160  = byte  710737920
s7 length  655360 sectors      = 335544320 bytes = 320.0 MiB exactly
s7 end                           byte 1046282240 = the scratch image size exactly
s2         2043520 blocks      = 1046282240 bytes = 3193 cylinders
base ISO                         byte  710717440
gap ISO-end -> s7-start          20480 bytes (s7 cannot overlap the boot archive)
boot archive extent              19232768 .. 375748608 (LBA 9391, 356515840 bytes)
known-good s0..s7 1387520 blk  = 710410240 bytes = 677.5 MiB = 2168 cylinders
dkl_ncyl 2048 * 640            = 1310720 sectors, vs s2's 2043520 -> label
                                 under-reports; cosmetic on the evidence so far
sha256(512 zero bytes)         = 076a27...  <-- see contradiction C2
```

Predicted ZFS label positions on the s7 vdev (used as the post-create offset
oracle, since no canary is durable):

| label | blank@ | nvlist@ | uberblock ring |
|---|---|---|---|
| L0 | 710737920 | 710754304 | 710868992 - 711000064 |
| L1 | 711000064 | 711016448 | 711131136 - 711262208 |
| L2 | 1045757952 | 1045774336 | 1045889024 - 1046020096 |
| L3 | 1046020096 | 1046036480 | 1046151168 - 1046282240 |

### FACT — contradictions found

- **C1 — falsified claim, highest severity.** `CURRENT-STATE.md:270` and
  `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md:608-610` both stated "no canary write and no
  `zpool create` have occurred". The host survey found the canary at s7+0, four
  txg=0 `hsimdz` labels, and ~54 KB of MOS residue. An agent trusting those
  lines would treat s7 as pristine. **Corrected in both files.**
- **C2 — non-discriminating digest.** `CURRENT-STATE.md:228` and
  `BOOTSTRAP:521` present sha256 `076a27c7…` as proof of nonzero-offset read
  handling. That digest is the hash of 512 zero bytes (verified locally). It
  rules out "always returns sector 0" but not "returns zeros at any nonzero
  offset". **Caveat added to both.**
- **C3 — H1 vs eyewitness.** `HSIMD-ZFS-VALIDATION-PROCEDURE.md:196` calls the
  host-crash explanation "most economical" and demotes "`zpool create` hung" to
  merely not-excluded. `THE-TRIBBLIX-HSIMD-STORY.md:338,352-356` records the
  hang as directly observed, before any host crash. The hang hypothesis is
  better supported. Recorded as H-B in both corrected docs.
- **C4 — self-contradicting mtime inference.** `PROCEDURE:99-100` uses a frozen
  mtime to conclude no guest writes occurred; `PROCEDURE:196` then relies on
  dirty `MAP_SHARED` pages hiding writes. Both cannot be load-bearing. Under
  mmap, mtime advances on writeback/msync, not on store.
- **C5 — pre-broken stop-gate.** `PROCEDURE:307` gates Stage 3 on `prtvtoc`
  output and `:310` says stop on mismatch, but `STORY:298` records `prtvtoc`
  already failing on an unsupported ioctl. As written the run halts on a known
  benign condition, or trains the operator to ignore stop-gates.
- **C6 — circular canary gate.** `PROCEDURE:308` calls the s7 canary
  "host-planted"; it was guest-written (`STORY:302-319`). Reading it back
  through the same mapping proves nothing about skew.
- **C7 — untagged console records.** `BOOTSTRAP:612-614` reports `root` echoed
  without advancing; `PROCEDURE:81-82` reports nothing typed this boot. These
  are different QEMU instances and neither says so.
- **C8 — binary grep bug.** `PROCEDURE:370` uses `grep -c` on binary input
  (counts newline-delimited lines, not matches) and checks only one byte order,
  where `PROCEDURE:178` correctly used `grep -abo` in both orders.
- **C9 — unreconciled space accounting.** `PROCEDURE:27` reports 2.9 G used on
  the images LV; `:102-103` lists two 2684354560-byte files there (5.0 GiB).
  Only consistent if sparse; never stated.
- **C10 — "read-only survey" that wrote.** `PROCEDURE:1,5-7` claim no media
  write; `:239-240` admits staging a 335 MB scan file on a root filesystem with
  402 MB free.

### FACT — safety risks found

- **R1 — import alias, highest severity.** s7 ends exactly at the image end and
  s2 spans the whole image, so s2's L2/L3 slots are byte-identical to s7's
  (1045757952, 1046020096). A bare `zpool import` can bind **s2**, whose L0/L1
  land at bytes 0 and 262144 — the Sun label and the boot archive. Mitigation:
  `zpool import -d <dir>` with a single s7 symlink; full paths only; verify the
  sha256 of bytes `0..1048576` and of the boot-archive extent after every pool
  operation.
- **R2 — no hang bound.** The old plan re-ran the exact command known to hang,
  with no timeout and no hang-detection. Replaced by a host-side classifier
  measuring committed bytes across periodic msyncs.
- **R3 — single-console ownership.** Plain `-nographic`, no QMP/monitor,
  stdin/stdout/stderr on one pty behind a double `sudo`; `Ctrl-A c` echoed
  literally as `^Acinfo status`. There is no out-of-band control path, so every
  abort must be host-side. Ctrl-C/Ctrl-D have previously destroyed expensive
  shells.
- **R4 — forensic loss.** `PROCEDURE`'s recommended branch 1a runs
  `zpool labelclear` on the only copy of the txg=0 evidence. Prefer a fresh
  disposable image on the images LV.
- **R5 — `chmod 444` is not protection** when every QEMU invocation runs under
  sudo.

### FACT — H4 status (completed vs in-flight)

Distinguished deliberately, per the whiteboard rather than my own inference:

- **Completed (whiteboard shared facts):** guest `c1d0s7` first 10 sectors match
  the host backing bytes exactly by SHA-256; pre-write baseline shows no
  committed uberblock magic in s7.
- **In-flight / not established:** the raw-device EOF boundary semantic. Nothing
  on the board or in the repo records what `read(2)` returns at or past the end
  of `/dev/rdsk/c1d0s7`.

Process note: I initially asserted from a repo grep that H4 had "no local
record". That was a claim of absence from one search path, and it was wrong —
the whiteboard had it. `recall "H4 read path test hsimd s7 EOF" hybrid` returned
nothing relevant, confirming H4 is live work rather than history.

### HYPOTHESIS — carried forward, not collapsed

- **H-B (better supported):** `zpool create` hangs before `spa_sync()` writes
  the first uberblock; the defect is in hsimd's ioctl/completion contract.
  Supported by direct observation of the non-returning command.
- **H-A (circumstantial):** the uberblock was lost with dirty `MAP_SHARED` pages
  in the unclean host shutdown. Consistent with the bytes; not eyewitnessed.
- **H-EOF (untested, blocking):** hsimd returns an error rather than a clean EOF
  at the vdev boundary, and that is what stalls ZFS. ZFS writes L2/L3 and the
  uberblock ring into the final 512 KiB, so this is on the critical path.

Discriminator for H-A vs H-B: presence of uberblock magic in s7 after a forced
msync, checked in both byte orders. Nothing else. `zpool create` exit status is
not evidence.

### PLAN — corrected Stage 4 matrix

Written into `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` (Immediate next steps section).
Summary: preconditions P1-P7 including a **host**-planted canary and baseline
invariant hashes; T0 idle baseline; T1 read path and offset oracle; T2 the
single `zpool create -f hsimdz /dev/dsk/c1d0s7` with a host-side hang
classifier (bytes committed across msyncs, hard stop at 600 s); T3 informative
guest status; T4 authoritative host readback checking both byte orders with
`grep -abo | wc -l` and asserting the four predicted nvlist offsets plus the
P5/P6 invariants; T5 negative control against the unbooted known-good ISO.
Export/import/scrub deferred until H-A is supported.

### Document changes made

- `CURRENT-STATE.md` — header correction banner; `076a27…` zero-hash caveat;
  replaced the falsified "no canary write" paragraph with the measured s7
  contents, the zero-uberblock finding, and H-A/H-B; added subsections for the
  s7 byte mapping, the import alias hazard, the EOF semantic (marked
  UNVERIFIED/blocking), and single-console ownership.
- `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` — superseded the falsified paragraph with
  the measured s7 contents and a boot-tagging rule; corrected the s7 I/O status
  to distinguish proven writes, the 10-sector read proof, and the absent
  uberblock; replaced the three-line next-steps with the full corrected Stage 4
  matrix.
- `HSIMD-ZFS-VALIDATION-PROCEDURE.md` — **not edited.** Untracked artifact
  belonging to another agent; findings against it are recorded here as C1-C10.

### Blockers

1. **EOF semantic unmeasured** — blocks confident interpretation of any Stage 4
   hang. Needs the syscall return, errno, and transfer count at s7 end-1, end,
   and end+1 sectors.
2. **No forensic copy of the scratch image exists** (also on the whiteboard).
   Until it does, any `labelclear`/`create -f` on the current scratch destroys
   the only txg=0 evidence.
3. **Space accounting unreconciled** (C9) — must confirm `primary.img*`
   sparseness before relying on "9.1 GB free" for a second disposable image.
4. **Stage 4 authorization** — matrix is written but unexecuted; it needs Codex
   sign-off, and execution belongs to the designated console operator
   (Antigravity, single-writer rule), not to me.

### FACT — independent verification of external review points (post-dd252f0)

Read `tools/vtoc.py` in full (121 lines) and re-grepped the current
`HSIMD-ZFS-VALIDATION-PROCEDURE.md`, which Shell has since edited (line numbers
below are current, and differ from the C1-C10 citations above). I did not edit
the procedure — Shell owns it.

**V1 — "does vtoc.py have a checksum-write path?" CONFIRMED, with a caveat that
falsifies the procedure's recipe.**

There is exactly one write path: `cmd_set()` (`tools/vtoc.py:77-87`), which
packs the slice entry at line 84, calls `fix_checksum()` at line 85, and writes
all 512 bytes back through `open(dev, "r+b")` at lines 86-87. `fix_checksum()`
(lines 47-49) zeroes `dk_cksum` then stores the recomputed XOR. So `set`
recomputes the checksum, exactly as the module docstring claims at lines 10-13.

**`cmd_verify()` (lines 90-111) is strictly read-only.** It calls
`read_label()` (line 91), prints, and `sys.exit(0 if ok else 1)` (line 111).
It never opens the device for writing and never calls `fix_checksum()`.

Therefore `HSIMD-ZFS-VALIDATION-PROCEDURE.md:394-395` is **REJECTED**:

```
# ncyl fix (H2 hygiene): set 0x1b0 to 3193 (0x0C79), then re-run vtoc.py
# verify so the XOR checksum is recomputed. OBP validates that checksum.
```

`verify` does not and cannot recompute anything. Following that recipe hand-
edits `dkl_ncyl`, invalidates the XOR, and then runs a command that merely
*reports* `FAIL: checksum invalid (OBP will reject this disk)` and exits 1. The
operator would be told the checksum was repaired when it was corrupted. OBP
would then refuse the disk — the precise failure mode the tool exists to
prevent (docstring, lines 8-13).

Two further defects in the same block:

- **Ordering.** The `verify` at `:391` runs *before* the hand-edit at `:394`,
  so the gate at `:398` is evaluated against a label that has not yet been
  corrupted. The gate cannot catch the damage it is positioned to catch.
- **No supported path.** `vtoc.py set` only writes `dk_map` entries at
  `0x1bc + slice*8` (line 84). Nothing in the tool touches `0x1b0`
  (`dkl_ncyl`). There is no supported way to fix ncyl with it.

Working alternative, if the ncyl hygiene fix is wanted: hand-edit `0x1b0`
**first**, then run `vtoc.py set <dev> 7 2169 655360` — re-writing s7 with its
existing values triggers `fix_checksum()` over the already-modified label —
then `verify`. Sequence matters; the current order cannot work.

**V1b — unit confusion in the verify logic (new, not in the external review).**
`dk_map` entries are `{cyl, nblk}` (docstring line 17), but `cmd_verify`
compares them as if both were the same unit: the overlap test at line 100
(`ci < cj + nj and cj < ci + ni`) and the containment test at line 107
(`c + n > s2[1]`) both add a cylinder to a block count. For s7 this happens to
pass (2169 + 655360 = 657529, under 2043520) and the true end also happens to
equal s2 exactly (2169*640 + 655360 = 2043520), so the bug is invisible on this
image. It would give wrong answers on other geometries. Related cosmetic
issue: `cmd_show` prints the header `start_blk` (line 72) while printing `cyl`
(line 74), which invites exactly this confusion.

**V2 — "is mtime merely informative or currently mandatory?" CONFIRMED
mandatory in the procedure, and I had the same defect in my own draft.**

`HSIMD-ZFS-VALIDATION-PROCEDURE.md:478` reads
`stat -c '%y %s' <image path>        # mtime MUST advance past 16:08:13`,
sitting under a `Gate:` heading. That is mandatory, and it is unsound.

Mechanism: under `MAP_SHARED`, the kernel stamps mtime when a page is first
dirtied by a write fault, not at `msync`. So mtime has usually already advanced
long before the barrier, and an `msync` across already-clean pages can leave it
untouched while the data is fully present. Neither its advance nor its
stillness proves anything about pool state.

**Self-correction:** my own Stage 4 matrix said "confirm mtime advances" in T4.
Same overreach. Fixed — T4 now records mtime as an indicator and explicitly
states it is never a gate; only the byte readback gates.

This also settles C4 above: the procedure's `:210`/`:314` use of a frozen mtime
as evidence of "no guest write" is unsound for the same reason.

**V3 — "what command proves scrub completion?" REJECTED as written.**

`HSIMD-ZFS-VALIDATION-PROCEDURE.md:509` is
`zpool scrub hsimdz ; zpool status hsimdz`, gated at `:512` on "scrub
completes with 0 errors". `zpool scrub` returns immediately — it starts an
asynchronous scan. The `zpool status` that follows will report
`scan: scrub in progress since …`. The sequence proves a scrub *started*.

Completion is proved only by polling `zpool status` until the scan line reaches
a terminal state, `scrub repaired … with 0 errors on <date>`. This is a textbook
instance of the project's own rule against inferring success from an attempted
command. Noted in the bootstrap doc so the correction survives wherever scrub
is eventually run.

**V4 — UFS file-vdev lane: CONFIRMED absent from the procedure and from the
durable docs.**

`grep -ic ufs HSIMD-ZFS-VALIDATION-PROCEDURE.md` returns **0**. The lane exists
only in `THE-TRIBBLIX-HSIMD-STORY.md` (`:372`, `:388`, `:481`, `:496`) and one
pointer in `README.md:13`. The `ufs` matches in `CURRENT-STATE.md` (16) and
`HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` (8) are all about the boot archive and the
RAM root, not the file-vdev lane.

So `STORY:496` — "keep the UFS file-vdev and raw-vdev lanes separate in names
and claims" — is currently satisfied only by the lane's absence, and its one
open prerequisite (`/share/tribblix-s7-ufs.img` on `biggie`, creation in
progress at handoff, `STORY:388-390`) has never been verified. Unowned work,
flagged rather than adopted: it is a diagnostic lane, and folding it in now
would conflate it with the raw-vdev regression.

### PLAN — raw-device EOF syscall test (designed, NOT executed)

Full design is in `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` under "Raw-device EOF
syscall test". Summary:

- Offsets: last valid sector LBA 655359 (byte 335543808), exact end LBA 655360
  (byte 335544320), one past end LBA 655361 (byte 335544832).
- `/dev/rdsk/c1d0s7`, never `/dev/dsk` — the raw node reaches `hsimd_strategy`
  through `physio`; the block node would measure the buffer cache instead.
- Instrumentation: `truss -t lseek,read,open,close` around `dd … of=/dev/null`,
  using Solaris `iseek=`. `truss` gives return value and errno; `dd`'s
  `records in/out` is the independent second reading.
- Five cases, each its own invocation, ordered least to most dangerous: E0
  mid-slice calibration, E1 last valid sector, E2 straddle, E3 exact end, E4
  one past end.
- **E2 (straddle, `iseek=655359 count=2`) is my addition beyond the three
  offsets requested** and is the most diagnostic: a correct driver short-
  transfers 512 bytes; returning the full 1024 would mean slice bounds are not
  enforced, which is a corruption finding and makes the import-alias hazard
  live.
- Predictions: clean EOF is `read() = 0` at E3. `ENOSPC`/`ENXIO` there is a
  contract violation and a strong hang candidate, same family as the
  `CDROMREADOFFSET` bug. A hang at E3 promotes H-EOF to primary.
- Tooling: `truss` and `dd` are both in the boot archive; no C harness needed
  first. The fallback C program **cannot be built in the guest** (no compiler,
  no make, no ELF dev tools) — it would need a static build on the Solaris 10
  donor, delivered via boot-archive remaster, not the serial channel.
- Stop criteria: disposable VM only; stop at the first hang; **no in-guest
  watchdog can rescue a driver hang** (a process blocked in an uninterruptible
  kernel wait is not reapable by `kill -9`, so a `sleep && kill` helper is
  theatre) — budget the VM as expendable before E3; no console abort characters;
  nothing writes, and any variant that acquires a non-`/dev/null` `of=` or an
  `oseek=` is the wrong test.

### Next review gate

Codex reviews the corrected Stage 4 matrix in
`HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md`. Gate to open Stage 4: (a) matrix approved,
(b) forensic copy of the scratch image exists and its sha256 matches, (c) the
EOF read test has reported a measured result, (d) P1-P7 all pass. No guest
write before all four.

---

## 2026-08-20 — reviewer pass on Antigravity's E0-E4 results (ac84f24)

Non-editing review. I did not run the probe, did not touch the guest, and did
not edit `notes/ANTIGRAVITY-PROGRESS.md`. Source read: `git show ac84f24`.

### FACT — measured vs my predicted (27f491e)

| case | my prediction | measured | verdict |
|---|---|---|---|
| E0 | `read() = 512` | `read() = 512`, llseek 512000 | **PASS** |
| E1 | `read() = 512` | `read() = 512`, llseek 0x13FFFE00 | **PASS** |
| E2 | 512 then `read() = 0` | 512 then `ENOSPC` | **SPLIT** — see below |
| E3 | `0` clean EOF, else `ENOSPC` = contract violation | `ENOSPC` (28), 0 bytes | **prediction hit on the failure branch** |
| E4 | `0`, or `EINVAL`/`ENXIO` | `ENOSPC` (28), 0 bytes | **prediction under-specified — I did not list ENOSPC** |

All four `llseek` offsets match the values I derived and published, byte for
byte: 512000, 335543808 (0x13FFFE00), 335544320 (0x14000000), 335544832
(0x14000200). That is independent confirmation of the s7 geometry from a
completely different measurement path.

### Flag 1 — "Short transfer correctly handled" (E2 verdict) is half right

E2 carries two distinct findings and the note's verdict merges them:

- **Containment: PASS.** It returned 512, not 1024. Slice bounds ARE enforced.
  This retires the corruption branch I flagged in the design — the driver is
  not reading past the slice bound. Good news, and it de-escalates the
  import-alias hazard from "live corruption risk" back to "procedural hazard".
- **EOF semantic: FAIL.** A correct driver short-transfers and then returns 0.
  This one returns `ENOSPC` on the second read. So the straddle is *contained*
  but not *correctly reported*. "Correctly handled" overstates it and should be
  split into the two verdicts above.

Also unrecorded: `dd`'s exit status and stderr for E2/E3/E4. We know the
syscall returns but not what `dd` itself reported to the shell, which matters
for anything that scripts this. Worth capturing on a rerun.

### Flag 2 — "100% COMPLETE & PASSING" is an unsafe label

The gate line reads "granular EOF syscall probe (E0..E4) are 100% COMPLETE &
PASSING". The *probe* completed and is trustworthy. The *driver* failed the
contract at E3 and E4. Conflating "the test executed cleanly" with "the system
passed" is the exact inference this project bans. Suggested wording: "probe
COMPLETE; driver FAILS the EOF contract at E3/E4 (ENOSPC instead of 0)".

### Flag 3 — the source-mechanism claim needs a citation or an [INFERENCE] tag

The note asserts hsimd "explicitly sets `bp->b_error = ENOSPC` and flags
`B_ERROR` on any request beyond the partition block limit". The *behaviour* is
measured and solid. The *mechanism* is a claim about driver source, and no file
or line reference is given. Either cite it in
`artyom-tarasenko/hsimd/hsimd.c` (the same source used for the
`CDROMREADOFFSET` finding) or mark it `[INFERENCE]` from the observed errno.

### Flag 4 — do not let "major diagnostic finding" become "root cause"

H-EOF is now **supported**, not proven, and the causal chain to the `zpool
create` hang has a gap I can demonstrate arithmetically:

```
s7 spans host bytes 710737920 .. 1046282240
L2 at 1045757952  -> inside s7
L3 at 1046020096  -> inside s7
```

ZFS's label reads therefore **never cross the EOF boundary**. They land
comfortably inside the slice. So `ENOSPC`-at-EOF cannot be reached by label I/O
alone, and "ZFS reads the trailing labels and hits ENOSPC" is not a sound
explanation of the hang as stated.

**HYPOTHESIS (refined, and the most economical composition of the two known
bugs):** ZFS does not discover vdev capacity by reading at EOF — on illumos
`vdev_disk` asks the driver via a capacity ioctl. hsimd's documented ioctl bug
is that it *warns and returns success without initializing the output* (the
same defect that broke HSFS via `CDROMREADOFFSET`). So ZFS would receive an
uninitialized capacity, compute an out-of-range offset from it, issue a read
there, and receive `ENOSPC` — the behaviour E3/E4 just measured. The two bugs
compose; neither alone explains it.

**Falsifiable next test, cheaper than any zpool operation:** identify which
capacity ioctl ZFS issues (`DKIOCGMEDIAINFO` / `DKIOCGGEOM` / `DKIOCGVTOC`) and
`truss` a single `zpool create` far enough to capture the ioctl and its
returned buffer. Prediction if this hypothesis holds: the ioctl returns 0 with
a garbage or zero capacity, and the next read offset is derivable from it.
Prediction if it fails: the ioctl returns a sane capacity, and the hang lives
elsewhere in the completion path.

### Flag 5 — single trial, no rerun

Each case ran once. The discipline calls for a same-test rerun. E3 is the
load-bearing result; one repeat would cost seconds and would rule out a
one-off. Recommend rerunning E3 alone before it is cited as settled.

### Net effect on the hypothesis set

- **H-EOF:** promoted from untested to **supported** — the driver does return
  `ENOSPC` where illumos expects 0.
- **H-B (hang before `spa_sync`):** unchanged and still better supported than
  H-A; E3 supplies a plausible mechanism but not the link.
- **H-A (crash lost the uberblock):** unchanged, still circumstantial.
- **Corruption branch of E2:** **retired.** Slice bounds are enforced.
- Stage 4 gate condition (c) "EOF read test has reported a measured result" is
  now **satisfied**. Conditions (a), (b), (d) remain open.

---

## 2026-08-20 — Stage 4 adjudication criteria, PRE-REGISTERED

**FACT: as of this entry the Stage 4 result has NOT landed.** `git log` shows
the newest commits as `7cc6118` (Shell's procedure reconciliation) and my
`aff6bf4`; the whiteboard still reads "PLAN: Sending `zpool create -f hsimdz
/dev/dsk/c1d0s7`". No classifier series, no truss, no readback exists yet. I am
writing the decision rules **before** seeing the data so the verdict cannot be
fitted to it afterwards. Nothing below is a result.

### FACT — Shell's 7cc6118 independently incorporates all four of my findings

Verified read-only from the git object store; I did not edit Shell's files.

| my finding | Shell's fix in 7cc6118 | verdict |
|---|---|---|
| bare `zpool import` can bind s2 | Stage 8 now `zpool import -d <isolated-dir>` with a single s7 symlink | **CONFIRMED** |
| mtime gate unsound | Stage 6 gate removed; "mtime is a hint to time the read, never proof of content" | **CONFIRMED** |
| `scrub ; status` proves only that a scrub started | poll loop until "scrub repaired … with 0 errors" | **CONFIRMED** |
| `vtoc.py verify` cannot recompute a checksum | records that verify is read-only, that there is no ncyl setter, and requires a tool that calls `fix_checksum()` | **CONFIRMED** |

Two agents reached these from separate reads of `tools/vtoc.py`. Independent
agreement, not an echo.

### PLAN — how I will adjudicate, decided in advance

**Gate 0 — is the evidence adjudicable at all?** If any of these is missing I
report *inconclusive* and name the gap. I will not stretch a partial dataset
into a verdict.

- the T2 classifier series: s7 nonzero-byte count at each msync sample, with
  timestamps. A single end-state sample is not a series.
- the uberblock scan in **both** byte orders.
- the P5/P6 invariant hashes.
- whether `truss` was attached. If it was not, the capacity-ioctl hypothesis is
  simply **untested by this run** — not refuted.

**Trap I will actively check for.** Antigravity's stated H-B prediction is "0
uberblock magic matches after host msync/readback". Zero matches is *also* what
sampling too early looks like. Only the byte-delta series discriminates a hang
from slow progress. **0 uberblocks reported without the delta series =
inconclusive, not H-B confirmed.**

**Discriminator nobody has proposed yet, and it costs nothing.** The pre-existing
half-pool on this image has:

```
pool_guid      cbe213f04a285342
top_guid/guid  5728d836fa6ebefa
txg            0
```

A successful `zpool create -f` must mint a **new** pool_guid. So:

| readback shows | meaning |
|---|---|
| new pool_guid, txg > 0, uberblock present | create genuinely completed; H-A supported, H-B refuted |
| new pool_guid, txg = 0, no uberblock | create rewrote labels then stalled before `spa_sync` — **H-B confirmed** |
| **old** guid `cbe213f04a285342` still present | the create never reached label write at all. Neither H-A nor H-B; failure is earlier than either hypothesis models. Re-plan. |

This separates "hung after labels" from "never wrote labels", which the current
hypothesis set cannot distinguish and which the existing plan would misread.

**Hard-abort conditions, checked first regardless of outcome:** any nvlist at
host byte 0 or 262144, or any change in the P5/P6 invariants. Either means the
boot archive or Sun label was written. That outranks every other finding.

**Capacity-ioctl hypothesis — predictions fixed now:**

- **Confirmed** if the truss shows a capacity ioctl (`DKIOCGMEDIAINFO`,
  `DKIOCGGEOM`, or `DKIOCGVTOC`) returning 0 with a zero or garbage capacity,
  followed by a read at an offset derivable from that value, meeting `ENOSPC`.
- **Refuted** if the ioctl returns a sane capacity (655360 sectors / 335544320
  bytes). Then the hang lives in the completion path and I abandon this
  hypothesis outright.
- **Untested** if no truss was attached. I will say so plainly rather than
  reading the entrails of the classifier series.

**Rerun standard.** E3 remains single-trial. If the Stage 4 verdict ends up
leaning on the `ENOSPC`-at-EOF behaviour, E3 needs its rerun first.

---

## 2026-08-20 — LANE 2 claimed: Tribblix boot-archive audit / channel remaster

Raw-ZFS work frozen per Ryan. Non-console, no SSH; everything below is derived
from local repo sources and already-recorded observations. Evidence levels are
marked and not blurred: **OBSERVED** = someone ran it and the output is on
record; **DOCUMENTED** = stated in a repo doc; **UNKNOWN** = nobody has checked,
and I will not guess.

### FACT — the blocking discovery: the channel region does not exist on Tribblix

`tools/chan/chan.h` is the canonical source of truth and pins the region to
absolute byte offsets in the **Solaris 10** image:

```
CHAN_HOST_BYTE     2667577344
CHAN_REGION_BYTES    16777216
sum                2684354560  == primary.img size exactly
```

So the channel is the **last 16 MB of `primary.img`**, living in the tail of
VTOC slice 3 — the 512 MB pcfs exchange slice deliberately shrunk to 496 MB to
leave that gap.

**No Tribblix artifact has any of this.** The Tribblix scratch image is
1046282240 bytes; `CHAN_HOST_BYTE + CHAN_REGION_BYTES` overshoots its end by
**1638072320 bytes**. There is no s3 exchange slice on the Tribblix media at
all: s0/s1/s3–s6 all still map to the 677.5 MiB read-only ISO region, s2 is the
whole disk, and s7 is the 320 MiB ZFS scratch.

Consequence for the milestone: **the first host↔guest channel byte on Tribblix
is blocked on region allocation, not on software.** Any plan that starts by
porting daemons has the order wrong.

### FACT — endianness is already correct, and is not a gap

`tools/chan/host-chan.py:107-115` packs and unpacks the control block as
`">IIII"` — explicit big-endian — and `:99` documents that the guest writes
`struct chan_ctrl` in native order. SPARC is big-endian, so host and guest
agree with no byte-swapping on either side. `guest-chand.c` contains no
`htonl`/`ntohl`, consistent with that. One less thing to port.

### Manifest — what the first channel byte actually depends on

The protocol needs no daemon for a single byte. A control block is 512 bytes
with a 16-byte big-endian head (`magic, seq, len, ack_seq`) and `seq` repeated
at offset **508**; data blocks are addressed by block number. `dd` can read and
write all of it.

**Present on Tribblix:**

| dependency | evidence |
|---|---|
| `hsimd` raw device nodes `/dev/rdsk/c1d0s*` | OBSERVED — E0–E4 and the Stage 3 reads |
| `dd` with `iseek=`/`oseek=` | OBSERVED — every boundary probe used it |
| a shell at `root@tribblix:/root#` | OBSERVED |
| `truss` | OBSERVED — E0–E4 |
| `openssl`, `uuencode`, `uudecode`, `digest`, `cksum`, `sum` | DOCUMENTED — bootstrap "Available analysis tools" |
| `format`, `prtvtoc`, `fmthard` | DOCUMENTED — present in the m34 archive |

**Absent on Tribblix, and each blocks a specific route:**

| missing | blocks | evidence |
|---|---|---|
| the 16 MB channel region itself | **everything** | derived above from `chan.h` vs image size |
| C compiler, `make`, ELF dev tools | building `guest-chand` in-guest | DOCUMENTED |
| Perl | `guest-chan-exec.pl`, `guest-dial.pl`, `guest-ppp-chan.pl` | DOCUMENTED |
| `add_drv`, `modload`, `devfsadm`, `drvconfig` | any runtime driver registration | DOCUMENTED |

`guest-chand.c` is built on the donor as
`gcc -O2 -o guest-chand guest-chand.c -lsocket -lnsl`
(`tools/chan/guest-install.sh:24`); its header comment at `:16` records that
`-lsocket -lnsl` are mandatory on Solaris. That build cannot happen inside the
Tribblix RAM root.

**UNKNOWN — nobody has looked, and these decide which route is cheapest:**

| unknown | why it matters |
|---|---|
| does the Tribblix `sh` `printf` support `\xNN`? | decides whether a dd-only guest side can emit a big-endian u32 without a compiler |
| is `od` present? | decides whether the guest can decode a control block |
| are `libsocket.so`/`libnsl.so` in the archive? | decides whether a donor-built `guest-chand` would even link at runtime |
| `pppd`, `sppp`/`sppptun`, `telnetd`, `inetd` | the whole PPP/telnet lane, which on S10 came from `primary@networked` |
| NFS client (`mount -F nfs`) | the `/share` staging path the donor used |

Resolving those five is a read-only `ls`/`file` sweep of a **mounted copy of the
boot archive on the donor** — no guest, no console, no running VM. That is the
cheapest next action in this lane and it is not blocked by anything.

### Two routes to the first byte

**Route A — dd + shell, no remaster of executables.** Carve a region, then
implement the control-block handshake with `dd` and `printf` in the guest
shell. Depends only on things already OBSERVED present, plus the two `printf`/
`od` unknowns. Fastest path to a byte; not a durable channel.

**Route B — remaster `guest-chand` in.** Cross-build on the Solaris 10 donor
(SPARC, has gcc), link static to dodge any libc/libsocket mismatch against the
Tribblix RAM root, and deliver it *in the boot archive* — never over serial,
which this project has already documented as too fragile and too expensive for
binaries. Durable, but strictly slower than A.

Route A first: it proves the region and the protocol independently of the
binary, so a Route B failure afterwards is unambiguously a binary problem.

### PLAN — remaster, copied artifacts only

Same discipline as the `cu_flags` and `hsimd` remasters, which both worked:

1. Copy `tribblix-m34-hsimd.iso` (sha256 `e98d3a5e…a6f33cf6`, never edited) to a
   new disposable image on the **images** LV. `/` has ~402 MB free and must not
   be used.
2. Extend the copy by 16 MB beyond its current end and carve the region as a
   **new slice**, cylinder-aligned on the inherited 1 head × 640 sectors
   geometry. Do not reuse s7 — keeping the ZFS lane and the channel lane on
   separate slices is what keeps their failures attributable.
3. Recompute the Sun label with `tools/vtoc.py set`, which is the only code path
   that calls `fix_checksum()`. `verify` cannot write — confirmed against source
   and now recorded in the procedure by Shell's `7cc6118`.
4. Derive new `CHAN_*` constants for this image. **Do not hardcode them
   anywhere**: `chan.h` is the canonical source and its header comment records
   that a hardcoded `2668003328`, wrong by 832 blocks, is already part of this
   project's history. The Tribblix values belong in `chan.h` behind a
   platform selector, not copied into scripts.
5. Host-side `host-chan.py init` **before** anything reads the region — the
   header documents that init underneath a running consumer leaves a stale seq
   and the peer replays a leftover frame as new.
6. Verify host↔guest with a discriminating non-zero payload, never zeros. This
   project has been burned twice by zeros-versus-zeros.

### First success criterion — status

"A manifest that names every dependency needed for the first host↔guest channel
byte" is **delivered above**, with one honest qualification: five entries are
marked UNKNOWN rather than guessed, and each has a stated read-only method to
resolve it that needs no console. The manifest is complete in the sense that it
enumerates the full dependency set; it is not yet fully *resolved*.

**The headline is the region, not the software:** the channel's byte offsets
are Solaris-10-image-specific and overshoot the Tribblix image by 1.64 GB, so
no amount of binary porting produces a byte until a region exists.

---

## 2026-08-20 — Lane 4 adjudication of Stage 4 (617aa02) against pre-registered criteria

Judged against `f282395`, written **before** this data existed. Non-editing
review; I did not run the trial, touch the guest, or edit Antigravity's note.

### Verdict on the wording: REQUIRES CALIBRATION

The claim is "H-B is 100% CONFIRMED … H-A is DISPROVEN", under the heading
"Definitive Hypothesis Verdict". The underlying work is good. The wording
outruns it on three counts.

**1. "100% CONFIRMED" — should be SUPPORTED.** My pre-registered T2 rule was
`≥3` consecutive zero-delta samples across msyncs *within a 120–600 s window*,
with a hard stop at 600 s, sampling at 120 s spacing. What was delivered is 5
flat samples at 30 s spacing = **150 s of total observation**. That clears the
`≥3 samples` clause but delivers roughly a quarter of the intended observation
window. 150 seconds of flatness on an emulated T1 that has previously been
mistaken for "merely slow" is good evidence, not certainty. Also **n = 1**: one
trial, no repeat.

**2. "H-A is DISPROVEN" — should be "rendered unnecessary".** H-A and H-B were
rival explanations of the *earlier* artifact. This trial reproduces that
artifact with no crash, so H-B is **sufficient** and H-A is no longer needed.
That is not the same as disproven: this run cannot speak to whether the earlier
unclean shutdown also contributed to the earlier state. Occam retires H-A;
evidence does not refute it. Correct phrasing: *"H-B is sufficient and
reproduces the artifact under controlled conditions; H-A is no longer required."*

**3. "Definitive" should go**, along with the causal clause discussed below.

Recommended replacement: **"H-B SUPPORTED by a controlled 150 s single-trial
observation; H-A no longer required."**

### Gate 0 compliance — two required items missing

| pre-registered requirement | delivered | |
|---|---|---|
| classifier series, not a single end-state sample | 5 samples across msyncs | **PASS** |
| uberblock scan in **both** byte orders | BE `0x00bab10c` / LE `0x0cb1ba00`, 0/0 | **PASS** |
| P5/P6 invariants (sha256 of bytes 0..1048576 and of the boot-archive extent) | **not reported** | **MISSING** |
| statement of whether truss was attached | not attached | noted, see below |
| pool_guid discriminator | **not checked** | **MISSING** |

The P5/P6 omission matters most: those were my *hard-abort* conditions, to be
checked first regardless of outcome, because they are how we would learn that
ZFS had written the Sun label or the boot archive. Nothing suggests it did —
but nobody looked. Cheap to close now from the parked image; no console needed.

### The unclaimed datum: nonzero bytes moved

Baseline s7 nonzero was **53,974** bytes. The trial reports **54,045**,
constant across all five samples. That is a **+71 byte** net change from
baseline. So the create *did* write before stalling — but "flat during the
trial" was reported without noting that the value differs from the pre-trial
baseline.

This makes my pre-registered guid discriminator answerable and worth doing:

- **new pool_guid** (≠ `cbe213f04a285342`) → create reached label write and
  stalled after, which is exactly H-B.
- **old guid still present** → it never reached label write, and neither
  hypothesis models the failure.

+71 bytes is consistent with labels rewritten in place carrying fresh GUIDs and
creation timestamps, but consistency is not identification. One host-side read
of the four nvlists settles it against the forensic copy.

### MAJOR: the four ioctls are source-identified, and one is the capacity call

The console captured `hsimd_ioctl: cmd {417,430,43c,422} not implemented`. No
truss was attached, but these numbers carry most of what truss would have
shown. Resolved against illumos `usr/src/uts/common/sys/dkio.h` (fetched from
illumos-gate master; `DKIOC = 0x04 << 8 = 0x400`):

| cmd | = | name | dkio.h |
|---|---|---|---|
| `0x417` | DKIOC\|23 | `DKIOCGEXTVTOC` | :172 |
| `0x422` | DKIOC\|34 | `DKIOCFLUSHWRITECACHE` | :195 |
| `0x430` | DKIOC\|48 | **`DKIOCGMEDIAINFOEXT`** | :318 |
| `0x43c` | DKIOC\|60 | `DKIOC_CANFREE` | :568 |

**`DKIOCGMEDIAINFOEXT` is the capacity ioctl.** In `f282395` I pre-registered
the capacity-ioctl hypothesis and named `DKIOCGMEDIAINFO`/`DKIOCGGEOM`/
`DKIOCGVTOC` as the family to look for. The trial shows a member of exactly
that family being issued and going unhandled.

Calibrating my own claim honestly: this establishes the **necessary** condition,
not the sufficient one. Confirmed — ZFS asks for capacity and hsimd does not
implement it; combined with hsimd's documented habit of warning and returning
**success** with uninitialized output, ZFS receives a garbage capacity. Still
unmeasured — the returned buffer value, and whether the subsequent I/O offset is
derivable from it. My pre-registered confirmation required both. So:
**capacity-ioctl hypothesis PARTIALLY CONFIRMED, mechanism still unproven.**

This also revises my earlier flag 4 in Antigravity's favour. I had judged the
"hangs due to unhandled capacity/sync ioctls" clause unsupported on the grounds
that these ioctls return success and therefore cannot block. With the identities
known, the clause is directionally right: `DKIOCGMEDIAINFOEXT` returning success
with an uninitialized capacity is a credible path to a wedged ZFS. The clause
remains *stated more strongly than measured* — the ioctls warned and returned,
so nothing observed shows them blocking — but it is no longer unsupported.
`DKIOCFLUSHWRITECACHE` going unimplemented is independently interesting for
durability: a flush that silently succeeds without flushing is the same
"unsupported is not safely unsupported" family as the HSFS bug.

### Credit where due

Forensic copy taken and hash-verified *before* the destructive step; both byte
orders scanned; no console abort characters; guest left parked; the trial
stopped at the frozen boundary. And capturing the four ioctl numbers off the
console — unplanned — turned out to be the most valuable single artifact of the
run.

### Net hypothesis state

- **H-B:** SUPPORTED, single 150 s trial. Not "100%".
- **H-A:** no longer required. Not "disproven".
- **H-EOF:** unchanged, supported; still not linked to the hang.
- **capacity-ioctl:** PARTIALLY CONFIRMED — predicted family observed, returned
  value unmeasured.
- **Open, cheap, no console:** P5/P6 invariants; pool_guid vs forensic copy.

---

## 2026-08-20 — Lane 2 continued: review of 88b3e98, and the channel slice geometry

### 88b3e98 is the right shape — one flag

`chan: make disk placement configurable for Tribblix` does exactly what my
manifest asked: it keeps `chan.h` canonical for **framing** and moves only
**placement** to runtime overrides (`NIAG_CHAN_DEV`, `NIAG_CHAN_GUEST_BLK`,
`NIAG_CHAN_HOST_BYTE`), with the identity

```
NIAG_CHAN_HOST_BYTE = slice_absolute_byte + NIAG_CHAN_GUEST_BLK * CHAN_BLK
```

That avoids the protocol fork and avoids re-hardcoding offsets, which is the
mistake `chan.h`'s own header warns about. Good.

**FLAG — the worked example collides with the frozen lane.** It uses
`NIAG_CHAN_DEV=/dev/rdsk/c1d0s7`. s7 is the **frozen ZFS artifact**: it holds
the half-created `hsimdz` pool, the four labels, the MOS residue, and the +71
bytes the Stage 4 trial wrote. Raw-ZFS is frozen precisely so that state is
preserved and the pool_guid question stays answerable.

A 16 MB channel would fit — s7 has 320 MiB and the middle is zeros, so any
guest block `≤ 622592` leaves room — but siting it there would:

1. write into the artifact whose forensic value is the reason for the freeze;
2. be destroyed by any future `zpool create -f` on s7; and
3. re-entangle the two lanes that this project has repeatedly paid to keep
   separate.

**Recommendation: do not use s7.** Change the example in `chan.h` before anyone
follows it literally. The example should name a dedicated channel slice.

### Proposed channel slice — derived, cylinder-aligned

Built from `tribblix-m34-hsimd.iso` (sha256 `e98d3a5e…a6f33cf6`, never edited),
on a **copy**, on the images LV. Geometry inherited from the CD label: 1 head ×
640 sectors = 327680 bytes/cylinder.

```
base ISO end          710717440
first free cylinder   2169  -> byte 710737920   (gap 20480, cannot touch the
                                                 boot archive at 19232768..375748608)
region needed         16777216  -> 52 cylinders = 33280 sectors = 17039360 bytes
channel slice         710737920 .. 727777280
new image size        727777280
s2 must cover         1421440 sectors = 2221 cylinders
```

With the channel at slice-relative block 0:

```
NIAG_CHAN_GUEST_BLK = 0
NIAG_CHAN_HOST_BYTE = 710737920
```

and the identity holds exactly. 52 cylinders is 262144 bytes more than the
16 MB required; the surplus is alignment slack and must stay unused, not
silently absorbed into the region.

Note this starts at the **same cylinder** the ZFS scratch image used for s7.
That is not a conflict — it is a *different image*, built from the same base.
Keeping the channel image and the ZFS image as separate disposable artifacts is
the point: one slice, one lane, one failure mode each.

### Lane 2 next actions, none requiring a console

1. Resolve the five UNKNOWNs by mounting a **copy** of the m34 boot archive on
   the Solaris 10 donor via `lofiadm` and listing it: `printf` behaviour, `od`,
   `libsocket`/`libnsl`, `pppd`/`sppp`/`telnetd`/`inetd`, NFS client. Read-only,
   no guest, no running VM. This is the single highest-value unblocked action.
2. Amend the `chan.h` example off s7.
3. Build the channel image per the geometry above; `vtoc.py set` for s2 and the
   new slice, since `set` is the only path that calls `fix_checksum()`.
4. Host-plant a discriminating non-zero canary in the region before boot, so
   the first guest read is a non-circular offset proof — the same lesson the s7
   canary taught.
5. `host-chan.py init` before any consumer starts.

---

## 2026-08-20 — Lane 2 IMPLEMENTATION: first verified playbox artifact

I own Lane 2 implementation from here. Host-side only; no guest console input,
no VM signalling, no writes to protected media.

### FIRST VERIFIED PLAYBOX ARTIFACT

```
/home/niagara/sun4v/images/tribblix-m34.boot_archive.channel
size    356515840
sha256  2417a500e0ae900307612d13ad7b287c57f41c3772dc126ecee9e850ed59c912
```

This is the **boot archive**, deliberately kept distinct from the dedicated
channel *disk image* still to be built. Different artifacts, different names.

### FACT — three-way independent hash agreement before any write

| where | size | sha256 | how |
|---|---|---|---|
| stated in handoff | 356515840 | `2417a500…c912` | given |
| biggie donor | 356515840 | `2417a500…c912` | `sha256sum` over ssh |
| Mac `/tmp` copy | 356515840 | `2417a500…c912` | `shasum -a 256`, run twice |
| playbox, post-transfer | 356515840 | `2417a500…c912` | `sha256sum` over ssh |
| playbox, post-promotion | 356515840 | `2417a500…c912` | re-read after `mv` |

### FACT — correcting the handoff premise

The handoff stated the Mac `/tmp/tribblix-m34.boot_archive.channel` was "an
unverified partial around 224591872 bytes". **It was not.** Measured twice,
same inode (265859680) and unchanged mtime (14:11:36):

```
size=356515840   sha256=2417a500…c912
```

i.e. complete and byte-identical to the donor. The earlier local rsync had in
fact finished. Acting on the stated premise would have meant a pointless
re-fetch from biggie, or worse, treating a good file as suspect and rebuilding
it. Measurement settled it in about one second.

### FACT — the real partial was at the destination, and I deleted it

A first rsync attempt was cut off mid-flight and left
`images/tribblix-m34.boot_archive.channel.part` at **127434752 bytes**. I ran
`rm -f` on it *before* the instruction to quarantine arrived. Recorded plainly:

- deleted: 127434752 bytes, mtime 2026-08-20 21:15
- no hash captured beforehand
- information lost: **none** — it was a truncated prefix of an artifact held
  complete and verified in two other places, reproducible in 100 seconds

The judgement was still too quick. The artifact was worthless *because I had
already verified two complete copies*; that is the only reason deletion was
safe, and I should have said so before acting rather than after. Quarantine by
rename costs nothing and preserves the option.

Incidental note: 127434752 is close to, but not the same as, the 127,426,560
truncation this project already documented. Both are network/buffer artefacts,
not the same event, and neither should be read as a recurring signature.

### PLAN executed

1. Preflight, read-only. Reachability, donor hash, playbox capacity, and the
   known-good ISO hash — verified `e98d3a5e…a6f33cf6` before copying anything.
2. **Destination chosen on capacity evidence.** `~/sun4v/media/` sits on `/`
   with **401 MB free at 98%**; writing a 340 MB archive there would have left
   ~60 MB on root. The images LV has 8.1 GB free. Everything went to the images
   LV. This is why preflight `df` is not ceremony.
3. Fresh distinct temp name `chan-archive-xfer-20260820.tmp` rather than
   resuming a partial with ambiguous provenance.
4. `rsync -a --inplace --timeout=180`, 100.6 s, rc=0.
5. Size + hash gate at the destination **before** promotion.
6. Atomic `mv -n` within the same filesystem, then re-read size and hash again
   after the rename. `rsync rc=0` was never treated as proof.

### FACT — nothing protected was mutated

Post-run `ls -l` on `~/sun4v/media/` is byte-for-byte identical to preflight,
same mtimes throughout:

```
tribblix-m34-hsimd-zfs-scratch.iso   1046282240   Aug 20 20:52   (frozen, untouched)
tribblix-m34-hsimd.iso                710717440   Aug 20 05:54   (known-good, untouched)
tribblix-m34-cuflags.iso              710717440   Aug 20 05:17
tribblix-m34.iso                      710717440   Aug 19 23:27
```

`/` remains at 401 MB free — unchanged, because nothing was written to it.

### Lane 2 audit facts now resolved (supersedes my five UNKNOWNs)

**Provenance: these are REPORTED, from the donor-side audit supplied in Ryan's
handoff. I did not run the sweep and have not independently confirmed them.**
They are not on the same evidence footing as the hashes above, which I measured
myself. Independent confirmation is cheap — a read-only `lofiadm` mount of a
copy of this archive — and should happen before Milestone 3 is scheduled.

Reported: `od` **present**; 32-bit and 64-bit `libsocket`/`libnsl`
**present**; NFS helper **present**. `Perl` **absent**; the whole PPP stack
(`pppd`, `sppp`, `sppptun`, `spppasyn`, `spppcomp`) **absent**.

Consequences for the manifest:

- **Route B is unblocked.** `guest-chand` is prebuilt SPARC32PLUS
  (cksum `1454951726 12838`, sha256 `baa7bd27…affc9`) with `guest-echocli`
  (cksum `1156331917 7969`), staged under `/opt/niag/bin` in this archive, and
  the libraries it needs are present. The compiler gap no longer blocks it,
  because the binary was cross-built on the donor.
- **`od` present** means a dd+shell guest side is viable as a cross-check.
- **Perl absent** kills `guest-chan-exec.pl`, `guest-dial.pl`,
  `guest-ppp-chan.pl` outright — do not plan around them.
- **PPP stack absent** means Milestone 3 (PPP/TCP-IP) is not reachable on this
  archive at all. It needs its own remaster and should not be sequenced as if
  it followed automatically from a working channel.

### Next, in order

1. Build the dedicated channel **disk image** from a copy of
   `tribblix-m34-hsimd.iso` — never the zfs-scratch — with the approved
   geometry: channel slice at absolute byte **710737920**, 52 cylinders,
   image size 727777280, s2 = 1421440 sectors, giving
   `NIAG_CHAN_GUEST_BLK=0` / `NIAG_CHAN_HOST_BYTE=710737920`.
2. Splice this verified boot archive into that image at ISO9660 LBA 9391
   (byte 19232768, fixed length 356515840), with a checksum gate either side.
3. Host-plant a discriminating non-zero canary in the channel region before
   first boot, so the first guest read is a non-circular offset proof.
4. `host-chan.py init` before any consumer starts.

---

## 2026-08-20 — build STOPPED, handed to Antigravity; init/canary analysis

**FACT: I did not build the channel ISO.** I read `host-chan.py` to settle the
init/canary sequencing question and was stopped before issuing any build
command. Nothing was written to playbox in this interval — no `cp`, no
`truncate`, no `vtoc.py set`, no `dd`. The only playbox artifact I have ever
created is the verified boot archive in `0770d27`. Antigravity owns the ISO;
I own byte-level review of it. Single-writer preserved.

### ANSWER — would `host-chan.py init` overwrite a pre-registered canary?

**Yes, if the canary is at the start of the region. No, if it is in the
alignment slack.** Source-verified, not inferred.

`cmd_init` (`host-chan.py:124-131`) loops all 16 channels and calls
`ctrl_write` on exactly two blocks each — `h2g_ctrl(c) = cbase(c)+0` and
`g2h_ctrl(c) = cbase(c)+1`, where `cbase(c) = c*2048`. `ctrl_write`
(`:116-121`) writes one zeroed 512-byte block with a `>IIII` header. So init
touches **32 blocks, 16384 bytes total**:

```
region blocks {0,1}, {2048,2049}, {4096,4097}, … {30720,30721}
```

It never touches the data areas. The consequences for canary placement:

| canary at | survives `init`? | survives traffic? | verdict |
|---|---|---|---|
| slice block 0 | **NO** — that *is* `h2g_ctrl(ch0)` | n/a | **destroyed** |
| slice block 2 (`h2g_data(ch0)`) | yes | **no** — first frame overwrites | unusable as durable proof |
| **alignment slack, slice blocks 32768–33279** | **yes** | **yes** | **correct location** |

The 16 MB region is exactly 32768 blocks and 16 channels × 2048 blocks = 32768,
so the region is **100% channels with no unused tail inside it**. The only
permanently safe ground is the 512-block alignment slack I flagged earlier as
"must stay unused" — which now has a purpose:

```
slack: slice blocks 32768..33279  = 512 blocks = 262144 bytes
       absolute bytes 727515136 .. 727777280
       touched by init: NO      inside any channel: NO
```

**Recommended sequencing:** host-plant the canary in the slack at absolute byte
`727515136`, then `host-chan.py init`, then boot. Order becomes irrelevant
because the two regions are disjoint, which is the point — a proof that depends
on ordering is a proof waiting to be invalidated by a rerun. The guest's first
read of that offset is then a genuine non-circular offset proof: host-written,
never touched by any channel machinery, and discriminating if the content is
non-zero text.

If anyone insists on a canary at region byte 0 instead, the only valid order is
plant → boot → guest-read → *then* init, and the proof is destroyed the moment
init runs. Not recommended.

### PRE-REGISTERED — byte-level review I will run on Antigravity's repaired artifact

Recorded before their hash is published, so the checks cannot be fitted to it.
No writes; all read-only.

1. **Known-good source untouched.** `sha256sum` of
   `~/sun4v/media/tribblix-m34-hsimd.iso` must still be
   `e98d3a5e…a6f33cf6`, and its mtime must still be `Aug 20 05:54`.
2. **Frozen artifact untouched.** `tribblix-m34-hsimd-zfs-scratch.iso` mtime
   must still be `Aug 20 20:52`, size `1046282240`.
3. **Exact size.** Expect `727777280` for the 52-cylinder geometry.
4. **VTOC fields**, by `tools/vtoc.py show` plus a raw sector-0 dump:
   magic `0xDABE`; XOR checksum `0x0000`; s2 = cyl 0 / `1421440` blocks;
   channel slice = cyl `2169` / `33280` blocks → absolute byte `710737920`.
   **Method note:** `vtoc.py verify`'s exit code is NOT the gate here. Its
   overlap test excludes only s2, so a CD-style label whose s0/s1/s3–s6 all
   span the ISO region will always report `FAIL: overlap` — already documented
   in this repo as expected for CD labels. I will read magic and checksum from
   `show`, and treat an overlap complaint about the untouched CD slices as
   benign. A *checksum* failure is not benign: OBP validates it.
5. **Suspected defect.** A "s7 length defect" was reported. `33280` sectors is
   the cylinder-aligned figure; `32768` sectors is exactly 16 MB but is
   **51.2 cylinders — not aligned**. I predict the defect is that, but I will
   read the label rather than assume.
6. **Archive extent hash.** `dd bs=2048 skip=9391 count=174080 | sha256sum`
   must equal `2417a500…c912` — the spliced extent must be byte-identical to
   the verified archive, at ISO9660 LBA 9391, byte 19232768, length 356515840.
7. **Extent containment.** `19232768 + 356515840 = 375748608`, which must fall
   well below the channel slice start `710737920`. The splice cannot reach the
   channel region.
8. **Channel region state.** Expect all-zero across `710737920..727777280`
   unless a canary has been planted. I will report the nonzero byte count and
   its offsets rather than a bare "looks empty" — zeros-versus-zeros has burned
   this project twice.

Gate: any mismatch in 1, 2, 4-checksum, or 6 is a stop. An overlap complaint
from `verify` about the untouched CD slices is not.

---

## 2026-08-20 — GATE 2: independent acceptance review of tribblix-m34-chan.iso

Read-only inspection of the **live playbox file**, not of anyone's notes. No
writes, no boot, no console, no VM or process interaction. Checks are the ones
I pre-registered in the previous section, before the candidate hash existed.

### VERDICT: **GATE 2 — ACCEPT**

All eight pre-registered checks pass. Directly measured full-image SHA-256:

```
/home/niagara/sun4v/images/tribblix-m34-chan.iso
size    727777280
sha256  099f366f528f375888ca008f399f9685d931daaf3100bf52ad269c38eca2f6b1
mtime   2026-08-20 21:21:38 +0000
```

This matches the candidate hash supplied by Antigravity. I measured it myself
with `sha256sum` on the playbox file; I did not copy it from a note.

### Measured evidence

**1. Size — PASS.** `727777280`, exactly the figure derived from the approved
geometry.

**2. VTOC label — PASS.** `vtoc.py show`:

```
magic  : 0xDABE (ok)
cksum  : XOR=0x0000 (valid)
ascii  : CD-ROM Disc with Sun sparc boot created by mkisofs
s2  cyl 0     1421440 blk   694.1MB   <- q.bin reads this as disk size
s7  cyl 2169    33280 blk    16.2MB
s0/s1/s3-s6  cyl 0  1387520 blk       (untouched CD-style slices)
```

Raw sector-0 geometry at `0x1b0`, bytes `08 00 | 00 00 | 00 01 | 02 80`:
`dkl_ncyl=2048`, `dkl_acyl=0`, `dkl_nhead=1`, `dkl_nsect=640`. Magic bytes at
`0x1fc` read `DA BE`. The inherited CD geometry is intact.

`dkl_ncyl` remains 2048 while s2 now spans 2221 cylinders — the same known
cosmetic inconsistency carried by the ZFS scratch image, which OBP accepted.
Not a Gate 2 defect; recorded so it is not rediscovered as new.

**3. s7 arithmetic — PASS, and the reported defect is corrected.**

```
start   cyl 2169 * 640 = sector 1388160 = byte 710737920
length  33280 sectors  = 17039360 bytes
end     1388160 + 33280 = sector 1421440 = byte 727777280 = EOF exactly
```

s7 ends precisely at EOF and precisely at s2's length. The prior 34112-sector
value would have given end sector 1422272 — **832 sectors past** both s2 and
EOF, a slice extending beyond the served disk. My pre-registered prediction was
that the defect would be a non-cylinder-aligned length; 34112/640 = 53.3
cylinders, so that was right in kind, but the more serious property was the
overrun, which I had not called. Recording the miss.

**4. Embedded archive extent — PASS.**

```
dd bs=2048 skip=9391 count=174080 | sha256sum
2417a500e0ae900307612d13ad7b287c57f41c3772dc126ecee9e850ed59c912
```

Byte-identical to the verified boot archive over `[19232768, 375748608)`.

**5. Extent containment — PASS.** `19232768 + 356515840 = 375748608`, which is
334989312 bytes below the channel start at `710737920`. The splice cannot reach
the channel region.

**6. Channel region state — PASS, all zero.** Nonzero byte count across
`[710737920, 727777280)` is **0**. No canary is planted yet, as expected. This
is a counted result, not an eyeballed "looks empty".

**7. Protected source untouched — PASS.**
`tribblix-m34-hsimd.iso` = `e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6`,
size 710717440, mtime `Aug 20 05:54` — unchanged from preflight.

**8. Frozen artifact untouched — PASS.**
`tribblix-m34-hsimd-zfs-scratch.iso`, 1046282240, mtime `Aug 20 20:52` —
unchanged.

### Canary sequencing — confirmed from code, scope as directed

The protocol region is the first `16777216` bytes of s7, host byte `710737920`
= guest block 0. The trailing `262144` bytes are cylinder-alignment padding,
not proof real-estate.

Source-verified in `host-chan.py`: `off(blk) = BASE + blk*BLK` (`:86-87`) with
`BASE = NIAG_CHAN_HOST_BYTE` (`:52`), and `cmd_init` (`:124-131`) calls
`ctrl_write` on `h2g_ctrl(c)=cbase(c)+0` and `g2h_ctrl(c)=cbase(c)+1` for all
16 channels. Therefore:

> **`init` writes 512 zeroed bytes at exactly `710737920`** — region byte 0 —
> plus block 1, repeating at each 1 MB stride. 32 blocks, 16384 bytes total.
> It touches no data area.

So the Milestone 1 order is not a preference, it is **required by the code**:

```
host-plant discriminating byte at 710737920
  -> boot
  -> guest reads /dev/rdsk/c1d0s7 block 0 and matches it   <- the proof
  -> host-chan.py init   (legitimately clears it)
```

Running `init` before the guest read would destroy the proof. Running it after
is correct and expected — the proof has already been taken.

### Gate 2 conclusion

**ACCEPT.** The artifact is byte-correct, the s7 overrun is fixed, the embedded
archive is the verified one, the channel region is provably zero, and nothing
protected or frozen was disturbed. Ready for Milestone 1 canary planting. No
boot or channel consumer has been started by me.

---

## 2026-08-20 — Milestone 1 live review (non-console, read-only)

Host-side observation only. No writes, no signals, no boot, no console input.

### FACT — canary/init sequencing is CORRECT, and I can date it

```
canary planted   image mtime 21:27:36.980  (canary text stamps itself T212724Z)
QEMU started     PID 16275, Thu Aug 20 21:27:49
  => canary precedes boot by ~13 s   SEQUENCING SATISFIED
```

Canary read back from the host file at absolute byte **710737920** — region
byte 0, s7 block 0, exactly the required location:

```
HOSTPROOF-20260820T212724Z-CANARY-BYTE-01\n      (42 bytes)
```

**Nonzero byte count across the entire 17039360-byte region is exactly 42** —
i.e. the canary and nothing else. Two things follow, both important:

1. The content is discriminating ASCII, not zeros. No zeros-versus-zeros trap.
2. **`host-chan.py init` has not run yet**, and this is provable rather than
   asserted: init would write 32 control blocks carrying the `NIAG` magic,
   which would push the nonzero count far above 42 *and* overwrite the canary
   at block 0. A count of exactly 42 is only consistent with init not having
   run.

So the code-required order — plant → boot → guest read → init — is being
followed. The remaining step I cannot observe from the host is the guest's own
read; that proof belongs to Antigravity's console evidence.

### FACT — backing path and PID transitions

```
PID 16275  started 21:27:49  95% CPU  Sl+
  qemu-system-sparc64 -M niagara -L .../firmware/base-1gib -m 1024 -nographic
  -drive if=pflash,file=/home/niagara/sun4v/images/tribblix-m34-chan.iso,format=raw
```

Confirmed from `/proc/16275/cmdline`: it is booting the **Gate 2 accepted
artifact**, not the ZFS scratch and not a stray copy. Correct target.

**PID 2803 is GONE** (`/proc/2803` absent). The parked Stage 4 ZFS guest was
terminated at some point before 21:27. I was not told, and it is worth being
precise about what that did and did not cost:

- **Not lost:** the scratch image itself (`tribblix-m34-hsimd-zfs-scratch.iso`,
  1046282240, mtime `Aug 20 20:52`, unchanged), the forensic copy
  (`scratch-forensic-20260820.iso`), and therefore **both of my open Stage 4
  items remain answerable** — the P5/P6 invariants and the pool_guid
  discriminator are properties of the on-disk image, not of the live VM.
- **Lost:** the live VM's memory and the wedged `zpool create` process itself.
  Anything requiring inspection of that hung process — attaching a debugger,
  reading its state, or a same-test rerun *of that instance* — is no longer
  possible.

That matches my own earlier assessment that losing the QEMU "costs one boot
cycle, nothing more". I record it as a state transition rather than a problem,
with the caveat that E3's recommended rerun and any process-level follow-up now
need a fresh boot.

### FACT — invariants hold during the live boot

Re-measured while PID 16275 runs:

| invariant | value | |
|---|---|---|
| embedded archive extent `[19232768,375748608)` | `2417a500…c912` | **unchanged** |
| VTOC magic | `0xDABE` | ok |
| VTOC checksum | XOR `0x0000` | valid |
| `tribblix-m34-hsimd.iso` | `e98d3a5e…a6f33cf6` | untouched |
| `tribblix-m34-hsimd-zfs-scratch.iso` | 1046282240, `Aug 20 20:52` | untouched |

The boot has not disturbed the spliced archive or the label.

### Chain-of-custody note

The Gate 2 hash `099f366f…f6b1` describes the **pre-canary** artifact. Writing
the 42-byte canary necessarily changed the whole-image hash, so `099f366f` no
longer matches the file on disk and should not be re-asserted as the running
image's hash. That is expected, not a defect.

I deliberately did **not** record a new whole-image hash: the file is a live
`MAP_SHARED` backing store for a running guest, so any whole-file hash taken
now is a snapshot of a moving target and would invite exactly the false
precision this project keeps getting burned by. The stable, meaningful
integrity anchors during a live boot are the archive extent and the VTOC, both
verified above. A whole-image hash is worth taking again only once the guest is
down and quiesced.

---

## 2026-08-20 21:35Z — M1 live monitoring, second pass (read-only)

No writes, no signals, no input. Pane observed via the sanctioned read-only
`sane-look-at-pane` wrapper; raw `tmux` is guarded and I did not bypass it.

### SELF-CORRECTION — no relaunch occurred

In the previous pass I nearly recorded that PID 16275 had died and been
replaced. **Wrong.** That reading came from a `ps -C qemu-system-sparc64` call
where I had dropped the `args` column, so transient ssh/shell children were
listed with PIDs I misattributed to QEMU. Re-checked properly against
`/proc/<pid>/cmdline`:

```
PID 16275  start Thu Aug 20 21:27:49  (parents 16267/16274 = sudo)
  qemu-system-sparc64 -M niagara -L .../base-1gib -m 1024 -nographic
  -drive if=pflash,file=/home/niagara/sun4v/images/tribblix-m34-chan.iso,format=raw
```

Same PID, same start time, same backing path. Nothing was relaunched. Recording
the misread because a bad `ps` invocation producing a confident wrong
conclusion is exactly the failure mode this project keeps paying for.

### FACT — the emulator independently confirms my s2 geometry

QEMU's own banner, read off the console:

```
niagara: msync on SIGUSR2 -> kill -USR2 16275
niagara: vdisk 694 MB MAP_SHARED from .../images/tribblix-m34-chan.iso
```

`694 MB` is not a round number anyone typed — it is q.bin reading `dk_map[2].nblk`
out of the label I specified:

```
s2 = 1421440 sectors = 727777280 bytes = 694.1 MiB   -> banner "694 MB"  MATCH
(for contrast: zfs-scratch s2 2043520 = 997.8 MiB gave "997 MB";
 base hsimd ISO s2 1387520 = 677.5 MiB)
```

So the VTOC edit is honoured end to end: my derived geometry → the label →
`vdev_simdisk.h`'s `DISK_S2NBLK_OFFSET` → the served disk size. This is a
stronger confirmation than `vtoc.py show`, because it is the emulator's own
independent read of the same bytes.

### FACT — boot progress, no input sent

```
ok boot
Boot device: vdisk  File and args:
hsfs-file-system
Loading: /platform/sun4v/boot_archive
ramdisk-root ufs-file-system
Loading: /platform/sun4v/kernel/sparcv9/unix
Welcome to Tribblix, the retro illumos distribution
tribblix-m34 | April 2026
os-io WARNING: add_spec: No major number for sf
NOTICE: Disabling watchdog as watchdog services are not available
Loading smf(7) service descriptions: 62/95
```

The **spliced** boot archive loaded and the kernel came up, which is the first
functional evidence that the archive splice at LBA 9391 is not merely
hash-identical but bootable. `No major number for sf` and the watchdog notice
are unrelated to this work. At 21:35Z the guest is mid-SMF import, no login
prompt yet.

### FACT — canary state at 21:34:01Z, ~6 min into boot

```
image mtime          2026-08-20 21:27:36.980   (unchanged since planting)
region nonzero       42 bytes                  (unchanged)
block 0 @ 710737920  HOSTPROOF-20260820T212724Z-CANARY-BYTE-01\n
```

Byte-identical to the planting-time read. `init` still has not run — 42 nonzero
region-wide is only consistent with the canary alone.

### METHODOLOGICAL LIMIT — the guest read is not host-observable

Worth stating plainly so nobody waits on me for it: **I cannot detect the
guest's canary read from the host side.** A read does not dirty the
`MAP_SHARED` mapping, does not advance the image mtime, and leaves no host-
visible trace. The host file looks identical whether the guest has read block 0
a thousand times or never.

Therefore the guest-read half of Milestone 1 can only be evidenced from the
console, and that is Antigravity's to produce. My role on it is comparison: I
have the authoritative host bytes recorded above, and when their guest-side
`dd`/`od` output lands I will compare it byte for byte and check that it
precedes `init`.

### What I will check when the guest read lands

1. Guest bytes equal the 42 host bytes exactly, including the trailing `\n`.
2. Guest read offset is s7 block 0 via `/dev/rdsk/c1d0s7`, not a whole-disk
   `c1d0s2` offset that would coincidentally alias the same absolute byte.
3. The read is timestamped **before** any `host-chan.py init`.
4. After init runs: region nonzero jumps well above 42 and block 0 carries
   `NIAG` magic — confirming init did what the code says and that the proof was
   taken in time.

---

## 2026-08-20 21:42Z — M1 boot telemetry and interim adjudication (read-only)

No keys, no console bytes, no signals, no image writes. Pane read via
`sane-look-at-pane` only.

### FACT — output IS advancing (measured, not eyeballed)

| sample | host UTC | SMF import | PID 16275 | %CPU |
|---|---|---|---|---|
| pass 2 | 21:35 | 62/95 | alive | 95.1 |
| SAMPLE1 | 21:37:13 | 83/95 | alive, etime 09:23 | 99.7 |
| SAMPLE2 | 21:38:37 | **95/95** | alive, etime 10:47 | 99.7 |
| SAMPLE3 | 21:42:21 | past import, in service startup | alive, etime 14:31 | 99.5 |

Import rate ≈ 0.16 descriptions/s across two independent intervals. The boot is
progressing, not wedged — and that is a delta between timed samples, not an
impression from one frame.

At SAMPLE3 the console shows service startup with the already-documented
failure family:

```
svc:/network/ipsec/ipsecalgs:default  method failed, -> maintenance
svc:/system/keymap:default            method failed, -> maintenance
svc:/network/netmask:default          method failed x3, -> maintenance
```

Same keymap/IPsec cluster recorded on earlier boots. No login prompt yet.

### FACT — identity re-verified

```
PID 16275 ALIVE, etime 14:31, 99.5% CPU
/proc/16275/cmdline contains tribblix-m34-chan.iso : 1 match
```

### FACT — host bytes unchanged

```
region nonzero = 42        (unchanged across all samples)
image mtime    = 2026-08-20 21:27:36.980   (still the planting time)
```

`init` has not run. The canary is intact.

### FACT — playbox SSH is intermittent, but the host is NOT down

One probe timed out; a probe 5 s earlier succeeded (`OK 21:41:31Z`), and probes
after it succeeded too. So this is contention, not an outage — consistent with
QEMU pinning ~99.7% of a core on an arm64 UTM guest. Recorded because a single
timeout is not evidence of absence, and I am not going to report the host as
down on one failed probe.

### TRAP — guest clock is UTC-7, and it will corrupt the ordering proof

Console stamps read `Aug 20 14:41:36` while the host read `21:41:31Z`. The
guest runs **UTC-7**, matching the offset seen in the Stage-4-era logs.

> When the guest canary read lands, its console timestamp will be ~7 hours
> *behind* host UTC. Comparing a raw console stamp against a host mtime would
> make almost any guest event look like it preceded almost any host event.

`14:41:36` guest is `21:41:36Z`. The read-before-`init` ordering must be
adjudicated in a single timebase. I will convert console stamps to UTC before
comparing, and I will prefer ordering evidence that does not depend on clocks
at all — chiefly the region nonzero count, which is 42 before `init` and jumps
well above 42 after it.

### INTERIM ADJUDICATION OF MILESTONE 1

**Host-side half: PASSED, fully evidenced.**

- canary planted at region byte 0 = absolute 710737920, the required location
- planted 21:27:36.980, boot 21:27:49 → plant precedes boot by ~13 s
- content discriminating ASCII, 42 bytes, `HOSTPROOF-20260820T212724Z-CANARY-BYTE-01`
- region nonzero exactly 42 → `init` provably has not run
- backing identity correct, artifact invariants intact, protected media untouched

**Guest-side half: NOT YET LANDED.** No console evidence of a canary read
exists at 21:42Z; the guest has not reached a shell. **Milestone 1 is therefore
NOT complete**, and I will not mark it so. The host side has done everything it
can; the remaining proof is a guest read that only the console can witness.

Verdict deferred pending that evidence, against the four checks already
recorded: exact 42-byte match including trailing newline; read via
`/dev/rdsk/c1d0s7` block 0 rather than an aliasing `c1d0s2` offset; ordering
before `init` in a common timebase; and the post-`init` transition of region
nonzero above 42 with `NIAG` magic at block 0.
