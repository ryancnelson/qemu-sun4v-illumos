# Tribblix persistent UFS root without `boot -a`

## Verified result

On 2026-08-20, the combined Tribblix image booted non-interactively with:

```text
ok boot disk:d -v
Boot device: /virtual-devices/disk@0:d  File and args: -v
hsfs-file-system
Loading: /platform/sun4v/boot_archive
...
root on /virtual-devices@100/disk@0:a fstype ufs
```

The boot archive is still loaded from ISO/HSFS slice `d`, but the kernel mounts
the persistent UFS filesystem on slice `a` as `/`. No `-a` prompts or kmdb
intervention are required.

Verified image on `niagara-playbox`:

```text
/home/niagara/sun4v/images/tribblix-m34-diskroot-512m-enotty.iso
```

Verified patched boot-archive extent SHA-256:

```text
509e6887b2990f5dcf2becce4718cfb8e52bc76e959eec94e79d76f9034f5baa
```

The pre-experiment rollback remains:

```text
/home/niagara/sun4v/images/tribblix-m34-diskroot-smf-rwfix.pre-512m-enotty.iso
```

## Why `/etc/system` did not work

The archive already contained:

```text
rootdev:/virtual-devices@100/disk@0:a
```

Adding `rootfs:ufs` did not change a normal boot. The illumos source explains
why:

- `usr/src/uts/common/os/modsysfile.c:setparams()` explicitly ignores
  `MOD_ROOTDEV`.
- `usr/src/uts/common/os/swapgeneric.c:loadrootmodules()` clears
  `rootfs.bo_fstype` and `rootfs.bo_name`, then obtains both values from the
  standalone boot properties.
- The SPARC standalone exports `boot-path` from the actual PROM boot device and
  `fstype` from the filesystem used to load the archive. Thus `boot disk:d`
  naturally exports slice `d` and `hsfs`.
- The SPARC boot and krtld option parsers do not support the commonly suggested
  `-B rootdev=...` property override.

Direct `boot disk:a -v` reached the UFS filesystem but could not open
`/platform/sun4v/boot_archive`; the 335 MiB root has only about 28 MiB free, so
placing the approximately 340 MiB archive there is not viable.

## Implemented boot-archive fix

The exact Tribblix `kernel/misc/sparcv9/swapgeneric` module is an unstripped,
relocatable SPARCV9 ELF object. Two private property readers were replaced with
position-independent leaf functions:

- `get_bootpath_prop()` writes `/virtual-devices@100/disk@0:a`.
- `get_fstype_prop()` writes `ufs`.

The reproducible inputs are:

- `patches/swapgeneric-rootprops.s` — audited SPARC assembly.
- `patches/patch-swapgeneric-root.py` — validates ELF layout and original
  prologues, replaces only the audited instruction ranges, and changes only
  relocations covered by those ranges to `R_SPARC_NONE`.

Exact module hashes from the verified run:

```text
original  85312e14fbda2ac7fa763935f6931c6599bcfd3354705760cf4fa3243d28da02
patched   331b9273de054559ca7a6c10193cbd5d91553afacdebaf43d2c544bb71a34f9a
```

The patched archive was mounted through lofi on the Solaris 10 donor, synced,
unmounted, checked clean with `fsck -F ufs -m`, transferred with rsync, and
hashed again after splicing into the exact ISO extent.

## Scope and caveat

This is deliberately a media-specific bootstrap patch. It makes this archive
always select the Niagara virtual disk's UFS slice `a`. It should not be used as
a generic Tribblix boot archive for other root devices.

The current image still contains the separate one-shot `hsimd` ioctl experiment.
Automatic persistent-root selection is verified; mounting the ISO as HSFS from
the running guest still requires replacing that experiment with the plain
ENOTTY `hsimd` build and retesting.

## 2026-08-21 batch remaster candidate

To avoid another approximately 40-minute boot for every missing tool, the next
candidate was rebuilt in one offline batch. It was booted and accepted on
2026-08-21.

Candidate on `biggie`:

```text
/export/solaris/tribblix-batch/tribblix-batch-final.iso
logical size  2158034944 bytes (4214912 sectors)
allocated     approximately 885 MiB (sparse)
SHA-256       31cba6fc3db21e02d0db768e0ade4dfb7209dba9193d5208f8f8be0a8e6c24dd
```

The byte-identical pre-boot candidate was transferred to playbox as:

```text
/home/niagara/sun4v/images/tribblix-m34-batch-final.iso
```

That file is now the live MAP_SHARED disk and has intentionally changed as the
guest installed a package and updated persistent SMF state. The hash above is
the immutable pre-boot candidate hash, not the current live-disk hash.

The UFS root is 1,430,257,664 bytes and has approximately 496 MiB free. Its
SHA-256 is `6ed680ca37104eef7ce810e43f5353f4112228ad514b029ef7811761f5134c4a`.
That value matched all three independent views: the sealed file inside the
Solaris donor, the host-extracted sparse file, and the root extent embedded in
the final image.

The boot archive SHA-256 is
`e108f186f41363a65b1adad2c9417ca2b748a4d16f9cc38a530e14b5fd5b8b3a`.
The batch put the real plain-`ENOTTY` `hsimd` binary (19,576 bytes, Solaris
`sum` `30293 39`) at `/kernel/drv/sparcv9/hsimd`, not the misleading
`hsimd-enotty` donor artifact that was actually byte-identical to the one-shot
experiment. Acceptance testing found that this was the wrong archive path for
sun4v: the kernel loaded `/platform/sun4v/kernel/drv/sparcv9/hsimd`, whose
Solaris `sum` is still `12843 48`. The existing `swapgeneric` persistent-UFS
root patch remains in place.

### Added userland foundation

The persistent root now contains:

- Vim, with `/usr/bin/vi -> vim`;
- Perl 5.34;
- Python 3.12;
- GCC 7, GNU make, GNU binutils, system headers, flex, and msgpack-c;
- `socat`, the existing channel tools, and the channel HTTP-proxy helpers;
- a quarantined Solaris 10 PPP experiment under `/opt/niag/sol10-ppp` (not
  installed into `/kernel` and not started automatically).

Packages were installed offline with `pkgadd -R` and the audited
`tools/tribblix-pkgadd-admin` policy. `pkgchk` was clean except for the
intentional `vi` symlink replacement. Runtime execution must be tested on the
Tribblix kernel; modern Tribblix binaries predictably raise `Bad System Call`
if executed in a chroot on the older Solaris 10 donor kernel.

The first live link test found one omitted package: GCC could compile but `ld`
failed with `crt1.o: open failed`. The now-mounted package media contained
`TRIBsys-lib-c-runtime.0.34.zap`; installing that tiny package persistently
provided both `/usr/lib/crt1.o` and `/usr/lib/sparcv9/crt1.o`. A subsequent
native test compiled, linked, and executed a libc-using program, printing:

```text
NATIVE_BUILD_OK
LINK_AND_EXEC_OK
```

`/etc/logindevperm.pre-niagara` preserves the original device-permission file.
The active headless version retains its comments but removes the invalid device
rules that spammed every console login. Offline SMF repository edits disabled
only the repeatedly failing `route` and `keymap` services; the user's earlier
persistent network/live-media disables remain intact.

### Final VTOC

The inherited geometry is one head and 640 sectors per cylinder:

```text
ncyl 8192
s0   start cylinder 2221 = sector 1421440, length 2793472 sectors
s1   unused
s2   start 0, length 4214912 sectors
s7   unchanged: cylinder 2169, length 33280 sectors
```

This exposed and fixed a dangerous tooling trap: `dk_map[].dkl_cylno` is a
cylinder number while `dkl_nblk` is a sector count. The old `vtoc.py` display
called both values blocks, and its overlap verifier compared cylinders directly
with sectors. Writing `1421440` as the s0 start would have made the root
unreachable; the correct stored value is `2221`. `tools/vtoc.py` now displays
both cylinder and derived sector starts, verifies ranges in sectors, permits the
identical s3-s6 aliases used by the hybrid CD label, and can update `ncyl` while
recomputing the Sun-label XOR checksum.

Before transfer, hashes proved that the non-archive boot prefix, the remainder
of the HSFS image, the 640-sector gap, and the complete s7 channel region were
unchanged. The final label has magic `0xDABE`, checksum XOR zero, and passes the
corrected geometry-aware verifier.

### Fast extraction from the donor

Normal NFS, virtual-NIC TCP, and hsimd channel copies of the 1.43 GiB sparse
file were all bottlenecked by the emulated guest. The successful method was:

1. close, sync, unmount, and `fsck -F ufs -m` the lofi filesystem in Solaris;
2. `sync` the donor root;
3. briefly `SIGSTOP` only the exact QEMU PID;
4. mount its backing image as Linux UFS read-only;
5. copy the closed file with `cp --sparse=always`;
6. unmount, detach the loop device, and always `SIGCONT` QEMU from an EXIT trap.

`tools/transfer/extract-file-from-frozen-ufs.sh` implements the checks and
cleanup. The copy took about seven seconds and preserved the running donor VM.
It can also hash a file in place by passing `-` as OUTPUT. The prior hour-scale
copy attempts were stopped and their partial outputs removed after verification.

### Acceptance boot and checkpoint

Normal `boot disk:d -v` passed without `-a` or kmdb:

```text
niagara: vdisk 2058 MB MAP_SHARED
root on /virtual-devices@100/disk@0:a fstype ufs
Remounting root read/write
```

The boot reached a login prompt in roughly three minutes after accepting the
one-time default keyboard prompt. The root reports 1,380,183 KiB total and
approximately 507,480 KiB available. Vim 9.1, Perl 5.34.3, Python 3.12.13,
GCC 7.3.0, GNU Make 4.4.1, Binutils 2.39, and socat 1.7.3.4 all execute on the
Tribblix kernel.

The first HSFS mount still failed with `CDROMREADOFFSET` because sun4v loaded
the old platform driver described above. A second mount succeeded—the old
binary's deliberate one-shot behavior—and exposed `/mnt/iso/pkgs`. The durable
next remaster must replace
`/platform/sun4v/kernel/drv/sparcv9/hsimd`, not `/kernel/drv/sparcv9/hsimd`.

The route service was regenerated/re-enabled during live-media image
preparation despite the offline repository edit. It was disabled persistently
from the running guest after its first failed retry loop; keymap was already
disabled. This explains why offline repository verification alone was not a
sufficient boot-time gate.

Channel 0 was then started on `/dev/rdsk/c1d0s7`, with the host bridge pointed
at the live final image and byte offset 710,737,920. The standard channel test
round-tripped 262,144 random bytes in 1.14 seconds at 450 KiB/s aggregate and
reported `MATCH`.

After `sync; lockfs -f /; sync` and QEMU's `SIGUSR2` vdisk flush, a reflink disk
checkpoint was taken while exact QEMU PID 49652 was stopped:

```text
/home/niagara/sun4v/images/tribblix-m34-batch-selfhost-checkpoint.iso
SHA-256 671d0cc2fdb8eacf6296647342ee1a00df85a28bc6dcc0cdd15733436f62300b
```

The checkpoint has a valid VTOC and contains the persistent C-runtime package
and service changes. It is a disk rollback, not a RAM/CPU machine-state image.
One operational caveat: because QEMU owns the real tmux tty, `SIGSTOP` lets the
shell reclaim the foreground; `SIGCONT` alone then leads to an immediate
job-control stop on terminal I/O. Resume it with `fg` in `rootpane`. The guest
was verified responsive afterward with `VM_ALIVE_AFTER_CHECKPOINT`.
