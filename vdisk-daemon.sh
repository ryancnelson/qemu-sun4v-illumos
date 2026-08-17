#!/usr/bin/env bash
# vdisk-daemon.sh — live writeback of QEMU vdisk_ram to ZFS zvol
#
# Runs on the HOST alongside the Solaris VM. Finds vdisk_ram in QEMU's
# address space via /proc/pid/maps + /proc/pid/mem, then periodically
# writes it to the backing zvol. Survives abnormal QEMU exits.
#
# Usage: sudo ./vdisk-daemon.sh [interval_seconds]   (default: 10)

set -euo pipefail

INTERVAL="${1:-10}"
ZVOL="/dev/zvol/datapool/niagara/vms/primary"
VDISK_SIZE=$(( 512 * 1024 * 1024 ))

find_vdisk_addr() {
    local pid="$1"
    python3 - "$pid" "$VDISK_SIZE" << 'EOF'
import sys, os, struct

pid = int(sys.argv[1])
target_size = int(sys.argv[2])

with open(f"/proc/{pid}/maps") as f:
    for line in f:
        parts = line.split()
        if len(parts) < 2: continue
        addrs = parts[0].split('-')
        if len(addrs) != 2: continue
        start = int(addrs[0], 16)
        end   = int(addrs[1], 16)
        size  = end - start
        perms = parts[1]
        if size == target_size and 'r' in perms and 'w' in perms and perms[2] == '-':
            # Check for SUN72G disk label at offset 0
            try:
                with open(f"/proc/{pid}/mem", "rb") as mem:
                    mem.seek(start)
                    header = mem.read(32)
                    if b"SUN" in header:
                        print(hex(start))
                        sys.exit(0)
            except Exception:
                pass

sys.exit(1)
EOF
}

writeback() {
    local pid="$1" addr="$2"
    python3 - "$pid" "$addr" "$VDISK_SIZE" "$ZVOL" << 'EOF'
import sys, os

pid  = int(sys.argv[1])
addr = int(sys.argv[2], 16)
size = int(sys.argv[3])
zvol = sys.argv[4]

with open(f"/proc/{pid}/mem", "rb") as src, \
     open(zvol, "r+b") as dst:
    src.seek(addr)
    dst.seek(0)
    remaining = size
    while remaining > 0:
        chunk = min(remaining, 4 * 1024 * 1024)
        data = src.read(chunk)
        if not data: break
        dst.write(data)
        remaining -= len(data)
    dst.flush()
    os.fsync(dst.fileno())
EOF
}

echo "[vdisk-daemon] interval=${INTERVAL}s zvol=$ZVOL"

echo -n "[vdisk-daemon] waiting for QEMU..."
QPID=""
for i in $(seq 1 60); do
    QPID=$(pgrep -f "qemu-system-sparc64" | head -1 || true)
    [[ -n "$QPID" ]] && break
    sleep 1; echo -n "."
done
[[ -z "$QPID" ]] && { echo " no QEMU found"; exit 1; }
echo " pid=$QPID"

echo -n "[vdisk-daemon] locating vdisk_ram..."
VDISK_ADDR=""
for i in $(seq 1 60); do
    VDISK_ADDR=$(find_vdisk_addr "$QPID" 2>/dev/null || true)
    [[ -n "$VDISK_ADDR" ]] && break
    sleep 1; echo -n "."
done
[[ -z "$VDISK_ADDR" ]] && { echo " FAILED"; exit 1; }
echo " $VDISK_ADDR"

do_writeback() {
    writeback "$QPID" "$VDISK_ADDR"
    echo "[vdisk-daemon] $(date +%T) wrote to zvol"
}

trap 'echo "[vdisk-daemon] signal — final writeback..."; do_writeback; exit 0' INT TERM

echo "[vdisk-daemon] running. ctrl-c for clean stop + final writeback."
while kill -0 "$QPID" 2>/dev/null; do
    do_writeback
    sleep "$INTERVAL"
done

echo "[vdisk-daemon] QEMU exited — final writeback..."
do_writeback
echo "[vdisk-daemon] done."
