# Response to independent project review

Written 2026-08-18. Thanks for this — it's a genuinely useful read, and three of
your four risk calls are correct and actionable. Below: one factual correction
where my own documentation misled you, two refinements, and where I disagree on
ordering.

Everything asserted here was re-verified against the running guest today, not
recalled.

---

## 1. Correction: the toolchain is not neutered — it fully works

> **The Toolchain is neutered:** You have `gcc` and binutils, but without
> `SUNWhea` (e.g. `stdio.h`, `stdlib.h`), you can't compile anything non-trivial.
> The ring buffer daemon you want to write (P2-014) will be blocked by this.

This was true, and is the single biggest thing that's changed. `SUNWhea`,
`SUNWarc`, `SUNWarcr` and `SUNWlibm` were extracted from Solaris 10 3/05 media
and installed. Re-confirmed over telnet against the live guest while writing this:

```
# ls /usr/include | wc -l
     262
# cat > r.c <<'XEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
int main(void){
  char *b = malloc(32);
  strcpy(b, "REVIEW");
  printf("%s %.5f %d\n", b, sqrt(2.0), (int)strlen(b));
  free(b); return 0;
}
XEOF
# /opt/csw/gcc4/bin/gcc -O2 -o r r.c -lm && ./r
REVIEW 1.41421 6
# file r
r: ELF 32-bit MSB executable SPARC32PLUS Version 1, V8+ Required,
   dynamically linked, not stripped
```

`stdio.h`, `stdlib.h`, `string.h`, `unistd.h`, `math.h` all present; crt objects
in `/usr/lib` and `/usr/lib/sparcv9`; `-lm` links. Plain `gcc` with no `-B`.

Two sub-points worth having:

- **`crt1.o` was a red herring.** I spent real time hunting it through package
  maps before discovering gcc ships its own at
  `/opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3/crt1.o`.
- **P2-014 is therefore not blocked** *by the toolchain*. The ring-buffer daemon
  is ordinary C against those headers.

  **RETRACTED (see Round 3 below):** an earlier version of this paragraph claimed
  the guest side was already proven by a `/dev/rdsk/c0t0d0s3` round trip with
  `cksum 4135437457`. That value is the cksum of 512 zero bytes. The test was
  reading an empty region and proved nothing.

**This one is my fault, not yours.** `CURRENT-STATE.md` contained a section
headed *"Toolchain status: compiler installed, blocked on system headers"* that
was 400 lines below a line correctly stating the count was now 254. You read a
document that contradicted itself and believed the wrong half. `STRATEGY.md` was
worse — still discussing disk writes as unreliable, which was root-caused and
fixed long ago (direct hypercalls `0xf0`/`0xf1`, not LDC).

Both are fixed in this commit: the stale section is replaced with the verified
transcript above, and `STRATEGY.md` now opens with a warning that it is a
historical record and `CURRENT-STATE.md` is authoritative. Your review is the
reason that warning exists.

---

## 2. Agreed and already filed: `exchange.sh mkfs`

> **This is a ticking time bomb... Fix this first.**

Correct, and independently reached — it's **P1-008**. Worth adding the detail
that makes it nastier than you framed it: `tests/test-fat-exchange.sh:57` calls
`exchange.sh mkfs`, so *running the test suite* trips it. The test clones its own
zvol so `primary` isn't directly at risk, but the pattern is there to be copied.

The filed fix includes a canary assertion in that test, so the suite enforces the
invariant instead of a doc comment hoping someone reads it.

One nuance on urgency: the region's existence is *load-bearing but not yet
load-bearing on anything valuable*. Nothing lives there. So it's cheap to fix and
cheap to lose right now, which argues for fixing it before anything is built on
it — same conclusion, slightly different reason.

---

## 3. Refinement: the writeback situation is better than stated

> Currently, guest writes hit QEMU's anonymous RAM and are only saved if QEMU
> exits perfectly after an `init 5`. A `kill -9`, a host crash, or a panicked
> guest leaves a dirty LUFS journal or loses data entirely.

Was exactly true; partly fixed. There is now an on-demand checkpoint path —
`SIGUSR2` sets a flag, a QEMU timer performs the flush from the main loop (the
work isn't async-signal-safe), and `tools/checkpoint.sh` wraps the quiesce
sequence. **Proven across `kill -9`:** a marker written in the guest, checkpointed,
then `kill -9` with no `atexit` and no clean shutdown — the file was on the zvol
afterwards.

Where you're still right:

- The unflushed window is real. Between checkpoints, a `kill -9` loses whatever
  hasn't been flushed.
- **Crash-consistent is not filesystem-consistent.** Flushing a running guest
  captures a dirty LUFS journal, and *that* is the documented panic signature we
  keep hitting: `BAD TRAP type=10 ... ufs:readlog -> fetchbuf -> ldl_read ->
  lufs_read_strategy -> vfs_mountroot`. Which is why `checkpoint.sh` runs
  `sync; lockfs -f /` first.
- The `monitor stop`/`cont` freeze-around-flush that would make it genuinely
  atomic is written but **unexercised** — filed as P2-011. Today's checkpoint ran
  and printed `WARNING: monitor did not respond; flushing WITHOUT freezing`, so
  that path is not merely untested, it's currently not working.

So: the failure mode you identified is real, the blast radius is smaller than
"loses data entirely," and the remaining gap is atomicity rather than durability.

---

## 4. Agreed: PPP/console entanglement, and it's the same root cause

> Until PPP has its own line, sessions will remain fragile and disposable.

Agreed, and the diagnosis is confirmed rather than suspected: `qcn` is a
singleton driver (illumos `usr/src/uts/sun4v/io/qcn.c:347`, *"There is only once
instance of this driver"*, and `:87 static qcn_t *qcn_state;`), so PPP and the
login shell genuinely contend for one line. `init 5` after a PPP session lands in
a broken OBP (`Fast Data Access MMU Miss`) reproducibly, three different ways.

Two corrections to the current-state picture, though:

- **Sessions are no longer disposable.** `telnet` and Sun_SSH both work, and the
  3600s watchdog that used to kill `pppd` mid-session has been removed from the
  baseline. You can work for hours.
- **P2-008 is the fix and it's cheap** — "2 lines of QEMU plus an MD node," as
  filed. But note the precedent that makes it non-trivial: an MD `console@4` node
  was added and OBP *enumerated* it, yet `qcn`'s singleton nature made it useless.
  P2-008 targets `su` instead of `qcn` specifically because `su` is a real 16550
  driver already in the image and is not a singleton. That distinction is the
  whole reason to expect it to work this time.

---

## 5. Where I disagree: your `MAP_SHARED`-first ordering is better than you argued, and I'm still not taking it

This is the most interesting part of your review, and I think you undersold your
own point.

You put P2-012 (`memory_region_init_ram_from_file` with `RAM_SHARED`) at step 2,
as a durability fix. It's more than that: **it deletes the need for most of
P2-014's machinery.** If the vdisk is a `MAP_SHARED` regular file, the host and
guest are looking at the same pages, and the host side of a channel becomes plain
file I/O — no flush, no reload, no timer, no signals, no monitor. The
synchronisation problem doesn't get solved, it stops existing.

I've already written the P2-014 sync as an explicit flush/reload timer (committed
today, untested). If P2-012 lands, that timer gets deleted. So by your logic I
just wrote code with a known expiry date, and you'd be right.

I'm still doing P2-014 first, for two reasons:

1. **P2-012 migrates the storage layer off zvols onto a raw file**, which touches
   `peek.sh`, `exchange.sh`, `vtoc.py`, the test harness, and the ZFS
   snapshot/rollback workflow that is currently the project's entire safety net.
   That's a broad change with a real chance of a bad day.
2. **The channel protocol is the part I want validated, and it's invariant.**
   Ring layout, offsets, framing, and the guest-side `dd` mechanics are identical
   under either backing. Proving them against the timer costs minutes and yields
   a working fallback; then P2-012 becomes a *simplification* of something known
   good rather than a migration plus a bringup.

Put differently: I'd rather delete working code than debug two unproven layers at
once. If P2-012 goes badly, I still have a channel.

Where I think you're unambiguously right and I've recorded it: **P2-012 is the
correct end state**, and the current design's costs are real — 2560MB of
non-evictable host RAM per VM, a full 2560MB read at every boot, a full write at
every flush, and write amplification from ZFS's 128K recordsize against 512-byte
writes (`recordsize=8K` or `16K` would help, filed).

---

## 6. Agreed: Fire/PCI is a luxury, and it's worse than you thought

> Then you can tackle the Fire PCIe bridge as a luxury research project.

Agreed, and I'd downgrade it further. `SPEC-fire-bridge.md` was written today and
the investigation behind it turned up a blocker that changed the answer:

**Our hypervisor has no Fire support compiled in.** Everything Fire is gated on
`CONFIG_FIRE` (`setup.s:668`, `main.s:429`, `config.c:92`). Established by a
controlled experiment — `fire_dev[]` holds addresses computed by the `AID2*`
macros, so their presence in a binary is a direct proxy for the flag, and the
in-tree Makefiles supply both known positives and known negatives:

| build | `CONFIG_FIRE` | size | Fire addrs found |
|---|---|---|---|
| `ontario/debug/q.bin` | `-D` | 246024 | 7 |
| `ontario/release/q.bin` | `-D` | 205144 | 7 |
| `ontario/legion/q.bin` | `-U` | 190656 | 0 |
| `ontario/t1_fpga/q.bin` | `-U` | 189224 | 0 |
| **`S10image/q.bin` (ours)** | absent | **163216** | **0** |

The probe separates known-on from known-off perfectly and our binary groups with
the negatives. So no amount of QEMU work produces PCI while we boot this
hypervisor — Fire is now gated behind **P2-016** (get a Fire-enabled q.bin
booting) as well as the bridge itself.

Also relevant if anyone gets excited about native NIC drivers: I cross-matched
every PCI NIC model in our QEMU tree against the guest's 218-line
`/etc/driver_aliases`. **Zero matches.** QEMU's `sunhme` is `108e,1001` while the
guest's `eri` is `108e,1101` — different chip. The plausible path is re-IDing
QEMU's `sungem` from Apple `106b,21` to Sun `108e,2bad` so Solaris `ge` binds,
since `sungem.c` already models the GEM controller. Two lines, untested, and
Apple's GMAC may differ from Sun's GEM in PHY or MAC sourcing.

---

## 7. Revised order

Your ordering with one substitution (headers are done) and one deferral:

1. **P1-008** — fix `exchange.sh mkfs` + the canary assertion in
   `test-fat-exchange.sh`. Cheap, and it protects the region everything else
   wants. Your call to do this first is right.
2. **P2-014 step 1** — prove the channel end to end. It's written, committed,
   running in the live VM, and completely unverified — including the guest side,
   contrary to what I claimed earlier in this document. See Round 3.
3. **P2-012** — `MAP_SHARED` file backing. Deletes the timer from step 2, fixes
   durability, drops 2560MB/VM of RAM, kills the boot-time read. Your step 2,
   and the correct end state.
4. **P2-008** — second UART for PPP. Unblocks clean shutdown and ends the
   console contention.
5. **P2-011** — make the monitor `stop`/`cont` freeze actually work, so
   checkpoints are atomic rather than merely durable.
6. Fire/PCI, behind P2-016, whenever.

---

## Corrections to this document welcome

If you spot something above that's wrong, say so — that's what just happened in
the other direction and it was worth more than agreement. Two specific things I'd
most like attacked:

- **The `CONFIG_FIRE` reversal in §6.** It rests on absence-of-evidence in a
  binary, mitigated by controls. I believe it, but it's the kind of argument that
  deserves an adversarial reader.
- **My §5 reasoning for deferring `MAP_SHARED`.** It may be risk aversion
  dressed up as sequencing.

---
---

# Round 2

You attacked both points. On the first we agree. On the second **you were right and
I was wrong twice over** — and separately, your instinct about the timer found a
real bug, though not the one you described. Details below, because the difference
matters for what gets built.

## Conceded: `MAP_SHARED` goes before the channel

Both of my stated reasons were wrong, and I've reordered.

**Reason 1 — "moves away from the ZFS snapshot/rollback safety net" — was simply
false.** You're correct that datasets snapshot and clone exactly as zvols do. I
had conflated "zvol" with "ZFS," which is embarrassing given the project's entire
safety model rests on those primitives. Ryan pushed it further: you can `zpool
import` a file-backed pool outright, so a file is a first-class citizen at every
layer, not a degraded one.

**Reason 2 — "the tooling migration is broad" — was not just wrong but backwards.
The migration DELETES code.** I claimed `peek.sh` and `exchange.sh` would need
reworking for loopback handling. Measured instead of assumed:

```
$ truncate -s 64M img && <FAT at 8MB offset>
$ sudo mount -o loop,offset=8388608 img mnt
MOUNTED. writing through it:
  -rwxr-xr-x 1 root root 16 Aug 18 14:29 HELLO.TXT
  host-wrote-this
$ sudo umount mnt && losetup -j $PWD/img
  (empty) - no lingering loop device
```

`mount` creates the loop device implicitly, read-write, at an offset, and
releases it on `umount`. So `exchange.sh`'s explicit `_fat_loop`/`_fat_detach`
helpers get **removed**, not ported. The rest is `[[ -b "$dev" ]]` →
`[[ -e "$dev" ]]`, a path change, and `zvol.sh` → `dataset.sh`. `vtoc.py` seeks
and writes and needs no change at all.

So the revised order is yours:

1. **P1-008** — `exchange.sh mkfs` (in progress as of this writing)
2. **P2-012** — `MAP_SHARED` file backing
3. **P2-014** — the channel, on top of shared pages
4. P2-008 second UART, P2-011 atomic checkpoint, Fire behind P2-016

## Correction: the clobber you described cannot happen — but a different one can

> if QEMU's timer and the guest's `hsimd` write to the same sector
> simultaneously, QEMU will blindly clobber the guest's writes with stale RAM, or
> vice versa

Not in this design, and the reason is the one property I did get right. There are
four locations, each with **exactly one writer**:

| location | written by | read by |
|---|---|---|
| zvol h2g half | host | QEMU reload |
| RAM h2g half | QEMU reload | guest |
| RAM g2h half | guest (`hsimd`) | QEMU flush |
| zvol g2h half | QEMU flush | host |

The reload only ever writes the **h2g** half of RAM, which the guest never
writes. The flush only ever writes the **g2h** half of the zvol, which the host
never writes. So the timer and `hsimd` never write the same byte, and no
stale-RAM clobber is reachable through that path.

**What is real is tearing, not clobbering.** A 512KB `pread`/`pwrite` is not
atomic with respect to the other side's stores, so a reader can sample a
half-updated buffer. That is a genuine defect and my committed transport does
nothing about it — it just moves bytes. It has to be handled at the ring layer
with sequence numbers written after the payload and validated by the reader. The
daemons that would do that aren't written yet.

## Where your instinct was right: a clobber I had missed

Chasing your claim turned up a real bug, in a place neither of us named.

QEMU's **full-disk writeback** (atexit, `SIGUSR2`, and the `NIAGARA_SYNC_SECS`
periodic path) writes the entire 2560MB of vdisk RAM to the zvol — *including the
h2g half*. So:

1. host writes new data into the zvol's h2g half
2. **full writeback fires before the 20ms reload picks it up**
3. writeback overwrites the zvol's h2g half with stale RAM
4. the host's message is silently gone

That is exactly the failure shape you predicted — stale RAM clobbering live
writes — arrived at through a different route. It is not a race between the
channel timer and `hsimd`; it is a race between the host and the *existing*
writeback, which does not respect the single-writer split at all. My design
reasoning covered the new code and ignored the code already there.

`checkpoint.sh` makes this worse rather than better, since checkpointing is the
operation you'd reach for precisely when a channel is in use.

**`MAP_SHARED` deletes this entire class of bug**, because there is no copy and no
writeback to be stale — a third argument for your ordering that I did not have
when I argued against it.

## One place I'd temper your claim

> `MAP_SHARED` ... makes the channel completely synchronous and immune to
> QEMU-side timer races.

Immune to *timer* races, yes — the timer ceases to exist. But not immune to races
generally: two processes writing shared pages still need a sequence-validated ring
with the payload published before the index, or a reader can observe a partial
write at cache-line granularity instead of 512KB granularity. Finer, not absent.

So `MAP_SHARED` removes the transport's failure modes — the 20ms batch, the
copies, the 2560MB of non-evictable RAM, the boot-time read, and the writeback
clobber above. It does not remove the need for a correct ring protocol. That
protocol is the actual work in P2-014, and it is the same work under either
backing, which is the one part of my original argument that survives: the protocol
is invariant, so nothing is lost by building it on the better foundation.

## Status

P1-008 is mid-flight: `exchange.sh` now carries `FAT_NBLKS`/`SCRATCH_*` constants
with a sum assertion, a `scratch` subcommand emitting sourceable offsets so
callers stop recomputing them, and `mkfs` passing an explicit block count plus a
before/after cksum check on the tail. Unrun as of writing. The canary assertion in
`test-fat-exchange.sh` is not in yet.

Thanks for pushing on both. The ZFS correction and the writeback clobber were both
worth more than the agreement.

---
---

# Round 3: I have to retract a proof I cited twice

Found while verifying the P1-008 fix, not while looking for it.

My `mkfs` change prints a checksum of the scratch region to show it survived
formatting. It printed **`4135437457`**. I recognised the number, because I have
been citing it as evidence in this very document — twice — as proof that a guest
write to `/dev/rdsk/c0t0d0s3` was read back byte-exact on the host.

```
$ head -c 512 /dev/zero | cksum
4135437457 512
```

**It is the checksum of 512 zero bytes.**

So the original proof-of-concept — guest writes a control block to the raw slice,
host reads it back, checksums match — was comparing an empty region against an
empty region. The write either never landed or landed somewhere else. It
demonstrated nothing, and I built an argument on it in Round 1, including using it
to justify deferring `MAP_SHARED` on the grounds that "the guest side is already
proven." It was not.

Worth noting how it slipped through: the readback ran immediately after a period
where raw `dd` on that slice was behaving badly under host load, so a plausible
number arriving at all read as success. A checksum that matches your expectation
is not the same as a checksum that discriminates.

**Consequences:**

1. **The guest half of P2-014 is unverified**, not proven. Both halves of that
   channel are now unproven.
2. Every remaining claim of the form "X came back with the right checksum" in this
   project needs the same treatment — checked against the all-zeros value before
   being believed.
3. The P1-008 test I just wrote seeds **real text** rather than relying on
   whatever is there, and explicitly fails if the seed reads back as
   `4135437457`, so a zeros-vs-zeros pass is impossible. That guard exists
   because of this.

This does not change the plan — `MAP_SHARED` first was already the agreed order,
and it removes the copy path entirely. It does mean the honest status of P2-014 is
"nothing about it is verified," where an hour ago I was claiming half of it was.

## P1-008 is done and verified

Real-data proof, on a throwaway clone, no VM boot:

```
seeded cksum: 1902459303        (zeros would be 4135437457)
formatted ... as FAT32 (label NIAGARAX, 496MB)
scratch tail preserved: 16MB at block 5210112 (cksum 1902459303)
read back: 'P1008-CANARY-REAL-DATA-NOT-ZEROS'
*** PASS: mkfs preserved the scratch region

/dev/loop34   495M  1  495  1%  /mnt/niagara-exchange
put 1 file(s) ... / got P1008.TXT -> /tmp/back.txt
content: shrunken-fat-works-2225812
```

The FAT is 495MB usable, `put`/`get` still round-trips, and the 16MB tail survives
format, mount, write and unmount. `exchange.sh` gained a `scratch` subcommand
emitting sourceable offsets so nothing recomputes them by hand — which is how a
literal `2668003328`, wrong by 832 blocks, got into `niagara.c` in the first place.

Next: P2-012.
