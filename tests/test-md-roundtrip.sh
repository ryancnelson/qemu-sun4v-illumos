#!/usr/bin/env bash
# TEST: mdgen regenerates the shipped MD blobs byte-identically.
#
# This is the trust anchor for all Machine Description work. If this passes,
# the .pdesc/.hdesc text files are the verified source of the binaries the
# Niagara machine loads, and we can edit the MD as text instead of doing
# binary surgery on 1up-md.bin.
#
# Host-only. No VM boot, no zvol, no root. Runs in ~2s.
#
# PASS = both 1up-md.bin and 1up-hv.bin reproduce with identical bytes.

set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENSPARC="${OPENSPARC:-$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)/vms/opensparc}"
CFG="$OPENSPARC/legion/src/config/niagara"
SHIPPED="$OPENSPARC/S10image"
MDGEN="$PROJ/build/mdgen/mdgen"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: test-md-roundtrip — $1"; exit 1; }

[[ -x "$MDGEN" ]] || bash "$PROJ/tools/build-mdgen.sh" >/dev/null \
    || fail "tools/build-mdgen.sh could not build mdgen"

rc=0
for pair in "1up.pdesc:1up-md.bin" "1up.hdesc:1up-hv.bin"; do
    src="$CFG/${pair%%:*}"
    ref="$SHIPPED/${pair##*:}"
    gen="$WORK/${pair##*:}"

    [[ -f "$src" ]] || fail "missing MD source $src"
    [[ -f "$ref" ]] || fail "missing shipped blob $ref"

    MDGEN="$MDGEN" bash "$PROJ/tools/gen-md.sh" "$src" "$gen" >/dev/null \
        || fail "gen-md.sh failed for $src"

    if cmp -s "$gen" "$ref"; then
        echo "OBSERVED: $(basename "$ref") byte-identical ($(stat -c%s "$gen") bytes)"
    else
        echo "OBSERVED: $(basename "$ref") DIFFERS ($(cmp -l "$gen" "$ref" | wc -l) bytes)"
        rc=1
    fi
done

[[ $rc -eq 0 ]] || fail "one or more MD blobs did not reproduce"
echo "PASS: test-md-roundtrip"
