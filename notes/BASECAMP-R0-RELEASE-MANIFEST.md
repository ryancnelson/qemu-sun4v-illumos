# BASECAMP_R0 release manifest

Pipeline stage: RELEASE. Built and verified 2026-08-25 on niagara-playbox.
Disjoint roles per hard gate (BOOT_MEDIA vs ISCSI_LUN are never the same
file).

## BOOT_MEDIA (R0 boot artifact)

```
path      /home/niagara/sun4v/images/basecamp-r0-20260825T054938Z.iso
size      644198400 bytes
sha256    5b73fa5d8b5c5500218273a6ab3b25bec8583553806b0f15bac1c488d43cf9c3
```

Built from immutable inputs, both re-verified fresh immediately before use:

```
pristine source   OpenIndiana_Text_SPARC_12_2025.iso.clean
                   size 644198400  sha256 173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04
boot archive       OpenIndiana_Text_SPARC_12_2025.boot_archive.hsimd
                   size 192595968  sha256 f334e542c0ba0ac35fea8bf8f6270f813e984727a6d5c77a3c6fda0906cee376
splice offset      byte 449744896 (sector 878408), length 192595968 bytes (376164 sectors)
```

Verification performed (sector-exact, not byte-granular — a byte-granular
`dd bs=1` readback over the full 192MB region silently produced a wrong
digest in this session and must not be trusted again for large regions):

- prefix `[0, 449744896)` byte-identical to pristine source (`cmp -n`)
- spliced region `[449744896, 642340864)` sha256-identical to the boot
  archive file, verified with `dd bs=512 skip=878408 count=376164`
- suffix `[642340864, 644198400)` byte-identical to pristine source
- total file size unchanged at 644198400 (in-place splice, no append)

This whole-file hash matches the previously-recorded pre-channel-scratch
`OpenIndiana_Text_SPARC_12_2025.hsimd.test.iso` hash from
`docs/design-plans/2026-08-23-openindiana-sparc-smoke.md`, confirming
byte-for-byte reproducibility from immutable inputs alone.

**Disposable-after-channel-init.** Per the historical channel extent
`[520093696, 536870912)` sitting inside the boot-archive extent
`[449744896, 642340864)`, initializing the host channel intentionally
overwrites live boot-archive bytes already resident in guest RAM. This
makes the deployed ISO single-use/non-rebootable after channel init BY
DESIGN, not a bug. Every deploy must rebuild BOOT_MEDIA fresh from the two
immutable inputs above; never reuse a post-channel-init file as a future
boot source. Dedicated non-boot-archive channel placement is a later
promotion gate, not required for R0.

## ISCSI_LUN (explicitly NOT boot media — separate role)

```
path      /home/niagara/sun4v/images/oi-iscsi-zpool-checkpoint-20260824.img
size      1073741824 bytes (1 GiB)
sha256    3ebd859053c8da8b1dd27d3e21115978e3716f35ce17d81eb84b23614861a502
role      exported iSCSI/LIO backing disk for the Linux target; NOT bootable
          OpenIndiana media. Must never be passed to QEMU as a boot drive.
```

## QEMU engine (R0)

```
path      /home/niagara/niag-proj/qemu/build/qemu-system-sparc64.baseline-11aa0b1
sha256    7073119a7c2c15527cd93a315ccce30bafacb537228e049eafb4118b46b0a053
version   QEMU emulator version 8.2.2 (v8.2.2-dirty)
source    base commit 11aa0b1f..., unpatched (no tlb-range/miss-storm fix)
```

Explicitly NOT `qemu-system-sparc64` (currently the R1 tlb-range binary,
sha256 `bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b`,
sitting at the unsuffixed path on playbox) and NOT
`qemu-system-sparc64.tlb-range` (same hash, explicit R1 copy). R1 will
reuse this same BOOT_MEDIA build recipe with only the tlb-range engine
substituted; R2 will additionally substitute the Masa hsimd driver. Device
paths and channel offsets are re-derived fresh for every release — never
carried forward from a prior release's values.

## Firmware

```
path      /home/niagara/sun4v/firmware/base-1gib
```

## Deploy status

Not yet deployed as of manifest write time. See runbook entry for the
DEPLOY/TEST/PROMOTE record.
