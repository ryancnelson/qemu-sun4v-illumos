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
