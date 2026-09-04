#!/usr/bin/env python3
"""Static regression guard for the two-CPU, no-KMDB appliance contract."""

import hashlib
import re
from pathlib import Path


root = Path(__file__).resolve().parents[1]
entrypoint = (root / "scripts/container-entrypoint.sh").read_text()
appliance = (root / "appliance").read_text()
ci = (root / "scripts/ci-self-contained-oci.sh").read_text()
dockerfile = (root / "Dockerfile").read_text()
firmware = (root / "scripts/prepare-release-firmware.sh").read_text()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

assert 'SMP_CPUS=${SMP_CPUS:-2}' in entrypoint
assert 'SMP_CPUS must be exactly 2 for this firmware' in entrypoint
assert '-smp "$SMP_CPUS"' in entrypoint
assert 'smp_cpus=$SMP_CPUS' in entrypoint
assert "qemu_patchset=0004-strand-id,0005-interrupt-dump,0006-mondo-deferral" in entrypoint
assert 'boot-file  = "-v"' in (root / "scripts/edit-release-md.py").read_text()
assert 'boot-file  = "-k' not in (root / "scripts/edit-release-md.py").read_text()
assert "self-smp)" in appliance
assert "cpu0 && cpu1 && count == 2" in appliance
assert "OCI_GUEST_SMP=PASS cpus=0,1 kmdb=absent" in appliance
assert "Loading kmdb|kernel debugger was booted|kmdb:" in appliance
assert "0004-niagara-smp-strand-id.patch" in dockerfile
assert "0006-niagara-defer-guest-mondo-in-hypervisor.patch" in dockerfile
assert "sha256sum -c SHA256SUMS" in dockerfile
assert "BASE_MD_SHA256=e5d0dfa0" in firmware
assert "HV_SHA256=e9b63c808" in firmware
assert "bash ./appliance self-smp" in ci
assert "bash ./appliance build" in ci
assert "OCI_SMP_IMAGE=PASS" in ci
assert "restore_guest_root" in ci
assert "GUEST_RELEASE_ROOT_RESTORE=PASS" in ci
assert "restore_release_bundle" in ci
assert "GUEST_RELEASE_BUNDLE_RESTORE=PASS" in ci
assert "@sha256:29cadb0eb0f103fecb5f22ab0707d71e66986724a49d10f3b213b4f9ae7819fe" in ci

guest_md = root / "firmware-smp/2c8t_guest.pp.bak"
hv_md = root / "firmware-smp/2c8t_hv.pp.bak"
assert len(re.findall(r"^node cpu\s", guest_md.read_text(), re.MULTILINE)) == 2
assert len(re.findall(r"^node cpu\s", hv_md.read_text(), re.MULTILINE)) == 2
assert sha256(root / "firmware-smp/md.bin") == (
    "e5d0dfa0cef98daef762ed48a19ace9c372e4bc46342bc03200eb1cf219379ac"
)
assert sha256(root / "firmware-smp/hv.bin") == (
    "e9b63c8084a5a124253659c200709dc9de8281e66d3c8c349bef2faa4b065099"
)
for line in (root / "qemu-patches/SHA256SUMS").read_text().splitlines():
    expected, filename = line.split()
    assert sha256(root / "qemu-patches" / filename) == expected

print("SMP_POLICY=PASS cpus=2 kmdb=disabled")
