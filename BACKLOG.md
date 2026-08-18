# Backlog

Priority: P1 (blocking) → P2 (important) → P3 (nice to have)
Status: [ ] todo, [~] in progress, [x] done

---

## P1 — Blocking

### P1-001: Implement ZFS storage layer and test isolation [x] DONE

The test suite currently assumes flat raw files. It must be rewritten around
zvols before any test can run safely on a live host.

Deliverables:
- `tests/zfs-setup.sh` — idempotent provisioning script
  - creates `datapool/niagara/`, `datapool/niagara/base`,
    `datapool/niagara/vms/`
  - imports `disk.s10hw2` into `datapool/niagara/vms/primary` zvol (512MB)
  - takes `primary@clean` snapshot
- `tests/lib/lock.sh` — acquire, release, check primitives
  - lockfile at `/run/niagara-<zvol-name>.lock` containing PID
  - check verifies PID is still alive before refusing
  - acquired before any QEMU open, released via trap on exit
- `tests/lib/zvol.sh` — clone, destroy, path resolution
  - clone: `zfs clone primary@clean → vms/test-<name>-<pid>`
  - path: `/dev/zvol/datapool/niagara/vms/<name>`
  - destroy: `zfs destroy` after lock released
- `tests/lib/vm.sh` — boot QEMU with lock held; expect interaction helpers
  - wraps QEMU invocation, holds lock for process lifetime
  - exits QEMU via monitor `quit` command (not SIGKILL) to ensure flush
- Rewrite `tests/test-*.sh` on top of new lib
- Rewrite `run-solaris.sh` to use lock + primary zvol

Acceptance: `sudo bash tests/run-all.sh` completes without corrupting any zvol,
even if interrupted mid-run (trap cleanup verified by killing the test process
mid-flight and confirming no lock file remains and the clone is destroyed).

### P1-002: Build patched QEMU and verify disk write fix [x] DONE

**RESOLVED.** `test-disk-writes-persist` passes: write to /etc, clean exit,
canary found in raw zvol, second boot reads it back. Storage is trustworthy.


Depends on: P1-001 (need test-disk-writes-persist running against a zvol)

- Apply `patches/0001-niagara-vdisk-ram-shared.patch` to `./qemu/`
- Build sparc64-softmmu target only: `./configure --target-list=sparc64-softmmu && make -j$(nproc)`
- Run `test-disk-writes-persist` against patched binary
- Expected: PASS (canary found in zvol via `strings /dev/zvol/...` after QEMU
  exits cleanly via monitor `quit`)
- Commit patch as proper `git format-patch` output with full explanation

Acceptance: `QEMU_BIN=./qemu/build/qemu-system-sparc64 sudo bash tests/run-all.sh`
shows test-disk-writes-persist PASS with observed canary string in output.

---

## P2 — Important

### P2-001: Fix OBP trap after guest reboot [ ]

Depends on: P1-001

Root cause: QEMU Niagara machine has no `machine_reset` handler. When the
guest calls `prom_reboot`, control returns to OBP firmware but the CPU's
MMU context (TLBs, trap base register) from the running kernel is still live.
OBP's first memory access takes an MMU miss trap, which OBP cannot handle.

Investigation plan:
- Read `hw/sparc64/niagara.c` for the reset code path (or absence of one)
- Compare with `hw/sparc64/sun4m.c` or `hw/sparc64/sun4u.c` reset handlers
  for the minimum CPU state that must be restored
- At minimum: TBA (trap base address register) must be reset to OBP's value;
  TLBs must be flushed

Test: `test-reboot-obp-intact.sh` must PASS.

### P2-002: Networking via PPP over serial [ ]

Depends on: P1-001, ideally P1-002 (persistent disk for pppd config)

The Niagara machine has no PCI or virtio bus, so standard NIC attachment
doesn't work. The serial port is the only available channel.

Plan:
- QEMU exposes the guest's serial device via `-serial` — can be a pipe,
  PTY, or socket on the host
- Guest: configure Solaris `pppd` over `/dev/ttya`
- Host: run Linux `pppd` against the other end of the pipe/PTY
- Result: a point-to-point IP link; full TCP/IP connectivity via `ppp0`

This is the fastest path to any networking. No QEMU machine changes required.

Test: from inside guest, `ping <host-side ppp IP>` succeeds.

**Refined plan (2026-08-17). Do NOT compile slirp.**

Artyom Tarasenko's OpenSolaris recipe compiles `slirp` and runs it IN the guest,
because his snv_77 image had no PPP. Ours does not need that: Solaris ships its
own PPP, and all of it is on CD1.

Recon results (`tools/peek.sh`):
- Guest has NO PPP at all: no `pppd`, no `chat`, no `/etc/ppp`, no `sppp`
  kernel modules, no ppp STREAMS modules.
- Guest DOES have `inetd`, `in.telnetd`, `in.ftpd`, `in.rshd`. So once IP
  exists, login and file transfer need nothing further installed.
- Only one serial device node exists: `/dev/term/a`.

Packages needed, all on CD1:
| package | supplies |
|---|---|
| `SUNWpppd` | `usr/kernel/drv/sparcv9/sppp`, `sppptun`, `sppp.conf`, `usr/kernel/strmod/sparcv9/spppasyn`, `spppcomp` |
| `SUNWpppdu` | `usr/bin/pppd`, `chat`, `pppstats`, `asppp2pppd` |
| `SUNWpppdr` | `/etc/ppp` templates, `etc/init.d/pppd` |

Using official packages rather than a compiled slirp means matching kernel
modules for this exact kernel, and no build risk.

**Status: payload built and staged.** All three extracted to
`/tmp/sunfiles/SUNWppp*`, unioned with a hand-written `/etc/ppp/options`
(`noauth nodetach local passive 115200`), tarred to 563200 bytes, and pushed to
the FAT slice as `ppp.tar`. `tools/provision-ppp.exp` installs it, runs
`add_drv sppp`, and verifies the 2005 `pppd` binary executes — deliberately
WITHOUT starting a link, see below.

**SOLVED: use `pppd notty`. Verified 2026-08-17.**

`/dev/console` is the `cn` -> `qcn` pseudo-device, and pppd cannot link it:

```
serial speed set to 115200 bps
Can't link tty to PPP mux: Invalid argument      <- STREAMS I_LINK, EINVAL
```

Both `pppd /dev/console 115200 ...` and `pppd 115200 ...` (controlling tty) fail
this way. pppd opens the tty and sets the speed, then the STREAMS link of the tty
stream under the sppp mux is rejected, because qcn provides no linkable serial
STREAMS stack. Structural, not configuration -- do not keep tuning options.

**`pppd notty` works.** It speaks PPP on stdin/stdout instead of manipulating the
tty's STREAMS stack, which sidesteps qcn entirely. Confirmed by real HDLC frames
on the console (`7e` delimiters, `7d` escapes, LCP Configure-Requests):

```
~\xff}#\xc0!}!}) } }4}"}&} } } } }%}&Y...~
```

and by the stack engaging -- `spppasyn (PPP 4.0 AHDLC v1.5)` and `spppcomp`
loaded, where previously only the mux was. Exit 16 was our own watchdog signal.
`ifconfig` showed only `lo0` because no peer was answering LCP.

So the link is asymmetric, which PPP does not mind:
- **guest**: `pppd notty ...` (qcn cannot be I_LINKed)
- **host**: `pppd /dev/<pty> ...` on a socat pty (Linux pppd links a real pty fine)

Host plumbing: run QEMU with `-serial unix:/tmp/sol.sock,server,nowait` and keep
ONE persistent `socat UNIX-CONNECT:/tmp/sol.sock PTY,link=...,raw` bridge up for
the whole session. Drive boot/login over the pty, start the guest's `pppd notty`,
then attach the host pppd to the SAME pty. The bridge must persist, otherwise the
guest sees its console close and pppd exits.

**Methodology note worth keeping.** The first attempt at this drove pppd directly
from expect and wedged: pppd leaves the line in raw mode, where CR is no longer
translated to NL, so `send "cmd\r"` never terminates a line and the session looks
hung. It then died without `init 5` and persisted a dirty journal, costing a
rollback to `@ppp-installed`. The fix that worked: put ALL fragile tty work in a
guest-side script (`tools/guest-ppp-probe.sh`) that recovers the tty itself with
`stty sane`, writes its results to the FAT slice, and runs `init 5` on its own.
Expect then only boots, hands off, and waits for the halt; the host reads results
off the slice afterwards. That is what the bidirectional channel (P2-005) is for.

**IP CONNECTIVITY ACHIEVED 2026-08-17.** LCP and IPCP negotiated in both
directions over the qcn console. Host pppd log:

```
rcvd [LCP Ident id=0x5f magic=0x508868dd "ppp-2.4.0b1 (Sun Microsystems, Inc.)"]
rcvd [IPCP ConfAck id=0x1 <addr 10.0.5.1>]
rcvd [IPCP ConfReq id=0x19 <addr 10.0.5.15>]
local  IP address 10.0.5.1
remote IP address 10.0.5.15
```

Host got `ppp0: inet 10.0.5.1 peer 10.0.5.15/32`, and **the guest answered
pings** — but only small ones:

| ICMP payload | result |
|---|---|
| 8 B  | reply |
| 16 B | reply |
| 32 B and up | no reply, `ppp0 RX errors` increments |

**Diagnosis: the qcn console is not 8-bit clean.** We negotiated
`asyncmap 0x0` (escape nothing). ICMP payloads are incrementing byte patterns,
so once long enough they contain control characters -- `0x11`/`0x13` (XON/XOFF),
`0x0d` -- which the console path mangles, so the frame fails FCS and is dropped.

**FIXED AND VERIFIED: `asyncmap 0xffffffff` on both ends.** Escapes all control
characters, so nothing in the payload can be eaten by the console path. Result:

| ICMP payload | before | after |
|---|---|---|
| 8 B, 16 B | reply | reply |
| 32 B ... 1400 B | **all failed** | **all reply** |

`ppp0 RX errors` went from 2 to **0**. Sustained test: 20 packets of 500B,
**0% loss**, rtt min/avg/max 52/80/168 ms; idle rtt ~17ms once nothing else was
running. The link is real and carries full-size frames.

**But two things stop this being a usable networked machine yet:**

1. **No TCP service answers.** Ports 21, 23, 79, 111, 512, 513, 514, 540, 7, 13
   all closed. `inetd` is not running and the telnet service is not enabled
   (`svcs -a | grep telnet` was empty). So the link carries IP but there is
   nothing to log into. **Enable inetd/telnet BEFORE handing the console to PPP**
   -- otherwise you have a link you cannot administer over, and a console you
   cannot reach because pppd owns it.
2. **A PPP session cannot currently be ended cleanly.** REPRODUCIBLE: `init 5`
   from the detached watchdog, after pppd is killed and `stty sane` run, always
   ends in a broken OBP:
   `ERROR: Last Trap: Fast Data Access MMU Miss / [Exception handlers interrupted]`
   i.e. P2-001. An interactive `init 5` gives the normal
   `syncing file systems... done / Program terminated`, so something about
   shutting down after a PPP session breaks it -- likely sppp still plumbed, or
   console tty state that `stty sane` does not fully repair. Both attempts ended
   this way and both cost a rollback to `@ppp-installed`.

**GOAL REACHED 2026-08-17: root shell on Solaris 10/sun4v over TCP/IP.**

```
$ telnet 10.0.5.15
login: root
# uname -a; id
SunOS unknown 5.10 Generic_118822-23 sun4v sparc sun4v
uid=0(root) gid=0(root)
```

The full stack that works:

| layer | mechanism | why not the obvious thing |
|---|---|---|
| transport | `pppd notty` on /dev/console | qcn cannot be STREAMS-I_LINKed to the PPP mux |
| framing | `asyncmap 0xffffffff` | the console is not 8-bit clean |
| tty | `stty raw -echo` first | else the guest echoes the host's frames back |
| telnetd | **perl mini-inetd** | SMF's inetd cannot start, see below |

**Why inetd could not be used, precisely:**

```
svc:/network/inetd:default (inetd)
 State: offline
Reason: Dependency svc:/milestone/name-services is absent.
```

ONE missing manifest, not a tangle. This image's SMF repository holds only 22
services. The telnet/ftp/shell/login/rexec manifests DO import cleanly
(`svccfg import /var/svc/manifest/network/telnet.xml` works); it is
`svc:/milestone/name-services` that is absent, so inetd never leaves `offline`
and its dependents stay `uninitialized`.

The proper fix is to import `/var/svc/manifest/milestone/name-services.xml`
(and whatever it in turn needs). NOT attempted yet, deliberately: importing
milestone manifests into a 22-service repository risks the system chasing
services that do not exist. Try it on a clone first.

**The bypass that works, and is arguably better here:**
`tools/guest-pinetd.pl` -- 20 lines of perl doing the only thing inetd does for
telnet: bind, accept, fork, exec `in.telnetd` with the socket as fd 0/1/2. No SMF
involvement. perl 5.8.4 is already in the image. Confirmed:
`pinetd: listening on 23 -> /usr/sbin/in.telnetd` and `*.23 ... LISTEN`.

Also required, already applied to the image: `/etc/default/login` with
`#CONSOLE=/dev/console` (root is otherwise console-only) and `PASSREQ=NO` (root
has no password, and we keep it that way so the console harness stays
password-free).

**STILL UNSOLVED: a PPP session cannot be terminated cleanly.** `init 5` after a
PPP session ALWAYS ends in a broken OBP
(`ERROR: Last Trap: Fast Data Access MMU Miss`) instead of
`Program terminated`. Tried three ways, all identical: from the detached
watchdog; from the watchdog after `pkill pppd` + `stty sane`; and initiated over
telnet with pppd killed first. So the shutdown path itself is broken after PPP
has run, independent of who owns the console.

**Operational consequence for now:** treat a PPP session as disposable. Run it on
a clone, or accept a rollback afterwards. Do not do work in a PPP session that
you need to persist.

**Which strongly motivates P2-008 (second UART).** With a second serial line the
console stays interactive, PPP runs on the other line, and `init 5` works
normally. The whole class of problem -- lockout, dirty journal, unterminable
sessions -- comes from PPP and the console being the same wire.

Two hard-won mechanics, both now encoded in `tools/guest-ppp-up.sh`:

1. **`notty` does not set terminal modes.** Leaving the console canonical with
   ECHO on makes the guest tty echo every byte the host sends, so host pppd
   receives its own frames -- `rcvd` identical to `sent`, same magic -- runs its
   loopback detection, and dies with `LCP: timeout sending Config-Requests`.
   Must `stty raw -echo < /dev/console` before starting pppd.
2. **pppd's stdout IS the link** in notty mode, so `debug` logging must be
   redirected (`2>/tmp/gppp.log`) or it corrupts the frame stream.

Host plumbing that worked: `-serial unix:/tmp/sol2.sock,server,nowait`, one
persistent `socat UNIX-CONNECT:... PTY,link=...,raw,echo=0` bridge, expect over
the pty for boot/login, then host `pppd /tmp/solcon2 115200 noauth nolock local
nodetach debug novj noccp 10.0.5.1:10.0.5.15`.

**Unresolved: session recovery.** The in-guest watchdog
(`tools/guest-ppp-watchdog.sh`, `sleep 300; pkill pppd; stty sane; init 5`) did
NOT recover the VM -- it ended in a panic and a broken OBP
(`ERROR: Last Trap: Fast Data Access MMU Miss`, i.e. P2-001), needing a rollback
to `@ppp-installed`. Before the next attempt, work out why: possibly `init 5`
while the console is mid-PPP, or pppd not dying to a plain `pkill`.

**The old console problem, now historical.** `qcn` is a singleton and ttyb is a dead end, so the
console is the only serial line. Handing it to PPP mid-session locks us out
before we can `init 5`, and a kill at a shell prompt persists a dirty LUFS
journal that panics the next boot. Two ways out:
1. Run QEMU with `-serial unix:/tmp/sock,server`, drive boot/login with an
   interactive `socat`, start the guest PPP endpoint, kill socat, then attach
   host `pppd` to the same socket. This is Artyom's sequence. Recovery for
   shutdown is `telnet` in and `init 5`.
2. **Better: get a second UART (P2-008) and never touch the console.**

### P2-003: Investigate vnet/vnex for native hypervisor networking [ ]

Depends on: P2-002 (networking exists before attempting this)

illumos-gate has a `sun4v/vnet` driver that implements the Oracle hypervisor's
virtual network interface. It talks to the hypervisor via Machine Description
(MD) table entries and the `vnex` nexus device. QEMU's Niagara machine does
not implement the MD networking entries or `vnex`.

This is a QEMU implementation task — the guest-side driver already exists in
Solaris/illumos. The work is on the QEMU side: implement the MD table network
device entries and a corresponding `vnex` QEMU device that backs them with
SLIRP or a tap interface.

Source: `usr/src/uts/sun4v/io/vnet.c` and `vnet_gen.c` in illumos-gate show
the expected hypercall interface.

Scope: significant QEMU work. Needs a spike to assess feasibility.

---

## P2 — Important (continued)

### P2-004: Clone illumos-gate and establish open-source guest OS [ ]

**Why this matters:** With illumos-gate in play, bugs at the QEMU/driver
interface can be fixed from either side. The ralph-loop produces test-verified
fixes to both QEMU and the guest OS simultaneously. Without open OS source,
every iteration is limited to QEMU-side changes only.

**Source lineage:** illumos-gate is the direct CDDL continuation of the
OpenSolaris Nevada (onnv) gate. The vnet, vdisk, ldc, mdeg drivers in
disk.s10hw2 descend directly from this source. We can read the exact code
running in our VM today — we just can't yet rebuild it.

**Why illumos over pre-2010 OpenSolaris:**
- Pre-2010 onnv required Sun Studio to build; illumos fixed gcc support
- The CDDL source is identical in substance; illumos is the living version
- Building from source is straightforward with gcc and standard Linux tooling
- Binary images for sun4v (Tribblix SPARC m34) exist if we need a pre-built OS

**Deliverables:**
- Clone illumos-gate: `git clone https://github.com/illumos/illumos-gate`
- Read `usr/src/uts/sun4v/` — this is the relevant platform directory
  Key files: `io/vnet.c`, `io/vnet_gen.c`, `io/ldc.c`, `io/mdeg.c`,
  `io/vdsk_common.c`, `sys/ldc.h`, `sys/mach_descrip.h`
- Document the LDC/MD protocol from source — this is the spec we implement
  in QEMU for P2-003
- Establish a build environment for sun4v kernel modules (needed before
  we can patch the guest side of any driver)

**Acceptance:** `usr/src/uts/sun4v/io/vnet.c` is readable and annotated
with our understanding of what QEMU must provide. Build environment
documented in this repo.


## P3 — Nice to have

### P3-001: illumos test suite on guest [ ]

Depends on: P1-002 (writable disk), P2-002 (networking to transfer files)

illumos-gate has a comprehensive test suite at `usr/src/test/`:
- `os-tests` — syscall, proc, signal, zone tests
- `zfs-tests` — ZFS correctness
- `net-tests` — networking stack
- `libc-tests`, `crypto-tests`, `elf-tests`, etc.

These run on any illumos derivative including OpenSolaris/Solaris 10 (with
some caveats — ZFS tests require a pool, net-tests require a working NIC).

The `test-runner` framework at `usr/src/test/test-runner` is a Python-based
runner. Transfer to guest via PPP/ftp or by embedding in a larger zvol.

Source: https://github.com/illumos/illumos-gate/tree/master/usr/src/test

### P3-002: Tribblix SPARC investigation [ ]

Depends on: P1-002, P2-002

Tribblix (by Peter Tribble) is an actively maintained illumos distribution
with a SPARC port (latest: m34 ISO). It runs on real Sun hardware
(T-series, Netra). Whether it can boot on QEMU Niagara is unknown.

Their SPARC overlays are at: https://github.com/tribblix/overlays.sparc
Their SPARC build environment is documented in:
https://github.com/tribblix/tribblix-build/tree/main/illumos

The claim that "Tribblix has SPARC64 virtio working" is ⚠️ UNVERIFIED.
No evidence found in their blog, repos, or build scripts. Needs direct
inquiry or source review once their actual gate location is found.

Contact: Peter Tribble (ptribble on GitHub, illumos discuss mailing list)
is responsive and would likely know the state of QEMU Niagara support.

### P3-003: virtio-net on Niagara [ ]

Depends on: P2-003 (understand vnet/vnex first)

Two paths, either requires QEMU machine changes:

**Path A — PCI bus:** Add a PCI bus to the Niagara machine. The guest's
existing `pci-hme` or `pcn` drivers would then attach to a `pcnet` or
`e1000` QEMU device. Risk: OBP may not enumerate a PCI bus correctly on
the Niagara machine type; extensive firmware work may be needed.

**Path B — sun4v native:** Implement the MD/vnex virtual network interface
that Solaris's `vnet` driver expects. This is the architecturally correct
path but requires understanding the full MD schema and hypercall ABI.

### P3-004: virtio framebuffer [ ]

Depends on: P3-003 (get virtio working first)

QEMU has `virtio-vga` and `virtio-gpu` devices. Whether the Niagara machine
can be extended to include a framebuffer path via `virtio-gpu` is unknown.
The sun4v platform has no framebuffer device in its original hardware spec
(Sun Fire T1000/T2000 are headless servers), so OBP has no framebuffer
initialization. A framebuffer would need to be self-identifying to the guest
via a different mechanism (e.g. a PCI VGA device if a PCI bus is added).

### P3-005: Submit disk write patch upstream [ ]

Depends on: P1-002 passing

Format patch per QEMU contribution guidelines, open thread on qemu-devel.
CC: Artyom Tarasenko (original niagara.c author).

### P3-006: Larger disk image / package installation [ ]

Depends on: P1-002

The stock `disk.s10hw2` is 512MB with a minimal Solaris install. Grow the
zvol and resize the UFS filesystem, or investigate adding a second zvol as
`/export` for packages and user data.

### P1-006: In-guest C toolchain works [x] DONE 2026-08-17

Depends on: P1-002 (persistence), exchange slice

Plain `gcc` compiles, links against `libm`, and the binary runs — verified by
asserting the program's own stdout (`SUM=5050 RC=1.41421`), not gcc's exit
status. Guarded by `test-toolchain-compiles`. Snapshot `primary@toolchain-working`.

Three findings worth keeping:
- `math.h` ships in **SUNWlibm**, not SUNWhea.
- `crt1.o` is NOT needed from Solaris media; gcc ships its own.
- gcc is `sparc-sun-solaris2.8` but binutils live under `solaris2.9`; symlink
  `as`/`ld` into gcc's private exec dir so plain `gcc` works (a `-B` flag only
  fixes one invocation and breaks configure scripts).

Full detail in CURRENT-STATE.md "Toolchain".

### P1-007: 1GiB of guest RAM [x] DONE 2026-08-17

Was 256MB. Artyom Tarasenko's sun4v MD files raise the ceiling; `prtconf`
reports "Memory size: 1024 Megabytes". Drop-in — only `1up-md.bin` and
`1up-hv.bin` differ from ours, everything else is byte-identical, so this is
purely a Machine Description change. In `/datapool/niagara/base-1gib`.
Source: `github.com/artyom-tarasenko/qemu-sun4v-md` @ `1GiB-experimental`.

### P2-005: FAT32 on slice 3 for a bidirectional host<->guest channel [x] DONE 2026-08-17

Depends on: exchange slice

Replaces raw `dd`+`tar` with a real filesystem both sides can mount, so files
can be dropped in and results read back without block counting.

Host side is **already verified**: `mkfs.vfat -F 32` on a loop device at offset
`4194304*512`, length 512MB; mounted `rw`, wrote files, unmounted, remounted,
read back. 2.25s, no boot. Linux vfat rw support is solid.

Guest side works, and it was easier than expected:
1. `mount -F pcfs /dev/dsk/c0t0d0s3:c /x` succeeded on the FIRST attempt. The
   feared FAT32-BPB/geometry mismatch never materialised — `mkfs.vfat -F 32
   -S 512 -h 0` is accepted as-is, no FAT16 fallback needed.
2. Guest writes are visible to the host after `init 5` + writeback.
3. `tests/test-fat-exchange.sh` asserts TWO exact cksum matches on 256KB of
   random data: host->guest and guest->host.
4. Harmless noise: `WARNING: hsimd_ioctl: cmd 760b not implemented`, pcfs
   probing an ioctl the RAM-disk driver does not implement. Mount still works.

Raw `push` is kept: it is still the right tool for a single big tar, and the
two modes share the slice exclusively (`mkfs` clobbers a pushed tar and vice
versa).

Note the mistake this item corrects: the earlier FAT32 attempt was abandoned
because it used a *second `-drive`*, which Solaris cannot see without an MD
node. That reason does not apply to a slice on the disk we already have.

### P2-006: Write the guest UFS root from the host [ ]

Would remove the boot-per-filesystem-edit loop entirely (symlinks, dropping in
headers). Currently every such change costs a ~60s boot plus a writeback.

**The stock kernel cannot do it**: `CONFIG_UFS_FS=m` but no
`CONFIG_UFS_FS_WRITE`, so `ufs.ko` is read-only by construction — an `rw`
mount is silently downgraded to `ro` and writes fail EROFS. Verified.
Reads are fine, which is what `tools/peek.sh` uses.

Two viable routes, both untested against *Solaris* UFS specifically (NetBSD FFS
is a close relative but Linux having a distinct `ufstype=sun` implies real
differences):

1. **rump kernel** (preferred — scriptable, no VM lifecycle). NetBSD's FFS
   driver as a userspace process on Linux. Nothing is packaged for Ubuntu;
   needs `buildrump.sh` plus `fs-utils` (`fsu_ls`, `fsu_cp`, `fsu_write`).
2. **NetBSD VM under KVM.** Attach the zvol as a second disk and
   `mount -t ffs -o rw /dev/wd1d`. Slice 0 starts at byte 0 of the zvol, so no
   partition offset is needed (this is why `peek.sh` mounts the zvol directly).

Progress on route 2, and the exact blocker: the live image
(`NetBSD-10.1-amd64-live.img.gz`) boots and its *loader* talks to serial, but
the **kernel** console defaults to VGA, so everything after the loader is
invisible. Fix is `consdev com0` at the loader prompt, reached by:
`SPACE` (stops the countdown, prints `Option: [1]:`) then `3` **and a newline**.
Getting only one of those two wrong is what defeated three attempts —
`3\r` alone lets the countdown pick option 1; `SPACE` then bare `3` never
submits. Alternatively remaster the ISO with `consdev com0` in `boot.cfg` and
avoid the keystroke race entirely.

### virtio-vsock for host<->guest comms [~] DEAD END, investigated 2026-08-17

Prompted by madebymikal.com/virtio-vsock-python-examples-of-running-the-server-in-the-guest/
Attractive because vsock gives a real sockets layer with multiplexing for free,
instead of hand-rolling framing over one channel.

Blocked twice over, both measured:

1. **No bus to attach it to.** Every vsock device QEMU builds needs either PCI
   or virtio-bus:
       vhost-vsock-pci        bus PCI
       vhost-vsock-device     bus virtio-bus
   The niagara machine has neither:
       -device vhost-vsock-pci: No 'PCI' bus found for device 'vhost-vsock-pci'
2. **No guest support.** Solaris 10 has no /dev/vsock and zero vsock kernel
   modules. vsock is a Linux/VMware construct, and virtio (2008) postdates this
   image (2005) entirely.

Host side is ready and irrelevant: vhost_vsock.ko and /dev/vhost-vsock exist.

Reviving it would need a virtio transport added to the niagara machine AND a
sun4v vsock driver written for Solaris 10 -- the same circularity that killed
the ttyb/qcn idea.

Keep the ARGUMENT though, which is the valuable part: do not hand-roll
multiplexing over a single channel. We get that two ways without vsock -- the
FAT slice (a filesystem is already a namespace, P2-005, done) and PPP+slirp
over the console (ports come free with TCP/IP, P2-002).

### P2-007: Rebuild q.bin — the highest-leverage unlock [ ]

Earlier docs called q.bin "a fixed binary we cannot rebuild". **That was wrong**
and it distorted the device strategy. The source is present: 4.6MB at
`~/vms/opensparc/hypervisor/src`, including the hypercall implementations we have
already read (`hcall_disk_read` 0xf0 / `hcall_disk_write` 0xf1 in
`vdev_simdisk.s`).

Two real obstacles:

1. **Sun toolchain.** `Makefile.master` wants `qas` (custom Sun assembler),
   `sas`, Sun Studio `cc`, `/usr/ccs/lib/cpp`, `/usr/ccs/bin/ld`, `mdgen-v1`.
   But those are *Solaris* paths, and we now have a Solaris 10 guest with gcc
   4.3.3 and binutils 2.21.1 — **the guest is the natural build host**, which it
   could not be before P1-006. We have also already cross-built `mdgen` from
   this same tree (`patches/0002-mdgen-x86-crossbuild.patch`).
2. **No matching build variant.** Targets are `debug dumbreset
   fpga_1thread_reset legion release t1_fpga`; there is no `sam` target and no
   Makefile mentions one. The working 163KB S10image q.bin was built for a
   QEMU/SAM-like config absent from the drop; the in-tree builds hang on missing
   SAM runtime APIs.

**Step 1 DONE 2026-08-17 — the assembler is NOT the wall.**

Probed all 28 hypervisor `.s` files through `gcc -E` then
`sparc64-linux-gnu-as -64 -Av9b` (binutils 2.42):

- **6/28 assembled cleanly**, including **`vdev_simdisk.s`** — the disk hypercall
  implementation itself. GNU binutils handles SPARC v9 hyperprivileged
  instructions fine.
- ~8 files fail only on `fatal error: offsets.h: No such file`. That is a
  **generated** header (source: `greatlakes/ontario/src/offsets.in`), i.e. a
  build step we never ran, not a syntax problem.
- 126 "unknown opcode" error lines are concentrated in `subr.s` and start with
  `Unknown opcode: 'struct'` — Sun's `.struct` *directive*, a dialect issue in a
  few files, not rejected instructions.
- `version.s`: one trivial `junk at end of line` on a version string.

**Step 2 — and this reframes everything: the authentic Sun toolchain is SHIPPED
in the tree.** `hypervisor/src/hypervisor-tools/bin/` contains:

```
qas       552960  ELF 32-bit MSB SPARC32PLUS   <- the custom Sun assembler
as        475364  ELF 32-bit MSB SPARC32PLUS
stabs      30656  ELF 32-bit MSB SPARC         <- generates offsets.h
objcopy  3532544  ELF 64-bit MSB SPARC V9
```

These are **Solaris SPARC binaries**, which is exactly why the original
assessment said the build environment was unavailable — they cannot run on this
x86 Linux host. **But they run natively in our Solaris 10 guest.** So we do not
need to port anything to GNU `as`, generate `offsets.h` ourselves, or fight the
`.struct` dialect: use Sun's own tools where they work.

Revised plan:
1. Get networking (P2-002) so the guest is iterable from inside. **This is the
   real reason networking is the prerequisite, not just convenience.**
2. Ship `hypervisor/src` (4.6MB incl. 2.1MB of tools) into the guest — it fits
   in the 512MB FAT slice comfortably.
3. Build in the guest with `qas`/`stabs`/`objcopy`.
4. Substitute for Sun Studio `cc`, which is NOT shipped: gcc 4.3.3 is present.
   40 C files; unknown how portable they are. This is the main remaining
   toolchain gap.

**Unresolved risk, unchanged and still the real danger:** the in-tree build
variants (`debug`/`release`/`legion`) all hang under QEMU because they want SAM
runtime APIs, and the working 163KB S10image binary corresponds to no variant in
the tree. A successful *build* is not yet a working q.bin. Do not treat this as
nearly-done.

Payoff if it works — it flips the closed half of the device fork open:
- `glvc`, a real byte channel whose driver is ALREADY in the guest
- our own paravirtual devices with custom hypercalls: a ring buffer **with a
  doorbell**, the one thing a shared-memory mailbox cannot express
- probably flatblk (P1-004), since q.bin's DMA address computation is the prime
  suspect and we would control it
- permanently removes "we can add MD nodes but nothing services them"

Risk: hyperprivileged SPARC assembly, exact trap-table layout.

### P2-008: Second UART, bound by the existing `su` driver [ ]

The cheapest possible route to a second channel, and nobody has tried it.

QEMU already emulates a 16550 at `NIAGARA_UART_BASE` which the guest never
touches (q.bin drives it to serve the `qcn` console). The guest **already ships
`su`, a 16550 driver**. So all three device requirements can be met with no new
guest driver:

1. Add a second `serial_mm_init` at a fresh address in `niagara.c` (~2 lines).
2. Declare a node for it in the MD with a `reg` property.
3. See whether `su` binds.

Success = a serial port serviced entirely by QEMU with **no q.bin involvement**,
which is the thing we keep concluding is impossible. It also removes P2-002's
console compromise, since PPP could then run on the second port.

Caveats: `su` normally attaches under `ebus`/ISA (PCI-parented on real T2000);
binding depends on the `compatible`/`name` properties Solaris matches; and MD ->
OBP may not emit a usable `reg` property for a node type that normally lacks
one. It may simply not bind — one boot to find out.

### P3-008: Build the TCG plugins for guest-level observability [ ]

Our QEMU is configured with `plugins = True` and the API includes
`qemu_plugin_register_vcpu_mem_cb`, so a plugin can observe **every guest memory
access** — including the vdisk traffic that syscall tracing structurally cannot
see (see STRATEGY.md "How the emulation actually works"). `contrib/plugins/` has
`execlog.c`, `hotblocks.c`, `hotpages.c`, `hwprofile.c`, `cache.c`, `drcov.c`,
none of them built yet.

Useful for: proving the block layer is absent from the I/O path, profiling where
boot time goes, and finding the guest code that touches a given address.

Plugins are **read-only** — they cannot service a device. Also note USDT probes
are absent from our build (`trace_backends = ['log']`), while eBPF uprobes work
today (not stripped, 48355 symbols).

### P2-009: NetBSD/sun4u + compat_svr4 as the q.bin build host [ ]

**This probably supersedes P2-002's justification.** The argument for networking
was "we need to iterate inside the Solaris guest to build q.bin with Sun's own
tools". But NetBSD runs Solaris SPARC binaries natively via `compat_svr4`, and
the man page states it explicitly: *"This code has been tested on ... sparc (with
binaries from Solaris) systems."*

NetBSD/sun4u under QEMU is a far better build host than our Niagara guest:
mature emulation, real disks, real networking out of the box, no 5 MHz-equivalent
crawl, and no PPP plumbing.

Mapping the shipped Sun toolchain (P2-007) onto it:

| tool | ELF class | compat option |
|---|---|---|
| `qas`, `as` | 32-bit SPARC32PLUS | `COMPAT_SVR4_32` on a 64-bit kernel, or `COMPAT_SVR4` on 32-bit NetBSD/sparc |
| `stabs` | 32-bit SPARC | same |
| `objcopy` | 64-bit SPARC V9 | `COMPAT_SVR4` + `EXEC_ELF64` |

These are the well-behaved case for compat_svr4: file-in/file-out CLI tools. The
documented limitations are `/proc`, threads, STREAMS admin and ticotsord RPC --
none of which an assembler touches.

Setup work:
1. NetBSD/sparc64 (or sparc) VM with `COMPAT_SVR4` / `COMPAT_SVR4_32`. Note the
   user is testing NetBSD 8.3; confirm the option still exists in whichever
   release is used, and that `EXEC_ELF64` is in for `objcopy`.
2. Populate the `/emul/svr4` shadow root with Solaris libs + `ld.so.1`. **We
   already have these**: `SUNWcsl`/`SUNWcslr` from CD1 give `/usr/lib` and
   `/lib`. Also `/usr/ucblib`, and zoneinfo if timestamps matter.
3. Verify each tool runs: `qas --version` or assembling one `.s`.
4. Build q.bin there. NetBSD/sparc64's native gcc can likely handle the 40 C
   files, covering the missing Sun Studio `cc`.

Keeps the SAM-runtime risk from P2-007 unchanged: a successful build is still not
a proven-working q.bin.

### P2-010: Checkpoint a running session to disk [x] DONE 2026-08-17

Removes the "a PPP session is disposable" problem. Previously the vdisk was only
flushed by `atexit`, so a session was all-or-nothing: if the guest wedged -- and
`init 5` after PPP reliably ends in a broken OBP -- the only safe move was to
discard everything and roll back.

`niagara_vdisk_writeback_full(bool final)` is now callable mid-run:

- **`kill -USR2 <qemu-pid>`** flushes 2560MB of vdisk RAM to the zvol.
- **`NIAGARA_SYNC_SECS=<n>`** flushes unattended every n seconds.
- `tools/checkpoint.sh [snapname]` does the whole safe sequence.

**Use SIGUSR2, never SIGUSR1.** QEMU defines `SIG_IPI` as `SIGUSR1` on Linux and
uses it to kick CPU threads, so a handler on SIGUSR1 is swallowed. Measured
exactly that: the setup line printed, the guest quiesced, and `kill -USR1`
produced no flush whatsoever.

Two implementation details that matter:

1. The signal handler only sets a `volatile sig_atomic_t`; a 1-second QEMU timer
   does the work from the main loop. The writeback calls `fprintf`, `open`,
   `pwrite` and `system()`, none of which is async-signal-safe.
2. The old code ended with `g_free(niagara_vdisk_path)`, which was fine for a
   one-shot atexit but made every subsequent call bail at the
   `!niagara_vdisk_path` guard -- silently disabling checkpointing after the
   first one. Freeing is now gated on `final`.

**Consistency, stated honestly.** Flushing a running guest is CRASH-consistent,
not filesystem-consistent: the guest may be mid-transaction and its LUFS journal
needs replay, which is the `ufs:readlog -> vfs_mountroot` panic. So
`checkpoint.sh` first quiesces over telnet (`sync; lockfs -f /`) -- which is only
possible because networking now works. For a fully atomic image, add monitor
`stop`/`cont` around the flush, which needs `-monitor unix:...`. Not done yet.

**VERIFIED end to end:** wrote `/CKMARK` in the guest over telnet, ran
`checkpoint.sh`, then `kill -9` the QEMU pid so no atexit path could run, and the
file was still on the zvol:

```
niagara: checkpoint requested (SIGUSR2)
niagara: vdisk writeback complete (2560 MB)
$ peek -> CKMARK PRESENT: CHECKPOINT-PROOF-9f3a
```

### P3-007: Multi-CPU Machine Descriptions [ ]

`/datapool/niagara/base` already contains `1g2p-md.bin`/`1g2p-hv.bin` (2 CPUs)
and `1g32p-md.bin`/`1g32p-hv.bin` (32 CPUs) alongside the 1-CPU `1up-*`. Never
tried. Solaris on sun4v should bring up multiple strands, and a compile is
CPU-bound, so this is the cheapest remaining speedup. Unknown whether QEMU's
niagara model handles more than one strand correctly.

---

## Friction log

### 2026-08-17 — six ways a run looks broken when it is not (or is)

- **The Solaris console silently truncates a line over 256 bytes AND eats its
  carriage return.** A ~300-byte `ln -s ... ; ln -s ... ; ls -l ...` appeared in
  the pane cut off mid-path with no new prompt, and expect then waited out its
  whole timeout. It reads exactly like a hang. Keep sent lines under ~200 bytes:
  `cd` first, use short relative paths.
- **One global `set timeout 600` made a permanent failure indistinguishable
  from progress for ten minutes.** Boot legitimately needs ~40s; a shell command
  needs under a second. Size timeouts per step, and make a missing prompt ABORT
  rather than fall through — ten dead commands at 30s each is a 300s fake hang.
  `tools/waitfor.sh` now also exits 3 the moment the log stops growing.
- **expect buffers `puts` when stdout is a pipe**, so `RESULT:` markers only
  appeared at exit and a poller saw nothing. `fconfigure stdout -buffering none`.
- **`| tail -N` buffers until the pipeline ends**, so the tmux pane a human is
  watching stays completely blank. Use `| tee`. Tests additionally buffer
  because `out=$(vm_run ...)` captures the whole transcript — hence
  `VM_TRANSCRIPT`.
- **`Ctrl-A c` does not reach QEMU from a scripted expect.** With no `interact`,
  `\x01c` goes to the guest, which echoed it at the OBP prompt as `ok s^Ac`
  while expect waited for a `(qemu)` prompt forever. Signal the pid instead.
- **Killing a guest that is at a shell prompt persists a dirty LUFS journal.**
  Self-inflicted and expensive: the killed state got snapshotted, and every
  clone then panicked in `ufs:readlog -> vfs_mountroot`. Cost a rollback to
  `@gcc-planted` and redoing the header install. Only `init 5` then SIGTERM.
  Corollary: keep payloads reproducible from `tools/`, because that is what
  makes rolling forward from a clean snapshot cheap instead of catastrophic.
- **Trusting a downstream read after an upstream failure pushed the wrong
  payload.** `tar cf /tmp/toolchain.tar` failed with EPERM against a stale
  root-owned file from an earlier session; `stat` then happily reported the OLD
  file's size and 62MB of the wrong archive went onto the slice. Check the
  command that produces a file, not just the file. The fix that caught it was
  verifying the slice bytes `cksum`-match the tar after pushing.

- `cache=writethrough` on the QEMU drive did nothing — the block layer is
  not involved in the vdisk write path at all. Misleading QEMU option.
- qcow2 overlay silently fails for pflash — OBP reads qcow2 magic bytes as
  raw disk label and panics. No error from QEMU at startup.
- OBP `boot disk` fails after any guest reboot — session must be restarted.
  Makes iterating on the guest tedious until P2-001 is fixed.
- `sync` inside the guest is meaningless until P1-002 is done.
- SAM simulator binaries in the OpenSPARC package are SPARC ELF — they only
  ran on Solaris/SPARC hosts and are useless on this x86 Linux host.
- Tribblix SPARC illumos gate location not found publicly. `tribblix/illumos-tribblix`
  on GitHub returns 404. May be a private or unlisted repo.

### P1-004: Investigate flatblk panic — adding RAM region corrupts UFS mount [~] SUPERSEDED

No longer blocking: storage works without flatblk. Left here as a record of
the failure mode in case a second RAM region is ever needed again.


**Symptom:** Adding ANY new RAM region to the Niagara guest physical address
space via `memory_region_add_subregion` causes a deterministic kernel panic:

```
BAD TRAP: type=10 (illegal instruction)
pc=0x300005e7840  ← data buffer address, not code
ufs:fetchbuf+74 → ufs:readlog → ufs:lufs_read_strategy → vfs_mountroot
```

Same virtual address every time, regardless of the new region's physical
address (tested: 0x1f50000000, 0x400000000), size, or timing of the
`memory_region_add_subregion` call within `niagara_init`.

**Secondary finding:** atexit fires on abnormal QEMU exit (after kernel panic
→ OBP restart → process exit). The vdisk writeback saves corrupted RAM state
to the zvol. Always `zfs rollback primary@clean` after a panicking run.

**Hypothesis:** QEMU's host mmap for existing RAM regions (vdisk_ram,
partition RAM) is moved when a new large allocation is added, staling the
TCG software TLB's host-address pointers. Next vdisk read via the stale
pointer returns garbage → UFS function pointer corruption → illegal
instruction jump.

**Investigation needed:**
- Read QEMU's `physmem.c` / `exec.c` RAM allocation path
- Check if `qemu_ram_alloc` uses a slab allocator that can move existing blocks
- Try: allocate flatblk RAM before all other regions (make it index 0) — if
  it can't be moved, subsequent regions are added to a different pool
- Try: `memory_region_init_ram` with a pre-allocated host buffer
  (`memory_region_init_ram_ptr`) to bypass QEMU's allocator entirely
- Try: use a `/dev/shm`-backed anonymous shared region instead of file mmap

**Additional findings (overnight loop):**

All four approaches tried, all panic the same way:
- New RAM region at 0x1f50000000 (device space adjacent to vdisk)
- New RAM region at 0x400000000 (16GB, "safe" zone)
- New RAM region via `memory_region_init_ram_ptr` (user-supplied buffer)
- Extended vdisk_ram to include flatblk tail (0x1f60000000)

Instrumentation confirmed vdisk_ram host ptr does NOT move (mmap-moves
hypothesis eliminated). The panic is NOT from QEMU moving allocations.

**Current hypothesis:** extending any allocation at NIAGARA_VDISK_BASE or
adding RAM anywhere in the physical address space changes q.bin's internal
DMA behavior. q.bin targets a DMA write to the wrong kernel virtual address,
corrupting a SPARC64 register window (%i7 / return address), causing the
kernel to return into a data buffer (0x300005e7840) and fault on illegal
instruction.

**Blocked on:** q.bin source code or binary instrumentation to trace DMA
target computation. q.bin is a closed binary from the OpenSPARC T1 package.

**Next steps for P1-004:**
- Disassemble q.bin to find vdisk DMA read/write routines
- Instrument QEMU to intercept all writes to partition RAM during vdisk I/O
  and log the target physical addresses — look for writes near the kernel
  stack at the time of panic
- Consider patching q.bin binary if the DMA offset calculation can be found

---

## P1-005: Determine disk write path (vdc: direct hypercall vs LDC) [x] DONE

**ANSWER: direct hypercalls (0xf0/0xf1), not LDC.** q.bin has no LDC
implementation at all. Writes reach vdisk_ram; the atexit writeback
persists them. Measured directly via /proc/<pid>/mem: the canary is present
in the vdisk_ram mapping while the guest is running.


**Why this matters:** Everything else depends on this. If the kernel uses direct
hypercalls (0xf0/0xf1), writes reach vdisk_ram and atexit saves them — we have
working storage already. If it uses LDC, writes are silently dropped by q.bin's
unimplemented LDC handler and we need a different fix.

**Investigation plan:**

1. Read `usr/src/uts/sun4v/io/vdc.c` in illumos-gate (we have the source).
   Look for: does vdc use `hv_disk_read`/`hv_disk_write` (direct hypercalls)
   or `ldc_write` (LDC channel)? The answer is in the I/O submission path.

2. If direct hypercalls: re-run the hostname write test with a CLEAN zvol,
   clean QEMU exit (monitor `quit`), and inspect the zvol with `strings`.
   If the canary appears, writes already work and atexit just wasn't firing.

3. If LDC: implement the minimal LDC vdisk server in QEMU's niagara machine.
   Protocol is documented in `usr/src/uts/sun4v/io/vdc.c` (client side).

4. Alternative — patch disk.s10hw2 kernel to use direct hypercalls:
   The `hcall_disk_read`/`hcall_disk_write` interface (0xf0/0xf1) is simpler
   than LDC. If we can patch or rebuild the vdc driver to use direct hypercalls,
   writes work immediately with no QEMU changes.

**Acceptance:** `test-disk-writes-persist.sh` PASSES.

---

## P2-005: Cross-compile q.bin on Linux / patch binary for debug output [ ]

**Context:** q.bin source is in `~/vms/opensparc/hypervisor/src/`. The build
requires `qas` (custom Sun SPARC assembler) and Sun Studio. Standard Linux
tools may work as a substitute.

**Investigation:**
- `binutils` includes `sparc64-linux-gnu-as` — check if this is compatible with
  the hypervisor assembly syntax (Sun SPARC vs GNU SPARC differences)
- The Makefile uses `qas` and `sas` for assembly. Try substituting with:
  `sparc64-linux-gnu-as -xarch=v9 -64` and `sparc64-linux-gnu-ld`
- If assembly compiles: add `printf`-equivalent debug output to `hcall_disk_write`
  (write a pattern to a known physical address readable via QEMU pmemsave)
- If not: binary patch the working q.bin to add NOPs + MMIO writes at the
  `hcall_disk_write` entry point

**Value:** Definitive proof of whether writes reach q.bin, independent of
the Solaris kernel source analysis in P1-005.

---

## P2-006: q.bin source study — full hypervisor behavior map [ ]

Source location: `~/vms/opensparc/hypervisor/src/greatlakes/`

Key files to read and annotate:
- `common/src/vdev_simdisk.s` — disk hypercall implementation (READ, done)
- `common/src/hcall.s` — full hypercall dispatch table
- `common/src/svc.s` — service channel handling (possible LDC routing)
- `ontario/src/setup.s` — guest initialization, DISK_PA/DISK_SIZE setup
- `ontario/src/main.s` — hypervisor entry, trap table
- `common/src/vdev_console.s` — console (for comparison with disk path)
- `common/include/vdev_simdisk.h` — disk constants (DISK_S2NBLK_OFFSET=0x1d0, etc.)

**Goal:** Build a complete picture of what the working q.bin can and cannot do,
without needing to rebuild it. Specifically: does it have any path from an LDC
channel message to a disk read/write? (Look for LDC-related symbols via `nm` or
`strings` on the working binary.)

**Quick start:**
```bash
nm /datapool/niagara/base/q.bin 2>/dev/null || \
  objdump -t /datapool/niagara/base/q.bin 2>/dev/null
strings /datapool/niagara/base/q.bin | sort
```

---

## P1-006: Add console@4 (ttyb) — second serial data channel [ ]

Now tractable: the MD is editable as text with a verified round-trip
(`tests/test-md-roundtrip.sh`), so this is a source edit, not binary surgery.

`console@1`'s unit address comes from `cfg-handle = 0x1` in the MD's
`virtual-device console` node (`common.pdesc`). `nvram1` already aliases
`ttyb -> /virtual-devices/console@4`, so OBP expects a node that has never
existed.

Steps:
1. Copy `~/vms/opensparc/legion/src/config/niagara/{1up,common}.pdesc` into
   `md/` in this repo (so our MD source is version-controlled).
2. Add a second `virtual-device console` node: `cfg-handle = 0x4`,
   `channel# = 1`, `compatible = "qcn"`, distinct `ino`.
3. Regenerate: `tools/gen-md.sh md/1up.pdesc /datapool/niagara/base/1up-md.bin`
4. Add the matching UART in `hw/sparc64/niagara.c`, wire to `serial_hd(1)`.
5. Expose host-side: `-serial pty` (or a unix socket), attach with `screen`.
6. Verify: `show-devs` lists `console@4`; Solaris has `/dev/term/b`.

Acceptance: a new test that writes a canary out the second serial from the
guest and reads it on the host, with no console interference.

Value: a real bidirectional data channel — enough to move a compiler in with
`sz`/`rz`, without needing networking or a second block device.

---

## P1-007: Install a C compiler in the guest [ ]

Depends on: P1-006 (or any working data channel).

1.6GB free on the 1.9GB UFS is enough for gcc4core.

- Source: `http://mirror.opencsw.org/opencsw/stable/sparc/5.10/`
  `gcc4core-4.9.0,REV=2014.04.27-SunOS5.10-sparc-CSW.pkg.gz` (~137MB gz)
- Dependencies per the OpenCSW catalog: libgcc_s1, libgmp10, libmpfr4,
  libmpc3, libiconv2, libz1, binutils, coreutils, ggrep, gsed
- Transfer via the P1-006 serial channel, then `pkgadd -d`

Acceptance: `gcc hello.c -o hello && ./hello` works in the guest.

First target once it works: build a `format(1M)` that does not reject the
`SUNW,sun4v-virtual` controller name (see CURRENT-STATE "Known gaps" #2).

---

## Harness bugs found and fixed (2026-08-17 review)

Recorded because each one silently produced wrong results:

1. `test-disk-writes-persist` wrote its canary to `/tmp` — which is tmpfs
   (`swap - /tmp tmpfs`). It never touched the disk, so the test could only
   ever fail. Now writes to `/etc`.
2. No test ran `lockfs -f /` before exit, so every run persisted a dirty LUFS
   journal. Added `$vm_clean_shutdown_fragment`.
3. **expect matched the terminal echo of the command it had just typed.**
   `send "... && echo WROTE_OK"` + `expect "WROTE_OK"` matches the echo, so
   expect continued before the shell ran anything — QEMU was quit before the
   write happened. Match the shell prompt `"# "` instead; never an echo-able
   marker.
4. **`strings "$DEV" | grep -qF ...` under `set -o pipefail`.** `grep -q`
   exits on first match, `strings` dies of SIGPIPE (141), and pipefail reports
   the pipeline as FAILED even though the match succeeded. This masked a fully
   working writeback as a failing test. Use `grep -a -q -F` on the device
   directly.
5. **`lock_acquire` installed `trap ... EXIT`, clobbering the caller's cleanup
   trap.** Bash has one EXIT trap. Tests set `trap cleanup EXIT` then called
   `lock_acquire`, which replaced it — so no test ever destroyed its clone.
   15 orphans (~3.3GB) had accumulated. `lock_acquire` no longer sets traps;
   callers own cleanup.
6. `zfs destroy` on a test clone fails permanently with "volume has children"
   because the atexit writeback snapshots the clone itself. Needs `-r`.
7. `$HOME` under `sudo` is `/root`, so `$HOME/vms/opensparc` did not resolve.
   Use the invoking user's home via `SUDO_USER`.
8. `run-solaris.sh reset` rolled back to `@clean` — the 512MB original —
   silently downgrading the disk, despite its comment claiming `@clean-2gb`.
9. `run-solaris.sh` ran `sudo exec "$QEMU"`, which asks sudo to find a binary
   named `exec`. Also took no lock, so it could race the test suite on
   `primary`.
