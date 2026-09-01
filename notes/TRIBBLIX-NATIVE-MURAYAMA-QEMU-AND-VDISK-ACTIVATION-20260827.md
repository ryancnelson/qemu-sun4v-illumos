# Tribblix-native Murayama QEMU build and vdisk activation gate

Date: 2026-08-27

## Result

A native Tribblix build of Murayama's QEMU sun4v fork booted the existing
OpenIndiana installed-root image through kmdb and into the OpenIndiana banner.
The boot required a drive at QEMU unit 100 even though the intended root disk
was unit 104.

Unit 100 is an activation gate in the current implementation. This note calls
it an **activation sentinel**. That is a project term, not a name used by
Murayama or QEMU.

This is not evidence that the guest disk driver is limited to unit 100. Once
the backend is active, the same driver and hypercall path use unit 104
successfully. The defect is in the QEMU machine's host-side initialization
gate, before the guest can discover or operate the disk.

If neither unit 100 nor the unit-102 fallback is attached, the machine does not
initialize the new vdisk backend. A valid disk attached at unit 104 then looks
broken to the firmware. Adding a small carrier image at unit 100 activates the
backend, after which the initialization scan finds both units 100 and 104.

## Source-level explanation

`niagara_init()` in `hw/sparc64/niagara.c` probes for a drive at
`VDISK_UNIT_BASE`, which is unit 100. If unit 100 is absent, it checks unit 102.
Only when one of those probes succeeds does it call `niagara_load_vdisk()`.

`niagara_load_vdisk()` does two important things:

1. It sets `s->use_new_vdisk = 1`.
2. It scans the complete unit range 100 through 107, including unit 104.

The vdisk trap handler in `target/sparc/int64_helper.c` starts with an activation
test equivalent to:

```c
if (!NiagaraBoardStatePtr->use_new_vdisk)
    return FALSE;
```

The implementation therefore asks whether unit 100, or its special fallback
unit 102, exists before it asks which disks exist across the supported range.
Unit 104 by itself never gets as far as the full scan.

The carrier image's contents are secondary to activation. Its presence causes
the new backend to initialize. It is still exposed as vdisk 0, so it should be
a deliberate, run-local artifact rather than an unexplained production disk.

## OpenBoot path and QEMU unit mapping

OpenBoot places the vdisks beneath one virtual-device bus:

```text
/virtual-devices@100/disk@0
/virtual-devices@100/disk@1
/virtual-devices@100/disk@2
/virtual-devices@100/disk@3
/virtual-devices@100/disk@4
/virtual-devices@100/disk@5
/virtual-devices@100/disk@6
/virtual-devices@100/disk@7
```

The `@100` in `/virtual-devices@100` is the address of the parent bus. It does
not mean that OpenBoot sees only QEMU drive unit 100. The child address selects
the vdisk slot:

| OpenBoot node | QEMU drive unit |
| --- | ---: |
| `disk@0` | 100 |
| `disk@1` | 101 |
| `disk@2` | 102 |
| `disk@3` | 103 |
| `disk@4` | 104 |
| `disk@5` | 105 |
| `disk@6` | 106 |
| `disk@7` | 107 |

This mapping explains QEMU's normalized startup messages such as `unit:0`,
`unit:3`, and `unit:4` for command-line units 100, 103, and 104.

On 2026-08-28, this OpenBoot command loaded the UFS boot archive from the image
attached at QEMU unit 103:

```text
boot /virtual-devices@100/disk@3:d -v
```

That boot is direct evidence that OpenBoot can address Murayama's additional
vdisk units. `show-devs` lists the firmware-described slots; it does not prove
that every slot has a backing image. A successful label, filesystem, or boot
read proves that the selected slot is backed and operational.

### Unit 103 on-disk offsets

The raw unit-103 image is:

```text
/tink/disk-images/workstation-multiuser-raw-20260827T010500Z/artifacts/installer-unit103.img
size: 2,791,702,528 bytes
```

Its valid SPARC VTOC8 describes the following relevant regions. Offsets and
lengths are in bytes; sector numbers use 512-byte sectors.

| Region | Start sector | Byte offset | Byte length | Meaning |
| --- | ---: | ---: | ---: | --- |
| `s0`, `s1`, `s3`-`s6` | 0 | 0 | 643,891,200 | Aliases of the bootable ISO/HSFS region |
| `s2` | 0 | 0 | 2,791,702,528 | Whole served disk |
| `s7` | 1,258,240 | 644,218,880 | 2,147,483,648 | Appended region through end of file |

There is one embedded UFS filesystem used as the boot archive inside the
ISO/HSFS region:

```text
start sector:       878,408
start byte:         449,744,896
length:             192,595,968 bytes
end byte exclusive: 642,340,864
last byte:          642,340,863
```

A full-file big-endian UFS magic scan found the primary superblock at that
offset and the expected sequence of backup superblocks through the same
extent. Those repeated magic values are replicas within this single UFS
filesystem, not additional UFS partitions. No UFS superblock was found in
`s7`. Thus `disk@3:d` selects VTOC slice 3, an alias of the ISO region, while
the boot archive it ultimately uses is the embedded UFS extent beginning at
byte 449,744,896.

For isolated archive work, the source was preserved and copied into this named
lab artifact directory on 2026-08-28:

```text
/tink/lab/images/IMG-20260828-unit103-ufs-split/
```

The directory contains:

| Artifact | Exact size | Source byte range |
| --- | ---: | --- |
| `installer-unit103-copy.raw` | 2,791,702,528 | Complete working copy |
| `beforeufs.raw` | 449,744,896 | `[0, 449744896)` |
| `insideufs.raw` | 192,595,968 | `[449744896, 642340864)` |
| `afterufs.raw` | 2,149,361,664 | `[642340864, 2791702528)` |

The archival source, complete working copy, and the stream formed by
concatenating `beforeufs.raw`, `insideufs.raw`, and `afterufs.raw` all have the
same SHA-256:

```text
e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c
```

This proves that the split is lossless and that the three pieces can recreate
the exact unit-103 image.

### Cross-endian UFS limitation on Tribblix x86

Attaching `insideufs.raw` with `lofiadm` on the Tribblix x86 host produced:

```text
lofiadm -a insideufs.raw
/dev/lofi/2

fstyp /dev/lofi/2
unknown_fstyp (no matches)

fsck /dev/lofi/2
BAD SUPERBLOCK AT BLOCK 16: MAGIC NUMBER WRONG
```

The extraction boundary is correct. Reading four bytes at offset 9,564 in
`insideufs.raw` returned:

```text
00 01 19 54
```

This is the UFS magic `0x00011954` in SPARC big-endian byte order. Tribblix is
running on x86, and its native `fstyp` and `fsck_ufs` do not recognize this
cross-endian filesystem. Searching for alternate superblocks cannot fix the
byte-order mismatch. Creating a generic superblock from the x86 host would
replace valid SPARC metadata with incompatible metadata.

The `fsck` attempt was interrupted before generic-superblock creation. A
post-attempt hash of the concatenated split files still matched the protected
source:

```text
e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c
```

Use `lofiadm -r -a` for read-only host probes. Perform `fsck`, mount, and edits
to this UFS archive inside a Solaris or illumos SPARC guest. Do not answer yes
to generic-superblock prompts from the x86 tools.

### Eight-byte host I/O observation

A three-second DTrace sample of QEMU PID 47702 during guest boot measured:

```text
read:   2,960 calls, 23,680 bytes
write:  3,012 calls, 24,096 bytes
```

Both averages are exactly eight bytes per call. The `io` provider reported no
physical device operations in QEMU process context during the same window.
These calls are probably event-loop or notification traffic, not guest disk
payload. They do not show that the Niagara vdisk backend issues eight-byte disk
requests and must not be used to justify read-size or caching changes. Accurate
vdisk rates require probes around `sparc_vdisk_trap` and its completion path.

The unit-100 activation requirement is separate from OpenBoot visibility. Once
the host-side vdisk backend is active, OpenBoot paths such as `disk@3` and
`disk@4` reach QEMU units 103 and 104 through the same backend.

## Failure evidence

With only unit 104 attached:

- plain `boot` reached `vdisk` and trapped at MAXTL;
- `boot /virtual-devices@100/disk@4:a -k -v` reported
  `Bad magic number in disk label`;
- an offline inspection showed that the first sector was valid and ended in
  `da be 10 f3`, including the valid Sun VTOC8 magic `da be`;
- a temporary `DEBUG_VDISK` build produced no vdisk-handler messages.

The lack of debug output was decisive. The disk label error was downstream
misdirection: the new vdisk handler had never been entered.

With `carrier-unit100.img` attached, QEMU logged:

```text
niagara_load_vdisk: unit:0 slice2 found
niagara_load_vdisk: unit:0 size:1073741824
niagara_load_vdisk: unit:4 slice2 found
niagara_load_vdisk: unit:4 size:64424509440
```

The exact firmware command then loaded `unix`, `genunix`, the platform and
UltraSPARC-T1 modules, kmdb, and CTF data, and reached:

```text
OpenIndiana Hipster 2025.12 Version illumos-31d3d510d0 64-bit
```

## Native Tribblix build

Executable:

```text
/tink/builds/qemu-sun4v-879fee-tribblix/build/qemu-system-sparc64
```

Clean executable SHA-256:

```text
6601afd11321905c900249df62b4d3667ccbdad2f8b126a8e72c36a365358be7
```

The executable is QEMU 10.2.0, a 64-bit AMD64 illumos ELF, and supports
`-M niagara`.

Source:

```text
https://github.com/masa-murayama/qemu-sun4v.git
commit 879fee341ad8307f8f0a0110b4a7dc6d6853d639
describe v10.2.0-sun4v-0.2-dirty
```

The dirty description accounts for two retained patches.

### Retained patches

1. The playbox TLB range-flush patch changes `target/sparc/ldst_helper.c` to
   use `tlb_flush_range_by_mmuidx()` instead of calling `tlb_flush_page()` once
   per 8 KiB page.

   ```text
   /tink/builds/playbox-ldst-helper-range-flush.patch
   SHA-256 26772dd1d8ff08ae764b8d89971708f994624590708337165e33dc20494aeac9
   ```

2. The illumos-host portability patch makes two changes:

   - `hw/sparc64/dklabel.h` undefines the host `_SUNOS_VTOC_16` and forces the
     SPARC VTOC8 on-disk layout.
   - `hw/sparc64/niagara.c` uses QEMU's `cpu_to_be*` and `be*_to_cpu` helpers
     instead of the unavailable host `htobe*` and `be*toh` interfaces.

   ```text
   /tink/builds/qemu-sun4v-illumos-host-portability.patch
   SHA-256 4f7692dfedc3d47e437981e3feae977f351af0e8226dd25debb7fb71f1a722c7
   ```

The temporary `DEBUG_VDISK` instrumentation was reverted. Relinking after the
revert restored the clean executable hash exactly.

### Configure environment

```sh
PATH=/usr/gnu/bin:/usr/bin:/usr/sbin
PKG_CONFIG_LIBDIR=/usr/lib/amd64/pkgconfig:/usr/share/pkgconfig

bash ../configure \
  --cpu=x86_64 \
  --cc=gcc \
  --host-cc=gcc \
  --target-list=sparc64-softmmu \
  --disable-werror \
  --disable-docs \
  --disable-sdl \
  --disable-sdl-image \
  --disable-gtk \
  --disable-opengl \
  --disable-dbus-display \
  --disable-vnc \
  --disable-curses \
  --disable-plugins
```

The explicit 64-bit pkg-config path is required because the default lookup
found 32-bit GLib metadata. Plugins are disabled because the illumos linker
rejected GNU `--dynamic-list`. The resulting build is headless and uses TCG.

Tribblix needed Git, GCC 14, GNU make, Meson, Ninja, pkg-config, development
headers, native assembler support followed by GNU binutils, and the C runtime
startup objects.

## Firmware

The firmware set used the following `q.bin`:

```text
SHA-256 47ddae19e1d4ee0143326991ffc71eca71b5d7b0383cd3947187171bbb2eaee3
```

Compatibility links:

```text
1up-md.bin -> md.bin
1up-hv.bin -> hv.bin
```

## Disk chain and launch constraints

Run directory:

```text
/tink/runs/ec2-tribblix-smoke-20260827-01
```

Proven disk chain:

```text
/tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/root-unit104.qcow2
  -> /tink/disk-images/runs/workstation-playbox-known-good-20260827T165948Z/images/known-good-state.qcow2
  -> /tink/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
```

Raw base SHA-256:

```text
964d10a2f0bba82bffb940db4e30c7fb111f27b6acd3400d0da6fe826ecc3fbd
```

The middle layer matched the playbox copy byte for byte before any rebase:

```text
30c5ff6e773f3fae0d50c321247437bf17a016586fe476d95cb4ee6a4144ff44
```

The Tribblix host has `/mnt/disk-images -> /tink/disk-images` so the original
qcow2 backing paths resolve without rewriting the known-good middle layer.

QEMU 10.2's automatic file-locking probe succeeds on Tribblix/ZFS, but the
subsequent byte lock fails with `EINVAL`. Disable locking on every protocol
node in the chain:

```text
file.locking=off
backing.file.locking=off
backing.backing.file.locking=off
```

Required drive arguments:

```sh
-drive id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file.locking=off,file=./proven-lineage-exact/carrier-unit100.img

-drive id=target104,format=qcow2,if=none,bus=0,unit=104,readonly=off,cache=none,file.locking=off,backing.file.locking=off,backing.backing.file.locking=off,file=./proven-lineage-exact/root-unit104.qcow2
```

Firmware boot command:

```text
boot /virtual-devices@100/disk@4:a -k -v
```

The earlier known-good playbox launch attached units 100, 101, 103, and 104.
This investigation isolated unit 100 as the activation requirement. Units 101
and 103 are not part of this initialization gate.

## Rollback and reference points

Boot environment:

```text
pre-qemu-sun4v-build-20260827
```

ZFS source snapshots:

```text
tink/builds/qemu-sun4v-879fee-tribblix@murayama-879fee-pristine
tink/builds/qemu-sun4v-879fee-tribblix@built-headless-20260827
tink/builds/qemu-sun4v-879fee-tribblix@final-clean-20260827
```

## Live-process caveat

At the time of this note, the successful guest remained in local tmux pane
`trib:1.0`. That process had started from the temporary trace-enabled executable
before the clean relink. The executable currently on disk is the clean build
with the recorded SHA-256.

## Candidate upstream fix

Initialization should activate the new backend when any supported vdisk unit
from 100 through 107 is configured. A full-range presence scan would make unit
104 independently usable and remove the hidden carrier requirement. Any patch
should preserve the intended unit-to-vdisk mapping and test unit 104 both alone
and alongside unit 100. The first patch target is QEMU's `niagara_init()`, not
the illumos/Solaris guest disk driver.

## 2026-08-28 host-side archive-recovery transition

The immediate image task is to recover the newer OpenIndiana UFS boot archive
that contains `/usr/bin/awk`. Project history says that archive was already
built and was retained inside a ZFS pool in one of the other workstation disk
images. The archive currently used by unit 103 is older: its early-boot
`devfsadm` gate cannot parse the mount table because `/usr/bin/awk` is absent.

Before attaching disk images with `lofiadm` or importing an embedded pool on
the Tribblix host, we stopped the active QEMU instance so the image chain would
have one owner. The affected run was:

```text
/tink/runs/oi-basecamp-20260828T100852Z-41597
QEMU PID 41629
```

Ryan reported that the guest was stopped at OpenBoot, so no guest filesystem
was mounted. QMP `system_powerdown` was accepted and emitted a `POWERDOWN`
event, but QEMU remained running. This confirms that the current sun4v/OpenBoot
state does not act on that nominally graceful request. We then sent QMP `quit`.
QEMU emitted:

```text
SHUTDOWN guest=false reason=host-qmp-quit
```

The runner reported exit status 0, no `qemu-system-sparc64` process remained,
and the complete run directory was retained. This was a deliberate host-side
emulator stop, not a successful in-guest shutdown.

Before proceeding beyond the initial read-only lofi attachment, we created the
host checkpoint Ryan requested:

```text
tink@pre-unit104-bootarchive-recovery-20260828T102000Z
creation: 2026-08-28 03:18 PDT
referenced: 11.2 GiB
```

The snapshot had `USED=0B` immediately after creation. It captures the
unit-104 base image in `/tink/disk-images` before embedded-pool inspection.

Initial whole-file `zdb -l` probes against both the 60 GiB unit-104 image and
the unit-103 installer image found no labels. That does not show that unit 104
lacks a zpool. A read-only lofi attachment of the raw 60 GiB base exposed one
whole-disk VTOC slice, but both `zdb -l /dev/rlofi/1` and `zpool import -d
/dev/lofi` found no ZFS labels. The raw file is only the bottom of the installed
disk's qcow2 chain; it is not the complete logical disk.

The stopped run's complete unit-104 chain is:

```text
/tink/runs/oi-basecamp-20260828T100852Z-41597/disks/root-unit104.qcow2
  -> /tink/runs/ec2-tribblix-smoke-20260827-01/proven-lineage-exact/root-unit104.qcow2
  -> /tink/disk-images/runs/workstation-playbox-known-good-20260827T165948Z/images/known-good-state.qcow2
  -> /mnt/disk-images/workstation-unit104-known-good-20260826T210446Z/extra-unit104-60g.img
```

The current run layer is about 198 KiB, the proven-lineage layer about 600 MiB,
and the known-good-state file about 72 MiB. The next inspection must flatten
this complete, stopped chain into a separately named sparse raw recovery
artifact, attach that artifact with `lofiadm`, identify its Sun-label slices,
and import the candidate pool read-only under an alternate root.

The native archive-editing procedure is already documented in
`HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md`, with Ryan's SmartOS article as prior art:

```text
copy boot_archive -> lofiadm -a -> fsck -> mount -> edit -> umount -> fsck
```

For this recovery, extraction precedes editing: locate the newer archive in
the read-only imported pool, copy it into a separately named artifact, record
its size and SHA-256, mount that copy, and verify `/usr/bin/awk` plus its runtime
dependencies before using it to assemble a new unit-103 image.
