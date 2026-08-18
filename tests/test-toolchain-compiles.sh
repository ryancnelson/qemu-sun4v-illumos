#!/usr/bin/env bash
# TEST: the in-guest C toolchain compiles, links and RUNS a program.
#
# Gilfoyle standard: PASS only when the compiled binary's own stdout appears in
# the transcript. "gcc exited 0" is not evidence -- it links against the wrong
# crt objects and produces a core-dumping binary just as happily. The program
# computes sum(1..100)=5050 and sqrt(2), so the assertion is a value the guest
# can only print by having actually executed correct code.
#
# Exercises the full chain: cpp finds the Solaris headers, gcc drives `as` and
# `ld`, and the linker resolves libm.
#
# Deliberately invokes gcc with NO -B flag. gcc 4.3.3 was built as
# sparc-sun-solaris2.8 but its binutils live under .../solaris2.9/bin, so gcc
# cannot find `as` on its own and fails with:
#     gcc: error trying to exec 'as': execvp: No such file or directory
# Passing -B papers over that per-invocation. This test requires plain `gcc`
# to work, which is what a human (or a configure script) will actually run.
#
# Requires a snapshot with gcc AND the Solaris headers installed:
#   SUNWhea  -> /usr/include/stdio.h + 240 more
#   SUNWarc  -> /usr/lib/crti.o, values-Xa.o
#   SUNWlibm -> /usr/include/math.h (NOT in SUNWhea)
# crt1.o is NOT needed from Solaris media; gcc ships its own.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# This test needs the toolchain, so it cannot clone the bare @clean-2gb
# baseline that every other test uses.
export NIAGARA_SNAP="${NIAGARA_SNAP_TOOLCHAIN:-vms/primary@toolchain-working}"
# The toolchain is unusable at 256MB-era settings; 1GiB is a drop-in MD swap.
export NIAGARA_MEM="${NIAGARA_MEM:-1024}"
export S10DIR="${S10DIR:-/datapool/niagara/base-1gib}"

source "$TESTS_DIR/lib/lock.sh"
source "$TESTS_DIR/lib/zvol.sh"
source "$TESTS_DIR/lib/vm.sh"

ZVOL="vms/test-toolchain-$$"

cleanup() {
    lock_release "$ZVOL" 2>/dev/null || true
    zvol_destroy "$ZVOL" || true      # NOT 2>/dev/null: let leak warnings through
}
trap cleanup EXIT INT TERM

if ! zvol_snap_exists "$NIAGARA_SNAP"; then
    echo "SKIP: test-toolchain-compiles — no such snapshot: $NIAGARA_SNAP" >&2
    exit 0
fi

zvol_clone "$ZVOL"
lock_acquire "$ZVOL"

# Every line sent below MUST stay under 256 bytes. The Solaris console tty
# canonical input buffer silently truncates a longer line AND drops its
# carriage return, so the command never runs and the run looks hung. Hence
# `cd` first and short relative paths rather than one long command.
output=$(vm_run "$ZVOL" "$(vm_boot_to_login_script '
    send "root\r"
    expect "# "
    puts "OBSERVED: root shell reached"

    send "cd /var/tmp\r"
    expect "# "
    send "rm -f tc.c tc\r"
    expect "# "
    send "echo \x27#include <stdio.h>\x27 > tc.c\r"
    expect "# "
    send "echo \x27#include <math.h>\x27 >> tc.c\r"
    expect "# "
    send "echo \x27int main(void){\x27 >> tc.c\r"
    expect "# "
    send "echo \x27int s=0,i; for(i=1;i<=100;i++) s+=i;\x27 >> tc.c\r"
    expect "# "
    send "echo \x27printf(\"SUM=%d RC=%.5f\", s, sqrt(2.0));\x27 >> tc.c\r"
    expect "# "
    send "echo \x27putchar(10); return 0; }\x27 >> tc.c\r"
    expect "# "

    puts "OBSERVED: compiling with plain gcc (no -B)"
    send "/opt/csw/gcc4/bin/gcc -O2 -o tc tc.c -lm 2>&1\r"
    expect "# "
    send "./tc\r"
    expect "# "
    puts "OBSERVED: ran the binary"
    '"$vm_halt_writeback_fragment"'
')") || true

echo "$output"

# sum(1..100) = 5050, sqrt(2) = 1.41421. Both must appear, from the binary.
if echo "$output" | tr -d '\r' | grep -q 'SUM=5050 RC=1.41421'; then
    echo "PASS: test-toolchain-compiles"
    exit 0
fi

echo "FAIL: test-toolchain-compiles — binary did not print the expected values"
if echo "$output" | grep -q "trying to exec 'as'"; then
    echo "  cause: gcc cannot find its assembler."
    echo "  gcc is sparc-sun-solaris2.8; binutils are in /opt/csw/sparc-sun-solaris2.9/bin."
    echo "  fix: symlink as and ld into gcc's private exec dir:"
    echo "    /opt/csw/gcc4/lib/gcc/sparc-sun-solaris2.8/4.3.3/"
elif echo "$output" | grep -qE 'math\.h: No such file'; then
    echo "  cause: math.h missing — install SUNWlibm (it is not in SUNWhea)."
elif echo "$output" | grep -qE 'stdio\.h: No such file'; then
    echo "  cause: libc headers missing — install SUNWhea."
else
    echo "  last observation: $(echo "$output" | grep 'OBSERVED:' | tail -1)"
fi
exit 1
