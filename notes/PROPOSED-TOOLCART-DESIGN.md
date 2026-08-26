# Proposed Design: Deterministic PCFS "Tool Cart" Disk for Masa `hsimd`

> **STATUS: UNTESTED PROPOSAL / DESIGN DRAFT**
>
> This document records a proposed design for an out-of-band PCFS (FAT16) "tool cart" virtual disk for the Masa multi-disk Niagara QEMU environment. It has **not yet been built or booted in a live VM**.

---

## 1. Architectural Concept & Objectives

The **Tool Cart** is a dedicated, read-only FAT16/PCFS virtual disk image attached as a discrete QEMU drive (`unit=104` -> `disk@4`). It is intended to provide an immutable, out-of-band supply of audited SPARC binaries, scripts, and patches to any guest (OpenIndiana, Tribblix, Solaris 10) **without modifying guest boot archives, depending on network/PPP, or risking shared-disk channel mailbox corruption**.

```
+---------------------------------------------------------------------------------------------------------+
|                                    TOOL CART SYSTEM TOPOLOGY                                            |
+--------------------------+------------------------------------+-----------------------------------------+
| HOST CREATION (No Root)  | QEMU TOPOLOGY                      | GUEST ATTACH (Read-Only)                |
+--------------------------+------------------------------------+-----------------------------------------+
| • Userland `mtools`      | • Discrete `-drive unit=104`       | • Discovered via `fstyp == pcfs`        |
| • Deterministic FAT16    | • `DTYPE_RODIRECT` (Write-locked)  | • `mount -F pcfs -o ro ... /mnt/toolcart`|
| • Checksum manifest      | • Zero mailbox / channel overlap   | • Safe on S10, Tribblix, OpenIndiana    |
+--------------------------+------------------------------------+-----------------------------------------+
```

---

## 2. Capacity Recommendation & Filesystem Format

* **Recommended Size**: **`64 MiB`** ($67,108,864$ bytes / $131,072$ sectors).
* **Format**: **Partitionless FAT16 ("superfloppy" / `-I`)**.
  * *Rationale*: FAT16 with 2 KiB clusters is natively supported by the kernel `pcfs` driver across all Solaris revisions (Solaris 10, Tribblix, illumos/OpenIndiana) without needing MBR/fdisk partition parsers or VTOC labeling.
  * 64 MiB easily holds all userland rescue binaries (`guest-chand`, `socat`, `pppd`, `dtrace` helpers), scripts, and source tarballs ($< 25 \text{ MiB}$ total) while keeping memory footprint negligible.

---

## 3. Host-Side Creation & Population Recipe (Zero-Root / Fully Reproducible)

Executed completely in userland using standard `mtools` / `dosfstools`:

```bash
#!/usr/bin/env bash
# build-toolcart.sh: Generates deterministic 64MB FAT16 Tool Cart
set -euo pipefail

CART_IMG="toolcart-sparc-20260825.img"
CART_SIZE_BYTES=67108864
VOLUME_LABEL="TOOLCART"

# 1. Create fixed-size sparse backing file
rm -f "$CART_IMG"
truncate -s "$CART_SIZE_BYTES" "$CART_IMG"

# 2. Format as deterministic FAT16 (raw partitionless)
mkfs.vfat -F 16 -n "$VOLUME_LABEL" -I "$CART_IMG"

# 3. Create Manifest & Identity Marker
mkdir -p /tmp/toolcart-staging
cat <<EOF > /tmp/toolcart-staging/TOOLCART.ID
NAME="Niagara SPARC Tool Cart"
RELEASE="2026-08-25"
COMPAT="OpenIndiana-Hipster,Tribblix-m34,Solaris-10"
EOF

# 4. Copy Staged Payloads into FAT16 Image (mtools requires no root/loop mounts)
# Staged binaries: guest-chand, guest-echocli, guest-ppp-chan.pl, guest-rootpty.sh, hsimd.o
mcopy -i "$CART_IMG" /tmp/toolcart-staging/TOOLCART.ID ::/TOOLCART.ID
mcopy -i "$CART_IMG" -s /tmp/toolcart-staging/bin ::/bin
mcopy -i "$CART_IMG" -s /tmp/toolcart-staging/scripts ::/scripts

# 5. Generate and embed SHA-256 Manifest
mdir -i "$CART_IMG" -/ :: > /tmp/toolcart-manifest.txt
sha256sum "$CART_IMG" > "$CART_IMG.sha256"
```

---

## 4. QEMU Niagara Integration (Masa Multi-Disk Bus)

Attach as discrete Unit 104 (`disk@4`), leaving Unit 100 (`disk@0` / root) and Unit 103 (`disk@3` / ISO) isolated:

```bash
-drive id=toolcart,file=/path/to/toolcart-sparc-20260825.img,format=raw,if=none,readonly=on \
-global niagara.vdisk4=toolcart
```
*(In Murayama's `-drive` syntax: `unit=104` binds to hypervisor vdisk 4)*.

---

## 5. Guest-Side Discovery & Mount Protocol (Zero `cXdY` Assumptions)

Because `hsimd` or system controllers may enumerate as `c1t4d0`, `c4d0`, or `c0t4d0`, the guest uses **filesystem probing (`fstyp`) rather than device naming**:

```sh
# 1. Invariant PCFS Scanner: Finds Tool Cart regardless of controller numbering
find_toolcart() {
    for rdev in /dev/rdsk/*s2 /dev/rdsk/*c /dev/rdsk/*p0 2>/dev/null; do
        [ -c "$rdev" ] || continue
        # Probe filesystem signature without invoking format
        fs=$(/usr/lib/fs/pcfs/fstyp "$rdev" 2>/dev/null || true)
        if [ "$fs" = "pcfs" ]; then
            bdev=$(echo "$rdev" | sed 's|/rdsk/|/dsk/|')
            mkdir -p /tmp/tc_probe
            if mount -F pcfs -o ro "$bdev" /tmp/tc_probe 2>/dev/null; then
                if [ -f /tmp/tc_probe/TOOLCART.ID ]; then
                    umount /tmp/tc_probe
                    rmdir /tmp/tc_probe
                    echo "$bdev"
                    return 0
                fi
                umount /tmp/tc_probe
            fi
        fi
    done
    return 1
}

# 2. Mount to target location
CART_DEV=$(find_toolcart)
if [ -n "$CART_DEV" ]; then
    mkdir -p /opt/toolcart
    mount -F pcfs -o ro "$CART_DEV" /opt/toolcart
    echo "Tool Cart mounted at /opt/toolcart from $CART_DEV"
    cat /opt/toolcart/TOOLCART.ID
else
    echo "ERROR: Tool Cart not detected on any storage minor" >&2
fi
```

---

## 6. Proposed Acceptance Test Matrix

- [ ] 1. Host Artifact Integrity:
      Verify `sha256sum toolcart.img` matches checked-in manifest.
- [ ] 2. Guest Discovery & Label Test:
      Execute `find_toolcart`. Must return device node (e.g. `/dev/dsk/c1t4d0s2`) in < 2 seconds.
- [ ] 3. Execution & Checksum Test:
      Mount at `/opt/toolcart`.
      Verify `cksum /opt/toolcart/bin/guest-chand` matches captured hash (`baa7bd27...`).
- [ ] 4. Read-Only Protection:
      Execute `touch /opt/toolcart/test.tmp`. Must fail with `Read-only file system` (EROFS).

---

## 7. Flagged Uncertainties

1. **Illumos PCFS Superfloppy Minor Link**:
   On some illumos builds, raw partitionless FAT devices are linked under `/dev/dsk/cXdYs2` (whole disk), while on others they appear under `/dev/dsk/cXdYp0:boot` or `:c`. The discovery script handles this by probing all available minor slices (`*s2`, `*c`, `*p0`).
2. **Murayama QEMU Read-Only Flag Propagation**:
   Setting `readonly=on` on `-drive` ensures hypervisor-level write protection (`DTYPE_RODIRECT`), returning `EIO` or `EROFS` if the guest attempts writes.
