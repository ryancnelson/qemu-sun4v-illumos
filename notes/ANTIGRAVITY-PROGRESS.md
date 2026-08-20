# Antigravity Progress & Verification Log (Niagara / Tribblix m34)

**Last Updated**: 2026-08-20T20:44:15Z (13:44 PDT)  
**Operator**: Antigravity (Sole persistent-console operator for disposable guest)  
**Methodology**: Strict TDD & Gilfoyle Standards (**FACT**, **HYPOTHESIS**, **PLAN**; readback-verified; zero state mutation).

---

## 1. System Orientation & Invariant Identity (FACT)

- **Target Host**: `niagara-playbox` (`100.112.174.2`), user `niagara`.
- **tmux Console Target**: Session `tribblix-zfs-test`, Window `1`, Pane `0`.
- **Active QEMU Process**: PID `2803` (`/home/niagara/niag-proj/qemu/build/qemu-system-sparc64 -M niagara -L /home/niagara/sun4v/firmware/base-1gib -m 1024 -nographic -drive if=pflash,file=/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso,format=raw`).
- **Active Backing Image**: `/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso`
  - **Size**: `1046282240` bytes (997.81 MiB / `2043520` 512-byte sectors).
  - **Mtime**: `2026-08-20 16:08:13.916223599 +0000` (Unchanged since session start).
  - **Whole Image SHA-256**: `17e39e63f4f1f59e6532dcd71a49289b41a40d4cf6a89c440b3d017855316617`
- **Rollback Source (Protected / Unmodified)**: `/home/niagara/sun4v/media/tribblix-m34-hsimd.iso`
  - **SHA-256**: `e98d3a5e2a1e3be4f270d76697349ad4263104f756b38778628cf49af6a33cf6`
- **Images LV Inventory (`/home/niagara/sun4v/images`, 9.1 GB free)**:
  - `primary.img`: `2684354560` bytes (Solaris 10 donor)
  - `primary.img.clean`: `2684354560` bytes
  - `scratch-forensic-20260820.iso`: Does **not** exist yet.

---

## 2. Slice 7 Geometry & Pre-Write Baseline Hashes (FACT)

- **Sun VTOC**: Magic `0xDABE`, Checksum XOR `0x0000` (Valid).
- **Geometry**:
  - `s2` (Whole Disk): Cylinder 0, `2043520` sectors (`997.81 MiB`).
  - `s7` (Scratch Partition): Cylinder 2169, `655360` sectors (`320.0 MiB`).
  - **s7 Absolute Sector Start**: `1388160` (Absolute start byte `710737920`).
  - **s7 Absolute End Byte**: `1046282239`.

### Pre-Write Region Hashes in Slice 7

| Region | Absolute Byte Range in s7 | Region Length | SHA-256 Checksum |
| :--- | :--- | :--- | :--- |
| **Canary Sector** | `s7 + 0 .. 512 B` | 512 B | `08661dac6b8f75c1ba71d37ec1db41896c489d218c115e984d41564884770e15` |
| **L0 Full** | `s7 + 0 .. 256 KiB` | 256 KiB | `e8f58e210c110b37b2f26a3b793f0c306e890ce546b79cf6bc78c5845678f1bb` |
| **L0 nvlist** | `s7 + 16 KiB .. 128 KiB` | 112 KiB | `1474244d96a34264560f9eb59882cd33e50b585df9f6d35aabbce48088ba3897` |
| **L0 Uberblock Ring** | `s7 + 128 KiB .. 256 KiB` | 128 KiB | `85eadebfb3f8206bf1d2fc10cc8f34af18a18446a284526561c7e8d8a4e076fe` |
| **L1 Full** | `s7 + 256 KiB .. 512 KiB` | 256 KiB | `9e60a5856ce653b9f9b6409d6427c1097d216c63004de9f3169125dfa42adb8a` |
| **L1 nvlist** | `s7 + 272 KiB .. 384 KiB` | 112 KiB | `936181ba9bcaa9f707afa175aff55b0fa1d883686ced72e4b81ac0f6c319f333` |
| **L1 Uberblock Ring** | `s7 + 384 KiB .. 512 KiB` | 128 KiB | `ee22c81ec0786e1b8a14661214a5dfb40c6515092cda3269229928438da52ddb` |
| **L2 Full** | `s7_end - 512 KiB .. -256 KiB`| 256 KiB | `c709c817f87d29948d40254be132e48601d5d98fff8dbf319ff86148ec24ca4a` |
| **L2 nvlist** | `s7_end - 496 KiB .. -384 KiB`| 112 KiB | `05ab95b48c51417e8377059ffd34512daa1e8c5994bf40ab6b2a207c33db85d4` |
| **L2 Uberblock Ring** | `s7_end - 384 KiB .. -256 KiB`| 128 KiB | `57f23f6d6cfcb9e89b431b59b9742e8d15d6ae9f259176907d8da5518ea8b05e` |
| **L3 Full** | `s7_end - 256 KiB .. s7_end` | 256 KiB | `5d99d2387c2b68c1da3091ac03599f280f9af9e17b1f9dbe3aae760a35170399` |
| **L3 nvlist** | `s7_end - 240 KiB .. -128 KiB`| 112 KiB | `9a760c5fa7ba048119cf7369449507ad240fb387ba9d35c550bcd1708167fdb4` |
| **L3 Uberblock Ring** | `s7_end - 128 KiB .. s7_end` | 128 KiB | `8858c860595e9dafa362f46fffa1480bd5cd7251c3b049533c399353378fe57a` |
| **Uberblock BE Magic (`0x00bab10c`)** | Full s7 | 320 MiB | **0 occurrences** |
| **Uberblock LE Magic (`0x0cb1ba00`)** | Full s7 | 320 MiB | **0 occurrences** |

---

## 3. Console Actions & Read-Path Verification (FACT)

### Maintenance Login
- Resolved interactive layout picker by providing `47` (US-English).
- Submitted `root`, followed by `tribblix` at the password prompt.
- Reached single-user root shell: `root@tribblix:/root#`.

### Device Nodes & Minor Link Verification
- `modinfo | grep hsimd` -> `115 7bab25e8 1e48 265 1 hsimd (hsimd)`.
- `ls -l /dev/dsk/c1d0s* /dev/rdsk/c1d0s*` -> All slices `c1d0s0`..`c1d0s7` present; `s7` links to `/devices/virtual-devices@100/disk@0:h` and `:h,raw`.

### Canary Readback
- `dd if=/dev/rdsk/c1d0s7 bs=512 count=1 2>/dev/null | head -1` -> `HSIMD-ZFS-CANARY-20260820`.

### 10-Sector Small Read Checksum Match
- Guest: `dd if=/dev/rdsk/c1d0s7 bs=512 count=10 2>/dev/null | digest -a sha256`  
  -> `3b0765bdc7171a059616724e07d5c0f1190dec556da6eb88af1d41ff9279d3b7`
- Host: `dd if=... bs=512 skip=1388160 count=10 2>/dev/null | sha256sum`  
  -> `3b0765bdc7171a059616724e07d5c0f1190dec556da6eb88af1d41ff9279d3b7` (Exact Match).

---

## 4. H4 Read-Path Falsification Sequence (FACT)

### Test A: Unbounded Device Digest
- **Executed Command**: `digest -a sha256 /dev/rdsk/c1d0s7`
- **Elapsed Time**: 40.01 seconds (scanned all 320 MiB at ~8.0 MB/s).
- **Exact Error Output**:
  ```text
  digest: error reading file: No space left on device
  digest: crypto operation failed for file /dev/rdsk/c1d0s7: CKR_GENERAL_ERROR
  ```
- **Finding**: Confirmed that `digest` attempts unbounded reads until EOF. `hsimd_strategy` returns `ENOSPC` (errno 28) when reading past the end of the slice geometry, causing `digest` to abort with `CKR_GENERAL_ERROR`.

### Test B: Bounded 655,360-Sector Read vs. Host Backing File
- **Guest Command**: `dd if=/dev/rdsk/c1d0s7 bs=512 count=655360 2>/dev/null | digest -a sha256`
  - **Elapsed Time**: 540.22 seconds (~9 minutes across 655,360 single-block hypercall transfers).
  - **Observed Guest SHA-256**: `20821fe2c9ae62cbb18e08a732cdae97e9e8fd726b1ed196968cb9440891b624`
- **Host Command**: `dd if=/home/niagara/sun4v/media/tribblix-m34-hsimd-zfs-scratch.iso bs=512 skip=1388160 count=655360 2>/dev/null | sha256sum`
  - **Observed Host SHA-256**: `20821fe2c9ae62cbb18e08a732cdae97e9e8fd726b1ed196968cb9440891b624  -`
- **Proof Statement**: **100% byte-exact identity across all 320 MiB of Slice 7** between guest raw character device reads and the host backing image file.

---

## 5. Actions NOT Taken & Current Gate Status

- **Actions NOT Taken**:
  - Zero guest writes, `zpool create`, or `zpool labelclear` commands executed.
  - Zero QEMU signals, stops, or kills executed.
  - Known-good media (`tribblix-m34-hsimd.iso` and production images) left untouched.
- **Current Gate**:
  - H4 read verification is **COMPLETE & PASSING**.
  - System is cleanly parked at `root@tribblix:/root#`.
  - Staged validation is stopped at Stage 4 gate pending Codex review.
