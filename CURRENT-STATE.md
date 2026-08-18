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
because each one loads 2-2.5GB into RAM and writes it back on exit. Each VM test clones its own throwaway zvol from
`primary@clean-2gb` and destroys it on exit, so tests cannot corrupt each
other or the daily driver.

## What works

- **Solaris 10 boots** to a login prompt in ~40s. Root, no password.
- **Disk writes persist.** Verified end-to-end: write to `/etc`, clean exit,
  canary found in the raw zvol, then a *second boot* reads the file back and
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
  always breaks OBP -- so treat such sessions as disposable and roll back.
- **Bidirectional host <-> guest file exchange** via FAT32 on VTOC slice 3.
  Host mounts it with `mount -t vfat` on a loop device, guest with
  `mount -F pcfs /dev/dsk/c0t0d0s3:c`. Verified with two exact `cksum` matches
  on the same 256KB of random data — host->guest and guest->host
  (`test-fat-exchange`). Drive it with `tools/exchange.sh mkfs|put|get|ls`.
  Guest writes reach the host only after `init 5` + the atexit writeback.
- **Bulk host -> guest data channel** via a raw VTOC slice. Verified
  byte-for-byte: a 256KB random binary transfers with a matching `cksum`
  (`test-exchange-channel`). See "Data channel" below.

## How storage actually works

Guest writes go:

```
UFS -> hcall_disk_write (0xf1) -> q.bin -> vdisk_ram (host RAM)
                                              |
                          QEMU atexit handler | pwrite in 64MB chunks
                                              v
                                    zvol (persistent)
```

Confirmed by direct measurement: after a guest write, the canary is present
in QEMU's `vdisk_ram` region read live from `/proc/<pid>/mem` (the 2GB
writable mapping whose first bytes are the `SUN...` disk label).

q.bin uses **direct hypercalls (0xf0 read / 0xf1 write), not LDC.** There is
no LDC implementation in the hypervisor source. This resolves the old open
question in the backlog (P1-005).

### EXIT PROCEDURE — `init 5`, then SIGTERM the QEMU pid

```
init 5                     (inside Solaris; wait for "syncing file systems... done")
kill -TERM <qemu-pid>      (NOT SIGKILL; atexit writeback runs on a normal exit)
```

Confirm success by seeing this in the transcript:
`niagara: vdisk writeback complete (2560 MB)`.

**Do not rely on `Ctrl-A c` from a scripted expect.** It does not reach QEMU:
with no `interact`, expect delivers `\x01c` to the guest, which echoes it
verbatim at the OBP prompt (observed as `ok s^Ac`) while expect waits forever
for a `(qemu)` prompt that never comes. Interactively it is fine; in a script,
signal the pid. `$vm_halt_writeback_fragment` in `tests/lib/vm.sh` does this.

**Never SIGKILL, and never kill a guest sitting at a shell prompt.** Doing so
persists a dirty LUFS journal and the next boot panics (trace below). This was
re-learned the hard way: a killed session was snapshotted, and every clone of
that snapshot panicked in `vfs_mountroot`. Recovery was to roll back to the
last cleanly-shut-down snapshot and redo the work, since the payloads were all
reproducible from `tools/` — which is the reason to keep them reproducible.

**`lockfs -f / && sync` is NOT sufficient** and was the cause of repeated
corruption. It flushes, but the shell, syslog and atime updates keep writing in
the window before QEMU is yanked, so the LUFS journal is dirty again by the time
the atexit writeback runs. The next boot then panics replaying it:

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
sudo bash tools/peek.sh -s @clean-2gb 'df -h $MNT'
sudo bash tools/peek.sh                            # interactive shell
```

Clones the zvol, mounts the clone read-only (`ufstype=sun`), runs the command,
destroys the clone. 0.5s versus a ~60s boot. Use this for any read-only
question about the guest filesystem.

Do NOT mount the live zvol directly: QEMU's atexit writeback rewrites the whole
device on exit, so reading it races with that and can return a torn view. A
clone is a stable point-in-time image and is safe even while the VM runs.
Linux UFS write support for Solaris format is unreliable — to *change* the guest
filesystem, push a tar through `tools/exchange.sh`.

## Waiting for a VM run to finish

```bash
sudo expect /tmp/x.exp 2>&1 | tee /tmp/x.log &
bash tools/waitfor.sh /tmp/x.log 'vdisk writeback complete' 1800 'PANICKED|BOOT TIMEOUT'
```

Polls and returns the moment the marker appears. Do not use `sleep N` — it
wastes real time when the job finishes early and lies when it needs longer.
`vdisk writeback complete` is the patched QEMU's last action on a clean exit.

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
datapool/niagara/vms/primary             daily driver zvol
datapool/niagara/vms/primary@clean       pristine 512MB original image
datapool/niagara/vms/primary@clean-2gb   1.9GB UFS, 1.6GB free   <-- baseline
datapool/niagara/vms/test-<name>-<pid>   ephemeral test clones
```

`zfs rollback` reverts `volsize` to the snapshot's value. `@clean-2gb` was
taken at `volsize=2G` with a matching 2GB VTOC, so it is self-consistent and
needs no re-grow. `primary` is currently 3G (grown during the FAT32
experiment); `./run-solaris.sh reset` returns it to 2G.

## Operating it

```bash
./run-solaris.sh            # boot primary (takes the zvol lock)
./run-solaris.sh status     # zvol/snapshot state + lock holder
./run-solaris.sh reset      # rollback primary to @clean-2gb
sudo bash tests/run-all.sh          # full suite
sudo bash tests/reap-orphans.sh     # reclaim leaked test clones
bash tools/build-mdgen.sh           # build the MD compiler
bash tools/gen-md.sh src.pdesc out.bin
```

## Toolchain status: compiler installed, blocked on system headers

`gcc (GCC) 4.3.3` **runs in the guest** at `/opt/csw/gcc4/bin/gcc`, with
`as`/`ld` at `/opt/csw/sparc-sun-solaris2.9/bin/`. Snapshot: `primary@gcc-planted`.

**Blocker: this minimal image has no libc headers and no crt objects.**
```
/usr/include   12 entries — bzlib.h, dtrace.h, zlib.h, libxml2, partial sys/ ...
               NO stdio.h, stdlib.h, string.h, unistd.h, math.h
/usr/lib/crt1.o  MISSING
```
`SUNWhea` (headers) and the crt/startup objects were never installed. So:
`gcc hello.c` fails at `stdio.h: No such file or directory`, and even with
headers it could not link without `crt1.o`.

Options, roughly in order of practicality:
1. **A Solaris 10 3/05 SPARC install ISO** — gives `SUNWhea`, `SUNWarc`,
   `SUNWlibms`, `SUNWbtool` properly via `pkgadd`. Large download, but correct
   and complete. This is the clean fix.
2. **illumos-gate headers** — `usr/src/head/*.h` and `usr/src/uts/common/sys/`
   are the direct descendants of these exact headers (CDDL). Assemble a
   `/usr/include` tree and push it via the exchange slice. Version skew is a
   risk. Does not solve `crt1.o`, though illumos has the source
   (`usr/src/lib/crt/`) and the guest now has `as`, so it could be bootstrapped.
3. Hand-rolled minimal headers — fragile, wrong, not worth it.

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
