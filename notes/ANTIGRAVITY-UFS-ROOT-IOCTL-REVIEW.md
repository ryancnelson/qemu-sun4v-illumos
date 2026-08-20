# Technical Review: Mounting & Handoff to Prebuilt UFS Root on hsimd (Adversarially Corrected)

**Author**: Antigravity (Sole Live-Console Custodian & VM Operator)  
**Date**: 2026-08-20  
**Methodology**: Strict TDD & Gilfoyle Standards (**FACT / HYPOTHESIS / PLAN**).  
**Execution Invariant**: Read-only analysis; **zero** live console keystrokes, mutations, or guest writes.

---

## 1. Executive Summary & Strategy

- **Core Finding**: We **do not need in-guest `newfs`** over `hsimd` to establish persistent storage. We can construct a prebuilt, valid UFS root on a Solaris 10 build host/donor (with native `lofiadm`/`newfs`), splice it into an extended backing disk image, and hand off root execution.
- **Strategic Accelerator Sequence (Ryan's Standard)**:
  1. **Phase 1 (Prebuilt Persistent UFS Root)**: Splice an extended disk image containing a fully populated UFS root filesystem with toolchains (`gcc`, headers, build tools) into `s0` (following safe D1 partition geometry).
  2. **Phase 2 (Guest Compilation Smoke Test)**: Boot into the persistent UFS root; verify compiler, make, and linking functionality directly on the live guest.
  3. **Phase 3 (Self-Hosted `hsimd` Fixes)**: Recompile and iterate on `hsimd` source in-guest to implement missing ioctls (`DKIOCGGEOM`, `DKIOCGMEDIAINFOEXT`, `DKIOCGEXTVTOC`), fixing `prtvtoc`, `format`, and `zpool` natively.

---

## 2. Geometry Correction: Safe D1 Partition Map (Within 8,192 Cylinders)

### 2.1 The Alias Hazard with Old CD Geometry
- In the original CD label, `s0` (`0 .. 1387520` sectors) and `s1` (`0 .. 1387520` sectors) both aliased cylinder 0, overlapping the ISO header and embedded boot archive.
- Formatting `s0` or enabling swap on `s1` under the old map destroys the boot media.

### 2.2 Reconciled D1 Geometry Map (Shell #2 Cross-Checked)
Geometry: **1 head × 640 sectors/cylinder = 327,680 bytes/cylinder**.  
Total Cylinders: **8,192 cylinders = 5,242,880 sectors = 2,684,354,560 bytes (2.500 GiB)**.

| Slice | Role | Start Cylinder | Absolute Sector Start | Sector Count (`nblk`) | Byte Extent | Size |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ISO / Archive** | Base Media | 0 | 0 | 1388120 | `0 .. 710717440` | ~677.8 MiB |
| **s7** | Channel Region | 2169 | 1388160 | 33280 | `710737920 .. 727777280` | 16.0 MiB (Fixed) |
| **s1** | Swap Partition | 2221 | 1421440 | 655360 | `727777280 .. 1063321600` | 320.0 MiB |
| **s0** | **UFS Root** | **3245** | **2076800** | **3166080** | **`1063321600 .. 2684354560`** | **1545.9 MiB** (~1.39 GiB usable) |
| **s2** | Whole Served Disk| 0 | 0 | 5242880 | `0 .. 2684354560` | 2.500 GiB |

- **Containment Invariants**:
  - `s7`, `s1`, and `s0` are strictly contiguous with **zero overlaps**.
  - `s0` start (`cyl 3245 * 640 = 2076800 sectors = byte 1063321600`) begins immediately after `s1` end.
  - `s0` end (`byte 2684354560`) aligns exactly with whole disk `s2` end.
  - `dkl_ncyl` at offset `0x1b0` in the VTOC sector 0 must be updated to `0x2000` (8192) and the XOR checksum recomputed via `vtoc.py set`.

---

## 3. Early Kernel Boot & Root Handoff Mechanics (FACT & SOURCE PROOF)

### 3.1 Which `boot_archive` Does OBP Load?
- OBP on Niagara QEMU boots from the block device alias `vdisk` (`/virtual-devices@100/disk@0`).
- OBP parses the Sun VTOC in sector 0, locates the ISO9660 filesystem header at cylinder 0, and loads the boot archive from its embedded extent (`LBA 9391` / sectors `37564 .. 733975`, bytes `19232768 .. 375748608`).
- Therefore, OBP loads the **embedded boot archive inside the ISO extent**, regardless of what is populated in `s0`.

### 3.2 How Does the Kernel Determine and Mount Real Root?
1. **Early Kernel Initialization (`main()` / `rootconf()` in `usr/src/uts/common/os/rootconf.c`)**:
   - The kernel boots into memory from the boot archive and extracts the standalone ramdisk image.
   - It reads `/etc/system` from the **boot archive**.
2. **The `root_is_ramdisk` Branching Mechanism**:
   - If `set root_is_ramdisk=1` is present (current live media), `rootconf()` sets `rootfs` to ramdisk (`/devices/ramdisk-root:a`) and transfers control directly to `/sbin/init`.
   - If `set root_is_ramdisk=1` is **absent** (or stripped from the boot archive's `/etc/system`):
     - The kernel derives the physical root device path (`rootdev`) from OBP boot arguments or bootpath.
     - `rootconf()` evaluates OBP property `bootpath` (or explicit `boot disk:a -B rootdev=...` / `/etc/system` directive `rootdev:/virtual-devices@100/disk@0:a`).
     - The kernel calls `vfs_mountroot()`, executing `ufs_mount()` directly on `/virtual-devices@100/disk@0:a` (`/dev/dsk/c1d0s0`).
3. **No "Pivot" after Userland Init**:
   - The kernel does **not** pivot root from userland after init. The root filesystem mount happens in early kernel space inside `rootconf()` / `vfs_mountroot()` *before* PID 1 (`/sbin/init`) is spawned.
   - To boot off `c1d0s0`, the boot archive used by OBP must have `/etc/system` configured for the target physical root device, or passed via OBP boot arguments (`-B rootdev=...`).

### 3.3 Is `installboot` Required?
- **NO**. On SPARC sun4v, OBP does not execute stage 1/2 UFS filesystem bootblocks. OBP loads the standalone `/platform/sun4v/boot_archive` from the ISO/vdisk extent directly into RAM via hypercalls.
- Once the kernel boots from the archive, it executes `ufs_mount()` on `/virtual-devices@100/disk@0:a` to attach the persistent root.

---

## 4. Minimum `hsimd` Driver Capabilities for UFS Mount

| Ioctl / Operation | Code | Used By | Required for Prebuilt UFS Root Mount? | Finding |
| :--- | :--- | :--- | :--- | :--- |
| **`B_READ` / `B_WRITE`** | Strategy | Kernel I/O | **YES (MANDATORY)** | **100% Proven** on `hsimd` (Sector 0 digests, canary writeback, framed channels). |
| **`CDROMREADOFFSET`** | `0x04A4` | HSFS only | **NO** | Not called by UFS. |
| **`DKIOCGEXTVTOC`** | `0x0417` | `prtvtoc`, `zpool` | **NO** | Not called by UFS kernel mount. |
| **`DKIOCGMEDIAINFOEXT`**| `0x0430` | `zpool`, `newfs` | **NO** | Not called by UFS kernel mount. |
| **`DKIOCGGEOM`** | `0x0401` | `format`, `newfs` | **NO** | UFS uses superblock geometry (`fs_ncyl`, `fs_nsect`, `fs_nhead`). |
| **`DKIOCFLUSHWRITECACHE`**| `0x0422`| UFS write barriers | **NO** | Falls back cleanly if unhandled. |

---

## 5. Prebuilt UFS Pipeline & Verification Steps (Donor -> Playbox -> Guest)

1. **Donor (Solaris 10 Build Host)**:
   - Create sparse file of size `1621032960` bytes (3,166,080 sectors / 1545.9 MiB).
   - Attach via `lofiadm -a <file>` and run `newfs -N /dev/rlofi/X` with 1 head, 640 sect/cyl.
   - Mount and populate root filesystem with Tribblix OS, developer tools (`gcc`, `make`, `binutils`), and kernel headers.
   - Unmount, run `fsck -F ufs -m`, and compute SHA-256 hash.
2. **Host / Playbox (`niagara-playbox`)**:
   - Create 2.5 GiB image (`tribblix-m34-ufsroot.iso`) from verified base.
   - Patch `dkl_ncyl` to `0x2000` (8192) and set `s1` (`cyl 2221, nblk 655360`) and `s0` (`cyl 3245, nblk 3166080`).
   - Splice prebuilt UFS image at byte offset `1063321600` (`seek=2076800 bs=512`).
   - Verify archive checksum, VTOC XOR `0x0000`, and slice byte hash.
3. **Guest Verification & Self-Hosting**:
   - Boot VM; mount `/dev/dsk/c1d0s0` to `/mnt` from RAM root to verify read/write canary.
   - Boot directly to persistent disk root (`c1d0s0`).
   - Execute GCC compilation smoke test (`hello.c`).
   - Build updated `hsimd` driver in-guest with full ioctl support.

---

## 6. Verdict & Remaining Unknowns

- **Verdict**: **GO for Prebuilt UFS Root Strategy (Safe D1 Geometry)**.
- **Remaining Technical Unknowns**:
  1. Exact OBP command-line syntax for passing `rootdev` explicitly on sun4v if `/etc/system` in the boot archive is kept generic (e.g. `boot vdisk -B rootdev=/virtual-devices@100/disk@0:a` vs editing archive `/etc/system`).
  2. Verifying whether OBP rejects the 8,192-cylinder disk label if `dkl_ncyl` is left unpatched vs patched.
