# Live hsimd bootstrap into Tribblix m34

Recorded 2026-08-19/20 while both reference systems were live. This file is
the handoff for the current experiment. Do not infer that anything after the
"Current volatile state" section has already been executed.

## Result so far

Tribblix m34 reaches a login prompt and a root shell on the QEMU Niagara
machine after disabling the unsupported UltraSPARC-T1 performance counters in
kmdb. It is running entirely from `/platform/sun4v/boot_archive`; root is
`/ramdisk-root:a` (UFS). The kernel sees the Niagara virtual disk node but has
no driver for it, so `/dev/dsk` and `/dev/rdsk` are empty.

A known-working Solaris 10 `hsimd` binary has been copied byte-for-byte into
the live Tribblix RAM root as `/tmp/hsimd3`:

```
source: /platform/sun4v/kernel/drv/sparcv9/hsimd
size:   24472 bytes
sum:    12843 48
target: /tmp/hsimd3
```

The binary has not been loaded, registered, or attached. Static and live
kernel analysis removed the two largest ABI concerns:

1. All 45 undefined symbols required by the Solaris 10 module exist as global
   symbols in the Tribblix kernel.
2. The apparent `struct dev_ops` size mismatch is intentional legacy ABI:
   the module declares `devo_rev = 3`, so illumos does not access the later
   `devo_quiesce` member.

The boot archive contains none of `add_drv`, `modload`, `modunload`,
`update_drv`, `devfsadm`, or `drvconfig`. The first 10044-byte Solaris file
transferred as `/tmp/modadm` was initially misidentified as a multicall
utility. A no-argument execution proved that it is only the 32-bit ISA
dispatcher: it searches ISA subdirectories for the real `add_drv` or
`modload`. It made no driver or kernel change.

The actual Solaris 10 SPARCV9 `modload` has since been transferred and verified
as `/tmp/real-modload`. Transfer of the actual SPARCV9 `add_drv` stopped safely
after 23 independently verified chunks when the guest serial input path became
unresponsive. See the volatile-state section before touching either VM.

## Current volatile state -- preserve this VM

The state below exists only in RAM and tmux scrollback.

- tmux `here`: Tribblix m34 root shell, login complete, RAM-root only.
- tmux `donor`: Solaris 10 root shell on `biggie`, working hsimd loaded.
- Do not send Ctrl-C to `donor`; it has previously killed the shell.
- Do not send Ctrl-D casually; it has logged out foreground/root shells.
- Use `~/bin/safe-bash --command` and the `~/bin/sane-*` tmux wrappers.
- Tribblix `/tmp/hsimd3` is complete and verified (`12843 48`, 24472 bytes).
- Tribblix `/tmp/modadm-transfer.b64` contains all four chunks: 13392 base64
  characters total.
- Tribblix `/tmp/modadm` is decoded and executable mode is set, but it has not
  modified driver state. It is the ISA dispatcher, 10044 bytes with `sum`
  output `13262 20`. Temporary hardlinks `/tmp/add_drv` and `/tmp/modload` were
  created; no-argument probes only reported that they could not find the real
  programs in ISA subdirectories.
- Donor and Tribblix MD5 are identical:
  `76b66713137851c1407fd9ea20785bc0`.
- Tribblix SHA-256 is
  `7f6356a77c0fae9a2e1c3e208f6d00ad4ba620ab327d1a353ad1af69b5948bf0`.
- The real SPARCV9 loader is complete as `/tmp/real-modload`:
  11792 bytes, `sum` = `26064 24`, MD5 =
  `8c8a308502b7232b37dedafc138194b8`. It has not been executed.
- The real SPARCV9 `add_drv` is 55984 bytes with donor `sum` = `39019 110`.
  Its marker-gated transfer run `1787194147-71060` has correct 1364-character
  part files `.000` through `.022`; parts `.023` onward are absent. Do not
  concatenate or decode it yet.
- The `here` serial input path stopped executing commands after part 22. QEMU
  PID 302613 on `niagara-playbox` remains alive at normal TCG CPU load and the
  host has ample available memory. The guest did not panic and no driver state
  changed. Control-Q, Control-U plus a short command, and direct PTY-master
  text injection did not restore shell execution. Direct PTY text was echoed,
  but its marker command did not run. A `here2` root shell on the QEMU host
  confirmed QEMU's stdin/stdout/stderr are all `/dev/pts/6`; the command line
  has plain `-nographic` and no separate monitor or QMP socket. A reversible
  direct `Ctrl-A c`, `info status`, `Ctrl-A c` probe produced literal
  `^Acinfo status` echo from the guest rather than an HMP prompt, so the escape
  is not intercepted as a usable monitor path. Investigation stopped before
  attaching a debugger or restarting QEMU.
- QEMU uses `/dev/pts/6`; tailscaled PID 972 holds its PTY master as fd 26/30
  (`tty-index: 6`). This is diagnostic evidence, not permission to kill or
  restart tailscaled.
- The donor mounted the existing NFS export
  `10.0.5.1:/export/solaris` at `/share`. Copies of the real tools are on
  biggie as `/export/solaris/sol10-sparcv9-add_drv` and
  `/export/solaris/sol10-sparcv9-modload`.
- No binding file, module path, device node, or kernel module state has been
  changed yet.
- There is no verified QEMU save/resume checkpoint for this session. Treat a
  panic or reboot as losing all of the Tribblix-side work.

The initially transferred dispatcher is:

```
/usr/sbin/modload              # same inode/content as add_drv on Solaris 10
size: 10044 bytes
sum:  13262 20
file: ELF 32-bit MSB executable SPARC, dynamically linked, stripped
NEEDED: libc.so.1 only
```

The real executables are:

```
/usr/sbin/sparcv9/add_drv   55984 bytes   sum 39019 110
/usr/sbin/sparcv9/modload   11792 bytes   sum 26064 24
```

The completed transfer was decoded with the OpenSSL already present in the
Tribblix boot archive and verified before execution:

```
openssl base64 -d -A \
  -in /tmp/modadm-transfer.b64 \
  -out /tmp/modadm
chmod 755 /tmp/modadm
sum /tmp/modadm
ls -l /tmp/modadm
```

The expected result (`13262 20`, 10044 bytes) was observed. Subsequent probing
showed that dispatch is not by `argv[0]` inside this binary. Instead, the
binary uses its name to locate and execute a real ISA-specific utility. The
hardlinks exist only in `/tmp` and are harmless; they are not the utilities we
need.

## Live device-tree contract

Tribblix `prtconf -vp` reports:

```
name:        'virtual-devices'
compatible:  'SUNW,sun4v-virtual-devices' + 'SUNW,virtual-devices'

    name:        'disk'
    device_type: 'block'
    interrupts:  00000001
    reg:         00000000
    compatible:  'SUNW,legion-disk'
```

The working Solaris 10 reference binds the same node as follows:

```
/etc/name_to_major: hsimd 251
/etc/driver_aliases: hsimd "SUNW,legion-disk"
/etc/path_to_inst: "/virtual-devices@100/disk@0" 0 "hsimd"
module: /platform/sun4v/kernel/drv/sparcv9/hsimd
```

`vnex` is already attached in Tribblix. The missing piece is the leaf driver,
not the nexus or the firmware node.

## Module inventory and ABI evidence

The module is a SPARC V9 relocatable object:

```
ELF 64-bit MSB relocatable SPARC V9 Version 1,
UltraSPARC1 Extensions Required
```

Defined driver routines found with Solaris `nm`:

```
_init                     92 bytes
_info                     24 bytes
_fini                     64 bytes
hsimd_attach             840 bytes
hsimd_detach             136 bytes
hsimd_getinfo            176 bytes
hsimd_read                44 bytes
hsimd_write               52 bytes
hsimd_strategy           832 bytes
hsimd_diskio             544 bytes
hcall_diskio             412 bytes
hsimd_dump               260 bytes
hsimd_ioctl              944 bytes
hsimd_prop_op            452 bytes
hsimd_get_valid_geometry 264 bytes
hsimd_build_user_vtoc    280 bytes
hv_disk_read              24 bytes
hv_disk_write             24 bytes
```

The 45 undefined symbols are:

```
bcopy biodone bp_mapin bp_mapout bzero cmn_err cv_init cv_signal cv_wait
ddi_copyout ddi_create_minor_node ddi_get_instance ddi_get_name
ddi_get_parent ddi_get_soft_state ddi_model_convert_from ddi_prop_op
ddi_remove_minor_node ddi_report_dev ddi_soft_state_fini
ddi_soft_state_free ddi_soft_state_init ddi_soft_state_zalloc debug_enter
getminor kmem_alloc kmem_free kmem_zalloc minphys mod_driverops mod_info
mod_install mod_remove mutex_destroy mutex_enter mutex_exit mutex_init
nochpoll nodev nulldev physio prom_printf strcmp strcpy va_to_pa
```

Every one was found in the live Tribblix kernel with read-only
`mdb -k ::nm -n`. The most suspicious/private-looking symbols also resolve
globally:

```
bp_mapin     0x105d740 global FUNC
bp_mapout    0x105d760 global FUNC
debug_enter  0x1010b40 global FUNC
prom_printf  0x1059ac0 global FUNC
va_to_pa     0x101a660 global FUNC
```

Names prove linkability, not semantic ABI compatibility. The structure checks
therefore matter:

```
Tribblix live CTF: sizeof (struct dev_ops) = 0x58 (88)
Tribblix live CTF: sizeof (struct cb_ops)  = 0x88 (136)
module symbol:     sizeof hsimd_ops        = 80
module symbol:     sizeof hsimd_cb_ops     = 136
module bytes:      hsimd_ops[0:8]          = 00000003 00000000
```

Thus `cb_ops` matches exactly. `dev_ops` is the pre-quiesce, revision-3
layout. The module bytes were read at ELF file offset `0x1bb0`: `.data`
begins at file offset `0x1a10`, and `hsimd_ops` is at section offset
`0x1a0`.

## Why revision 3 is safe from the missing quiesce slot

Upstream illumos-gate was checked at commit
`f575c89ce756e25eb681abb11ecb88068bd11413` (2026-08-19).

- `usr/src/uts/common/os/modconf.c:544-635` shows `mod_installdrv()` using
  the module's `drv_dev_ops` pointer directly; line 621 assigns
  `devopsp[major] = ops`. There is no size check or copy.
- `usr/src/uts/common/sys/devops.h:363-420` defines current `DEVO_REV` as 4
  and puts `devo_quiesce` last in the 88-byte structure.
- `usr/src/uts/common/os/driver.c:265-275` checks
  `ops->devo_rev < 4` before reading `ops->devo_quiesce`.

Because hsimd's first word is 3, current illumos takes the short-circuit and
does not read beyond the 80-byte legacy object. If that word had been 4, this
binary would have been unsafe to install without patching/relinking.

Upstream source URLs:

- https://github.com/illumos/illumos-gate/blob/master/usr/src/uts/common/os/modconf.c
- https://github.com/illumos/illumos-gate/blob/master/usr/src/uts/common/os/driver.c
- https://github.com/illumos/illumos-gate/blob/master/usr/src/uts/common/sys/devops.h

## Attach path is not a disk-I/O path

Solaris `mdb` disassembled the relocatable module and `dump -rv` named its
call relocations. `hsimd_attach` calls the expected DDI setup functions:

```
ddi_get_instance
ddi_soft_state_zalloc
ddi_get_soft_state
mutex_init
cv_init
ddi_create_minor_node
ddi_report_dev
```

Its error paths call `ddi_remove_minor_node`, `mutex_destroy`, and
`ddi_soft_state_free`. It also builds a default geometry/VTOC. There are no
relocations to `hv_disk_read`, `hv_disk_write`, or `va_to_pa` in attach.

Actual storage I/O is isolated later:

```
hsimd_strategy -> hsimd_diskio -> hcall_diskio
                                  -> hv_disk_read  (FAST_TRAP 0xf0)
                                  -> hv_disk_write (FAST_TRAP 0xf1)
```

This means registration/attach should not modify the backing disk. The first
explicit read from a created device node is the first hypervisor storage test.
It does not make loading risk-free: old binary/DDI behavior can still differ,
and several driver error paths contain `debug_enter`.

## Available analysis tools

Tribblix boot archive includes:

```
file strings mdb adb truss pstack pmap pldd modinfo kstat prtconf prtdiag
cfgadm fmdump ldd crle digest cksum sum openssl uuencode uudecode isainfo
```

It does not include ELF developer tools, DTrace, Perl, a compiler, make, or the
driver registration/loading utilities named above.

Solaris donor includes `nm`, `dump`, `mdb`, `adb`, DTrace, Perl, and the
normal device tools. Its `/usr/ccs/bin/elfdump` is unusable because of a local
`libelf.so.1` version mismatch, and `/usr/ccs/bin/dis` is unusable because
`libdisasm.so.1` is missing. `mdb` can still disassemble the relocatable
object, and `dump -rv` provides relocation names.

## Reliable serial transfer protocol

Several seemingly reasonable console methods failed:

- bulk `uuencode` input lost or damaged lines;
- `sane-send-keys` may classify a payload beginning with an uppercase letter
  followed by lowercase letters as a tmux special key;
- foreground read loops made Ctrl-D hazardous;
- long unframed pastes made it impossible to identify where corruption began.

The driver transfer that succeeded used small independently verifiable chunks:

1. Split the donor file into 1024-byte chunks (`aa` through `ax`).
2. Encode one chunk at a time with Perl `MIME::Base64`.
3. Print unique `BEGIN`/`DONE` markers around each chunk.
4. Capture donor tmux scrollback and remove only framing whitespace.
5. On Tribblix, terminate each receiver with an explicit sentinel rather than
   EOF or Ctrl-D.
6. Decode with `openssl base64 -d` and verify each chunk with Solaris `sum`.
7. Concatenate only after all chunks verify, then verify the final size/sum.

For the smaller modload bootstrap, the improved method sends each captured
base64 chunk inside a shell command beginning with lowercase `printf`:

```
printf '%s' '<base64>' >> /tmp/modadm-transfer.b64
```

That forces `sane-send-keys` down its literal-text path and avoids an
interactive receiver entirely. All four chunks arrived this way and decoded
to a byte-identical executable.

The full donor scrollback from the earlier transfer was also preserved at:

```
/tmp/donor-scrollback-20260819.txt
2010 lines, 121304 bytes
```

That host `/tmp` file is not durable documentation; this section records its
purpose and measurements.

## Recommended continuation

Do these in order and stop on any mismatch:

1. Create `/tmp/add_drv` and `/tmp/modload` names for the multicall binary
   and test only their usage output first.
2. Copy `/tmp/hsimd3` to the module path expected by the loader in the RAM
   root (normally `/platform/sun4v/kernel/drv/sparcv9/hsimd`). Verify again.
3. Before changing registration files, save copies in `/tmp` and record their
   checksums. Choose an unused major instead of assuming donor major 251 is
   free; inspect Tribblix `/etc/name_to_major` first.
4. Register `hsimd` with alias `"SUNW,legion-disk"`. Prefer `add_drv` so
   all volatile binding files are changed consistently. Do not invent
   `/etc/path_to_inst` state unless attachment fails and evidence requires it.
5. Load the module and inspect only `modinfo`, console messages, `prtconf`,
   and `/devices`/`/dev` first. Do not open a disk device yet.
6. If attach succeeds, issue a minimal read-only probe (one aligned 512-byte
   block) and checksum it. Do not mount or write the backing media initially.
7. If anything enters kmdb or reports a trap, preserve the console and inspect
   before continuing. Do not reflexively send Ctrl-C or reboot.

The VM-state checkpoint experiment remains backlog P2-033. Completing it before
module installation would lower the cost of failure, but it is not yet known to
work with the Niagara machine's custom vdisk mapping.

## Boot-archive remaster path (research handoff, 2026-08-20)

Ryan noted that this is familiar SmartOS-style work: boot archives are the
normal operating-system delivery artifact, not an exotic recovery mechanism.
The Niagara-specific work is adapting that established procedure to the
Tribblix SPARC media and QEMU pflash launch path.

### Proven prior art: SmartOS boot-archive surgery

Ryan authored the 2011 procedure, [Installing the newly-released Joyent SmartOS
ISO onto a writable disk partition](https://www.ryan.net/smartos-disk-blogpost/real_disk_smartos.html).
The relevant boot-archive portion establishes the exact native-Solaris workflow:

```
copy boot_archive -> lofiadm -a -> fsck -> mount -> edit -> umount -> replace
```

The article demonstrates that the archive is a UFS filesystem image mounted via
`lofiadm`, and that normal file edits survive after copying the modified image
back to boot media. This is authoritative prior art for the approach here, not
new theory. The required adaptation is only the media and platform path:

```
SmartOS x86:    /platform/i86pc/amd64/boot_archive
Tribblix sun4v: /platform/sun4v/boot_archive
```

Keep the original safety rule from that procedure: perform all surgery on a
copy, and replace only copied/disposable boot media for validation.

The recommended durable bootstrap is therefore:

1. Work on a copied Tribblix archive/media artifact only; never alter the
   currently booted instance or the source image in place.
2. Use the working Solaris 10 sun4v donor on `biggie` as the native SPARC/UFS
   workshop. It has working disk I/O and a read/write NFS staging area at
   `/share` (`10.0.5.1:/export/solaris`).
3. Extract the Tribblix `/platform/sun4v/boot_archive` from copied media,
   attach the copied UFS image with Solaris `lofiadm`, and mount it read/write.
   This has now been directly verified for m34 on the Solaris 10 donor, with
   the archive mounted **read-only** as `/dev/lofi/1`: `fstyp` reports `ufs`
   and the filesystem has 343,894 KiB total / 33,139 KiB free. The archive
   contains `sun4v/kernel/drv/sparcv9/vnex`, but no `hsimd` module or mapping.
   The outer ISO has also been read-only checked with `tools/vtoc.py`: sector
   zero has Sun-label magic `0xDABE` and a valid checksum. Its eight slices all
   intentionally span the 677.5 MiB CD image; `vtoc.py verify` flags their
   overlap because it is written for writable-disk maps, not CD-style labels.
   Preserve sector zero unchanged. The exact replacement mechanism for the
   archive has now been located read-only: ISO9660 LBA 9391 (byte offset
   19,232,768), fixed length 356,515,840 bytes. This makes the outer-media
   operation a replacement of the same-size extent in a *copied* ISO, e.g.
   `dd if=boot_archive.copy of=tribblix.copy.iso bs=2048 seek=9391 conv=notrunc`
   after independently checking the copy size and checksum. Do not run that
   against the original or currently booted file. `iso-extract.py` prints the
   ISO record as `BOOT_ARCHIVE.` (with a trailing dot), so its current direct
   pathname lookup needs that spelling even though OBP uses `boot_archive`.
4. First make the smallest independent edit: add `set cu_flags=0` to the
   archive's `/etc/system`. Boot a fresh QEMU from the copied artifact and
   prove it bypasses the T1 PCBE/CU panic without kmdb. **Completed and
   verified 2026-08-20:** `boot disk -sv` reached `SINGLE USER MODE` and the
   maintenance username prompt after loading 95/95 SMF descriptions, with no
   `-k`, kmdb intervention, or `ni_pcbe_program` panic.
5. Only after that succeeds, add `hsimd` and its bootstrap/registration
   material. Do not copy Solaris major number 251 blindly: inspect the
   Tribblix archive's own `/etc/name_to_major` first and choose a safe mapping.
6. Validate in stages: module/attach observations only, then one aligned
   512-byte read and checksum, and only later a mount or write experiment.

The end-to-end copy/edit/replace/boot test is now complete. Verified artifacts
on `niagara-playbox` are:

```
tribblix-m34.boot_archive.cuflags
  356515840 bytes
  sha256 3ae66e650c4c5aa16bfda142eeed602d7e978b1ce39aa3942f608e5416a1164b

tribblix-m34-cuflags.iso
  710717440 bytes
  sha256 c5f576b79344d9216b7d4da7408c12aa49368588050f717a7760d888dab4cbc7
```

The first `scp` transfer of the archive silently ended at 127,426,560 bytes.
The size/checksum gate caught it before the ISO write; `rsync --append-verify`
resumed it to the exact donor size and checksum. Preserve this gate for every
future archive transfer. `bootadm` availability is irrelevant to this method:
the archive is edited as a fixed-size UFS image and replaced in a copied ISO at
its existing extent.

## Durable hsimd boot and first disk read (verified 2026-08-20)

The Solaris 10 binary has now been tested successfully in a disposable m34
boot archive. Starting from the proven `cu_flags` archive, the candidate adds:

```
/platform/sun4v/kernel/drv/sparcv9/hsimd
  24472 bytes; Solaris sum 12843 48

/etc/name_to_major:
  hsimd 265

/etc/driver_aliases:
  hsimd "SUNW,legion-disk"

/etc/path_to_inst:
  "/virtual-devices@100/disk@0" 0 "hsimd"
```

Major 251 from the donor was deliberately not copied: Tribblix uses 251 for
`ecpp` and 252 for `glm`; its table ended at 264, so 265 was selected. The
working donor has no `hsimd.conf`, and none was added. The archive passed
`fsck -F ufs -m` before and after editing.

Verified artifacts on `niagara-playbox`:

```
tribblix-m34.boot_archive.hsimd
  356515840 bytes
  sha256 6d42e684145975ef9c1a678c1f95ed0363fe48766aef0ab70bc5a55f3212af5a

tribblix-m34-hsimd.iso
  710717440 bytes
  sha256 e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6
```

A fresh `boot disk -sv` loaded the copied Solaris module without kmdb. Device
configuration reported:

```
virtual-device: hsimd0
hsimd0 is /virtual-devices@100/disk@0
```

At the maintenance root shell, `modinfo` showed `hsimd` loaded at major 265,
and `/dev/dsk` plus `/dev/rdsk` contained all `c1d0s0` through `c1d0s7`
links. The first and only storage operation was one aligned 512-byte read from
whole-disk raw slice `/dev/rdsk/c1d0s2`. Its SHA-256 exactly matched sector
zero of the host backing ISO:

```
77d82f36b345774a9f55e7f6c5b939da956cd1ddf161b7ae0881ed349d84e958
```

No guest write, filesystem mount, format/geometry ioctl, or additional disk
probe had been attempted at that point. A second read-only validation then
used 512-byte sector 37564, which is ISO9660 LBA 9391 and therefore the first
sector of the embedded boot archive. Host and guest hashes again matched:

```
076a27c79e5ace2a3d47f9dd2e83e4ff6ea8872b3c2218f66c92b89b55f36560
```

This proves nonzero seek/offset handling through hsimd as well as sector-zero
reads. No guest write or format/geometry ioctl has been attempted. The healthy
VM remains parked at a root prompt in
`tribblix-hsimd-test`, QEMU PID 331073 at the time of this record.

### Read-only HSFS mount boundary and root cause

An explicitly read-only mount was attempted next:

```
mount -F hsfs -o ro /dev/dsk/c1d0s2 /mnt/hsimd-iso
```

It failed without leaving a mount active:

```
WARNING: hsimd_ioctl: cmd 4a4 not implemented
NOTICE: hs_findisovol: bread: error=(28)
mount: /dev/dsk/c1d0s2 is corrupted. needs checking
```

The media is not corrupt. The exact failure is now traced through authoritative
source:

- illumos [`sys/cdio.h`](https://github.com/illumos/illumos-gate/blob/master/usr/src/uts/common/sys/cdio.h)
  defines `0x4a4` as `CDROMREADOFFSET`.
- HSFS
  [`hs_findvoldesc()`](https://github.com/illumos/illumos-gate/blob/master/usr/src/uts/common/fs/hsfs/hsfs_vfsops.c)
  passes an uninitialized `secno` to that ioctl. If the ioctl returns an error,
  HSFS correctly falls back to volume-descriptor sector 16; if it returns
  success, HSFS treats `secno` as a valid multisession offset.
- Upstream
  [`hsimd_ioctl()`](https://github.com/artyom-tarasenko/hsimd/blob/master/hsimd.c)
  logs every unknown command but then incorrectly returns `0` (success).
- HSFS consequently adds 16 to an uninitialized offset and issues an
  out-of-slice read. `hsimd_strategy()` returns `ENOSPC`, which is errno 28 and
  explains the observed `bread` failure.

The minimal source fixes to test separately are either (a) return `ENOTTY` for
unsupported ioctls, allowing HSFS's existing fallback, or (b) explicitly
implement `CDROMREADOFFSET` and return an offset of zero for this single-session
image. No binary or live-kernel patch has been attempted yet.

## ZFS on the hsimd-attached disk (2026-08-20, IN PROGRESS -- newest result, not yet fully durable)

Following directly from the verified hsimd attach/read-only-probe work above.
A disposable EXTENDED image (larger than the base 710,717,440-byte ISO, to
carry a real writable ZFS vdev rather than trying to shoehorn one into the
read-only HSFS region that hit the ioctl bug documented above) was built and
booted. The exact artifact is:

```
/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso
1046282240 bytes (2043520 512-byte sectors, 997.8 MiB)
```

It is a disposable copy of the verified `tribblix-m34-hsimd.iso`; the latter
remains the rollback source and was not opened for guest writes. The copy keeps
the bootable ISO and embedded UFS boot archive at their original offsets, then
appends a cylinder-aligned scratch region. The Sun label was changed only in
the copy and its XOR checksum was recomputed:

```
geometry inherited from CD label: 1 head, 640 sectors/cylinder
s2: cylinder 0,    2043520 sectors (whole served disk)
s7: cylinder 2169,  655360 sectors (320 MiB scratch)
s7 absolute start: 2169 * 640 = sector 1388160
```

QEMU session `tribblix-zfs-test` reported a 997 MB MAP_SHARED vdisk. OBP
accepted the recomputed Sun label, loaded the original boot archive, and the
kernel reached the single-user SMF milestone. Confirmed results:

- `hsimd0` attached cleanly (same major/alias/path_to_inst binding pattern as
  the verified boot above).
- **`zfs0` (the ZFS pseudo-driver) loaded successfully** -- this is the first
  time any ZFS kernel component has been brought up on this guest at all.
- Offline inspection of the durable m34 archive confirmed `/sbin/zpool`,
  `/sbin/zfs`, the SPARC V9 ZFS module, `zfs.conf`, `format`, `prtvtoc`, and
  `fmthard`. No userland scoop is required for this experiment.
- The kernel printed `Booting to milestone "milestone/single-user:default"`,
  then configured devices and printed both `hsimd0 is
  /virtual-devices@100/disk@0` and `zfs0 is /pseudo/zfs@0`.

**Not yet done / in progress at time of this note**: the disposable VM has not
reached a usable maintenance shell, so no raw canary has been written to s7 and
`zpool create` has not run. After keymap, IPsec, IPMP, and nwam failures,
`svc.startd` printed `failed to abandon contract 44: Permission denied` and the
console remained quiet while QEMU continued consuming an emulated CPU. A plain
Enter and then the username `root` were the only subsequent inputs; `root` was
echoed but did not advance to a password prompt. No control character was sent.

One current hypothesis is that the copied CD label still advertises 2048
cylinders while s7 ends at cylinder 3193. `hsimd` and OBP accepted it, so this
is not established as the cause of the later milestone stall. Update the label
geometry in the next disposable copy or disprove this hypothesis before
blaming SMF. Treat `hsimd0`/`zfs0` attachment as confirmed; do **not** infer that
s7 I/O or any zpool operation has succeeded.

### SMF iteration-speed side investigation

A read-only cheap-model subagent was dispatched while the disposable VM
booted. Its key correction is that `Loading smf(7) service descriptions: 95/95`
records repository/manifest loading, not 95 services successfully starting.
The measured post-import retries are likely a separate and avoidable part of
the delay. Preserve device configuration, console login, `svc.configd`,
`svc.startd`, the single-user milestone, hsimd, and ZFS. First compare boot
timings without editing the archive:

```
boot disk -sv
boot disk -sv -m milestone=single-user
boot disk -sv -s
```

At a usable shell, capture `svcs -a`, `svcs -xv`, and dependency graphs for
`milestone/single-user`. The first concrete disable candidates, based on this
boot's actual failures, are keymap, IPsec algorithms, IPMP, and nwam; inspect
dependencies and disable one at a time in a copied archive repository. Do not
delete manifests. Retain `/etc/svc/repository.db`, `/etc/svc/profile/`, and
`/var/svc/manifest/` until a measured profile proves otherwise. Time OBP to
kernel, description import, hsimd attach, and maintenance prompt separately.

**Why this matters, tying back to the endianness research from the same
session (see `BACKLOG.md` P2-035 for the fuller writeup)**: ZFS uses an
adaptive-endian on-disk format -- blocks are written in the writer's native
byte order and tagged with a byteorder bit, converted on read if a pool is
later imported on a different-endian machine (confirmed directly against the
OpenZFS on-disk format specification). This means a ZFS pool built here, on
a real big-endian SPARC guest via the verified hsimd path, is not fighting an
extra endianness battle at the filesystem layer -- any future need to move
this pool's data to/from a little-endian machine (the host, a future
virtio-backed image, etc.) is something ZFS was already designed to handle
transparently. This is a meaningfully different, and more favorable, position
than the driver/transport layer (hsimd, or any future virtio port) currently
has to deal with.

**Immediate next steps, in order:**

1. Reach the maintenance shell reliably against the extended image (currently
   blocking -- unclear yet whether this is a boot-archive-editing issue with
   the extension itself, a timing/console issue, or something else; not yet
   diagnosed).
2. `zpool create <name> /dev/dsk/c1d0s7` (or the raw/rdsk equivalent,
   following the same raw-disk-access discipline already proven for hsimd:
   whole 512-byte blocks, `iseek=`/`oseek=` not `skip=`/`seek=` for any
   manual verification reads).
3. Verify the pool actually imports and a trivial filesystem create/write/read
   round-trips, the same "verify the artifact, not the attempt" discipline
   used everywhere else in this project (a `zpool create` reporting success is
   not itself proof; read something back).
4. Only then consider whether this becomes the new default disposable-image
   baseline, or stays a separate experimental branch pending more validation.
