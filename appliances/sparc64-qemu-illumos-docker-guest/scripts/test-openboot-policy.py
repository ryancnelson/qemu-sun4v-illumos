#!/usr/bin/env python3
"""Regression guard for the unit105-to-disk@5 automatic boot mapping."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
entrypoint = (root / "scripts/container-entrypoint.sh").read_text()
appliance = (root / "appliance").read_text()
smoke = (root / "scripts/smoke-login.py").read_text()

assert "OPENBOOT_UNIT=${OPENBOOT_UNIT:-$((ROOT_UNIT % 100))}" in entrypoint
assert "OPENBOOT_DEVICE=${OPENBOOT_DEVICE:-/virtual-devices@100/disk@${OPENBOOT_UNIT}:a}" in entrypoint
assert '-prom-env "boot-device=$OPENBOOT_DEVICE"' in entrypoint
assert '-prom-env "boot-file=$OPENBOOT_FILE"' in entrypoint
assert '-prom-env "auto-boot?=$OPENBOOT_AUTO_BOOT"' in entrypoint
assert "AUTO_BOOT_REQUIRED=1" in appliance
assert "APPLIANCE_AUTO_BOOT=PASS" in smoke
assert "APPLIANCE_AUTO_BOOT=FAIL" in smoke

print("OPENBOOT_POLICY=PASS root_unit=105 openboot_disk=5 auto_boot=true")
