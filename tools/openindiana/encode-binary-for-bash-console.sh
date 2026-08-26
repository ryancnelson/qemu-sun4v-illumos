#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
    echo "usage: $0 INPUT GUEST_OUTPUT" >&2
    exit 2
fi

input=$1
guest_output=$2

printf ': > %q\n' "$guest_output"
od -An -v -to1 -w96 "$input" | awk -v output="$guest_output" '
BEGIN {
    sq = sprintf("%c", 39)
    bs = sprintf("%c", 92)
}
{
    printf "printf %s%%b%s %s", sq, sq, sq
    for (i = 1; i <= NF; i++) {
        printf "%s0%s", bs, $i
    }
    printf "%s >> %s\n", sq, output
}
'
printf 'echo __TRANSFER_DONE__; wc -c %q\n' "$guest_output"
