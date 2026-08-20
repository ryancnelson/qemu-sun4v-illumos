# Technical Review: UFS Root Disk Formatting & hsimd Ioctl Contract

**Author**: Antigravity (Sole Live-Console Custodian & VM Operator)  
**Date**: 2026-08-20  
**Methodology**: Strict TDD & Gilfoyle Standards (**FACT / HYPOTHESIS / PLAN**).  
**Execution Invariant**: Read-only evaluation; **zero** console inputs, mutations, or image edits.

---

## 1. Executive Summary & Verdict

- **Target Objective**: Determine the shortest, evidence-backed route for formatting `/dev/rdsk/c1d0s0` as a UFS root disk, and assess boot handoff requirements.
- **Formatting Verdict**: **CONDITIONAL GO (with `newfs -s <sectors>` bypass) / NO-GO for bare `newfs`**.
  - Standard `newfs /dev/rdsk/c1d0s0` issues `DKIOCGMEDIAINFO` / `DKIOCGMEDIAINFOEXT` / `DKIOCGGEOM` / `DKIOCGVTOC` to determine sector count and track geometry.
  - In `hsimd.c`, unknown ioctls log a warning and return `0` (success) **without initializing user output buffers**, causing userland tools (`prtvtoc`, `mount -F hsfs`, `zpool`, `newfs`) to compute offsets/extents from stack garbage.
  - Providing explicit geometry/size via `newfs -s <sectors> -t 1 -o space /dev/rdsk/c1d0s0` may bypass capacity discovery, but **clean ioctl implementation in `hsimd` or returning `ENOTTY`** is the only robust architectural fix.
- **Boot Handoff Verdict (`installboot`)**:
  - For **UFS root booted from an existing OBP boot-archive**, `ufs_install.sh` demonstrates that `installboot` is **NOT required** if OBP loads `/platform/sun4v/boot_archive` from `/devices/virtual-devices@100/disk@0` directly, provided `/etc/system` (without `root_is_ramdisk`) and `/etc/vfstab` point to `/dev/dsk/c1d0s0`.
  - For native UFS bootblocks loaded directly by OBP stage 1/2 without an archive, `installboot` would be required; however, Tribblix SPARC uses the boot archive (`bootadm update-archive -R /a`).

---

## 2. Technical Evaluation: `newfs` & `hsimd` Ioctl Behavior

### 2.1 The `hsimd` Unimplemented Ioctl Bug (FACT)
As documented in `HSIMD-TRIBBLIX-LIVE-BOOTSTRAP.md` and observed during `prtvtoc` and `zpool create`:
1. `hsimd_ioctl()` logs:
   ```text
   WARNING: hsimd_ioctl: cmd <hex> not implemented
   ```
2. **The Defect**: It returns `0` (`DDI_SUCCESS`) instead of `ENOTTY` / `EINVAL`.
3. **The Consequence**: The calling kernel or userland subsystem assumes the ioctl populated the output structure. Because the structure contains uninitialized stack/heap memory, caller logic branches on garbage values (e.g. `hsfs` adding 16 to uninitialized multisession sector offset, `prtvtoc` declaring `Invalid VTOC`, `zpool` reading garbage geometry).

### 2.2 Can `newfs -s <sectors>` Avoid the Bug?
In illumos / Solaris `usr/src/cmd/fs.d/ufs/newfs/newfs.c` and `mkfs.c`:
- If `newfs` is invoked with explicit size `-s <sectors>` (e.g. `newfs -s 1387520 /dev/rdsk/c1d0s0`), `mkfs` uses the command-line sector count for the superblock calculation rather than querying `DKIOCGMEDIAINFO` (`0x0430`).
- However, `mkfs` and `libdiskmgt` still issue `DKIOCGGEOM` (`0x0401` / `0x0402`) or `DKIOCGVTOC` (`0x0417` / `0x0419`) to determine cylinders, heads, and sectors per track (nsect/ntrack) unless also overridden (e.g., `-t 1 -o space`).
- If `hsimd_ioctl` returns `0` for geometry queries, `mkfs` may read `ntrack=0` or `nsect=0`, causing floating-point exceptions (`SIGFPE` divide by zero) or corrupted cylinder group layout.

---

## 3. Specification of Required `hsimd` Ioctls (1 Head x 640 Sectors D1 Label)

If `hsimd` is patched/recompiled, it must support standard Sun disk ioctls for the `c1d0` geometry:

### 3.1 Geometry Constants
- **Heads (`dkl_nhead`)**: `1`
- **Sectors per Track (`dkl_nsect`)**: `640`
- **Sectors per Cylinder**: `640`
- **Total Cylinders (`dkl_ncyl`)**: `2221` (Dedicated channel disk: 1,421,440 sectors / 640 = 2221 cyl)
- **Sector Size**: `512` bytes

### 3.2 Required Ioctl Implementations & Exact Field Values

```c
#include <sys/dkio.h>
#include <sys/vtoc.h>

int hsimd_ioctl(dev_t dev, int cmd, intptr_t arg, int mode, cred_t *credp, int *rvalp)
{
    minor_t instance = getminor(dev) >> 3;
    minor_t slice = getminor(dev) & 7;

    switch (cmd) {
    case DKIOCGGEOM: { /* 0x0401 / 'd'<<8 | 1 */
        struct dk_geom geom;
        bzero(&geom, sizeof(geom));
        geom.dkg_ncyl = 2221;
        geom.dkg_nhead = 1;
        geom.dkg_nsect = 640;
        geom.dkg_secsize = 512;
        geom.dkg_acyl = 0;
        geom.dkg_bcyl = 0;
        geom.dkg_nwinf = 0;
        geom.dkg_rpm = 3600;
        geom.dkg_pcyl = 2221;
        if (ddi_copyout(&geom, (void *)arg, sizeof(geom), mode) != 0)
            return (EFAULT);
        return (0);
    }

    case DKIOCGMEDIAINFO: { /* 0x042A / 'd'<<8 | 42 */
        struct dk_minfo minfo;
        bzero(&minfo, sizeof(minfo));
        minfo.dki_lbsize = 512;
        /* Slice capacity in sectors */
        minfo.dki_capacity = (slice == 2) ? 1421440 : (slice == 0 ? 1387520 : 33280);
        minfo.dki_media_type = DK_FIXED_DISK;
        if (ddi_copyout(&minfo, (void *)arg, sizeof(minfo), mode) != 0)
            return (EFAULT);
        return (0);
    }

    case DKIOCGVTOC: { /* 0x0419 / 'd'<<8 | 25 */
    case DKIOCGEXTVTOC: { /* 0x0417 / 'd'<<8 | 23 */
        /* Must parse or return populated struct vtoc / extvtoc */
        /* If unhandled, MUST return ENOTTY rather than 0 */
        return (ENOTTY);
    }

    default:
        /* CRITICAL ERROR SEMANTIC: Never return 0 for unhandled ioctls! */
        return (ENOTTY);
    }
}
```

### 3.3 Error Semantics Rule (MANDATORY)
- **Invariant**: Any unhandled `cmd` **MUST return `ENOTTY`** (`errno 25` - Inappropriate ioctl for device) or `EINVAL`.
- **Prohibited**: Never return `0` with uninitialized output buffers. Returning `ENOTTY` allows userland fallback paths to activate cleanly.

---

## 4. Boot-Archive-to-Disk-Root Handoff & `installboot` Assessment

1. **How Tribblix SPARC Boots on Niagara QEMU**:
   - QEMU OBP reads sector 0 (VTOC), finds slice 2 / ISO header, and loads `/platform/sun4v/boot_archive` directly via virtio/hsimd hypercalls.
   - The kernel boots from the archive in memory (`ramdisk-root:a`).
2. **The Root Transition (`ufs_install.sh`)**:
   - `ufs_install.sh` copies the entire filesystem tree to `/a` (`c1d0s0`).
   - Removes `set root_is_ramdisk=1` from `${ALTROOT}/etc/system`.
   - Populates `${ALTROOT}/etc/vfstab` with `/dev/dsk/c1d0s0` as `/`.
   - Runs `/sbin/bootadm update-archive -R ${ALTROOT}`.
   - **`installboot`**: `ufs_install.sh` does **not** invoke `installboot` because OBP continues to load the updated boot archive from disk, and the kernel mounts the root filesystem from `/dev/dsk/c1d0s0` specified in `/etc/vfstab` and `/etc/system`.

---

## 5. Remaining Unknowns & Risks

1. **`hsimd` Driver Rebuild / Reload**:
   - `hsimd` in the live guest is currently loaded into kernel space (major 265). Modifying `hsimd` requires recompiling the driver binary on a donor/build host and re-inserting it into the boot archive or dynamically reloading via `modload`.
2. **OBP Root Device Property**:
   - `eeprom` shows `boot-device=vdisk`. When `root_is_ramdisk` is removed, the kernel checks OBP boot properties and `/etc/system` `rootdev` / `/etc/vfstab`. We must verify that `c1d0s0` mounts cleanly without panicking on devfs resolution.
3. **`newfs -s` Tolerance under Current Driver**:
   - Because `hsimd` currently returns `0` on unhandled ioctls, `newfs` may succeed if given `-s 1387520 -t 1 -o space`, or it may crash on unhandled `DKIOCGGEOM`. Testing this requires an explicit isolated trial.
