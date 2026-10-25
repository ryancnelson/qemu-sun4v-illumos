#!/usr/bin/env bash
set -euo pipefail
script=${1:?harness path required}
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
run_dir=$test_dir
console_log=$test_dir/console.log
container=test-only
source "$(dirname "$script")/console-outcomes.sh"
source "$(dirname "$script")/cmd646-trace.sh"
container_created=1
docker() {
    case "$1" in
        inspect)
            if [[ "$*" == *--format* ]]; then printf 'false true 0\n'
            else printf '[]\n'; fi ;;
        logs) : ;;
    esac
}
sleep() { :; }
eval "$(sed -n '/^wait_for_console() {$/,/^}$/p' "$script")"
printf 'ready\n' >"$console_log"
wait_for_console ready 0
printf 'panic[cpu0]/thread=3000: no nucleus hblk8 to allocate\nready\n' >"$console_log"
if wait_for_console ready 0; then echo 'FAIL: panic masked by prompt'; exit 1
else [[ $? == 20 && "$outcome" == PANIC ]]; fi
outcome=
printf 'booting\n' >"$console_log"
if wait_for_console ready 0; then echo 'FAIL: timeout accepted'; exit 1
else [[ $? == 23 && "$outcome" == TIMEOUT ]]; fi
echo 'PASS: prompt, panic precedence, timeout (3/3)'
