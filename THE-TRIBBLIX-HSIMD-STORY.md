# The Session That Put illumos, hsimd, and ZFS on the Virtual Niagara

## Why this story exists

This is an orientation story for an agent joining the project after August 19–20,
2026. It is deliberately not just a list of commands or a polished account in
which every idea was right the first time. The useful part is the path: what we
believed, what the machine disproved, which questions changed the direction,
where we damaged or nearly damaged state, and how a pile of individually modest
observations became a bootable modern illumos system with a working legacy disk
driver and the beginnings of a ZFS pool.

For exact procedures and current artifacts, read
`HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` and `CURRENT-STATE.md`. This document explains
how we got there.

## The question at the beginning

The session began as a media hunt: find an SXCE build 77 SPARC ISO. The apparent
plan was to locate an operating system image old enough to match the OpenSPARC
environment and complete enough to contain the storage stack we wanted.

That framing inherited several assumptions:

- Solaris needed a sufficiently authentic OpenBoot environment to boot at all.
- The Niagara machine's virtual disk was useful only to an image that already
  contained Sun's `hsimd` driver.
- A newer illumos distribution would therefore either fail to boot or boot and
  remain unable to see storage.
- Finding exactly the right historical DVD might solve the circularity.

The project already had something unusually valuable: Solaris 10 running on the
QEMU Niagara machine with acceptable performance, a working disk, networking,
and hacky but effective channels back to the host. The first request was to read
the recent commits and understand the discussion about “wanting something that
can talk to the disk.” Then Ryan changed the mode of collaboration explicitly:
use the assistant as a Socratic rubber duck, with root shells in real guests and
permission to probe rather than merely speculate.

The key question became:

> If I can connect you to a VM console booted into an illumos SPARC kernel with
> a boot-archive ramdisk mounted, can you probe the hardware and bootstrap a
> storage driver in the absence of hsimd?

That question was better than “which ISO has the driver?” It separated booting
the kernel from attaching the disk.

## Tribblix disproved the first large assumption

Tribblix m34 was mounted on the QEMU host. We built a Niagara boot command around
its `boot_archive` and booted it. The first attempts panicked, including the
`ni_pcbe_program` path that eventually became the durable `set cu_flags=0`
workaround. There were firmware resets, panics that left OpenBoot state unusable,
and restarts with `-s` and kmdb arguments.

Then Tribblix kept booting.

It crawled through 95 SMF service descriptions. It prompted for a keyboard type
on a serial console. It emitted service and contract failures that looked like
stalls. Eventually Ryan wrote:

> WOO! login prompt

The default maintenance credentials were `root` / `tribblix`, and we had a
modern illumos SPARC kernel alive on the emulated T1.

This was a major correction. Stock Tribblix did **not** need `hsimd` to boot from
the boot archive. OpenBoot and QEMU's hypervisor path could load the archive and
kernel; the missing driver mattered only after the RAM-root system was running
and wanted ordinary block-device access.

That distinction reopened several routes that the earlier “no hsimd means no
boot” conclusion had incorrectly closed.

## The firmware problem split into two directions

During the long Tribblix boot, the conversation widened. Existing QEMU SPARC64
machines could already boot Linux and NetBSD, but Niagara was the only example
in this project that booted Solaris-family software with the expected firmware
personality.

The question was whether our Niagara work taught us enough to go the other way:
instead of adding modern devices to the fragile Niagara machine, make OpenBIOS
on an existing `sun4u` machine satisfy the firmware and device-tree contracts
Solaris expects.

Ryan summarized the idea in the right deliberately simplified form:

> Are you saying that we could make the thing we work on the openbios, and then
> iterate on that with test-driven harnesses until openbios satisfied the
> “things” that solaris expects to find in the device tree?

Yes. The running Solaris 10 system, its kmdb, and the booting Tribblix guest
could become behavioral oracles. A future two-VM “Ralph loop” could compare a
protected known-good Niagara reference against a disposable OpenBIOS candidate,
eroding one firmware or device-tree mismatch at a time. That line of thought is
captured in `what-if-we-went-the-other-way/`.

It did not replace the immediate storage work. It gave the project a second,
less hardware-constrained strategic direction.

## Two live guests turned speculation into measurement

We now had two complementary machines:

- A Tribblix m34 RAM-root guest on `niagara-playbox`, modern enough to contain
  current illumos analysis tools but initially unable to see the disk.
- A Solaris 10 donor on `biggie`, already using the virtual disk through the
  original `hsimd` driver and reachable over the network.

The donor answered questions that static source reading could not settle as
quickly:

- The device-tree node was `/virtual-devices@100/disk@0`.
- Its compatible string was `SUNW,legion-disk`.
- The driver was bound through `vnex`.
- The installed SPARC V9 module was 24,472 bytes.
- Its major number on Solaris 10 was 251, but that number was already occupied
  in Tribblix and therefore could not be copied blindly.
- The driver performed disk I/O through fast traps `0xf0` and `0xf1`.

Static ABI analysis then showed something surprisingly favorable. The Solaris
10 module's imports were ordinary DDI/kernel interfaces available in Tribblix.
Its legacy `dev_ops` revision was structurally safe despite a newer current
revision, and its attach path created soft state and minor nodes without doing
disk I/O. Loading it was not obviously crazy.

Ryan asked exactly that:

> Did you try to modload that, or is that crazy?

It was not crazy. But getting the binary into the RAM-root guest became its own
adventure.

## The serial-transfer ordeal

The Tribblix boot archive had no convenient bulk-transfer utility. The donor
had networking, OpenSSL, and likely `uuencode`; the target had a serial console
whose input path was fragile. We explored base encodings, Perl availability,
chunking, QEMU monitor injection, free RAM, `socat`, ptys, and `reptyr`.

The operational hazards were real:

- `Ctrl-C` in the donor session could kill the shell rather than merely cancel
  the intended foreground operation.
- `Ctrl-D` logged out of precious root shells.
- A large serial paste could stop partway without making the corruption point
  obvious.
- tmux, reptyr, X terminals, Tailscale failures, and host swapping could all
  masquerade as guest failures.
- One transfer method silently truncated a large boot archive at 127,426,560
  bytes; only the checksum gate prevented us from embedding it.

Ryan found an existing trick under `~ryan/tricks/`, and the data was divided
into recoverable chunks. We captured the full donor scrollback, searched for
the generating loop, measured how far the first method had reached, and sent
the remaining nine chunks with the old method.

The important outcome was not elegance. It was a verified copy of `hsimd` in
the target RAM filesystem, with Solaris `sum` matching the donor. The more
important lesson was that this transfer path was too expensive and too fragile
to be the durable bootstrap.

## Ryan recognized the durable path because he had lived it

The conceptual pivot came from experience, not archaeology. Ryan pointed out
that SmartOS had always booted from RAM boot archives and then found persistent
storage in zpools:

> I remastered boot-archives ALL THE TIME when I was a SmartOS head of field
> engineering.

He supplied his 2011 post,
`https://www.ryan.net/smartos-disk-blogpost/real_disk_smartos.html`, as practical
prior art. The operation was familiar:

1. Copy the boot archive.
2. Attach it with `lofiadm` on a Solaris-family host.
3. Run UFS sanity checks.
4. Mount and edit it.
5. Unmount and check it again.
6. Replace the fixed-size archive extent in a copied ISO.

This changed the project from “somehow type a module into every booted guest”
to “manufacture a reproducible boot artifact.”

The actual Tribblix `boot_archive` proved to be an uncompressed UFS image,
356,515,840 bytes long, embedded at ISO9660 LBA 9391. The outer ISO's Sun label
had valid `0xDABE` magic and checksum. We could edit the archive on the Solaris
donor, verify it with `fsck -F ufs -m`, and replace exactly the same number of
bytes in a copied ISO.

First we made the smallest durable change: `set cu_flags=0` in `/etc/system`.
A fresh boot passed the PCBE panic and reached single-user mode. Only then did
we add `hsimd`.

Tribblix used major 251 for `ecpp` and 252 for `glm`; its table ended at 264,
so `hsimd` became major 265. The durable archive gained:

```text
/platform/sun4v/kernel/drv/sparcv9/hsimd
/etc/name_to_major: hsimd 265
/etc/driver_aliases: hsimd "SUNW,legion-disk"
/etc/path_to_inst: "/virtual-devices@100/disk@0" 0 "hsimd"
```

There was even a small but dangerous quoting error in the first registration
edit: the alias and path records lost their quotes. Readback caught it, the
malformed records were removed, and exact quoted forms were installed. That is
why every archive mutation in this project needs readback, not just a successful
exit status.

## The first durable disk proof

The remastered ISO booted. Device configuration printed:

```text
virtual-device: hsimd0
hsimd0 is /virtual-devices@100/disk@0
```

`modinfo` showed major 265, and devfs created `c1d0s0` through `c1d0s7` under
both `/dev/dsk` and `/dev/rdsk`.

A 512-byte raw read from whole-disk slice 2 matched the host backing image. A
second read at a nonzero offset matched too, proving that the hypercall path was
not accidentally returning sector zero for every request.

At that moment Ryan asked the natural compressed version of the result:

> Wait, so we have Tribblix with hsimd now?!

Yes. Not source-compatible in theory, not transferred into one volatile shell,
but durably booting and attaching from a remastered Tribblix image.

One historical caution belongs here. The SHA-256 value used for the second
sector, `076a27...`, is also the hash of 512 zero bytes. It therefore did not
discriminate nonzero content by itself, despite matching the selected host
sector. Later work used a textual canary specifically to avoid the project's
already-documented “zeros equal zeros” proof failure.

## The HSFS failure was good news in disguise

The first read-only filesystem mount failed:

```text
WARNING: hsimd_ioctl: cmd 4a4 not implemented
NOTICE: hs_findisovol: bread: error=(28)
mount: /dev/dsk/c1d0s2 is corrupted. needs checking
```

The tempting conclusion was media corruption. Source tracing showed otherwise.
`0x4a4` is `CDROMREADOFFSET`. HSFS expects an unsupported driver to return an
error, in which case it falls back to sector 16. `hsimd_ioctl()` logs unknown
commands but returns success without initializing the output. HSFS therefore
uses garbage as a multisession offset and eventually receives `ENOSPC`.

This was the first clear example of the next class of work: hsimd's basic data
path was sound, but its ioctl contract lied. The minimal correct behavior for
an unsupported ioctl is an error such as `ENOTTY`, not false success.

## ZFS moved from ambition to an experiment

Tribblix m34's archive already contained `/sbin/zpool`, `/sbin/zfs`, and the
SPARC V9 ZFS modules. QEMU's Niagara machine exposes one virtual disk, not a
separate boot disk plus test disk. We therefore created a disposable combined
image:

- Start with the known-good hsimd ISO.
- Extend it to 997.8 MiB.
- Keep slice 2 as the whole served disk.
- Place a cylinder-aligned 320 MiB scratch slice at `s7`.
- Recompute the Sun-label checksum.
- Preserve the original ISO as the rollback source.

The copied image booted in tmux session `tribblix-zfs-test`. Both layers
attached:

```text
hsimd0 is /virtual-devices@100/disk@0
zfs0 is /pseudo/zfs@0
```

SMF again consumed a long time. A cheap-model subagent was dispatched to plan
a minimal single-user profile. Its most important correction was that
“Loading 95/95 service descriptions” is manifest/repository loading, not proof
that 95 services are starting. The later failures and retries—keymap, IPsec,
IPMP, nwam, RBAC, and contract cleanup—are separate timing targets.

The console eventually asked for the maintenance username and password. Ryan
entered them and said simply:

> Take it away.

## The canary that made the storage proof real

`prtvtoc` exposed another unsupported ioctl and reported an invalid VTOC, but
the attach-time slice map had created `c1d0s7`. Before involving ZFS, we tested
that mapping with content that could not be confused with an untouched region.

The guest wrote exactly one padded 512-byte sector containing:

```text
HSIMD-ZFS-CANARY-20260820
```

The guest readback hash was:

```text
08661dac6b8f75c1ba71d37ec1db41896c489d218c115e984d41564884770e15
```

The exact host backing-file sector produced the same hash and the same visible
text. This proved all of the following at once:

- `s7` used the intended nonzero absolute offset.
- hsimd guest writes worked, not merely reads.
- QEMU's `MAP_SHARED` backing exposed those writes to the host file.
- The result was not a zeros-versus-zeros false positive.

This also clarified a historical question about performance. The earliest
storage patch loaded a whole disk into anonymous host RAM and copied it back on
exit. P2-012 replaced that with a `MAP_SHARED` file mapping. Both the working
Solaris 10 system and this Tribblix experiment use the latter: guest writes
dirty the host page cache directly, and `msync` provides an explicit durability
barrier. The difference between fast Solaris 10 storage and the new ZFS test
was therefore not the QEMU backing mechanism.

## ZFS wrote a pool—and then taught us where hsimd stops

We ran:

```text
zpool create -f hsimdz /dev/dsk/c1d0s7
```

hsimd logged four unsupported disk ioctls. The command stopped returning.
Rather than assuming the emulated `clock 5 MHz` message meant we merely needed
patience, we inspected the host backing file while QEMU remained alive.

ZFS had written all four expected label areas, two near each end of `s7`. The
labels contained:

- pool name `hsimdz`;
- hostname `tribblix`;
- vdev path `/dev/dsk/c1d0s7`;
- physical path `/virtual-devices@100/disk@0:h`;
- pool and vdev GUIDs;
- `ashift`, `asize`, metaslab, and creation transaction fields.

The middle of the 320 MiB slice remained zero. The backing file's modification
time stopped changing while QEMU continued consuming a host core. This was not
a completed pool and not useful slowness. It was a clean boundary: ZFS could
write its labels through hsimd, then hung during later raw-disk setup or
synchronization, almost certainly in the broader ioctl/completion contract.

We saved the complete console, forced QEMU's documented `SIGUSR2` `msync`
barrier, and terminated only the disposable test VM by exact PID. The two
known-good Tribblix VMs remained untouched.

## The next experiment deliberately hides some bugs

Ryan proposed the right diagnostic compromise:

> I feel like we'd have better luck (but hide real bugs) if we made a UFS file,
> and put the ZFS pool on that file.

The proposed stack is:

```text
ZFS file vdev
    -> regular file on UFS
    -> UFS filesystem on c1d0s7
    -> hsimd strategy/read/write
    -> QEMU MAP_SHARED backing file
```

This still exercises hsimd data I/O and persistence, but bypasses ZFS's direct
disk ioctl probing. If it works, it isolates the blocker to the raw-vdev
contract. If it hangs, the problem lies deeper in hsimd write completion,
flush behavior, or general I/O.

It must remain a diagnostic lane, not a declaration that raw ZFS works. The
raw `s7` test remains the eventual correctness regression.

At the point this story was written, the Solaris donor on `biggie` had begun
creating `/share/tribblix-s7-ufs.img`, a native 320 MiB UFS image intended for
that experiment. Verify whether that command completed before resuming. Do not
assume the image is formatted merely because the file exists.

## Mistakes that belong in the story

Several errors materially shaped the procedures now in the repository:

### We killed the wrong live Solaris VM

A QEMU PID believed to represent a halted or wedged guest was actually a newly
booted Solaris system. It was terminated, potentially dirtying its disk. The
lesson became explicit: identify a VM by start time, exact backing file, and
live console state before sending any signal. “The old PID” is not an identity.

### Console control characters were destructive

`Ctrl-C` and `Ctrl-D` did not always have the local, narrow effect expected.
They killed or logged out of shells that were expensive to recover. The safe
serial discipline became: one short printable command at a time, read it back,
and do not use control characters reflexively.

### A successful copy was not necessarily a complete copy

The first archive transfer truncated silently. Size and checksum checks caught
it. `rsync --partial --append-verify` became the right tool for the large
artifact, and every boot-archive mutation now has an explicit checksum gate.

### A matching checksum can prove nothing

The project had already been burned by comparing zero-filled regions. This
session nearly repeated that mistake with a sector whose SHA-256 was the hash of
512 zeros. The textual s7 canary repaired the proof standard: verify known,
nonzero, discriminating content.

### Unsupported is not the same as safely unsupported

hsimd's habit of warning and returning success is worse than returning
`ENOTTY`. It turns feature probes into uninitialized outputs. HSFS demonstrated
that precisely, and the raw ZFS hang likely belongs to the same family.

### Long waits need layers and clocks

Tribblix's boot delay combined kernel initialization, manifest loading, device
configuration, retrying SMF methods, and human-facing prompts that could own
stdin asynchronously. “It is loading 95 services” was too coarse to optimize.
Future timing needs separate markers for OBP, kernel handoff, 95/95 import,
hsimd attach, maintenance prompt, and authenticated shell.

## What changed in our understanding

By the end of the session, the project had moved through these corrections:

1. **From:** another Solaris-family system cannot boot without hsimd.
   **To:** Tribblix boots completely from a RAM archive; hsimd is a post-boot
   storage problem.

2. **From:** find the one historical installer that already contains everything.
   **To:** use a modern bootable archive and surgically add the one missing
   legacy driver.

3. **From:** serially transfer a module into every live guest.
   **To:** remaster a verified UFS boot archive using the same operational model
   SmartOS used for years.

4. **From:** ABI compatibility is speculative.
   **To:** the Solaris 10 SPARC V9 hsimd module loads, attaches, creates device
   nodes, and performs verified nonzero-offset reads and writes on Tribblix.

5. **From:** the disk path may be fundamentally broken.
   **To:** the data path works; the driver-control contract is the exact next
   boundary.

6. **From:** ZFS is a future ambition.
   **To:** Tribblix loads ZFS alongside hsimd and writes a structurally
   recognizable four-label pool before hanging.

7. **From:** Niagara is the only possible route.
   **To:** Niagara is also a behavioral oracle for a test-driven OpenBIOS/sun4u
   route with better existing emulated hardware.

## How a new agent should enter the project

Start by preserving the distinction between evidence levels:

- **Proven:** Tribblix boots from the remastered archive.
- **Proven:** the Solaris 10 hsimd binary is ABI-compatible enough to load and
  attach under Tribblix m34.
- **Proven:** aligned raw reads and a discriminating aligned raw write traverse
  hsimd and appear at the exact host backing-file offset.
- **Proven:** ZFS loads and writes four pool labels through the raw vdev.
- **Not proven:** a raw-device zpool completes creation, imports, mounts, or
  survives reboot.
- **Not proven:** the UFS-hosted file-vdev experiment works; its image creation
  was in progress at the handoff.
- **Not proven:** QEMU machine-state save/restore works for Niagara. Disk
  rollback exists; a booted-VM restore point does not.

Then follow these rules:

1. Preserve known-good live VMs unless the task explicitly supersedes them.
2. Treat every writable experiment as disposable and name the exact backing
   file before starting QEMU.
3. Read `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` for artifacts and checksums.
4. Do not conflate boot archive, outer ISO, raw disk slice, and host backing
   file; each is a different layer with different failure modes.
5. Fix or emulate hsimd ioctls one behavior at a time, beginning with a failing
   test. The HSFS `CDROMREADOFFSET` case is already a minimal regression.
6. Keep the UFS file-vdev and raw-vdev lanes separate in names and claims.
7. Optimize SMF only after measuring the actual dependency/retry delays. Do not
   delete manifests to make the counter smaller.
8. Capture console scrollback before terminating anything.
9. Never accept “command returned success” as the artifact. Read the bytes back.

## The human pattern worth preserving

The most productive moments came when the conversation switched levels:

- “Can we probe the hardware?” replaced media guessing with observation.
- “Can we put tools and data into the boot archive?” replaced volatile heroics
  with a reproducible artifact.
- SmartOS experience supplied a proven operational pattern that generic
  research had not surfaced quickly enough.
- “Did you try to modload that, or is that crazy?” forced the ABI evidence to
  become an executable test.
- “Are we really running at 5 MHz?” stopped patience from being used as a
  substitute for diagnosing a hang.
- “Would a ZFS file on UFS hide bugs?” introduced a deliberately layered test
  instead of pretending one experiment could prove everything.

That is the collaboration model the new Maestri crew should inherit: keep the
wild ideas, but attach each one to a cheap discriminating test; preserve the
machines that are expensive to recreate; and write down corrections as eagerly
as successes.
