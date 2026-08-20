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
