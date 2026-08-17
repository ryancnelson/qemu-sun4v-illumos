#!/usr/bin/env bash
# TEST: A file written inside the guest survives QEMU exit.
#
# Method (Gilfoyle standard):
#   1. Boot guest, log in as root.
#   2. Write a unique canary string to a file inside the guest.
#   3. Run sync twice, then halt the guest.
#   4. Exit QEMU.
#   5. Search the raw image file on the HOST for the canary string.
#
# PASS = canary found in raw image file.
# FAIL = canary absent. The write was lost.
#
# This test currently FAILS against stock QEMU 8.2.2 because the Niagara
# machine maps the vdisk as anonymous RAM (memory_region_init_ram +
# rom_add_file_fixed). No write-back path exists.
# It should PASS after applying patches/0001-niagara-vdisk-ram-shared.patch.

source "$(dirname "$0")/lib.sh"

CANARY="NIAGARA_WRITE_TEST_$$_$(date +%s)"
IMAGE=$(make_test_image "disk-write-persist")
trap "cleanup_test_image disk-write-persist" EXIT

log "Canary string: $CANARY"
log "Booting guest to write canary ..."

run_expect "$IMAGE" "
    set timeout $BOOT_TIMEOUT
    spawn \$env(QEMU) -M niagara -L \$env(S10DIR) -m 256 -nographic \\
        -drive if=pflash,file=\$env(IMAGE),format=raw
    expect \"ok\"
    send \"boot disk\r\"
    expect \"login:\"
    send \"root\r\"
    expect \"#\"

    set timeout $WRITE_TIMEOUT
    send \"echo $CANARY > /tmp/canary.txt && sync && sync && echo WRITE_DONE\r\"
    expect {
        \"WRITE_DONE\" {
            puts \"OBSERVED: guest confirmed write and sync\"
        }
        timeout {
            puts \"OBSERVED: timed out waiting for write confirmation\"
            exit 1
        }
    }

    # Exit QEMU cleanly via monitor so the process flushes its state.
    send \"\x01c\"
    expect \"(qemu)\"
    send \"quit\r\"
    expect eof
"

log "QEMU exited. Searching raw image for canary ..."

if strings "$IMAGE" | grep -qF "$CANARY"; then
    pass "canary '$CANARY' found in raw image after QEMU exit"
else
    fail "canary not found in raw image — write was lost" \
         "strings $IMAGE | grep $CANARY → no match"
fi
