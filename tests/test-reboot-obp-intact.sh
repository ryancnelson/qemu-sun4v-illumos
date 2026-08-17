#!/usr/bin/env bash
# TEST: OBP is functional after a guest-initiated reboot.
#
# Method:
#   1. Boot to Solaris, log in.
#   2. Run "reboot" inside the guest.
#   3. Wait for the OBP "ok" prompt to return.
#   4. Send "devalias" — a benign OBP command with predictable output.
#   5. PASS = "devalias" output contains "disk" (it always does on a clean OBP).
#   6. FAIL = OBP traps ("Last Trap"), hangs, or devalias produces no output.
#
# This test currently FAILS. After "reboot", OBP returns but immediately
# traps on any command ("ERROR: Last Trap: Fast Data Access MMU Miss").
# Root cause: QEMU Niagara has no machine_reset handler — the kernel's MMU
# context remains live when control returns to OBP firmware.

source "$(dirname "$0")/lib.sh"

IMAGE=$(make_test_image "reboot-obp-intact")
trap "cleanup_test_image reboot-obp-intact" EXIT

log "Booting guest to test reboot behavior ..."

output=$(run_expect "$IMAGE" "
    set timeout $BOOT_TIMEOUT
    spawn \$env(QEMU) -M niagara -L \$env(S10DIR) -m 256 -nographic \\
        -drive if=pflash,file=\$env(IMAGE),format=raw
    expect \"ok\"
    send \"boot disk\r\"
    expect \"login:\"
    send \"root\r\"
    expect \"#\"

    set timeout 15
    send \"reboot\r\"

    # Wait for OBP to return
    expect {
        \"ok\" {
            puts \"OBSERVED: OBP ok prompt returned after reboot\"
        }
        timeout {
            puts \"OBSERVED: timed out waiting for OBP after reboot\"
            exit 1
        }
    }

    # Probe OBP with a simple command
    set timeout 10
    send \"devalias\r\"
    expect {
        \"disk\" {
            puts \"OBSERVED: devalias responded with disk alias — OBP intact\"
            exit 0
        }
        \"Last Trap\" {
            puts \"OBSERVED: OBP trapped after reboot — MMU state corrupted\"
            exit 1
        }
        timeout {
            puts \"OBSERVED: devalias timed out — OBP unresponsive after reboot\"
            exit 1
        }
    }
")

echo "$output"

if echo "$output" | grep -q "OBP intact"; then
    pass "OBP functional after guest reboot"
else
    reason=$(echo "$output" | grep "OBSERVED:" | tail -1)
    fail "OBP not functional after guest reboot" "$reason"
fi
