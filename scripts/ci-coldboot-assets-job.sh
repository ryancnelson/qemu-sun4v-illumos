#!/bin/bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive PYTHONDONTWRITEBYTECODE=1
apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=20 update
apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=20 install -y --no-install-recommends gcc libc6-dev libasan8 libubsan1 clang libclang-rt-18-dev git python3 patch ca-certificates
dpkg-query -W gcc gcc-13 libgcc-13-dev libasan8 libubsan1 clang clang-18 libclang-rt-18-dev git python3
cc --version
clang --version
for f in libasan_preinit.o libasan.so libubsan.so; do p=$(cc -print-file-name="$f"); test -f "$p"; dpkg-query -S "$p"; done
cd /src
python3 scripts/validate-coldboot-assets.py
python3 work/maestro-sun4u-001/diskboot-loader-kestrel/test_token_contract.py work/maestro-sun4u-001/diskboot-loader-kestrel/candidate/forth/device/table.fs
python3 scripts/test-tokenfix-build-integration.py
python3 work/maestro-sun4u-001/ata-dad-compatible-kestrel/tests/test_node.py
DADCOMPAT_TEST_SOURCE=work/maestro-sun4u-001/dadcompat-recipe-integration/upstream python3 scripts/test-dadcompat-build-integration.py
python3 scripts/validate-dad-retained-assets.py
python3 scripts/validate-firmware-topology-assets.py
