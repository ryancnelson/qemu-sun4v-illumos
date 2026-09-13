#!/bin/bash
# Pinned downloads from notes/OPENINDIANA-NATIVE-GCC13-TOOLCHAIN.md.
# This fetches the toolchain; it does not solve pkg incorporations or install it.
set -euo pipefail
PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH
mkdir -p /jack/toolchain-downloads
cd /jack/toolchain-downloads
fetch() {
    local name=$1 expected=$2 actual
    if [[ ! -f $name ]]; then
        curl --fail --location --retry 3 --connect-timeout 30 --max-time 1200 \
            -o "$name.partial" \
            "https://dlc.openindiana.aurora-opencloud.org/SPARC/$name"
        actual=$(/usr/bin/digest -a sha256 "$name.partial")
        [[ $actual == "$expected" ]] || { echo "GCC_DIGEST=FAIL $name" >&2; return 1; }
        mv "$name.partial" "$name"
    fi
    actual=$(/usr/bin/digest -a sha256 "$name")
    [[ $actual == "$expected" ]] || { echo "GCC_DIGEST=FAIL $name" >&2; return 1; }
    echo "GCC_DOWNLOAD=PASS file=$name sha256=$actual"
}
fetch gcc-13.4.0.tar.xz 7c2193369b0f6accd56c4fc5cacc3cd175e387b20ed942b13a1e710a6c7ee038
# The sysroot's .tar.gz extension is misleading: it is XZ, use gtar -xJf.
fetch illumos-sysroot-sparc-20260117-31d3d510d0-v1.tar.gz 753ca4b2e24a2a2c3d3ac5de3a590c6b1a106f8fe5cbd89f78f70f80431cb027
