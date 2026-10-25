#!/usr/bin/env bash
set -euo pipefail
script=${1:?harness path required}
test_dir=$(mktemp -d)
trap 'rm -f "$test_dir/console.log" "$test_dir/container-inspect-failed.json"; rmdir "$test_dir"' EXIT
run_dir=$test_dir
console_log=$test_dir/console.log
container=test-only
docker() { printf 'true\n'; }
sleep() { :; }
eval "$(sed -n '/^wait_for_console() {$/,/^}$/p' "$script")"
printf 'ready\n' >"$console_log"
wait_for_console ready 0
printf 'panic[cpu0]/thread=3000: no nucleus hblk8 to allocate\nready\n' >"$console_log"
if wait_for_console ready 0; then echo 'FAIL: panic masked by prompt'; exit 1; fi
printf 'booting\n' >"$console_log"
if wait_for_console ready 0; then echo 'FAIL: timeout accepted'; exit 1; fi
echo 'PASS: prompt, panic precedence, timeout (3/3)'
