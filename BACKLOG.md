### P2-026: Tribblix SPARC on QEMU sun4u as the hsimd build host (Ryan's idea)

This is the idea that BREAKS THE CIRCULARITY, and it is the most promising route to
owning hsimd. The bind is that building hsimd needs a SPARC host, and every SPARC guest
that could serve as one cannot see a disk without hsimd.

Tribblix SPARC supports **sun4u**, and QEMU's sun4u target has ordinary disk emulation --
no hsimd required. A sun4u host can build the **sun4v** module, because it is the same
sparcv9 ISA and the gate builds `uts/sun4v` regardless of the build host's platform. So:

    Tribblix on QEMU sun4u  ->  build sun4v hsimd  ->  install into a sun4v image

No real hardware, no circular dependency.

THE COST IS THE HONEST PROBLEM: a full ON gate build under TCG emulation. Tarasenko
measured Tribblix *booting* at roughly 1 hour on his laptop; a gate build is orders of
magnitude more work than a boot, so plausibly days rather than hours.

RUN THE CHEAP TESTS IN THIS ORDER:
  1. Does the hsimd binary already in our S10 image load on another kernel? One
     `modinfo` / `elfdump -e` comparison. A positive result collapses P2-021 entirely.
  2. Does Tribblix SPARC actually boot under QEMU sun4u at a usable speed? Boot first,
     before contemplating a build.
  3. Does `make` in `uts/sun4v/hsimd` succeed against INSTALLED kernel headers rather
     than a fully built gate? Sun's README demands a clean gate, but they were
     describing their supported workflow, not the minimum. If a partial build works, the
     whole item shrinks from days to an afternoon.
  4. Only then consider a full gate build, and measure a fraction of it before
     committing to the whole.

DO NOT INHERIT TARASENKO'S PERFORMANCE NUMBERS. The "~1 hour to boot Tribblix" figure and
the "sun4v can definitely be significantly optimized" remark come from a much worse
baseline than ours, in three separate ways:

  storage   He used `pmemsave 0x1f40000000 83886080 vdisk.ram` at the QEMU monitor after
            init 5, booting read-only (`if=pflash,readonly=on`) from an 80 MB dump, with
            everything lost if he forgot. patches/0001 makes the vdisk a MAP_SHARED
            mapping of a regular 2.5 GB file, so writes land in the page cache as the
            guest makes them, durably, with no shutdown ritual. Different mechanism, not
            a tuning delta.
  network   He compiled slirp INSIDE the guest and ran pppd over a socat pty, putting a
            userspace TCP/IP stack on an emulated SPARC in the data path. We run pppd on
            the host over the shared-memory channel: measured 4000 blocks/sec through
            single-block hypercalls, and 458 KB across three concurrent channels in
            0.26s wall, genuinely parallel.
  hardware  A laptop in 2016-17 and again Jan 2025. The QEMU merge predates Apple silicon
            entirely. qemu-system-sparc64 is TCG on every host, so his number is
            TCG-on-a-2016-laptop and not a floor.

CONSEQUENCE: the "plausibly days" estimate for a gate build above was scaled from HIS
number and may be badly pessimistic on an M-series core. Measure a fraction of a real
build on the playbox before deciding the whole thing is impractical -- and measure a
Tribblix boot there too, since that is the cheap proxy for everything else.

Note Tarasenko also lists **dilos** as booting under niagara with 1 GiB (Ryan has ruled
dilos out) and v9os/Tribblix as too heavy there because they use a bootarchive -- but
that judgement was about running them ON niagara, not about using sun4u as a build host,
which is a different question.

### P2-021 UPDATE: hsimd source read — the driver is trivial, the GATE is the work

`github.com/artyom-tarasenko/hsimd`, GPL-2.0, 18 KB repo, five files:

    hsimd.c        23,456 B   (~700 lines)
    hsimd_asm.s     2,137 B   (the 0xf0/0xf1 hypercall trampolines)
    Makefile        2,175 B
    README.hsimd      882 B

It slots in as an ordinary sun4v driver: add `HSIMD_OBJS = hsimd.o hsimd_asm.o` to
`usr/src/uts/sun4v/Makefile.files`, add `hsimd` to `DRV_KMODS` in
`Makefile.sun4v.shared`, copy the three files into `uts/sun4v/{hsimd,io,ml}`, make.

THE CONSTRAINT IS SUN'S OWN, quoted from README.hsimd (2006):

    "Using a cleanly installed and built Solaris gate with sun4v support..."
    "NOTE: You should use the same release of Solaris as the version on the disk image
     that you will be using the hsimd driver for under simulation."

So a full ON/OS-Net gate build for the EXACT target release is required. That confirms
the module-ABI reasoning from measurement rather than inference, and it is why b59 media
is useless to us and why matching build numbers matter.

    target                 assessment
    Solaris 10 3/05        nothing to do -- our image ALREADY has hsimd
    illumos-gate (modern)  most tractable: actively maintained, builds on illumos, but
                           sun4v support is thin and a SPARC build host is needed
    SXCE b77               needs a b77 gate plus its Studio-era toolchain; sourcing that
                           in 2026 is the project, not the driver

CHEAP EXPERIMENT WORTH DOING FIRST: is the hsimd binary already inside our S10 image
loadable by another kernel? Almost certainly not -- that is the ABI rule -- but it is one
`modinfo` / `elfdump -e` comparison rather than a gate build, and a positive result would
collapse this entire item. Do that before contemplating a gate.

WHY THIS MATTERS: hsimd is the single gate on running ANY other Solaris or illumos on the
emulator. Without it a distribution boots and finds no disk (measured on b59, P2-025).
With it, snv_77-plus-ZFS/zones becomes reachable -- and note the compatibility direction
finally favours us there: the snv_77 ramdisk provides up to SUNW_1.23 while our Solaris 10
binaries need at most SUNW_1.22.1, so gcc, dropbear, socat and the channel daemons we
built today should run on snv_77 unchanged. We had that backwards when testing b59.

### P2-028: textinstall-134-sparc measured — same wall, and a limit on my own method

`textinstall-134-sparc.iso`, 450.9 MB, label OpenSolaris, mounted read-only as /dev/sr0.
Unlike the AI image this one carries a payload rather than expecting a network repo:

    solaris.zlib      91 MB   (lofi-compressed root)
    solarismisc.zlib  14 MB
    platform/sun4v/   nearly empty in the uncompressed tree

hsimd is ABSENT from the uncompressed tree. That is measured.

HONEST LIMIT, recorded because a false "verified absent" is worse than an admitted
unknown: I also grepped the .zlib payloads for the string `hsimd` and got 0, and that
result is MEANINGLESS. solaris.zlib is lofi-compressed (`file` reports only "data"), so
plaintext will not appear whether the driver is inside or not. The control confirms the
method rather than the conclusion: our own primary.img, uncompressed UFS and known to
contain the driver, yields 62 matches for the same grep.

So the state of knowledge is: absent where I could look, UNKNOWN inside the 91 MB payload.
Checking properly needs `lofiadm` on a Solaris host, and our 3/05 guest predates compressed
lofi support. Linux has no lofi decompressor.

HOW TO CLOSE IT: **`omniosce-1` on the tailnet is an illumos host** (tailscale reports
os=illumos; currently offline). OmniOS CE is modern illumos, so it has `lofiadm` with
compressed-lofi support plus native UFS/HSFS mounts -- exactly what is missing on Linux
and on our 3/05 guest. Bring it up and:

    lofiadm -a /path/to/solaris.zlib          # compressed lofi, mounts read-only
    mount -F ufs -o ro /dev/lofi/1 /mnt       # or -F hsfs depending on the payload
    ls /mnt/platform/sun4v/kernel/drv/sparcv9/hsimd
    ls /mnt/sbin/zpool /mnt/usr/sbin/{zoneadm,dladm}

That answers both open questions in one pass: whether hsimd is in the payload, and
whether b134's userland carries the ZFS/zones/Crossbow tools that motivated looking at
it. Ryan confirmed there is NO SmartOS host -- nothing in homelab-map hosts.yml, nothing
in the ansible inventories, and omniosce-1 is the only illumos machine on the tailnet.

NOTE omniosce-1 is x86, so it CANNOT build the sun4v hsimd module (the illumos gate
builds for the host ISA). It is an inspection tool here, not a build host -- that role
still belongs to P2-026's Tribblix-on-sun4u idea.

The practical conclusion is unchanged, on the strength of the prior rather than a
measurement: Tarasenko states other distributions do not ship hsimd, and three other media
now agree. But if anyone wants to close this properly, decompressing solaris.zlib is the
one remaining test, and it would also reveal whether b134's userland carries
zpool/zoneadm/dladm -- which would matter the moment hsimd exists, since this ISO would
then be the install source for a ZFS-root b134 system.

### P2-027: osol-dev-134 AI SPARC measured — dead end, and it completes the pattern

`osol-dev-134-ai-sparc.iso`, 278 MB, mounted read-only on the Ubuntu VM as /dev/sr0
(label `automated_installer_image_sparc`). b134 is the LAST public OpenSolaris dev build
(early 2010) and the direct ancestor of illumos-gate, so it was the best remaining
candidate for ZFS/zones/Crossbow. Measured:

    platform/sun4v                       present
    .../sun4v/kernel/drv/sparcv9/hsimd   ABSENT
    zpool / zoneadm / dladm / vnic       ABSENT
    lib/libc.so.1                        not present in the miniroot
    solaris.zlib                         91 MB  (lofi-compressed userland)
    solarismisc.zlib                     14 MB
    auto_install/ai_manifest.xml         wants a network IPS repo

Two independent disqualifiers. No hsimd, so it cannot see the vdisk. And it is an
AUTOMATED INSTALLER: it boots a stub and pulls packages from an IPS repository over the
network -- Sun's, which no longer exists. The tools we actually want were never on the
media.

`solaris.zlib` IS mountable (lofiadm on Solaris; decompress then mount -t ufs on Linux)
if anyone wants to inspect b134 binaries or headers, but the libc direction rules out
running them on our Solaris 10 image, exactly as with b59.

THE PATTERN IS NOW UNAMBIGUOUS, three media tested:

    media                        boots?                       donates?
    snv_77 OpenSPARC ramdisk     YES -- only image with hsimd  75 MB, no perl/pkgadd/tar
    SXCE b59 DVD                 no hsimd                      libc too new (1.22.2)
    osol-dev-134 AI              no hsimd                      network installer, no userland

hsimd is the whole game. STOP TESTING MEDIA -- the answer will be the same for any
distribution image, because the driver was only ever shipped inside Sun's OpenSPARC
simulator bundle. Every route forward runs through building it: P2-021 (source is 25 KB,
GPL-2.0) and P2-026 (Tribblix on QEMU sun4u as the build host, which breaks the
circularity).

### P2-025: SXCE b59 SPARC DVD measured — dead end BOTH ways

Ryan supplied `sol-nv-b59-sparc-dvd-iso.iso` (3.88 GB), attached to the Ubuntu VM as a
virtual DVD (`/dev/sr0`, label SOL_11_SPARC) rather than copied, since the playbox had
only 5.1 GB free. Two measurements settled it:

1. **It cannot boot on this machine.** The DVD has a sun4v miniroot
   (`Solaris_11/Tools/Boot/platform/sun4v`) so it runs on real T1000/T2000 hardware, but
   `kernel/drv/sparcv9/hsimd` is ABSENT and there is no SUNWhsim* package. Under QEMU
   niagara the installer would boot and find NO DISK, because the vdisk is reachable only
   through hsimd's 0xf0/0xf1 hypercalls. Confirms Tarasenko's remark that other
   distributions do not ship it. Also note the machine has no CD-ROM device at all --
   OBP sees only /virtual-devices/disk@0 -- so there is nothing to boot the DVD *from*
   even before the driver question.

2. **It cannot donate binaries to our Solaris 10 image.** Measured with readelf -V:

       b59 libc provides:        up to SUNW_1.23
       b59 /usr/bin/tar needs:   SUNW_1.22.2
       our S10 3/05 provides:    SUNW_1.22.1   <- the ceiling

   Any b59 binary demanding 1.22.2 dies with the same `ld.so.1: version 'SUNW_1.22.2'
   not found` that killed the 2014 CSW packages. Bringing b59's libc along cascades into
   replacing the OS.

CONSEQUENCE FOR THE SCOOP IDEA (P2-024): for THIS image the only safe source of binaries
is Solaris 10 3/05 media, which we already have and already use via
tools/iso-extract.py. Post-2006 Nevada/SXCE media can donate headers, source and data
files, but not executables or libraries. Check every candidate with `readelf -V` on the
host or `pvs -d` in the guest BEFORE copying anything in.

Still open and unaffected: building hsimd from
github.com/artyom-tarasenko/hsimd (GPLv2) for a chosen kernel, which is the only route
that makes any non-prepared image bootable here (P2-021).

Also on minnie: osol-0811-99-global.iso (OpenSolaris 2008.11) and Solaris 9 SPARC media,
both newer/older respectively and both subject to the same two tests.

### P2-024: boot the minimal snv_77 (it has hsimd) and scoop userland from full media

THE PLAN, Ryan's: boot the 80 MB OpenSPARC ramdisk image because it is the one thing
that can see the QEMU vdisk, then grow it and copy in whatever userland we need from
full-distribution media.

WHY hsimd IS THE GATE FOR EVERY OTHER ROUTE. The vdisk is reachable only through
`hsimd`, the OpenSPARC RAM-disk driver. Tarasenko states other illumos distributions do
not ship it. So a stock OpenSolaris/SXCE SPARC installer boots and then finds NO DISK to
install onto. That single fact, not licensing and not features, is what rules out
"just install a full distro". Our Solaris 10 image works because somebody had already
put hsimd in it.

MEASURED, ramdisk contents (mounted read-only on the host,
`mount -o loop,ro,ufstype=sun`):

    75 MB filesystem, 6.9 MB free (90% full)
    /usr/bin 82 entries, /usr/sbin 33 entries   (Solaris 10 ships ~700 in /usr/bin)
    174 kernel modules total                    (a full install has thousands)
    present : sh, sed, awk, dd, ifconfig, dld, /usr/local/bin/slirp-1.0.16-no-rsh-emu
    ABSENT  : perl, pkgadd, tar, cpio, gcc, cc, pppd
    ABSENT  : zpool, zfs, zoneadm, zonecfg, dladm, ipadm, and the zfs/vnic kernel modules
    libc ceiling: SUNW_1.23     (Solaris 10 3/05 here is SUNW_1.22.1)

So the ZFS/zones/Crossbow argument is true of snv_77 THE DISTRIBUTION but false of THIS
artifact: it is a stripped FPGA test ramdisk. Those features have to be scooped in, and
the kernel modules for them are not present either.

SCOOP SOURCE -- PREFER SXCE b77, NOT OpenSolaris 2009.06. Same build number means
binaries match the kernel and libc exactly. The ramdisk's ceiling is SUNW_1.23; pulling
2009.06 userland onto a b77 kernel reintroduces exactly the libc-version wall that cost
this project a day on Solaris 10. Target media, in order:
  1. `sol-nv-b77-sparc-dvd.iso` (SXCE build 77) -- ideal, availability UNVERIFIED
  2. OpenSolaris 2009.06 SPARC -- VERIFIED to exist: archive.org/details/
     OpenSolaris_2009.06_x86_Sparc, and it is "the first release of OpenSolaris for
     SPARC, adding support for UltraSPARC T1, T2 (Sun4v)". Newer libc, so use only for
     self-contained pieces, and check `readelf -V` on each before copying.

DEAD ENDS, recorded so nobody re-walks them:
  * OpenIndiana has NO 2008 release -- founded September 2010 after Oracle discontinued
    OpenSolaris. SPARC existed only in the unmaintained legacy oi-dev-151x branch, and
    Hipster has never supported SPARC.
  * "Project Indiana" in 2008 was OpenSolaris 2008.05, x86 only.
  * DilOS: ruled out by Ryan.

FIRST STEPS WHEN RESUMING:
  1. Boot the ramdisk under our patched QEMU (`-m 1024`, base-1gib firmware) and confirm
     it reaches a shell. Note his invocation used `if=pflash,readonly=on`; ours must be
     writable for any of this to persist.
  2. Grow the image and lay down a VTOC + UFS the way tools/ already does for S10. With
     6.9 MB free, nothing can be installed until this is done.
  3. Bootstrap a file-in path with only dd/sh/sed/awk -- no tar, no cpio, no pkgadd.
     The exchange slice (raw dd to a VTOC slice) is the proven mechanism and needs no
     network. Getting `tar` in first is probably the highest-value single scoop.

### P2-021: hsimd source is available — reopens two "dead end" conclusions

`github.com/artyom-tarasenko/hsimd`, GPLv2, updated Jan 2025. The OpenSPARC RAM-disk
driver imported from Legion. **This is the driver our guest uses for every disk
access.** This repo previously recorded, twice, that touching the guest driver was
unavailable and therefore closed off two routes:

  * the `ttyb` / second-console route, abandoned because `qcn` is a singleton driver and
    rebuilding a guest driver was judged circular
  * **P2-018**, mapping the shared region directly so the channel stops paying a
    hypercall per 512-byte block. That measured `~4000 blocks/sec` ceiling and the
    `EINVAL` on non-multiple-of-512 lengths both come from `hsimd`

Neither conclusion is safe now. `hsimd` is small, published, buildable, and the exact
place both problems live. Before any work: confirm the published source matches the
driver actually in this image, since the image is Solaris 10 and the driver came from
the OpenSPARC release.

### P2-022: distribute OpenSolaris snv_77 instead of Solaris 10 (licensing)

Tarasenko ships a prepared image (`qemu-sun4v-md` branch `snv77_slirp`,
`snv-with-slirp.gz`) because **OpenSolaris snv_77 from the OpenSPARC T1 package is
redistributable**. Solaris 10 is not. If the goal is a downloadable VM for strangers,
that is the legally clean base.

Cost, stated honestly: it abandons everything installed in the Solaris 10 image — gcc
4.3.3, dropbear, socat, the channel daemons, the rc scripts — because those are
S10-specific installs, not repo artifacts. The channel transport itself is
image-agnostic (it is bytes in a disk region), so the mechanism would port; the
userland would need rebuilding. Also note snv_77 lacks a real disk: it is a RAM-disk
image, so `patches/0001` writeback semantics differ.

MEASURED, by downloading his image and mounting it read-only (23 MB gz -> 80 MB raw,
`mount -o loop,ro,ufstype=sun`):

    filesystem      75 MB, 6.9 MB free (90% full)
    /usr/bin        82 entries        (Solaris 10 ships ~700)
    /usr/sbin       33 entries
    perl            ABSENT
    pkgadd          ABSENT
    tar             ABSENT
    cpio            ABSENT
    gcc / cc        ABSENT
    sh, sed, awk, dd  present
    slirp           /usr/local/bin/slirp-1.0.16-no-rsh-emu  (his build, present)
    libc ceiling    SUNW_1.23

THIS INVERTS THE OBVIOUS ASSUMPTION that redoing gcc/dropbear/socat there would be
faster now that the walls are mapped. Our ENTIRE bootstrap path is absent. Every install
today went: deliver a tar over the exchange slice, `tar xf -`, then `pkgadd`. snv_77 has
no tar, no cpio and NO PACKAGE MECHANISM AT ALL. It also has no perl, and every piece of
our channel tooling is perl: guest-dial.pl, guest-ppp-chan.pl, guest-pinetd.pl,
guest-chan-exec.pl. So the task is not "redo the same work faster", it is "invent a
bootstrap into 6.9 MB of free space using dd, sh, sed and awk", after growing the image
(VTOC + UFS work) before a single compile.

WHAT DOES TRANSFER: the flags (-lrt, -lssp, -R, GREP/EGREP, gmake not SunOS make), the
'missing usually means misplaced' rule, and the verification discipline. Real, but the
cheap half.

THE ONE REAL WIN IS LARGE: libc ceiling SUNW_1.23 versus S10's SUNW_1.22.1. That ceiling
is what killed gcc4core 4.9.0 and every modern CSW package today and forced us onto
SunOS5.8/5.9 builds. On snv_77 that constraint mostly disappears -- IF a package can be
installed at all without pkgadd.

RECOMMENDATION: do this ONLY if distributing to strangers is the goal, since licensing is
the sole real motivation. For a working playground, the S10 image is far ahead and the
UTM route ships it today. Decide before more work lands in the S10 image.

### P2-023: read FWARC 2005/115 before touching MD structure

`https://sun4v.github.io/ARChive/FWARC/2005/115` — the authoritative MD format spec,
named by Tarasenko in his Jan 2025 post, in which he also says he no longer remembers
how he built his own MD files. We reached byte-identical regeneration by reverse
engineering. Anything that changes MD *structure* rather than field values should start
here. Relevant to P2-018 if a new region has to be declared to the guest, which is the
part that previously looked impossible ("the guest sees only its 1024MB of RAM").

### P2-019: SOLVED -- stale frame replay, not desync, not host-up.sh, not echocli

The guest's first dial into the BBS returned EXACTLY 65536 bytes: the stale chan-test
payload still sitting in the channel data area. Documented behaviour, and the fix is
one command with both sides detached:

    pkill host-chan.py bridge N ; pkill guest-chand N   (both sides down)
    sudo python3 tools/chan/host-chan.py init N
    restart bridge, then guest daemon

After init: 'ch1 h2g seq=0 len=0 ack=0 | g2h seq=0 len=0 ack=0' and the channel worked
immediately.

THREE WRONG THEORIES, all from the same contamination. Every "control" I ran on
ch1/ch2/ch3 was taken while the 64KB corpse of the previous failed test was still in the
region, so they all failed identically and each failure looked like fresh evidence:
  1. "the bridge cannot survive a guest daemon restart (sequence desync)"
  2. "host-up.sh broke it" -- exonerated by ch3, which it never touches
  3. "guest-echocli is lying" -- it was faithfully echoing the stale 64KB

RULE FOR THIS PROJECT: a channel that failed a test MUST be re-initialised before the
next test, or you are measuring the previous experiment.

### P2-020: BBS oracle on a channel -- COMPLETE, all three verified

tools/chan/host-bbs.py. Verified: the guest dialled ATDT, got CONNECT 2400 and a
banner, and ASK returned a correct, image-specific answer (-lrt for nanosleep, with the
libposix4 warning) in about 20 seconds.

VERIFIED:
  * ASK       correct image-specific answer (-lrt for nanosleep) in ~20s
  * GET       reject path 'NOT AVAILABLE: HTTP 404' with nothing written; success path
              'DELIVERED 1017723 bytes (gzip)' with cksum. First version handed over a
              345-byte HTML error page as a .pkg.gz because curl exited 0 -- it now
              HEADs for status, uses curl -f, and validates magic bytes.
  * STARTPPP  guest sppp1 inet 10.0.6.15 --> 10.0.6.1, host ppp1 10.0.6.1 peer
              10.0.6.15/32, ping 3/3 0% loss. TWO simultaneous PPP links over two
              channels of one region: ch0 carries SSH, ch1 was dialled by the guest.

GUEST-INITIATED NETWORKING IS SOLVED. The caller decides when the line switches, so a
guest reboot no longer needs a host-side command. tools/chan/guest-dial.pl does the
dialling (perl, because Solaris 10 has 5.8.4 with sockaddr_un and no python, and socat
cannot do a read-then-exec handoff on one fd).

KNOWN DEFECT, still open: Session.send() catches OSError and passes, so it cannot
report its own failure -- the same defect criticised in the dropbear rc script the same
afternoon. Make it log or raise.

TESTING NOTE: do not test this over 'socat - UNIX-CONNECT' inside shell pipes. That
harness reported 0 bytes against a daemon that was working; a direct Python socket
client showed 620 bytes of banner on the first try.

### P2-019: guest->host inbound dead on ch1/ch2 after reboot (BLOCKS dial-in)

MEASURED, not interpreted:

    channel | host->guest | guest->host
    ch0     | works       | works     (PPP + SSH bidirectional, verified repeatedly)
    ch1     | works       | NOTHING   (rc-started daemon, never touched by me)
    ch2     | works       | NOTHING   (echocli logged 'echoed 65536 bytes (total 131072)')

The guest receives and echoes the payload; the host never reads the return. Before the
guest reboot ch2 round-tripped 65536 B in 0.48s (269 KB/s, MATCH). After the reboot plus
a host-up.sh bridge restart, ch1 and ch2 time out at 45s with 'got 0' while ch0 carries
PPP and SSH perfectly.

WHY IT BLOCKS THE NEXT FEATURE. The plan is a host daemon listening on a channel for the
guest to ask for PPP -- guest-initiated dial-in ("ATDT 1800-old-skool") replacing the
manual host command. That depends on precisely the direction that is broken: guest->host
on a NON-PPP channel. Prerequisite, not a side issue.

NEXT STEP MUST BE AN INSTRUMENT CHECK, NOT A FIX. Test ch1 inbound BEFORE running
host-up.sh on a fresh boot. Every "control" in this stretch was taken AFTER a bridge
restart, so 'the reboot broke it' and 'host-up.sh broke it' are not yet
distinguishable. host-up.sh is the newest, least-tested code in the path and is suspect
number one.

TWO CLAIMS RETRACTED while chasing this, both from skipping controls:
  - "the host bridge cannot survive a guest daemon restart (sequence desync)" -- ran on
    ch2 with no control; ch1 fails identically untouched, so my restart is not the cause.
  - "/opt/niag/bin/guest-chand does not exist" -- it does; 'ps -eo args' shows it running
    and its log shows 'ch2 client connected'. My ls was mangled by ssh quoting and I read
    the mangled output as evidence.

STILL TRUE from a7337cd: the leak was real (3 bridge writers per channel, 5 pppd),
host-up.sh is verified idempotent, and PPP-after-reboot works via one command. But "the
leak was the whole bug" is no longer supported: inbound is dead WITH one writer per
channel.

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
the FAT slice as `ppp.tar`. the historical `tools/provision-ppp.exp` (removed; it targeted the pre-P2-012 zvol) installed it, ran
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

### P2-012: Back the vdisk with mmap(MAP_SHARED) instead of anonymous RAM [x] DONE 2026-08-18

**DONE and verified.** Commits ee588af (C change), d83960c + 5226a80 (tooling),
e7421aa (end-to-end boot), 1f33af1 (suite 7/7).

Proof it works, not an assertion: a canary written in the guest, quiesced, then
`kill -9` on QEMU — with the atexit writeback DELETED from the binary — was present
in the image file afterwards.

Measured wins:
- **~2.4GB host RAM per VM returned.** Running guest: RssAnon 422172 kB (guest RAM)
  + RssFile 125012 kB (vdisk pages touched), versus 2560MB pinned anonymous before.
  Page cache is evictable and grows only as the guest touches blocks.
- No 2560MB read at boot, no 2560MB write at exit.
- 239 lines of copy machinery deleted, including the P2-014 flush/reload timer
  written the same morning and the writeback-clobbers-host-writes race with it.
- Image is 585M on disk against 2.5G apparent (recordsize=8K + lz4).

Storage moved to `datapool/niagara/images/primary.img`; the pre-migration zvol is
retained at `vms/primary` with `@pre-p2012-cutover` as a fallback.

The reviewer was right that this belonged before P2-014, and both of my reasons for
deferring it were wrong — see REVIEW-RESPONSE.md Round 2.

Supersedes the entire checkpoint apparatus (P2-010, P2-011) if it works.

Today the vdisk is anonymous host RAM with a manual copy at each end: 2560MB read
at boot, 2560MB written on flush. Every storage annoyance descends from that one
choice -- 10s flushes regardless of how little changed, 2560MB of non-evictable
host RAM per VM, `kill -9` losing everything, durability needing a six-step
script, and the host being blind to guest writes until a flush.

Fix: `memory_region_init_ram_from_file()` with `RAM_SHARED`, i.e.
`mmap(MAP_SHARED)` of a raw image FILE. Then a guest store dirties a page-cache
page backing that file and the kernel writes it out. Writes reach the disk with
no writeback code at all, and pages fault in on demand so the boot-time read
disappears too. `msync(MS_SYNC)` becomes the durability point, replacing
`kill -USR2` + monitor stop/cont.

With the image on a ZFS filesystem, host-side `zfs snapshot` / `zfs rollback`
then give checkpointing and undo for free, at any time, with no guest
cooperation and no QEMU involvement.

Two constraints, both verified-by-reasoning not yet by test:
- Must be a regular FILE. Block devices (zvol) do not reliably support
  MAP_SHARED writeback, so this means migrating from the zvol to a raw file.
- ZFS recordsize wants tuning (8K/16K) against small guest writes, or every
  512-byte write becomes a 128K read-modify-write.

Migration cost is tooling, not emulator work: peek.sh, exchange.sh, vtoc.py,
zvol.sh and the tests all address the zvol path today.

### P2-013: Shared-memory host<->guest channel with a guest daemon [ ]

The performance case, measured, is the entire argument:

| channel | throughput | needs VM down? |
|---|---|---|
| raw slice via vdisk RAM | **~11 MB/s** (91MB in 8s) | today yes, see below |
| NFS over PPP | **~11 KB/s** | no |

Three orders of magnitude. The ssh+bash install took ~7 minutes almost entirely
because 3.7MB crossed NFS-over-PPP; through the shared region it is well under a
second.

**Key realisation: the guest can already address the shared region live, with
nothing mounted.** `/dev/rdsk/c0t0d0s3` is the RAW character device, so a read is
`read()` -> `hsimd` -> hypercall 0xf0 -> `memcpy` from vdisk RAM. No buffer cache,
no filesystem, nothing to invalidate. So the earlier claim that the exchange slice
"requires the VM to be down" was WRONG. What is actually true is narrower: the
guest never re-reads the zvol after reset, because the whole 2560MB was copied
into QEMU's anonymous RAM. Host writes must therefore target QEMU's RAM, not the
zvol -- and a zvol write during a session is additionally doomed because the next
writeback copies RAM over it.

Design:

```
slice 3, first 64KB = control block
    magic | seq | direction | opcode | length | payload...
guest daemon: poll /dev/rdsk/c0t0d0s3 via lseek/read, act, write reply
host tool:    write the same offsets into QEMU's vdisk RAM
```

Two ways for the host to write:
1. ~~`/proc/<pid>/mem`~~ **RULED OUT 2026-08-18, do not retry.** Reads of
   `/proc/<pid>/mem` against a LIVE TCG guest block on QEMU's `mmap_sem` and the
   reader enters uninterruptible D state permanently -- one was left wedged for 13
   minutes and had to be SIGKILLed. Not permissions, not code: lock contention
   with the TCG execution loop. `/proc/<pid>/maps` reads fine (`wc -l` returns
   1080 lines); it is `mem` that wedges. The historical write-canary read
   presumably succeeded against a quiescent or stopped guest. If this route is
   ever wanted, `stop` the guest via the monitor first -- but route 2 is better
   anyway.
2. A reload path in `niagara.c` -- the exact inverse of
   `niagara_vdisk_writeback_full()`, re-reading ONLY slice 3 from the zvol into
   RAM. ~20 lines beside code that already exists, and safer since it cannot
   touch the root slice.

This is, structurally, what QEMU itself converged on: virtiofs DAX maps file
contents into a shared memory window so the guest reads them without copies. We
have the window; we lack the protocol. virtio-9p and virtiofs both need a virtio
bus and a guest driver, so neither is reachable without rebuilding q.bin (P2-007).

Caveats: polled, not interrupt-driven -- no doorbell exists, so a guest daemon
costs some TCG time (100ms with backoff is fine). And live host->guest visibility
is REASONED, not verified: the guest seeing the zvol's boot-time FAT content does
not prove it sees a mid-run host write.

Sequence deliberately: implement the route-2 reload FIRST, then the control
block, then the daemon.

PoC attempt 2026-08-18 was abandoned mid-flight for an unrelated reason worth
recording: biggie hit load average 170 from a swarm of unrelated `php` processes,
which starves a single-threaded TCG guest so badly that raw-slice `dd` commands
stopped returning. Guest-side timings are meaningless while host load is high --
check `uptime` before trusting any throughput measurement from this VM. If the write side surprises us, everything above it is
moot. gcc 4.3.3 is in the guest, so the daemon is a small C program.

### P1-008: exchange.sh mkfs silently destroys the 16MB scratch region [x] DONE 2026-08-18

**DONE and verified.** Commit 7d7d990. `mkfs` now passes an explicit 1K-block
count so the filesystem is 496MB inside its 512MB slice, named
`FAT_NBLKS`/`SCRATCH_*` constants with a sum assertion, a `scratch` subcommand
emitting sourceable offsets, and a before/after cksum check on the tail.
`test-fat-exchange.sh` seeds a real-text canary and asserts it survives a second
mkfs — and explicitly fails if the seed reads back as 4135437457, so a
zeros-vs-zeros pass is impossible.

Verified with real data: canary 1902459303 survived mkfs byte-exact, FAT 495MB
usable, put/get round-trips, tail intact through format+mount+write+umount.

`tools/exchange.sh` hardcodes `EXCH_NBLKS=1048576` (512MB) and `cmd_mkfs` formats
the FAT across the WHOLE slice. The scratch region P2-014 depends on exists only
because the filesystem was deliberately made SMALLER than its slice:

```
s3 slice:       1048576 blocks (512MB)
FAT filesystem: 1015808 blocks (496MB)   <- mkfs -o nofdisk,fat=32,size=1015808
scratch:          32768 blocks (16MB)    <- s3 blocks 1015808..1048575
```

So `exchange.sh mkfs` re-formats at 512MB, the FAT reclaims the tail, and the
region is gone with no warning -- corrupting anything there as soon as the
filesystem allocates into it.

**Worse: `tests/test-fat-exchange.sh:57` calls `exchange.sh mkfs`.** The test
clones its own zvol so `primary` is not directly at risk, but the pattern is
there to be copied, and running `mkfs` against `primary` kills the region.

Fix:
1. Named constants beside `EXCH_NBLKS`: `FAT_NBLKS=1015808`,
   `SCRATCH_START=1015808`, `SCRATCH_NBLKS=32768`, so the split is explicit and
   the two numbers cannot drift apart.
2. `cmd_mkfs` passes an explicit sector count instead of defaulting to the whole
   slice, matching the guest's `mkfs -F pcfs -o nofdisk,fat=32,size=1015808`.
3. Add `cmd_scratch_info` printing the byte offsets so callers stop recomputing
   them by hand (absolute bytes 2667577344..2684354559).
4. `test-fat-exchange.sh` writes a canary into the scratch region before `mkfs`
   and asserts it survives -- turning this from a doc comment into something the
   suite enforces.

Filed because a warning buried in CURRENT-STATE is not a guard. Until fixed,
treat `exchange.sh mkfs` as destructive to P2-014.

### P2-016: make a Fire-enabled hypervisor boot under QEMU [ ]  <-- gates all PCI work

Prerequisite for P2-015 / `SPEC-fire-bridge.md`. Our S10image q.bin has no
`CONFIG_FIRE`, so PCI cannot work no matter what QEMU does.

**No building required.** `greatlakes/ontario/release/q.bin` already exists
prebuilt with Fire compiled in (205144 bytes, 7/7 Fire addresses present). The
job is to find out why in-tree builds hang under QEMU when our S10image build
boots fine. Two known-good reference points to diff against.

Recorded from earlier sessions: debug/release/legion builds all hang, believed to
want SAM runtime APIs that QEMU does not provide. That belief is untested and is
the first thing to check.

Suggested approach:
1. Boot `release/q.bin` under QEMU and capture exactly where it stops. Compare
   against S10image's boot trace to localise the divergence.
2. `legion/q.bin` and `t1_fpga/q.bin` have Fire DISABLED like ours -- if either
   boots, the hang is unrelated to Fire and is about SAM/platform assumptions,
   which narrows the problem sharply. If neither boots but ours does, the delta
   is in whatever makes S10image special.
3. Only then decide between fixing the in-tree build's platform assumptions
   versus rebuilding S10image's configuration with `-DCONFIG_FIRE` added.

Note the size ordering is informative: ours (163216) is smaller than every
in-tree variant including the Fire-less ones (189224, 190656). S10image is a more
minimal configuration than anything in the tree, so its Makefile differs in more
than just CONFIG_FIRE.

### P2-014: 16 bidirectional channels as AF_UNIX sockets both sides [ ]  <-- NEXT

**REDESIGNED after P2-012, and much smaller.** The flush/reload timer this item
originally needed was written and then deleted, because host and guest now look at
the SAME PAGES: the host `mmap`s `images/primary.img`, the guest reaches the same
bytes via `/dev/rdsk/c0t0d0s3`. No timer, no signals, no copy, no monitor.

What remains is the part no backing store provides for free: **sequence-validated
framing**, so a reader cannot observe a torn write. Publish the payload, then the
index, and have the reader validate. That work is identical under any backing,
which was the one piece of my original argument that survived review.

Region (from `tools/exchange.sh scratch`, never recompute by hand):
```
SCRATCH_START_BLK=5210112      SCRATCH_BYTE=2667577344
SCRATCH_NBLKS=32768            SCRATCH_BYTES=16777216   (16MB)
SCRATCH_GUEST_S3_BLK=1015808
```

**THE RAW SHARED PATH IS NOW VERIFIED, both directions, on a LIVE VM**
(2026-08-18). Real non-zero checksums, agreed by both sides, with no msync, no
shutdown and no copy:

```
guest wrote blk 1015808  -> host read image blk 5210112:  1178759309  AGREE
host wrote  blk 5210113  -> guest read s3  blk 1015809:   1095390573  AGREE
```

The host->guest direction is the one that was IMPOSSIBLE before P2-012: host
writes went to the zvol while the guest read QEMU's private RAM copy. Shared pages
fixed it, and the channel premise is now proven rather than assumed.

**Use `iseek=`, never `skip=`.** `skip=1015808` takes ~254 seconds because it
linearly reads every intervening block at ~4000 blocks/sec; `iseek=1015808` is
0.1s via lseek. A stale rule in CURRENT-STATE claimed reads at high offsets hang,
which blocked this item for a day and was simply wrong — see the corrected entry.

**Throughput budget for the protocol design:** ~4000 single-block hypercalls/sec,
~2 MB/s at bs=512. That argues for large transfers per hypercall rather than many
small ones, so the ring should move big frames and the header poll should be a
single small read.

Guest-side rules that apply here (see CURRENT-STATE): raw `/dev/rdsk` writes MUST
be whole 512-byte blocks, never touch s2, and never interrupt in-flight disk I/O.

What the user actually wants: fast host<->guest comms to build network and
storage drivers on, replacing PPP (~11KB/s) as the foundation.

**Recommended mechanism: ring buffers in the 16MB tail of s3.**

Chosen over the 2MB ramdisk because the guest ALREADY has a working driver for
the vdisk (`hsimd`, hypercalls 0xf0/0xf1) and the offset is fixed by
construction. The ramdisk address (found at guest physical 0x82843000 by canary
scan) is an artifact of Solaris' allocator, not a contract.

```
16 channels x 1MB:  4KB header + 510KB h2g ring + 510KB g2h ring
header: magic | seq_h2g | seq_g2h | head | tail | len | flags
```

Two independent rings per channel = no cross-direction locking.

- **guest daemon** (~200 lines C, gcc is present): open /dev/rdsk/c0t0d0s3,
  create /tmp/niag/0..15 AF_UNIX sockets, shuttle bytes to/from ring slots,
  poll 10-20ms with backoff
- **host daemon**: same shape, /run/niag/0..15, same offsets
- result: identical AF_UNIX sockets on BOTH sides, so anything speaking sockets
  works -- PPP replacement, NFS transport, block protocol

**Required QEMU work: ranged flush/reload in niagara.c** -- `flush_range(off,len)`
and `reload_range(off,len)`, ~30 lines, because the existing writeback loop is
already offset-based. A 4KB header sync is sub-millisecond.

**Then immediately do P2-012**: back the vdisk with
`memory_region_init_ram_from_file(RAM_SHARED)`. The host side becomes plain mmap
of a file -- no signals, no flush, no QEMU cooperation -- and the whole
synchronisation problem disappears.

Expected: ~11MB/s bulk (1000x PPP), latency = poll interval, dropping to
microseconds once file-backed.

Order: (1) ranged flush/reload, (2) ONE channel end-to-end with `cat`,
(3) scale to 16 and measure, (4) MAP_SHARED, (5) then drivers.

Keep the ring format virtio-compatible so the userland daemon can later become a
kernel driver with nothing above it changing.

### P2-015: The real Niagara HAD PCIe -- and q.bin has Fire support [ ]

Overturns my earlier claim that PCI was hopeless. Evidence from the image:

```
/platform/sun4v/kernel/drv/sparcv9:  px  bge  ce
/kernel/misc/sparcv9:                busra pcicfg pcie pcihp
/dev/term/a -> ../../devices/pci@7c0/pci@0/pci@2/pci@0,2/isa@2/serial@0,3f8:a
```

`px` is Sun's PCIe nexus driver; `bge`/`ce` are the onboard NICs of the real
T1000/T2000; the dangling `/dev/term/a` symlink is a fossil of that hardware. So
**the GUEST is fully PCI-capable** -- what is missing is the host bridge in
QEMU's niagara machine.

**And q.bin already has Fire (the JBus-PCIe ASIC) support:**

```
hypervisor/src/greatlakes/common/src/vpci.s
hypervisor/src/greatlakes/common/src/vpci_msi.s
hypervisor/src/greatlakes/ontario/src/vpci_fire.s
hypervisor/src/greatlakes/ontario/src/vpci_errs.s
```

This matters because **sun4v PCI is HYPERVISOR-MEDIATED**: `px` does not touch
config space or MSI directly, it calls hypervisor APIs. So emulating Fire means
satisfying BOTH QEMU-side MMIO AND q.bin's `vpci_fire` expectations.

**INVESTIGATION DONE 2026-08-18. ANSWER REVERSED -- PCI IS *NOT* IN OUR q.bin.**

An earlier version of this item claimed the opposite. That was WRONG. Corrected
by a controlled experiment; the reasoning that misled me is preserved below so
nobody repeats it.

**Everything is gated on `CONFIG_FIRE`:**

```
setup.s:668   #if defined(CONFIG_FIRE)   ... setup_fire ... #endif  (line 793)
main.s:429    #ifdef CONFIG_FIRE   HVCALL(setup_fire)   #endif
config.c:92   #if defined(CONFIG_FIRE)   ... const struct fire_cookie fire_dev[]
```

**THE CONTROLLED TEST.** `fire_dev[]` holds hardcoded addresses computed by the
`AID2*` macros, so their presence in a binary is a direct proxy for
`CONFIG_FIRE`. The in-tree Makefiles state each variant's setting, giving known
positives AND known negatives to validate the method:

| build | CONFIG_FIRE | size | Fire addrs found |
|---|---|---|---|
| `ontario/debug/q.bin`   | `-DCONFIG_FIRE` | 246024 | **7** |
| `ontario/release/q.bin` | `-DCONFIG_FIRE` | 205144 | **7** |
| `ontario/legion/q.bin`  | `-UCONFIG_FIRE` | 190656 | 0 |
| `ontario/t1_fpga/q.bin` | `-UCONFIG_FIRE` | 189224 | 0 |
| **`S10image/q.bin` (OURS)** | **absent** | **163216** | **0** |

Addresses probed as 64-bit big-endian: `0x800f000000` (jbus A), `0x800f800000`
(jbus B), `0x800f600000` (pcie A), `0xe800000000` (cfg A), `0xf000000000` (cfg B).
The method separates known-on from known-off perfectly, and our binary groups
with the negatives. It is also the smallest of the five, 26KB below the smallest
Fire-less in-tree build.

**Why the earlier evidence was a red herring.** The `vpcidevice`/`cfgbase`/
`pciregs` strings ARE in our q.bin -- but `setup.s:164` sits inside NO
conditional, so those `GET_NAMEOFFSET` names are emitted unconditionally whether
Fire is compiled or not. Their presence proves only that the MD name table is
complete. Two further probes were inconclusive and should not be retried:
the hypercall dispatch table cannot be found in any build (see the negative
result below), and `PRINT` banner strings like `HV:setup_fire` exist only in
`debug` builds because `PRINT` is DEBUG-gated -- `release` has Fire but no banner.

**CONSEQUENCE: the order flips. Fire needs a Fire-enabled hypervisor first.**

But this is much cheaper than a from-scratch P2-007 rebuild, because
**`ontario/release/q.bin` ALREADY EXISTS prebuilt with Fire compiled in** (205144
bytes, 7/7 Fire addresses). Nothing needs building. The task becomes: find out
why the in-tree builds hang under QEMU where our S10image build boots. That is a
bounded debugging problem against a known-good reference, not a toolchain
project. See P2-016.

Three pieces of evidence:

1. **The PCI hypercall DISPATCH TABLE is unconditional** in
   `greatlakes/common/src/hcall.s` -- no `#ifdef` around it. NOTE: this is what
   originally misled me. The table being unconditional does NOT mean the Fire
   INITIALISATION is; `setup_fire` and `fire_dev[]` are both `CONFIG_FIRE`-gated,
   so a build can carry the hcall entries while having no initialised hardware
   behind them. Full API from `include/hypervisor.h`:
   ```
   VPCI_IOMMU_MAP    0xb0    VPCI_CONFIG_GET   0xb4
   VPCI_IOMMU_UNMAP  0xb1    VPCI_CONFIG_PUT   0xb5
   VPCI_IOMMU_GETMAP 0xb2    VPCI_IO_PEEK      0xb6
   VPCI_IOMMU_GETBYPASS 0xb3 VPCI_IO_POKE      0xb7
   VPCI_DMA_SYNC     (in group)
   MSIQ_*            0xc0-0xc8    MSI_*      0xc9-0xce
   MSI_MSG_*         0xd0-0xd3
   ```
   Declared as `GROUP_BEGIN(pci, API_GROUP_PCI)`, API group index #3, major 1
   minor 0.

2. **q.bin contains the COMPLETE MD-name string table, including every PCI
   property.** Re-verified properly 2026-08-18 after the first pass rested on a
   single `strings` hit. All **56/56** names that `setup.s` passes to
   `GET_NAMEOFFSET` are present in `/datapool/niagara/base/q.bin`,
   NUL-terminated, as a contiguous table at `0x14bc4`..`0x153f8` in source
   order:

   ```
   0x14ff0  vpcidevice     0x15018  cfghandle    0x15040  ign
   0x15060  intrtgt        0x15084  cfgbase      0x14dd4  membase
   0x150f0  pciregs   <-- additional PCI property, not in the earlier list
   ```

   The clincher is **string suffix sharing**, which proves these were emitted by
   one build construct rather than being incidental text:

   ```
   0x14ff0  vpcidevice      0x14d44  nvsize      0x14cf8  uartbase
   0x14ff4      device      0x14d46      size    0x14cfc      base
   ```

   `device` at +4 IS the tail of `vpcidevice`.

   **NEGATIVE RESULT worth recording so nobody repeats it:** the hypercall
   dispatch table could NOT be located in the image. `GROUP_HCALL_ENTRY(number,
   function)` expands to `.xword number, function`, but scanning q.bin for
   big-endian 64-bit hypercall numbers at a 16-byte stride found ZERO -- not
   0xb4, but also not `CONS_PUTCHAR 0x61` or the niagara disk calls 0xf0/0xf1,
   which demonstrably work. So that absence says nothing about PCI; it says our
   q.bin's table layout differs from this source tree, consistent with the
   already-known fact that it matches no in-tree build variant. Do not treat
   "hypercall number not found in binary" as evidence of anything.

3. **q.bin discovers PCI from the MACHINE DESCRIPTION**, which is the part we
   control:
   ```
   greatlakes/ontario/src/setup.s:164:
       GET_NAMEOFFSET("vpcidevice", HDNAME_VPCIDEVICE, %l1, %l2)
   greatlakes/ontario/include/config.h:146:
       uint64_t hdname_vpcidevice;
   ```

**The MD node properties q.bin reads**, from the `GET_NAMEOFFSET` calls
surrounding that line in `setup.s`:

```
vpcidevice: cfghandle, ign, intrtgt, cfgbase, membase, base, size, ino, xid, sid
```

`cfgbase` = PCI config space base, `membase` = memory window, `ign`/`ino`/
`intrtgt` = interrupt routing. That is exactly the Fire host-bridge description,
and it defines the QEMU side precisely.

**So the plan is now concrete:**
1. Add a `vpcidevice` node to `md/common.pdesc` with the properties above.
   We have the toolchain and `test-md-roundtrip` guards byte-identical
   regeneration.
2. Emulate the Fire host bridge in `niagara.c` at `cfgbase`/`membase` -- the
   first `MemoryRegionOps` this machine has ever had.
3. q.bin initialises its Fire driver and exposes the PCI hypercall API.
4. Solaris `px` attaches through that API (it never touches config space
   directly -- sun4v PCI is hypervisor-mediated).
5. Hang an emulated NIC that `bge` or `ce` can drive.

Step 5 is why this beats virtio: those drivers ALREADY EXIST in the image, so
real networking needs zero new guest code. Virtio would need a Solaris virtio
driver, which does not exist for 2005 Solaris.

**What the evidence does and does not establish.** PROVEN: q.bin's MD parser
resolves `vpcidevice` and all its properties, and the PCI hypercall group is
unconditional in the source. NOT PROVEN: that the handlers are present and
functional in our specific binary -- the dispatch table could not be located in
any form (see the negative result above). The real test remains q.bin's Fire init
running against an emulated bridge, so step 2 below should be built to fail
loudly and observably rather than silently.

Remaining unknowns, in order of risk: whether the PCI hypercall handlers are
actually live in our 163KB build; whether q.bin's Fire init tolerates a
partially-emulated bridge; whether `flatblk` bites when the config/mem windows
are added (though the vdisk region at 0x1f40000000 proves device-space regions
CAN work); and how much of Fire `px` actually requires before it will attach.

The prize is bigger than virtio: if `px` attaches, **`bge`/`ce` become reachable
with drivers that already exist** -- real networking, zero new guest code. Virtio
by contrast would still need a Solaris virtio driver, which does not exist for
2005 Solaris and would have to be written.

### P2-009 update: NetBSD 8.3 kernel cross-build BLOCKED [ ]

8.3 confirmed as the last release with COMPAT_SVR4, verified from the running
kernel -- but both options are COMMENTED OUT in its sparc64 GENERIC, and the
guest has no /usr/src. So it needs a kernel build.

Cross-build attempted on biggie at `/datapool/netbsd83`:
- sources fetched and `gzip -t` verified: src.tgz 175.7MB, syssrc.tgz 51.6MB,
  gnusrc.tgz 139.4MB, sharesrc.tgz 7.1MB (247819 files, 2.0GB extracted)
- `SVR4GEN` kernel config created = GENERIC + COMPAT_SVR4 + COMPAT_SVR4_32
- `./build.sh -U -u -m sparc64 -j 40 tools` **FAILED**:
  `external/gpl3/gcc/dist/gcc/reload1.c:115:24: error: use of an operand of type
  'bool' in 'operator++'` -- GCC-4-era source rejected by biggie's modern host
  compiler (bool++ removed in C++17). Needs an older host compiler or added
  `-std=`/`-fpermissive` flags.

Download note: `archive.netbsd.org` returns **HTTP 402 (rate limited)** if hit
with 16 connections, and that corrupted two archives mid-flight. `ftp.fau.de`
served them at 8.9MiB/s with `-x4`. Most other mirrors have dropped 8.3.

Reminder: this whole item is OPTIONAL. `qas` already runs natively on the
Solaris guest, which was the only reason we wanted compat_svr4.

### P2-011: Atomic checkpoints via monitor stop/cont  [ ]

Still open, but MUCH smaller after P2-012: there is no 2560MB copy to make atomic
any more, only an `msync`. Durability is automatic; what is missing is a
guaranteed-consistent instant. The `stop`/`cont` freeze remains unexercised — a
checkpoint run on 2026-08-18 printed
`WARNING: monitor did not respond; flushing WITHOUT freezing`, so the path is not
merely untested, it is currently not working.

Depends on: P2-010 (checkpoint facility, done)

`tools/checkpoint.sh` currently produces a **crash-consistent** image, not an
atomic one. It quiesces the guest filesystem over telnet (`sync; lockfs -f /`)
and then flushes, but **the guest's CPUs keep running throughout**, so any write
issued between the lockfs completing and the 2560MB flush finishing is still in
flight. In practice the guest is idle at a shell prompt so this has not bitten
us, but it is luck, not design — and the failure mode is the one that costs the
most: an image whose LUFS journal needs replay panics the next boot in
`ufs:readlog -> vfs_mountroot`.

Fix: freeze the CPUs around the flush.

```
monitor: stop          <- guest CPUs halted; vdisk RAM cannot change
host:    kill -USR2 <qemu-pid>
         (wait for "vdisk writeback complete")
monitor: cont
```

Work required:

1. Add `-monitor unix:/tmp/sol-mon.sock,server,nowait` to `tools/net-up.sh`.
   The monitor is currently on stdio, which is why it is not scriptable — and
   why `Ctrl-A c` was never an option under expect.
2. In `tools/checkpoint.sh`, drive that socket (`socat - UNIX-CONNECT:...` or a
   tiny expect) to issue `stop`, then the SIGUSR2 flush, then `cont`.
   Keep the telnet quiesce BEFORE the `stop`: `lockfs` needs a running guest.
3. Guarantee `cont` runs even if the flush fails, or the guest is left frozen —
   wrap in a shell trap.
4. While the monitor is scriptable, `pmemsave 0x1f40000000 <size> file` becomes
   available too, which is Artyom Tarasenko's original persistence trick and a
   useful independent cross-check that our writeback wrote what we think.

Acceptance: checkpoint a guest that is actively writing (e.g. a loop appending to
a file), `kill -9` QEMU, then boot the result. It must come up WITHOUT a journal
replay panic, and the file must be intact up to the checkpoint. That is a
stronger test than the P2-010 one, which checkpointed an idle guest.

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

### P2-018: Map the shared region DIRECTLY, off the disk codepath [ ]

**The honest critique of P2-014: we are doing message passing through a disk
stack.** Every byte goes guest userland -> pread/pwrite on /dev/rdsk/c0t0d0s3 ->
hsimd -> hypercall 0xf0/0xf1 -> q.bin -> memcpy -> the MAP_SHARED page. That exists
because it needed NO new guest driver, which was the right trade to get something
working. It is not the right long-term shape.

MEASURED COSTS of the disk path:
- ~2 MB/s ceiling: every 512-byte block is a hypercall round trip through TCG
  (~4000 blocks/sec). This is why 16 channels SHARE 2.4 MB/s rather than
  multiplying it.
- 512-byte alignment required on offset AND length (an unaligned length returns
  EINVAL; an unaligned write is silently dropped).
- Polling only. No doorbell, hence the 20ms->400ms backoff.
- **It contends with the real filesystem.** Root UFS uses the SAME hypercall path
  to the SAME vdisk, so channel traffic and guest disk I/O compete directly.

WHAT WOULD BE BETTER: let the guest map the region directly -- byte-granular,
memory-speed, no hypercall per block.

BLOCKER, verified 2026-08-18: the guest's physical map contains only its own RAM.
`prtconf` reports "Memory size: 1024 Megabytes" and zero mblock entries. The vdisk
region at 0x1f40000000 is real-address space that q.bin can reach and the guest
cannot. /dev/mem exists (pseudo/mm@0:mem) but cannot map a real address the
hypervisor has not given the guest.

EXPERIMENTS, cheapest first, all on a clone with a snapshot taken:
1. Try mmap of /dev/mem at 0x1f40000000 from guest userland anyway. Zero risk, and
   settles whether the hypervisor permits it. Expect failure, but it costs minutes.
2. Declare the region to the guest with an MD node and see whether Solaris maps it.
   We now have the MD toolchain with byte-identical regeneration
   (tests/test-md-roundtrip) which we did not when this was last attempted. THIS IS
   THE FLATBLK RISK: adding RAM regions previously panicked the guest four ways.
   Mitigated by the fact that the vdisk region at 0x1f40000000 already works as a
   device-space region, so device space is not inherently poisoned.
3. If 2 fails, this becomes a q.bin item (a hypercall that maps the region), which
   is gated behind P2-016.

Do NOT start this before P2-017. IP over the existing channel is worth more than a
faster channel with nothing on it, and P2-017 needs no new risk.

### P2-017: Move IP onto the channel [~] WORKING, not yet automated

**Achieved 2026-08-18.** IP runs over channel 0 and the console is FREE -- a root
shell with no pppd on it. That is what P2-008 was going to buy, obtained by deleting
the squatter rather than adding hardware.

```
ppp0            10.0.5.1 peer 10.0.5.15/32
ch0             h2g seq=8 ack=9 | g2h seq=9 ack=8   (both directions flowing)
ping guest      0% loss          telnet :23 open
guest->8.8.8.8  0% loss, 93-230ms
```

No pty was needed after all: `pppd notty` speaks stdin/stdout, so
`tools/chan/guest-ppp-chan.pl` just dup2s a channel socket onto fd 0/1. Perl 5.8.4
in the image has Socket with sockaddr_un, so nothing had to be built -- and
crucially NOT socat or netcat, which would have meant fighting the SUNW_1.22.1 libc
ceiling for machinery we do not need.

Guest default route now persisted to `/etc/defaultrouter`. It had never been
persistent, which is why it vanished across a reboot and looked like NAT had broken.
Host MASQUERADE was present throughout.

**MANUAL BRING-UP that works, in this exact order:**
```
host   stop everything; python3 tools/chan/host-chan.py init 0
guest  /opt/niag/bin/guest-chand 0 &
guest  perl /opt/niag/bin/guest-ppp-chan.pl 0 10.0.5.15:10.0.5.1 &
host   python3 tools/chan/host-chan.py bridge 0 &
host   socat UNIX-CONNECT:/run/niag0 EXEC:'pppd notty noauth local \
         asyncmap 0xffffffff 10.0.5.1:10.0.5.15 nodetach',nofork &
host   iptables MASQUERADE + ip_forward
guest  perl /opt/niag/bin/guest-pinetd.pl &      (for telnet)
```

**BUG 1 -- startup adoption deadlocks with a frame in flight.** Both sides adopt the
region's seq at startup to avoid replaying stale frames. But if the host bridge has
already published a frame (host pppd sends LCP immediately), the guest starts, adopts
seen_seq = that seq, treats the pending frame as already seen, and never acks it. The
bridge's gate is `peer.ack_seq >= my_seq`, so it waits forever for an impossible ack.
FIX: ack the adopted seq at startup, discarding a stale in-flight frame rather than
deadlocking on it.

**BUG 2 -- host pppd exits if the guest is not up yet.** It burns its LCP retries
against an empty channel and dies with an EMPTY log, leaving ppp0 DOWN and no clue
why. The guest side retries the connect forever; the host must too (`persist`,
`maxfail 0`).

**LATENCY REGRESSION worth fixing before this is the default:** RTT is 133-384ms
versus 26-46ms over the old console PPP. That is the idle backoff (20ms -> 400ms)
adding directly to per-packet latency. Fine for bulk, wrong for interactive IP. A
channel carrying PPP wants a much lower POLL_MAX, or to reset the backoff on ANY
traffic rather than only on a completed frame.

Guest autostart DOES work: S98niagchan and S99niagppp both ran at boot -- guest-chand
connected a client the instant it started, which was S99's pppd patiently retrying.
What failed was host-side ordering, not the guest.

Remaining for [x]: fix the two bugs, lower the poll ceiling, and automate the host
order. Boot automation is still the open piece (see the WIP notes in 4a5dc90).

P2-014 gave us a bidirectional byte stream at ~3 MB/s. PPP currently runs over the
`qcn` console at ~11 KB/s and, worse, OWNS that console -- which is the entire
reason P2-008 exists. Move IP to the channel and both problems go away at once.

```
guest:  pppd <-> /dev/pts/N <-> ptmx master <-> guest-chand
                                                    |  shared pages
host:   pppd <-> socat pty  <-> /run/niag0   <-> host-chan.py bridge
```

VERIFIED PREREQUISITE: the guest has full pty support -- 33 /dev/pts nodes, and
both `ptem` and `ldterm` STREAMS modules loaded. So pppd can be attached to a pty
whose master side is bridged to the channel; no new driver, no MD node, no QEMU
change.

Expected payoff beyond raw speed:
- the console stops being contended, so `init 5` after a networked session should
  stop landing in the broken OBP (`Fast Data Access MMU Miss`)
- NFS becomes usable: it is ~11 KB/s today, which is why a 3.7MB ssh install took
  seven minutes
- telnet/ssh/NFS all ride unchanged; only the transport underneath changes

Prerequisite from P2-014: the daemons need an accept loop first, since a transport
that exits when its client disconnects is no use to pppd.

### P2-008: Second UART, bound by the existing `su` driver [ ]  <-- DOWNGRADED

**Its original justification is being removed by P2-017, not satisfied by it.**

P2-008 existed because PPP squats on the single `qcn` console, so you could not
have networking and a usable console at once. The P2-014 channel does NOT replace a
serial line -- it is userland-to-userland over a disk device and is therefore absent
at OBP, absent during kernel boot, dead after a panic, and dead in single-user mode,
which are exactly the moments a console earns its keep. What it DOES do is remove
PPP's reason to be on the console at all (see P2-017). Delete the squatter and the
console is free without adding hardware.

Still worth doing eventually, at much lower priority: a second CONCURRENT
interactive console independent of userland, useful for watching one thing while
driving another. It remains cheap -- "2 lines of QEMU plus an MD node" -- and `su`
is a real 16550 driver that is NOT a singleton, unlike `qcn` (illumos
usr/src/uts/sun4v/io/qcn.c:347 "There is only once instance of this driver").

Reclassified from "unblocks the project" to "convenient for debugging".

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
