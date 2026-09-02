#!/usr/bin/env python3
"""Regression guard for the unit105-to-disk@5 automatic boot mapping."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
entrypoint = (root / "scripts/container-entrypoint.sh").read_text()
appliance = (root / "appliance").read_text()
smoke = (root / "scripts/smoke-login.py").read_text()
prepare = (root / "scripts/prepare-release-firmware.sh").read_text()
editor = (root / "scripts/edit-release-md.py").read_text()
howto = (root / "firmware-policy/how-to-edit-nvram.txt").read_text()

assert "OPENBOOT_UNIT=${OPENBOOT_UNIT:-$((ROOT_UNIT % 100))}" in entrypoint
assert "OPENBOOT_DEVICE=${OPENBOOT_DEVICE:-/virtual-devices@100/disk@${OPENBOOT_UNIT}:a}" in entrypoint
assert "AUTO_BOOT_REQUIRED=1" in appliance
assert "APPLIANCE_AUTO_BOOT=PASS" in smoke
assert "APPLIANCE_AUTO_BOOT=FAIL" in smoke
assert "MD_BASELINE_ROUNDTRIP=PASS" in prepare
assert "506db40dda9774f79ef2b110901a67f8ca451ef7645e12f5842229335dd4f693" in prepare
assert 'BOOT_DEVICE = "/virtual-devices@100/disk@5:a"' in editor
assert 'auto-boot?  = "true"' in editor
assert 'boot-file  = "-v"' in editor
assert "Update NVRAM with PD data" in howto
assert "do not binary-edit nvram1" in howto
assert 'OPENBOOT_AUTO_BOOT=false' in howto
assert 'md.bin.manual' in entrypoint

print("OPENBOOT_POLICY=PASS root_unit=105 openboot_disk=5 boot_file=-v auto_boot=true")
