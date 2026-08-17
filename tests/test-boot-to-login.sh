#!/usr/bin/env bash
# TEST: Machine boots to a login prompt.
#
# Gilfoyle standard: PASS only when the observed output contains the
# exact login prompt string. No inference.

source "$(dirname "$0")/lib.sh"

IMAGE=$(make_test_image "boot-to-login")
trap "cleanup_test_image boot-to-login" EXIT

log "Booting $QEMU with $IMAGE ..."

output=$(run_expect "$IMAGE" '
    spawn $env(QEMU) -M niagara -L $env(S10DIR) -m 256 -nographic \
        -drive if=pflash,file=$env(IMAGE),format=raw
    expect "ok"
    send "boot disk\r"
    expect {
        "login:" {
            puts "OBSERVED: login prompt appeared"
            exit 0
        }
        "Can'"'"'t open boot" {
            puts "OBSERVED: boot device error"
            exit 1
        }
        timeout {
            puts "OBSERVED: timed out waiting for login prompt"
            exit 1
        }
    }
')

echo "$output"

if echo "$output" | grep -q "OBSERVED: login prompt appeared"; then
    pass "login prompt observed after boot disk"
else
    fail "login prompt not observed" "$(echo "$output" | tail -5)"
fi
