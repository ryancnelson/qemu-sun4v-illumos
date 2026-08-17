#!/usr/bin/env bash
# ZFS zvol helpers for niagara QEMU tests.
#
# Dataset layout:
#   datapool/niagara/vms/primary        — daily driver zvol
#   datapool/niagara/vms/primary@clean  — clone source for tests
#   datapool/niagara/vms/test-<n>-<pid> — ephemeral test clone
#
# Usage:
#   source tests/lib/zvol.sh
#   zvol_path  vms/primary              # echoes /dev/zvol/datapool/niagara/vms/primary
#   zvol_clone vms/test-boot-$$         # clones primary@clean → test zvol, echoes name
#   zvol_destroy vms/test-boot-1234     # destroys test zvol

set -euo pipefail

POOL="${NIAGARA_POOL:-datapool}"
DATASET="${NIAGARA_DATASET:-niagara}"
CLEAN_SNAP="${NIAGARA_SNAP:-primary@clean}"

_zvol_full() {
    echo "$POOL/$DATASET/$1"
}

# zvol_path <name>
# Echoes the /dev/zvol/... block device path for a zvol name.
zvol_path() {
    echo "/dev/zvol/$POOL/$DATASET/$1"
}

# zvol_exists <name>
# Returns 0 if the zvol exists.
zvol_exists() {
    zfs list -t volume "$(_zvol_full "$1")" &>/dev/null
}

# zvol_clone <name>
# Clones primary@clean to the given name.
# Waits for the /dev/zvol device to appear (udev is async).
zvol_clone() {
    local name="$1"
    local full
    full=$(_zvol_full "$name")
    local src
    src="$(_zvol_full "$CLEAN_SNAP")"

    if zvol_exists "$name"; then
        echo "ERROR: zvol $full already exists" >&2
        return 1
    fi

    zfs clone "$src" "$full"

    # Wait for block device to materialise (udev)
    local dev
    dev=$(zvol_path "$name")
    local i=0
    while [[ ! -b "$dev" ]] && (( i < 30 )); do
        sleep 0.2
        (( i++ )) || true
    done

    if [[ ! -b "$dev" ]]; then
        echo "ERROR: block device $dev did not appear after clone" >&2
        return 1
    fi
}

# zvol_destroy <name>
# Destroys a zvol. Refuses to destroy primary or primary@clean.
zvol_destroy() {
    local name="$1"
    case "$name" in
        vms/primary|primary)
            echo "ERROR: refusing to destroy primary zvol" >&2
            return 1
            ;;
    esac

    local full
    full=$(_zvol_full "$name")

    if ! zvol_exists "$name"; then
        return 0   # already gone, idempotent
    fi

    zfs destroy "$full"
}
