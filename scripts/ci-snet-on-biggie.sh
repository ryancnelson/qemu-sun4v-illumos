#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
cache=${SNET_CI_CACHE:-$HOME/devel/woodpecker-cache/snet-driver}

cd "$project"
/usr/bin/python3 -m unittest discover -s tools/snet -p 'test_*.py' -v
/usr/bin/python3 -m py_compile tools/snet/protocol.py tools/snet/test_protocol.py
test -s include/sun4v_snet_protocol.h

QEMU_SNET_SOURCE="$cache/qemu-source" \
QEMU_SNET_BUILD="$cache/qemu-build" \
    scripts/build-snet-qemu.sh

scripts/build-snet-driver.sh
