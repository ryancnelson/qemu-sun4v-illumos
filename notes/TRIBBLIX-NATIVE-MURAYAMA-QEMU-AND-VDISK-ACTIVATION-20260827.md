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
