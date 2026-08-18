# Current State

Last verified: 2026-08-17. Everything below is backed by a passing test or a
recorded measurement. Claims without evidence are marked UNVERIFIED.

## Test suite: 7 tests

```
sudo QEMU_BIN=$PWD/qemu/build/qemu-system-sparc64 bash tests/run-all.sh
  PASS  test-boot-to-login
  PASS  test-disk-writes-persist
  PASS  test-exchange-channel      <- host->guest bulk data transfer
  PASS  test-md-roundtrip
  PASS  test-reboot-obp-intact     <- FLAKY, see Known gaps #4
  PASS  test-toolchain-compiles    <- in-guest gcc compiles, links AND runs
  PASS  test-fat-exchange          <- BIDIRECTIONAL host<->guest file exchange
```

Runs in ~5-7 min. `test-reboot-obp-intact` intermittently times out waiting for
the login prompt; boots occasionally exceed even the 180s timeout under load
because each pins guest RAM. Each VM test clones its own throwaway dataset from
`images@baseline` and destroys it on exit, so tests cannot corrupt each
other or the daily driver.

## What works

- **Solaris 10 boots** to a login prompt in ~40s. Root, no password.
- **Disk writes persist.** Verified end-to-end: write to `/etc`, clean exit,
  canary found in the raw image file, then a *second boot* reads the file back and
  the image is still bootable. This is `test-disk-writes-persist`.
- **2GB disk**, 1.9GB UFS, ~1.6GB free. Volume is 2560MB to carry slice 3.
- **1GiB of guest RAM** (was 256MB). Artyom Tarasenko's sun4v MD files lift the
  ceiling; `prtconf` in Solaris 10 reports "Memory size: 1024 Megabytes". It is
  a drop-in: `openboot.bin`, `q.bin`, `nvram1`, `reset.bin` are byte-identical
  to ours, and ONLY `1up-md.bin` / `1up-hv.bin` differ, so 1GiB is purely a
  Machine Description change. Firmware lives in `/datapool/niagara/base-1gib`.
  Select with `NIAGARA_MEM=1024 S10DIR=/datapool/niagara/base-1gib`.
  Source: `github.com/artyom-tarasenko/qemu-sun4v-md` @ `1GiB-experimental`.
- **A working C toolchain in the guest.** Plain `gcc` — no `-B`, no PATH
  games — compiles, links against `libm`, and produces a binary that runs:
  `SUM=5050 RC=1.41421`. Guarded by `test-toolchain-compiles`, which asserts
  the binary's own stdout, because "gcc exited 0" is not evidence.
  Snapshot: `primary@toolchain-working`. Details under "Toolchain" below.
- **Machine Descriptions are editable as text.** `1up-md.bin` / `1up-hv.bin`
  regenerate byte-identically from `.pdesc`/`.hdesc` source via a locally
  built `mdgen`. Guarded by `test-md-roundtrip`.
- OBP survives a guest `reboot` far enough to answer `devalias`
  (`test-reboot-obp-intact`). Note this is a weak assertion — see Known gaps.
- Perl 5.8.4 is present in the guest (`/usr/bin/perl`). No python.
- **NETWORKING: a root shell over TCP/IP.** `telnet 10.0.5.15` gives a Solaris
  root login. PPP over the qcn console (`pppd notty` + `asyncmap 0xffffffff` +
  `stty raw -echo`), telnetd served by a 20-line perl mini-inetd because SMF's
  inetd is stuck `offline` on an absent `svc:/milestone/name-services`.
  Bring-up: `tools/guest-ppp-up3.sh` in the guest, host side
  `pppd <pty> 115200 noauth nolock local nodetach novj noccp asyncmap 0xffffffff
  10.0.5.1:10.0.5.15`. 0% loss at 500B, ~60ms RTT.
  CAVEAT: a PPP session cannot be shut down cleanly yet -- `init 5` afterwards
  always breaks OBP -- so treat such sessions as disposable and roll back to
  `primary@networked`.

  Snapshot **`primary@networked`** is the starting point: PPP installed
  (`pppd` 2.4.0b1 + `libmd.so.1` + sppp/sppptun registered), `/etc/default/login`
  already permitting root network login, the telnet/ftp/shell/login/rexec SMF
  manifests imported, and the bring-up scripts on the FAT slice. VERIFIED to boot
  clean and halt with `Program terminated` before it was taken.
- **Bidirectional host <-> guest file exchange** via FAT32 on VTOC slice 3.
  Host mounts it with `mount -t vfat` on a loop device, guest with
  `mount -F pcfs /dev/dsk/c0t0d0s3:c`. Verified with two exact `cksum` matches
  on the same 256KB of random data — host->guest and guest->host
  (`test-fat-exchange`). Drive it with `tools/exchange.sh mkfs|put|get|ls`.
  Guest writes are visible to the host as soon as the kernel flushes the page —
  no shutdown required (see "How storage actually works").
- **Bulk host -> guest data channel** via a raw VTOC slice. Verified
  byte-for-byte: a 256KB random binary transfers with a matching `cksum`
  (`test-exchange-channel`). See "Data channel" below.

## How storage actually works

**P2-012 (2026-08-18): the vdisk is a `MAP_SHARED` mapping of a regular file.**
There is no load, no writeback, and no second copy of the disk anywhere.

```
UFS -> hcall_disk_write (0xf1) -> q.bin -> vdisk mapping
                                               |
                          kernel page writeback |  (dirty_expire ~30s,
                                               v   or msync on demand)
                              /datapool/niagara/images/primary.img
```

A guest store lands in the page cache for the image file, so it IS the persisted
state. Consequences, all measured:

- **Durability without any code.** A canary written in the guest, quiesced, then
  `kill -9` on QEMU — no `atexit`, no writeback path at all — was present in the
  image file afterwards.
- **~2.4GB of host RAM per VM returned.** Measured on a running guest:
  `RssAnon 422172 kB` (guest RAM) + `RssFile 125012 kB` (vdisk pages touched so
  far), against 2560MB of pinned anonymous RAM before. The file pages are
  evictable page cache that grows only as the guest touches blocks.
- **No 2560MB read at boot, no 2560MB write at exit.**
- The writeback-clobbers-host-writes race is gone, because there is no stale copy
  left to clobber anything with.

**`SIGUSR2` still exists** but now does `msync(MS_SYNC)` — an explicit durability
*point*, not a copy. Durability is automatic; what msync buys is a known instant.

**CONSISTENCY is unchanged and is still the thing that bites.** A running guest
may be mid-transaction, so an image captured at an arbitrary moment can carry a
dirty LUFS journal whose replay panics at `ufs:readlog -> vfs_mountroot`. Quiesce
with `sync; lockfs -f /` first. `tools/checkpoint.sh` does that.

The image MUST be a regular file: block devices do not support `MAP_SHARED`
writeback reliably. `niagara.c` checks `S_ISREG` and refuses rather than mapping
something whose writes go nowhere.

q.bin uses **direct hypercalls (0xf0 read / 0xf1 write), not LDC.** There is
no LDC implementation in the hypervisor source. This resolves the old open
question in the backlog (P1-005).

### HOST-side traps that produce silently wrong results

**`sed` on biggie is `sed 0.1.1`, NOT GNU sed, and it silently ignores `\b`.**
No error, no warning — the substitution simply does not happen. This bit me twice
in one afternoon:

```
$ printf 'zvol_destroy "$X"\n' | sed -e 's#\bzvol_destroy\b#disk_destroy#g'
zvol_destroy "$X"        <- unchanged, exit 0
$ printf 'zvol_destroy "$X"\n' | sed -e 's#zvol_destroy#disk_destroy#g'
disk_destroy "$X"        <- works
```

Worse than a plain failure: in a multi-`-e` command the non-`\b` expressions DO
apply, so the file's mtime changes and it looks processed. First occurrence left
two files unconverted; the second left every test with `$DISK` referenced but
`ZVOL=` still assigned, so all six VM tests died on `DISK: unbound variable`.
**Never use `\b` in sed here.** Verify a rename by grepping for the old name.

**A leaked loop device makes `zfs destroy` fail quietly enough to believe.** A
tool that dies between `losetup` and `losetup -d` leaves the image open; the
destroy then fails but the caller carries on thinking the dataset is gone. One
held `/datapool/niagara/xtest` alive at 585M after a destroy that appeared to
succeed. `tests/lib/disk.sh` detaches loops BEFORE destroying, and
`tests/reap-orphans.sh` reaps orphaned loops (skipping mounted ones).

**A cleanup helper that no-ops on the wrong type is a silent leak.** `disk_exists`
originally tested `-t filesystem` only, so `disk_destroy` returned 0 for a zvol
clone and leaked it with no message. It now accepts either type.

**A checksum that matches your expectation is not one that discriminates.**
`cksum` of 512 zero bytes is **4135437457**. A "successful" round-trip test
reported exactly that and was reading an empty region. Any checksum assertion must
be against known non-zero content, and should explicitly fail on that value.

### Rules for touching the disk from inside the guest

Learned the hard way 2026-08-18. Violating any of these looks like a hung or
broken machine.

**Raw writes MUST be whole 512-byte blocks.** `/dev/rdsk/*` is a character
device with no partial-block support. A 17-byte `dd` reported success
(`0+1 records out`) and silently wrote NOTHING -- verified afterwards by reading
the region from the host and finding zeros. Pad with `conv=sync` or write
512-byte multiples.

**NEVER write to `/dev/rdsk/c0t0d0s2`.** s2 is the whole-disk slice and overlaps
the mounted root filesystem; writes to it hang indefinitely. Use s3 with an
offset instead. s3 block N == absolute block 4194304+N.

**USE `iseek=`/`oseek=`, NEVER `skip=`/`seek=`, for random access.** This is the
single most expensive wrong belief this project has carried. MEASURED 2026-08-18
on a live guest:

```
dd ... bs=512 skip=1015808  count=1     ~254 SECONDS   (linear scan)
dd ... bs=512 iseek=1015808 count=1        0.1 seconds  (lseek)
```

`skip=` on this raw character device reads and discards every intervening block.
Sequential read rate is ~4000 blocks/sec (2000 blocks in 0.5s, ~2 MB/s), so
skipping a quarter-million blocks takes minutes. `iseek=` issues a real `lseek`
and is instant at any offset.

**The old rule here claimed "reads at high offsets hang" and told you to expect a
wedged driver. That was WRONG and it blocked P2-014 for a day.** The reads were
never hung; they were scanning. Processes I declared wedged had 79s, 44s and 36s
of accumulated CPU — consistent with scanning, and inconsistent with blocking on
I/O, which consumes none.

Corollary about interrupting: Ctrl-C during one of those scans is not what wedges
anything, and nothing was ever wedged. But a spinning `dd` does burn a core, so
kill it deliberately (`pkill -9 dd`) rather than leaving several behind. Four
accumulated during this investigation at ~20% CPU each.

**Diagnostic rule this cost me:** a process consuming CPU is working, not stuck. A
process blocked on I/O accumulates no CPU time. Check `ps -ef` CPU columns before
concluding anything is hung, and measure the throughput rate before deciding a
duration is unreasonable.

**`fmthard` cannot work here.** It asks the driver for geometry, `hsimd` does not
implement the ioctl (the familiar `WARNING: hsimd_ioctl: cmd 760b not
implemented`), so it computes nonsense and refuses:
`does not fit. The full disk contains 14087 sectors` -- that 14087 is the
CYLINDER count from the label. Same root cause as `format(1M)` rejecting the
disk. To change the VTOC, edit sector 0 from the host with `tools/vtoc.py` while
the VM is DOWN.

**`mkfs -F pcfs` needs `nofdisk`.** The `:c` suffix assumes an fdisk partition
table and fails with `No such logical drive (missing extended partition entry)`.
Correct form, and how the 496MB filesystem was made:

```
mkfs -F pcfs -o nofdisk,fat=32,size=1015808 /dev/rdsk/c0t0d0s3
```

### The 16MB scratch region at the tail of s3

`s3` is 512MB (1048576 blocks) but its FAT filesystem is now only 496MB
(1015808 blocks), so the last **16MB is outside any filesystem** and safe to
trample:

```
s3 block 1015808 .. 1048575          (guest: /dev/rdsk/c0t0d0s3)
absolute block 5210112 .. 5242879
absolute byte  2667577344 .. 2684354559
```

INVARIANT: anything that re-runs `mkfs -F pcfs` at the full 512MB destroys this.
`tools/exchange.sh mkfs` currently does exactly that -- fix it before using it
again, or the region silently disappears.

### Reading guest memory from the host: use the monitor, not /proc

`pmemsave` works and is fast. Two traps:

**Quote the filename** or the monitor parses it as part of the size expression:
`invalid char 't' in expression`. The monitor also echoes character-by-character
over a socket, which garbles naive line sends.

```
(printf 'pmemsave 0x80000000 1048576 "/tmp/out.bin"\r\n'; sleep 2) \
  | socat - UNIX-CONNECT:/tmp/sol-mon.sock
```

MEASURED cost: **~135 ms fixed + ~1.5 ms/MB.** 4KB=135ms, 1MB=150ms, 4MB=154ms,
16MB=160ms -- so marginal throughput is ~700MB/s and the payload is nearly free.
An earlier claim of "8.6MB/s" in this repo's history was WRONG: it measured a
`sleep 40` rather than the transfer.

Consequence: excellent for bulk reads, useless as a message channel, because
every round trip pays the 135ms floor (~7 msg/s).

Guest RAM is at physical **0x80000000**, not 0. Other bases in `niagara.c`:
`HV_RAM 0x100000`, `UART 0x1f10000000`, `NVRAM 0x1f11000000`,
`MD_ROM 0x1f12000000`, `VDISK 0x1f40000000`, `IOB 0x9800000000`.

### Guest console: do not let a pty close under it

If a driving process closes the console pty, the shell gets SIGHUP and SMF's
`console-login` does NOT respawn it. The result is a guest that is fully alive --
kernel executing, PC in kernel text, a full host core busy -- and completely
unreachable: no console, no shell, and no network if PPP was not up. Recovery is
a restart. `tools/net-up.sh`'s expect closes the pty by design after handing off
to PPP, which is safe ONLY because PPP then owns the line.

### What is installed in the guest now

- gcc 4.3.3 + GNU as/ld 2.21.1, 254 headers, crt objects -- verified compiling
- **bash 3.2** (`/usr/bin/bash`) and **Sun_SSH 1.1** (`/usr/lib/ssh/sshd`),
  native Solaris packages, all under the SUNW_1.22.1 ceiling (bash 1.22,
  ssh 1.19, sshd 1.21). Needed two libraries the image lacked:
  `libmd.so.1` from SUNWcslr and `libwrap.so.1.0` from SUNWcsl (both to
  `/usr/sfw/lib`, with `LD_LIBRARY_PATH=/usr/sfw/lib`).
- A modern client needs legacy algorithms to reach that sshd:
  `ssh -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa
  -o PubkeyAcceptedAlgorithms=+ssh-rsa root@10.0.5.15`
- perl 5.8.4, and `tools/guest-pinetd.pl` serving telnetd
- **NOT installed** (staged at `/tmp/devtools.tar`, ~1.5MB): SUNWbtool, SUNWsprot,
  SUNWtoo, SUNWgzip, SUNWgmake, SUNWesu -- i.e. `make`, `gmake`, `ar`, `ranlib`,
  `nm`, `gzip`, `ldd`, `od`, `strings`, `lex`, `yacc`. Needed for P2-007.

### 40GB NFS share

`datapool/niagara/share` (quota 40G) at `/export/solaris`, exported
`10.0.5.15/32(rw,sync,no_subtree_check,no_root_squash,insecure)`, mounted in the
guest as `/share`:

```
mount -F nfs -o vers=3,proto=tcp,rsize=8192,wsize=8192 10.0.5.1:/export/solaris /share
```

Verified bidirectional and byte-exact. BUT it runs at ~11KB/s over PPP, so it is
for convenience, not bulk -- a 3.7MB install took ~7 minutes. Hypervisor source
is staged there at `/share/hv/src` (198 files, 10593029 bytes, byte-identical).

### How fast is the guest, actually? ~3.7x slower than native

MEASURED 2026-08-18, identical C with `unsigned int` so host and guest do the
same 32-bit arithmetic (`unsigned long` would not: 64-bit on x86-64, 32-bit in a
SPARC32 binary). 500M iterations of `s += i ^ (i >> 3)`, gcc -O2 both sides,
same result `2132397440`:

```
host  (Xeon E5-2690 v3):  0.35 - 0.39 s
guest (TCG sun4v):        1.4 s          -> ~3.7x slower
```

**Do NOT call this a "5 MHz" machine.** The MD declares
`clock-frequency = 5000000` / `stick-frequency = 5000000`, so `prtconf` and the
boot log report 5 MHz -- but that is a DECLARATION, not throughput. It controls
what the guest reports about itself and how it calibrates spin delays like
`drv_usecwait()`; a low value there is arguably helpful, since delay loops come
out short. Effective compute is ~360M simple ops/sec, call it 700 MHz-class.

TCG gets close to native on tight integer code because the translation is a few
near-native x86 instructions per guest instruction. What makes the guest FEEL
slow is everything else:

| operation | cost | bound by |
|---|---|---|
| 500M integer ops | 1.4s | CPU, only 3.7x down |
| trivial gcc compile+run | ~10s | process startup, syscalls, small-file I/O |
| 3.7MB tar over NFS | ~7 min | the PPP link at ~11 KB/s |

Planning consequence: a q.bin build (P2-007) will NOT be CPU-bound, so SMP
(P3-007) buys less than fixing the I/O path (P2-013, ~11 MB/s through the shared
region). Benchmark only when `uptime` is quiet -- under load average 170 the
guest starved so badly that raw `dd` stopped returning.

### CHECKPOINTING A RUNNING SESSION

You no longer need a clean shutdown to keep work:

```
sudo bash tools/checkpoint.sh            # quiesce + msync + snapshot
sudo bash tools/checkpoint.sh mywork     # ... and snapshot as @mywork
kill -USR2 <qemu-pid>                    # msync only, no snapshot
NIAGARA_SYNC_SECS=120 ...                # unattended periodic msync
```

SIGUSR2, not SIGUSR1 — QEMU uses SIGUSR1 as SIG_IPI to kick CPU threads and
swallows it.

**What P2-012 changed here: durability no longer needs a checkpoint.** The kernel
writes dirty pages back on its own schedule, verified by writing a file over
telnet and then `kill -9`-ing QEMU with no `atexit` path in the binary at all —
the file was in the image afterwards. `msync` now buys a KNOWN durability point,
not durability that was otherwise absent.

A mid-run flush is still crash-consistent only, so `checkpoint.sh` quiesces the
guest first with `sync; lockfs -f /` over telnet. Verify any checkpoint boots
before trusting it.

### EXIT PROCEDURE — quiesce, then stop QEMU

```
guest:  sync; lockfs -f /          (or `init 5`, waiting for "syncing ... done")
host:   kill -TERM <qemu-pid>
```

**SIGTERM is no longer load-bearing for data.** There is no `atexit` writeback to
run, so `kill -9` does not lose the disk — it only risks catching the guest
mid-transaction. The reason to quiesce is CONSISTENCY, not durability.

**Do not rely on `Ctrl-A c` from a scripted expect.** It does not reach QEMU:
with no `interact`, expect delivers `\x01c` to the guest, which echoes it
verbatim at the OBP prompt (observed as `ok s^Ac`) while expect waits forever
for a `(qemu)` prompt that never comes. Interactively it is fine; in a script,
signal the pid.

**Never kill a guest sitting at a shell prompt without quiescing.** Doing so
persists a dirty LUFS journal and the next boot panics (trace below). This was
re-learned the hard way: a killed session was snapshotted, and every clone of
that snapshot panicked in `vfs_mountroot`. Recovery was to roll back to the
last cleanly-shut-down snapshot and redo the work, since the payloads were all
reproducible from `tools/` — which is the reason to keep them reproducible.

**`lockfs -f / && sync` alone is NOT sufficient** if the guest keeps running. It
flushes, but the shell, syslog and atime updates keep writing afterwards, so the
journal is dirty again moments later. The next boot then panics replaying it:

```
BAD TRAP type=10  addr=0x300005e7840
  ufs:readlog -> ufs:fetchbuf -> ufs:ldl_read -> ufs:lufs_read_strategy
  -> ufs:ufs_getpage_miss -> vfs_mountroot
```

`init 0` unmounts the filesystems properly, closing that window. Verified with a
two-pass test: write a marker, `init 0`, quit; then boot again — marker present,
no panic. `lockfs` is still worth running before long-lived sessions, but it is
not a substitute for a real shutdown.

Recover a panicking disk with `./run-solaris.sh reset`.

## Known gaps

1. **No networking.** The Niagara machine has no PCI or virtio bus. OBP lists
   `net -> /virtual-devices/network@0` in `devalias` but no such node exists in
   the device tree and QEMU backs nothing. `iscsi` and `scsi_vhci` are loaded
   and force-attached in the guest, waiting for a network that isn't there.

2. **`format(1M)` refuses the disk.** It reports
   `controller name (SUNW,sun4v-virtual) is invalid`. `format` validates
   against a compiled-in controller table containing only `SCSI`, `ata`,
   `pcmcia`; this cannot be fixed via `/etc/format.dat` (the `ctlr` field there
   is a controller *class*, not a name). `iostat -En` is also blank for the same
   reason. Use `fmthard`, `newfs`, `prtvtoc`, and `dd`, which don't consult it.

3. **No second serial (`ttyb`) — blocked in the guest, not fixable from here.**
   Adding a `console@4` node to the MD works: OBP enumerates it
   (`show-devs` lists `/virtual-devices@100/console@4`). But Solaris will not
   bind a driver to it — `prtconf` shows `console (driver not attached)` and
   `/dev/term/` still has only `a`. Cause, from illumos
   `usr/src/uts/sun4v/io/qcn.c`: line 347 *"There is only once instance of this
   driver"*, and line 87 `static qcn_t *qcn_state;` — one global, not
   per-instance. `qcn` is a singleton by construction. Fixing it means
   rebuilding the guest driver, which needs a compiler in the guest, which is
   circular. The node stays in `md/common.pdesc`, documented, and the
   regenerated MD is deliberately NOT installed. Superseded by the exchange
   slice below.

4. **`test-reboot-obp-intact` is weak AND flaky.** It intermittently times out
   waiting for the login prompt (seen once in five runs). It matches `"ok"` and then
   `"disk"` in `devalias` output, both of which appear in plenty of unrelated
   output. It passes, but it is not strong evidence OBP is truly healthy after
   a reboot. The guest still prints
   `panic - kernel: prom_reboot: reboot call returned!` on reboot.

5. **`exchange` zvol — DESTROYED 2026-08-17, reclaimed 569MB.** It was an early
   FAT32 attempt on a *second* `-drive`, which Solaris cannot see without an MD
   node (and q.bin tracks only one disk anyway — a single `disk_pa` in
   `vdev_simdisk.s`). Superseded by the exchange *slice*.

   **Read that reason narrowly.** What failed was the *second drive*, not FAT.
   Putting a FAT32 filesystem on **slice 3 of the one disk we already have** is
   a different proposition and is strictly better than the current raw
   `dd`+`tar` channel, because it is bidirectional and random-access:

   - Host side is **verified working**: `mkfs.vfat -F 32` on a loop device at
     offset `4194304*512`, length 512MB, mounted `rw`, files written, unmounted,
     remounted, read back. 2.25s, no boot. Linux vfat read-write support is
     solid, unlike UFS.
   - Guest side is **VERIFIED** too: `mount -F pcfs /dev/dsk/c0t0d0s3:c /x`
     works on the FIRST try with a Linux-made FAT32 — no geometry tweaking, no
     fallback form needed. Solaris reports it as
     `/dev/dsk/c0t0d0s3:c  523244 kbytes  1% /x`. The only noise is a harmless
     `WARNING: hsimd_ioctl: cmd 760b not implemented` as pcfs probes an ioctl
     the RAM-disk driver lacks; the mount succeeds regardless.
     Guarded by `test-fat-exchange`.

   Note the host CANNOT write the guest's UFS root: this kernel has
   `CONFIG_UFS_FS=m` but no `CONFIG_UFS_FS_WRITE`, so `ufs.ko` is read-only by
   construction — an `rw` mount attempt is silently downgraded to `ro` and
   writes fail with EROFS. Host reads are fine (`tools/peek.sh`). Writing the
   root FS from the host would need a rump kernel or a NetBSD VM; see BACKLOG.

## Toolchain

Snapshot: `primary@toolchain-working`. Guarded by `test-toolchain-compiles`.

```
gcc 4.3.3   /opt/csw/gcc4/bin/gcc          (target sparc-sun-solaris2.8)
as, ld      /opt/csw/sparc-sun-solaris2.9/bin/   (GNU binutils 2.21.1)
```

**The 2.8/2.9 mismatch is the whole problem.** gcc was built for
`sparc-sun-solaris2.8` but its binutils are installed under `solaris2.9`, so
gcc cannot find its assembler and dies with:

```
gcc: error trying to exec 'as': execvp: No such file or directory
```

Fixed permanently by symlinking into gcc's own private exec dir, which it
searches before PATH:

```
cd /opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3
ln -s /opt/csw/sparc-sun-solaris2.9/bin/as as
ln -s /opt/csw/sparc-sun-solaris2.9/bin/ld ld
```

`-B/opt/csw/sparc-sun-solaris2.9/bin/` also works but only per-invocation, so
it breaks anything that calls `gcc` for you (configure scripts, makefiles).

### Where the headers came from

`/usr/include` shipped with only 12 third-party entries — no `stdio.h`. Now 254.

| package  | supplies                                              | media |
|----------|-------------------------------------------------------|-------|
| SUNWhea  | `stdio.h`, `stdlib.h`, `string.h`, `unistd.h`, + 1200  | CD5   |
| SUNWarc  | `crti.o`, `crtn.o`, `values-*.o` (+ `sparcv9/`)        | CD5   |
| SUNWlibm | `math.h`, `floatingpoint.h`, `iso/math_*.h`, `ieeefp.h`| CD5   |

**`math.h` is in SUNWlibm, NOT SUNWhea** — that cost a boot to discover.

**`crt1.o` is a red herring.** It is absent from SUNWhea/SUNWarc/SUNWarcr/
SUNWsprot, and it does not matter: gcc ships its own at
`/opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3/crt1.o`. Do not hunt for it
in Solaris media.

Extraction: these ISOs are *repacked*, so each package holds
`archive/none.7z` with an empty `reloc/`. Unwrap in two layers —
`7z x none.7z` yields a single file named `none`, which is a cpio archive:
`cpio -idm < none`. `tools/iso-extract.py` pulls a package straight out of a
remote ISO over HTTP range requests when the ISO is not local.

### libc version ceiling: `SUNW_1.22.1`

This image is `Generic_118822-23` (Solaris 10 3/05) and caps at `SUNW_1.22.1`.
OpenCSW's 2014 `SunOS5.10` builds need `SUNW_1.22.2` and die at load with
`ld.so.1: fatal: libc.so.1: version 'SUNW_1.22.2' not found`. **Always take
`SunOS5.8` or `SunOS5.9` builds.** Check before installing:

```bash
readelf -V <lib> | grep -oE 'SUNW_1\.[0-9.]+' | sort -uV | tail -1
```

## Driving the guest over the serial console

**Lines sent to the console MUST stay under 256 bytes.** The Solaris tty
canonical input buffer truncates anything longer *and drops the carriage
return*, so the command never executes and the session looks hung — the pane
shows a command cut off mid-word with no new prompt. `cd` into a directory and
use short relative paths instead of one long absolute command.

Two more things that make a live run look dead:

- **expect buffers `puts` when stdout is a pipe.** Start every expect script
  with `fconfigure stdout -buffering none`.
- **`| tail -N` buffers until the pipeline ends**, so a tmux pane stays blank
  for the whole run. Use plain `| tee logfile` when a human is watching, and
  set `VM_TRANSCRIPT` for tests (whose output is otherwise captured whole by
  `out=$(vm_run ...)` and only echoed at the end).
- **A helper that reports a missing prompt must ABORT, not continue.** Marching
  through ten dead commands at 20s each is how a permanent failure disguises
  itself as a five-minute hang. `tools/waitfor.sh` also fails fast now: if the
  log stops growing for `WAITFOR_STALL` seconds (default 45) without matching,
  it exits 3 and dumps the tail instead of waiting out the timeout.

## Inspecting the guest WITHOUT booting

```bash
sudo bash tools/peek.sh 'ls $MNT/opt/csw/bin'      # ~0.5s
sudo bash tools/peek.sh -s @baseline 'df -h $MNT'
sudo bash tools/peek.sh                            # interactive shell
```

Clones the dataset, mounts the clone's image read-only (`-o ro,loop,ufstype=sun`),
runs the command,
destroys the clone. 0.5s versus a ~60s boot. Use this for any read-only
question about the guest filesystem.

Do NOT mount the live image directly: a running guest dirties its pages
continuously, so you would read a torn, mid-transaction view. Formerly the whole
device on exit, so reading it races with that and can return a torn view. A
clone is a stable point-in-time image and is safe even while the VM runs.
Linux UFS write support for Solaris format is unreliable — to *change* the guest
filesystem, push a tar through `tools/exchange.sh`.

## Waiting for a VM run to finish

```bash
sudo expect /tmp/x.exp 2>&1 | tee /tmp/x.log &
bash tools/waitfor.sh /tmp/x.log 'Program terminated' 1800 'PANICKED|BOOT TIMEOUT'
```

Polls and returns the moment the marker appears. Do not use `sleep N` — it
wastes real time when the job finishes early and lies when it needs longer.
`vdisk writeback complete` NO LONGER EXISTS — P2-012 deleted the writeback. Match
`Program terminated` (the guest's own last word) or `vdisk synced` from an msync.

## Data channel (host -> guest bulk transfer)

q.bin serves the whole vdisk, and its size comes from VTOC slice 2's `nblk` at
offset 0x1d0. Slices are just byte offsets into that same disk — so an unused
slice is readable in the guest as `/dev/rdsk/c0t0d0sN` with **no new MD node,
no new QEMU device, no q.bin change and no new driver.**

```
s0  blocks       0 .. 4194295   2048MB  root UFS (untouched)
s3  blocks 4194304 .. 5242879    512MB  exchange, raw, no filesystem
s2  blocks       0 .. 5242879   2560MB  whole disk -> q.bin's served size
```

Host:
```bash
tools/exchange.sh setup datapool/niagara/vms/primary   # grow + lay out s3
tar cf payload.tar -C payload .
tools/exchange.sh push  datapool/niagara/vms/primary payload.tar
```
Guest:
```
dd if=/dev/rdsk/c0t0d0s3 bs=512 count=<blocks> 2>/dev/null | tar xvf -
```

Slice 2 MUST cover the exchange slice or q.bin will not serve those blocks —
`tools/vtoc.py verify` checks exactly that. `tools/vtoc.py` also recomputes the
label checksum at 0x1fe on every write; OBP validates it and rejects the disk
with "Bad checksum in disk label" if it is wrong, while QEMU does not check it.

Cost: the served size is allocated as anonymous host RAM, so a 2560MB disk uses
2560MB per running VM and moves that much on every boot and every clean exit.

Solaris `/bin/sh` is not POSIX — no `$(...)`. Use backticks in payload scripts.

## Environment

- Host: biggie (Linux x86_64, Xeon E5-2690 v3)
- QEMU: `./qemu/build/qemu-system-sparc64`, upstream 8.2.2 +
  `patches/0001-niagara-vdisk-writeback.patch`
- Firmware: `/datapool/niagara/base/` (openboot.bin, q.bin, nvram1, 1up-*.bin)
- Hypervisor + MD source: `~/vms/opensparc/`
- MD source of record: `~/vms/opensparc/legion/src/config/niagara/{1up,common}.pdesc`
- Repo: `http://biggie:3000/ryan/niagra-qemu-solaris-project`

### ZFS layout

```
datapool/niagara/base                    firmware ROMs (filesystem)
datapool/niagara/images                  disk dataset, recordsize=8K + lz4
datapool/niagara/images/primary.img      THE DISK (2560MB, MAP_SHARED)
datapool/niagara/images@baseline         test + reset baseline   <-- DEFAULT
datapool/niagara/images@pre-mapshared    first copy off the zvol
datapool/niagara/<name>-<pid>            ephemeral test/peek clones (DATASETS)

datapool/niagara/vms/primary             PRE-P2-012 zvol, kept as a fallback
datapool/niagara/vms/primary@pre-p2012-cutover   state at the moment of cutover
```

**Clones are dataset clones**, so the image file comes along:
`zfs clone .../images@baseline .../test-x` gives
`/datapool/niagara/test-x/primary.img`. Instant, no extra space, identical
semantics to the old zvol clones — the review's key correction was that files lose
nothing here.

`recordsize=8K` because `MAP_SHARED` writeback is 4K-page granular and ZFS's 128K
default would turn each dirtied page into a 128K read-modify-write. With lz4 the
image is **585M on disk against 2.5G apparent**.

The old zvol at `vms/primary` is retained deliberately as a rollback path. It is
not used by anything and can be destroyed once the file stack has proven itself
over a few sessions.

**All disk paths go through `img_require()` in `tools/lib/image.sh`.** Nothing
reconstructs the path itself — six tools each building `/dev/zvol/$ds` is how a
literal `2668003328`, wrong by 832 blocks, got hardcoded into `niagara.c`. Handed
a zvol, `img_require` refuses with the `dd` conversion spelled out.

## Operating it

```bash
./run-solaris.sh            # boot the image (takes the lock)
./run-solaris.sh status     # dataset/snapshot state + lock holder
./run-solaris.sh reset      # rollback to @baseline
sudo bash tools/net-up.sh   # boot WITH networking, then: telnet 10.0.5.15
sudo bash tools/net-down.sh # tear it down  (--rollback to discard the session)
sudo bash tools/peek.sh 'ls $MNT/opt/csw'   # inspect the FS, no boot, ~0.6s
sudo bash tools/checkpoint.sh [snapname]    # quiesce + msync + snapshot
sudo bash tests/run-all.sh                  # full suite, 7 tests
sudo bash tests/reap-orphans.sh             # reclaim clones AND loop devices
bash tools/exchange.sh scratch              # sourceable scratch-region offsets
bash tools/build-mdgen.sh                   # build the MD compiler
```

Run VM work in the `sparc` tmux session so it is watchable:
`~/bin/sane-send-keys sparc "<cmd>" Enter`.

## Toolchain status: WORKING — compiles, links, runs

`gcc (GCC) 4.3.3` runs in the guest at `/opt/csw/gcc4/bin/gcc`, with GNU
`as`/`ld` 2.21.1 symlinked into gcc's exec dir. Snapshots:
`primary@toolchain-working`, and every later snapshot inherits it.

**Verified end to end** (re-confirmed 2026-08-18 over telnet against the live
guest, not inferred):

```
# cat > r.c   ... #include <stdio.h> <stdlib.h> <string.h> <math.h>
#              ... malloc, strcpy, sqrt, strlen
# /opt/csw/gcc4/bin/gcc -O2 -o r r.c -lm && ./r
REVIEW 1.41421 6
# file r
r: ELF 32-bit MSB executable SPARC32PLUS Version 1, V8+ Required,
   dynamically linked, not stripped
```

`/usr/include` now has **262 entries** including `stdio.h`, `stdlib.h`,
`string.h`, `unistd.h`, and `math.h`. crt objects (`crti.o`, `crtn.o`,
`values-*.o`) are in `/usr/lib` and `/usr/lib/sparcv9`.

Installed from packages extracted off the Solaris 10 3/05 media: `SUNWhea`
(1217 headers), `SUNWarc`, `SUNWarcr`, `SUNWlibm` (`math.h`,
`floatingpoint.h`, `iso/math_c99.h`, `iso/math_iso.h`, `sys/ieeefp.h`).

**`crt1.o` was never needed** — that hunt was a dead end. gcc ships its own at
`/opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3/crt1.o`, so plain `gcc` links
with no `-B` flag required.

### HOST-SIDE printf will silently corrupt guest C source

Burned twice, so it is recorded here. Generating a `.c` file with a host
`printf '...'` lets the HOST shell consume `%s`, `%d`, `%.5f` as its own format
specifiers. The file that lands in the guest has them substituted away, gcc
compiles it happily, and the program prints garbage — which looks exactly like a
broken compiler. First occurrence produced `SQRT2=%.4F` baked in as a literal;
second produced ` 0.00000 0` instead of `REVIEW 1.41421 6`.

Use a quoted heredoc (`cat > r.c <<'XEOF'`) or double every `%`. If a freshly
compiled program prints zeros or empty strings, suspect the harness before the
toolchain.

### Still not installed (staged at `/tmp/devtools.tar`, ~1.5MB)

`SUNWbtool`, `SUNWsprot`, `SUNWtoo`, `SUNWgzip`, `SUNWgmake`, `SUNWesu` — i.e.
`make`, `gmake`, `ar`, `ranlib`, `nm`, `gzip`, `ldd`, `od`, `strings`, `lex`,
`yacc`. Needed for P2-007 (building q.bin in-guest), not for ordinary compiling.
Note `strings` and `od` being absent has broken verification commands before.

### libc version ceiling (important for any future OpenCSW package)

This image's `libc.so.1` provides up to **`SUNW_1.22.1`**.

OpenCSW's 2014-era `SunOS5.10` builds require **`SUNW_1.22.2`** and fail at
runtime with:
```
ld.so.1: gcc-4.9: fatal: libc.so.1: version `SUNW_1.22.2' not found
```
Always prefer **`SunOS5.8` / `SunOS5.9`** builds from
`http://mirror.opencsw.org/opencsw/allpkgs/` — they need only symbols this libc
has. Check any candidate with:
```bash
readelf -V <lib> | grep -oE 'SUNW_1\.[0-9.]+' | sort -uV | tail -1
```
`libz.so.1` from CSWlibz1 (2013) is one of the casualties; Solaris' own
`/usr/lib/libz.so.1` needs only `SUNW_1.1` and works, so symlink to that.

## Next actions

1. **Resolve system headers + crt objects** (see above) — this is the only thing
   standing between us and a working build environment.
2. **Get a compiler in.** The channel exists and is tested. Fetch gcc4core +
   deps from OpenCSW (`http://mirror.opencsw.org/opencsw/stable/sparc/5.10/`,
   ~137MB compressed) — note the 512MB exchange slice holds it, but check the
   installed size against the 1.6GB free. Then `pkgadd -d` from the extracted
   payload. First thing to build once it works: a `format(1M)` that does not
   reject the `SUNW,sun4v-virtual` controller name (Known gaps #2).
2. **Strengthen and de-flake `test-reboot-obp-intact`** so it asserts something
   real and stops timing out.
3. `ttyb` is parked — blocked on the qcn singleton (Known gaps #3).
