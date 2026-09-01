# Disk topology

## Historical single-disk layout

The original hSIMD implementation exposed one disk. The historical `disk100`
therefore combined unrelated roles in separate VTOC slices:

- one or more installation HSFS images;
- a UFS filesystem;
- a PCFS exchange slice used to copy files between host and guest;
- payloads for the channels-for-sockets guest drivers;
- other recovery and development material; and
- at times, slices used as ZFS pool vdevs.

That layout was a response to the one-disk constraint. It is historical input,
not the layout for this bundle.

## Current hSIMD layout

Masayuki Murayama's hSIMD implementation exposes eight QEMU drive units. The
firmware paths use slot numbers rather than QEMU's command-line unit numbers:

| QEMU drive unit | OpenBoot and kernel path |
| ---: | --- |
| 100 | `/virtual-devices@100/disk@0` |
| 101 | `/virtual-devices@100/disk@1` |
| 102 | `/virtual-devices@100/disk@2` |
| 103 | `/virtual-devices@100/disk@3` |
| 104 | `/virtual-devices@100/disk@4` |
| 105 | `/virtual-devices@100/disk@5` |
| 106 | `/virtual-devices@100/disk@6` |
| 107 | `/virtual-devices@100/disk@7` |

The `@100` portion names the parent virtual-device bus. The child address after
`disk@` identifies the slot.

## Unit 100

Current `disk100` is a 32 MiB RAM-backed disk used only by the
guest-sockets-over-storage driver. It is not boot media, a root filesystem, an
installer image, a transfer filesystem, or a ZFS pool vdev.

Unit 100 also activates the current QEMU multi-disk backend. The current QEMU
initialization checks unit 100, then unit 102 as a fallback, before scanning all
eight slots. Keeping the RAM-backed channel disk at unit 100 satisfies that
requirement without assigning it another role.

## Intended persistent disks

The bundle will assign separate persistent images for:

| Role | Contents | Required behavior |
| --- | --- | --- |
| Boot UFS | boot block, secondary booter, kernel, and `boot_archive` | OpenBoot-readable and immutable in a release |
| Root UFS | the real OpenIndiana `/` filesystem | selected by the boot archive and writable only through per-run state |
| ZFS disk | one guest ZFS pool or its vdev | imported after the UFS root is mounted |

The manifest will assign exact units and slices. Documentation and scripts must
refer to both the QEMU unit and its firmware slot. For example, QEMU unit 104 is
firmware `disk@4`, not `disk@104`.

## Optional disks

Unused slots may later hold installation media, a PCFS exchange disk, audited
guest tools, recovery media, or test fixtures. Optional disks must not become
undeclared boot dependencies.

Each manifest entry records:

- role and QEMU unit;
- firmware path;
- image format, logical size, and SHA-256;
- expected VTOC and slice roles;
- release read-only policy;
- per-run writable policy; and
- whether absence is allowed.
