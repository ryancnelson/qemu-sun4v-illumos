#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/openbios"
test "$(git rev-parse HEAD)" = af97fd7af5e7c18f591a7b987291d3db4ffb28b5
sha256sum -c ../tracked-source-sha256.txt
git diff --check
./config/scripts/switch-arch sparc64
EXTRACFLAGS=-fno-stack-protector make -j2
test -s obj-sparc64/openbios-builtin.elf
test -s obj-sparc64/openbios-builtin.elf.nostrip
mkdir -p ../artifacts
sparc64-linux-gnu-objdump -d obj-sparc64/openbios-builtin.elf.nostrip > ../artifacts/disassembly.txt
if grep -Fq '%g7 + 0x28' ../artifacts/disassembly.txt; then
    echo 'FAIL: stack-canary TLS load' >&2
    exit 1
fi
sparc64-linux-gnu-nm obj-sparc64/openbios-builtin.elf.nostrip > ../artifacts/symbols.txt
install -m 0644 obj-sparc64/openbios-builtin.elf ../artifacts/openbios-sparc64.candidate
install -m 0644 obj-sparc64/openbios-builtin.elf.nostrip ../artifacts/openbios-sparc64.candidate.nostrip
git status --short > ../post-build-status.txt
git diff > ../post-build-source.patch
sha256sum ../artifacts/openbios-sparc64.candidate ../artifacts/openbios-sparc64.candidate.nostrip
sparc64-linux-gnu-gcc --version
make --version
echo OPENBIOS_CANDIDATE_BUILD=PASS
