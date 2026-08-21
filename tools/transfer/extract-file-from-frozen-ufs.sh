#!/bin/sh
# Copy one closed file from a live QEMU UFS backing image without rebooting it.
# The guest filesystem must be synced first. The image is mounted read-only, and
# an EXIT trap resumes the exact QEMU PID after every success or failure path.

set -eu

if [ "$#" -ne 5 ]; then
    echo "usage: $0 QEMU_PID IMAGE GUEST_PATH OUTPUT|- EXPECTED_BYTES" >&2
    exit 2
fi

qemu_pid=$1
image=$2
guest_path=$3
output=$4
expected_bytes=$5
loopdev=
mountpoint_dir=
stopped=0

case "$qemu_pid" in
    *[!0-9]*|'') echo "QEMU_PID must be numeric" >&2; exit 2 ;;
esac
case "$guest_path" in
    /*) ;;
    *) echo "GUEST_PATH must be absolute" >&2; exit 2 ;;
esac
[ -f "$image" ] || { echo "not a regular image: $image" >&2; exit 1; }
if [ "$output" != - ]; then
    [ ! -e "$output" ] || { echo "refusing to overwrite: $output" >&2; exit 1; }
fi

qemu_exe=$(readlink "/proc/$qemu_pid/exe")
case "$qemu_exe" in
    *qemu-system-sparc64*) ;;
    *) echo "PID $qemu_pid is not qemu-system-sparc64: $qemu_exe" >&2; exit 1 ;;
esac
tr '\000' '\n' < "/proc/$qemu_pid/cmdline" | grep -F "$image" >/dev/null || {
    echo "PID $qemu_pid command line does not reference $image" >&2
    exit 1
}

cleanup()
{
    rc=$?
    trap - EXIT HUP INT TERM
    if [ -n "$mountpoint_dir" ] && mountpoint -q "$mountpoint_dir"; then
        umount "$mountpoint_dir" || rc=1
    fi
    if [ -n "$loopdev" ]; then
        losetup -d "$loopdev" || rc=1
    fi
    if [ "$stopped" -eq 1 ]; then
        kill -CONT "$qemu_pid" || rc=1
        sleep 1
        qemu_state=$(awk '{print $3}' "/proc/$qemu_pid/stat" 2>/dev/null || echo '?')
        case "$qemu_state" in
            T|t)
                echo "QEMU remains job-control stopped; run fg in its controlling tty" >&2
                rc=1
                ;;
        esac
    fi
    if [ -n "$mountpoint_dir" ]; then
        rmdir "$mountpoint_dir" 2>/dev/null || true
    fi
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM

mountpoint_dir=$(mktemp -d /tmp/niag-ufs.XXXXXX)
loopdev=$(losetup --find --show --read-only "$image")
kill -STOP "$qemu_pid"
stopped=1

mount -t ufs -o ro,ufstype=sun "$loopdev" "$mountpoint_dir"
source_file="$mountpoint_dir$guest_path"
[ -f "$source_file" ] || { echo "not found in guest image: $guest_path" >&2; exit 1; }
[ "$(stat -c %s "$source_file")" = "$expected_bytes" ] || {
    echo "unexpected source size: $(stat -c %s "$source_file")" >&2
    exit 1
}
if [ "$output" = - ]; then
    sha256sum "$source_file"
else
    cp --sparse=always "$source_file" "$output"
    [ "$(stat -c %s "$output")" = "$expected_bytes" ] || {
        echo "unexpected output size: $(stat -c %s "$output")" >&2
        exit 1
    }
    sync "$output"
    echo "$expected_bytes bytes copied from frozen UFS image"
fi
