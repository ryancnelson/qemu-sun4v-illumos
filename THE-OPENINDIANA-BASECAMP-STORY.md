# The Night OpenIndiana Found the Internet on a Virtual Niagara

September4 follow-up: [Ethernet over a disk, on a virtual T2000](THE-ETHERNET-OVER-DISK-STORY.md)
records the later SMP session: native DLPI, TAP, ARP, bidirectional ping,
byte-verified TCP, and outbound DNS/HTTPS over channel2 with PPP inactive.
The August PPP session below is preserved as its own historical account.

## Prologue: 82,806 ways to ask what happened

The last command of the night was not a storage test, a network test, or a
desperate attempt to rescue the guest. It was simply:

```sh
dtrace -l
```

The live OpenIndiana VM reported 82,806 available probes. That count excludes
the command's one-line header and was measured directly with:

```sh
/usr/sbin/dtrace -l | /usr/bin/sed 1d | /usr/bin/wc -l
```

This was still the first OpenIndiana boot we had attempted. It had never been
rebooted. During one long session it had acquired a foreign disk driver,
mounted its own media by hand, accepted binaries through a disk mailbox,
negotiated PPP, reached the Internet, mounted NFS, discovered an iSCSI target,
created and exported a ZFS pool, and gained a second console safe enough for
Ctrl-C. After all that improvisation, the kernel was not merely alive. It was
offering tens of thousands of precise places to observe what it did next.

That transformed tomorrow's work. The odd `hsimd` ioctl behavior, failed
socket-family probes, `ifconfig` and `ipadm` paths, iSCSI latency, ZFS I/O, and
future DLPI relay no longer need to be debugged primarily from symptoms. This
guest can tell us where it went and what it returned.

It was the cherry on the sundae, and a very Solaris ending to the night.

## Why this story exists

This is the narrative of the August 23–24, 2026 session in which an OpenIndiana
SPARC installer image became a networked, recoverable development basecamp on
QEMU's strange and minimal Niagara machine.

It is not a replacement for the runbook. Exact hashes, commands, acceptance
gates, and preserved evidence live in
`docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md`,
`docs/design-plans/2026-08-23-openindiana-sparc-smoke.md`, and
`captures/openindiana-live-20260824/`. This story records why the session was
special: which constraints turned out to be real, which assumptions died, and
how several old tricks combined into something neither the firmware nor QEMU
had been designed to provide.

## The modest opening goal

The evening began with an OpenIndiana SPARC ISO in `~/Downloads` and a simple
idea: make a second branch of the Niagara experiments, using OpenIndiana's
filesystem and boot archive instead of Tribblix.

The machine was already peculiar. The laptop was an Apple-silicon Mac running
an AArch64 Linux VM under UTM. Inside that VM, QEMU emulated a 64-bit SPARC T1.
The guest firmware came from OpenSPARC, not QEMU's normal OpenBIOS. The QEMU
machine exposed almost nothing: a serial console, a clock, and one
memory-backed virtual disk consumed through sun4v hypercalls.

There was an obvious first question: could OpenBoot read the ISO as a CD even
if the kernel could not?

The answer was subtle. OpenBoot could interpret the bytes and load the kernel
and boot archive. But once OpenIndiana took control, there was no CD-ROM
controller. There was only the same single file-backed storage device.

Ryan compressed the correction into one sentence:

> we don't actually have a cd, dude.

That sentence prevented a great deal of imaginary-driver work.

## One disk, two views, and the return of hsimd

The source ISO already contained both `sun4u` and `sun4v` platform paths, with
the `sun4v` boot archive pointing at the common `sun4u` archive. The stock
kernel began booting but hit two measured obstacles: Niagara performance-counter
initialization needed the known `cu_flags=0` workaround, and the kernel had no
driver for the firmware's `SUNW,legion-disk` node.

The fix was deliberately small. A derivative archive received exactly the
known PCBE workaround and the proven Solaris 10 `hsimd` module, including the
earlier correction that unsupported ioctls must return `ENOTTY` instead of
pretending to succeed. The archive was spliced into a disposable reflink child
of the ISO, with the pristine input protected by size and SHA-256 gates.

OpenIndiana booted. `hsimd0` attached at
`/virtual-devices@100/disk@0`. Disk slices appeared. Slice 2 identified as
HSFS. It mounted at `/.cdrom`. `solaris.zlib` attached through lofi, and `/usr`
mounted from it.

The installer still stopped while preparing its text-install image. That was
not a storage failure. Its `media-fs-root` method searched USB and CD devices,
then network media; it never considered an ordinary virtual disk containing
valid HSFS installation media. Manual mounts proved that everything after
media discovery worked. The correct future patch was therefore a narrow
discovery fallback, not a fictional CD driver.

This established the session's governing fact: firmware and kernel were seeing
different abstractions over the same bytes. OpenBoot called them boot media.
The kernel called them one `hsimd` disk. There was no second device hiding
behind the curtain.

## The mailbox that became a network cable

The running root was ephemeral, but the project had already built a small
shared-disk channel. QEMU and the guest could exchange framed bytes through a
reserved region of that same virtual disk. It had previously served as a
mailbox, a BBS, and a way to deliver tiny rescue tools.

The immediate temptation was to keep treating it as a transfer mechanism.
Ryan saw the larger possibility:

> on the contrary, if you can make guest-chand work in this boot, you might
> have ppp networking in a few minutes

The right `guest-chand` binary was recovered from an earlier Tribblix artifact.
An initial candidate was rejected because direct execution proved it ignored
the placement override and opened its compiled disk path. The verified binary
accepted the device override, although its numeric block parser still rejected
every tested value in this OpenIndiana userland. We used the compiled block
default and matched it exactly on the host.

Before attempting networking, channel 0 passed an exact echo test. Only then
did it become the byte stream between OpenIndiana pppd and Linux pppd.

The first start failed. The kernel modules were present and their majors were
registered, but the `sppptun` clone node was missing. A targeted `devfsadm`
created it. The next clean start completed LCP and IPCP:

```text
OpenIndiana sppp0  10.0.5.15
Linux ppp0         10.0.5.1
```

The guest pinged the host. Then it pinged through the playbox's forwarding and
NAT. DNS sent directly to `8.8.8.8` returned `example.com`. A bounded ping to
`1.1.1.1` returned six replies between roughly 64 and 154 milliseconds.

Ryan's reaction belonged in the record:

> that is fucking amazing.

It was. A memory-mapped fake disk inside QEMU, itself running inside an AArch64
VM on a Mac, had become a PPP line for an illumos SPARC guest—and it was fast
enough to be useful.

## A console where Ctrl-C meant Ctrl-C

The achievement had a dangerous interface. QEMU owned the original serial
console. Sending Ctrl-C there could terminate QEMU instead of interrupting the
guest. Long commands, digest operations, and experiments therefore carried an
absurd risk: a normal shell reflex could destroy the live checkpoint.

Channel 1 became a separate root PTY through `socat`, exposed in the playbox
tmux session `oi-safe-console`. A controlled test ran `sleep 30` and sent
Ctrl-C. The sleep stopped; QEMU did not.

It was not yet an authenticated `ttymon` or getty. It was something immediately
more valuable: a console on which ordinary Unix muscle memory was safe.

With that console, OpenIndiana mounted an NFSv3 export from the playbox. A
125,440-byte rescue tar copied over NFS matched the same bundle recovered
through the raw-disk mailbox. We now had two independent ways to recover the
live guest's tools, configuration, logs, and driver payloads.

## The audacious iSCSI detour

Once ordinary IP worked, the guest revealed that it already contained the
illumos iSCSI initiator. Linux could provide a file-backed LIO target. This was
not the intended final storage architecture, but it offered a remarkable
experiment: could OpenIndiana build a real ZFS pool on a virtual disk reached
through PPP, whose physical transport was itself the shared region of the boot
disk?

The first `zpool create` failed. Host kernel logs showed LIO DataOut timeouts.
That failure was useful because it isolated a parameter: the ACL's default
three-second `dataout_timeout` was too short for this transport. PPP remained
alive, discovery still worked, and the failure did not justify blaming ZFS or
the entire channel.

Linux 6.8 capped the setting at 60 seconds. The same cleared sparse backing file
was re-exported with a fresh LUN identity and the timeout set before login.

The retry succeeded:

```text
zpool create -d -f oi_iscsi_test \
    c0t600140544D6BE8EE5BD4D559AFA788DCd0
```

The pool was `ONLINE`, with zero errors and optional features disabled for
portability. `CHECKPOINT.txt` read back with illumos cksum `3367977479 22`.
The pool was then exported cleanly, discovery disabled, and the target session
confirmed closed before the backing file was checkpointed.

The sparse image was preserved as a reflink on the playbox and as a compressed,
independently hashed copy on both the playbox and Minnie. The entire live guest
bundle, console transcripts, PPP logs, target configuration, ZFS state, and
checksum manifests entered the repository under
`captures/openindiana-live-20260824/`.

No QEMU machine snapshot was attempted. VMState restoration on this platform
was already known to be unreliable. Recovery was based on reproducible inputs,
captured payloads, deterministic setup, and exported storage—not wishful
serialization of a fragile emulator.

## The better disk was present all along

iSCSI was too wonderful to discard, but also too indirect to become the normal
data path. Ryan proposed the simpler design: grow the one disk the machine
already supports and place a two-gigabyte ZFS slice after the immutable
OpenIndiana media.

The geometry was measured. The clean image used 640 sectors per cylinder and
ended at byte 644,198,400. The next cylinder began at byte 644,218,880, leaving
a 20 KiB zero gap. A disposable sparse reflink was expanded, slice 7 was placed
at cylinder 1966 for exactly 4,194,304 sectors, slice 2 was grown to describe
the whole disk, and `ncyl` became 8520.

`tools/vtoc.py verify` passed. Every source byte after the edited label through
the old end of file remained identical, and the gap was all zero.

That was a geometry proof, not a declaration of victory. The previous ZFS
experiments had taught us that a label write can happen before a pool becomes
usable. The next runbook therefore requires guest-side canaries, boundary
tests, bounded progress observations, the actual `zpool create`, and an
export/import proof.

The iSCSI trick remains important. It is a portable checkpoint, recovery, and
Linux/illumos interchange path. The appended `hsimd` slice is the proposed fast
path.

## Ethernet without pretending the disk is a modem

PPP solved the bootstrap problem, but yesterday's notes contained a more
natural design. illumos etherstubs and VNICs can form a software Ethernet
switch. A small `libdlpi` relay can carry whole Ethernet frames over channel 2
to a Linux TAP interface.

Prior work had already proved that the guest could create the etherstub and
VNICs. It stopped because `ipadm` could not open its management handle and
`ifconfig` aborted while probing an unsupported address family. Those became
trace-first compatibility bugs, not reasons to abandon Ethernet.

The future channel allocation is now explicit:

```text
channel 0  PPP bootstrap and fallback
channel 1  safe console
channel 2  framed Ethernet to Linux TAP
```

The acceptance order is equally explicit: local switching, an exact frame in
each direction, ARP, bounded ICMP, then TCP, DNS, NFS, and throughput. PPP does
not disappear until Ethernet passes from a cold boot.

## From rescue environment to development basecamp

At this point the live guest had a modern illumos userland, safe console,
external networking, NFS, and two plausible routes to persistent ZFS. It was no
longer merely a rescued installer shell. It could become the place where its
own tools were developed.

The first compiler hypothesis was checked immediately and corrected. GCC 7 had
been present in the earlier Tribblix checkpoint, not this OpenIndiana
environment. `/usr/bin/gcc` and `/usr/versions/gcc-7/bin/gcc` were absent, and
no regular file named `gcc` existed below `/usr`. The guest did have a 64-bit
SPARC V9 kernel and the illumos 5.11-1.1790 linker.

So the development claim became precise: import or install a verified compiler
onto durable storage; compile and run small ABI and library probes; rebuild
`guest-chand` and the future DLPI relay; only then ask whether the headers and
build machinery are sufficient for `hsimd` or larger illumos components. The
Solaris 10 donor remains a bootstrap and regression oracle, not the permanent
center of development.

## The cost of waiting, and the machine doing all of it on battery

Tribblix boot cycles had taken roughly fifteen minutes. OpenIndiana was better,
but panics still destroyed momentum. Ryan proposed keeping a Solaris 10 donor
and an OpenIndiana basecamp ready while a disposable experiment occupied the
foreground.

Biggie made the idea practical: 188 GiB of RAM, 48 logical CPUs, and 2.1 TiB
free in `datapool`. Its already-running Niagara guest had survived nearly two
days while consuming about 1.48 GiB RSS and one host CPU. The supported design
became independently booted warm guests with isolated images, sockets,
channels, networks, and process identities. QEMU monitor `stop`/`cont` is an
optional experiment; known-broken VMState save/restore is not part of the plan.

But the interactive machine deserved its own recognition. The active stack was
running on an M5 Max MacBook Pro with 64 GiB unified memory. The AArch64 playbox
had only six CPUs and about 6 GiB assigned, yet its nested SPARC QEMU used about
1.19 GiB RSS and one CPU while remaining pleasantly interactive.

Then Ryan supplied the evening's final benchmark correction:

> we're doing this work on BATTERY POWER, dude.

`pmset` agreed. The laptop was discharging, at 29 percent when measured.

The preferred bench is therefore hybrid: this laptop remains the responsive,
watched development platform; biggie owns warm spares, background boots, and
soak tests. Console switching should be location-neutral over SSH and
Tailscale. Writable VM disks must never be shared.

## The firmware question returned at the end

With OpenIndiana alive, one final question reframed the entire project: was all
of this harder than using QEMU's feature-rich `sun4u` machine and grafting
OpenBoot onto it?

Niagara OpenBoot itself is the wrong transplant. It runs above the sun4v
hypervisor, consumes the machine description, calls `q.bin`, and assumes fixed
memory and hypercall contracts. Moving it onto generic sun4u PCI hardware would
be a firmware platform port.

But the question exposed two better paths already documented in the project.
QEMU's stock `sun4u` OpenBIOS has previously loaded and entered a Solaris kernel;
the first observed blocker was the EBus serial-console description. Repairing
that OpenFirmware contract may be surgical, and success would expose ordinary
IDE, CD, SCSI, PCI, and network devices with existing Solaris drivers.

The ARM64 illumos port offers the more radical precedent. It abandons OpenBoot
entirely: QEMU loads `inetboot` directly, passes an FDT, and a new platform layer
uses virtual devices without PROM runtime calls. A future `sparc64-virt` could
do the same with deliberately simple, endian-safe devices. The obstacles are
real—modern upstream illumos removed the SPARC kernel makefiles, and VirtIO's
little-endian ABI needs care on big-endian SPARC—but neither obstacle makes
OpenBoot fundamental.

The resulting order is clear:

1. test and repair the smallest OpenBIOS/Solaris boundary;
2. continue the working Niagara basecamp and custom-device path;
3. investigate a firmware-free `sparc64-virt` as the clean strategic design;
4. do not transplant Niagara OpenBoot merely because it is available.

## What the night actually achieved

By the end of the session, OpenIndiana on a virtual T1 had:

- booted from a reproducible derivative archive;
- attached Niagara's only disk through `hsimd`;
- mounted its own installation media and live userland;
- exchanged verified payloads over a shared-disk channel;
- negotiated PPP and reached the Internet;
- resolved DNS and mounted NFS;
- gained a Ctrl-C-safe root console;
- discovered Linux iSCSI and created an online ZFS pool through PPP;
- exported and preserved that pool as a hashed checkpoint;
- exposed exactly 82,806 available DTrace probes without ever rebooting;
- acquired a validated geometry for a direct two-gigabyte ZFS slice;
- recovered the etherstub/DLPI/TAP plan for non-PPP networking; and
- become the outline of a native development basecamp with warm-spare guests.

The best part was not any single trick. It was the way old experience kept
changing the level of the problem. A fake CD became one disk. A mailbox became
a modem. A modem made NFS and iSCSI possible. An iSCSI experiment proved ZFS,
then revealed the simpler direct slice. A rescue shell became a development
host. A slow emulator became a warm pool. And a battery-powered laptop became
the control room for a machine architecture that had been obsolete for years.

Ryan said it at the right moment:

> this is awesome. save everything

We did.

## Afterword: the next install cycle exposed the harness (2026-08-25)

The basecamp results above remain historical facts, including the earlier
PPP, SSH, NFS, iSCSI, and exported-ZFS proofs.  They should not be read as a
claim that every later remaster automatically retains those properties.

The next 6 GiB install experiment booted a verified range-flush QEMU build,
reached an interactive single-user root prompt, and proved a second root shell
over channel 1.  It also created a direct ZFS pool on the appended hsimd slice.
The installer transfer later failed to establish a completed installed root,
and the patched follow-up did not re-prove PPP or SSH.

The most serious failure was in the test harness, not illumos: playbox carried
a stale `host-up.sh` with unbounded pppd persistence.  Failed negotiation
produced an unreaped-child storm and transient fork failures.  The storm was
stopped without killing QEMU or the channel bridges, the stale script was
preserved, and the corrected project copy was deployed.  Guest startup was
also shown to be non-idempotent under repeated stop/start.

That incident sharpened the development rule: every boot starts from an
immutable image and verified script/QEMU hashes; one hypothesis, one isolated
change, one watched test, exact channel/PPP/SSH gates, independent process
readback, and a durable transcript.  A candidate that fails those gates is
evidence, not a new baseline.
