#!/usr/bin/env bash
# Run on the target illumos build guest after copying the cross-built objects.
set -euo pipefail

objects=${1:?usage: link-snet-driver.sh OBJECT_DIRECTORY OUTPUT_MODULE}
output=${2:?usage: link-snet-driver.sh OBJECT_DIRECTORY OUTPUT_MODULE}
[[ $(uname -s) == SunOS && $(uname -p) == sparc ]] || {
    echo 'SNET linkage requires a native SPARC SunOS linker' >&2
    exit 1
}
linker=${SNET_LD:-/usr/ccs/bin/ld}
test -x "$linker"
test -s "$objects/snet.o"
test -s "$objects/snet_hcall.o"
"$linker" -r -dy -N misc/mac -o "$output" \
    "$objects/snet.o" "$objects/snet_hcall.o"
file "$output"
