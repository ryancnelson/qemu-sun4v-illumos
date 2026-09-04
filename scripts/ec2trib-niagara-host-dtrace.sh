#!/usr/bin/bash

set -euo pipefail
umask 077

RUN_DIR=${1:-}
DTRACE_PROGRAM=${2:-/tmp/ec2trib-niagara-qemu-smp.d}
QEMU=/tink/builds/qemu-sun4v-879fee-tribblix/build/qemu-system-sparc64

die()
{
    echo "NIAGARA_HOST_DTRACE=FAIL reason=$*" >&2
    exit 1
}

[[ "$RUN_DIR" == /tink/runs/niagara-smp-* ]] || \
    die "unexpected run directory: $RUN_DIR"
[[ -r "$DTRACE_PROGRAM" ]] || die "DTrace program is unreadable: $DTRACE_PROGRAM"

for _ in {1..120}
do
    [[ -r "$RUN_DIR/qemu.pid" ]] && break
    sleep 1
done
[[ -r "$RUN_DIR/qemu.pid" ]] || die "QEMU PID did not appear"

QEMU_PID=$(cat "$RUN_DIR/qemu.pid")
[[ "$QEMU_PID" =~ ^[1-9][0-9]*$ ]] || die "invalid QEMU PID: $QEMU_PID"
kill -0 "$QEMU_PID" 2>/dev/null || die "QEMU PID is not live: $QEMU_PID"

QEMU_EXEC=$(readlink "/proc/$QEMU_PID/path/a.out" 2>/dev/null) || \
    die "cannot inspect QEMU PID: $QEMU_PID"
[[ "$QEMU_EXEC" == "$QEMU" ]] || \
    die "PID $QEMU_PID is not the selected QEMU: $QEMU_EXEC"

echo "NIAGARA_HOST_DTRACE=ATTACH pid=$QEMU_PID run_dir=$RUN_DIR"
/usr/sbin/dtrace -q -s "$DTRACE_PROGRAM" -p "$QEMU_PID" 2>&1 | \
    /usr/bin/tee "$RUN_DIR/host-dtrace.log"
