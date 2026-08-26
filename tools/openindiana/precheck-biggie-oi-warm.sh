#!/usr/bin/env bash
# Read-only admission check for a Biggie OpenIndiana warm-builder run.
set -euo pipefail

SESSION=${1:?usage: precheck-biggie-oi-warm.sh SESSION}
MASA=${MASA:-/home/ryan/devel/masa-sun4v}
RUN=${RUN:-$MASA/ci/runs/$SESSION}
fail=0
check() { if "$@"; then echo "PASS: $*"; else echo "FAIL: $*"; fail=1; fi; }

check test -f "$RUN/run.manifest"
check test -x "$RUN/qemu-system-sparc64"
check test -x "$RUN/qemu-owner.sh"
check test -f "$RUN/firmware/openboot.bin"
check test -f "$RUN/firmware/nvram1"
check test "$(stat -c %s "$RUN/carrier-unit100.img" 2>/dev/null || echo 0)" = 1073741824
check test "$(stat -c %s "$RUN/installer-unit103-rw.img" 2>/dev/null || echo 0)" = 2808741888
check test -S "$RUN/console.sock"
check test -S "$RUN/monitor.sock"
check tmux has-session -t "$SESSION"
if [[ -f $RUN/qemu.pid ]]; then
  qpid=$(<"$RUN/qemu.pid")
  check kill -0 "$qpid"
  check grep -F "$RUN/qemu-system-sparc64" "/proc/$qpid/cmdline"
else
  echo "FAIL: missing qemu.pid"; fail=1
fi
[[ $fail == 0 ]] || exit 1
echo "PASS: $SESSION is admitted"
