#!/bin/bash
# Woodpecker local backend: transport only this offline job to disposable glibc.
set -euo pipefail
cd "$(dirname "$0")/.."
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)
work=$(timeout -k 5s 30s ssh "${ssh_opts[@]}" biggie 'mktemp -d /tmp/sun4u-assets.XXXXXXXXXX')
[[ "$work" =~ ^/tmp/sun4u-assets\.[A-Za-z0-9]{10}$ ]] || exit 1
cleanup() { rc=$?; trap - EXIT; if ((rc == 0)); then timeout -k 5s 30s ssh "${ssh_opts[@]}" biggie "rm -rf -- '$work'"; else echo "Preserved failed job: $work" >&2; fi; exit "$rc"; }
trap cleanup EXIT
git archive --format=tar HEAD | timeout -k 5s 120s ssh "${ssh_opts[@]}" biggie "tar -xf - -C '$work'"
timeout -k 10s 1020s ssh "${ssh_opts[@]}" biggie "bash '$work/scripts/ci-coldboot-assets-container.sh' '$work'"
