#!/usr/bin/env python3
"""Regression guard for the container's mixed tmpfs/persistent drive policy."""

from pathlib import Path


entrypoint = Path(__file__).with_name("container-entrypoint.sh").read_text()
lines = entrypoint.splitlines()

carrier = next(line for line in lines if 'id=carrier100,format=raw' in line)
installer = next(line for line in lines if 'id=installer103,format=raw' in line)
root = next(line for line in lines if 'id=targetroot,format=raw' in line)

assert "cache=writeback" in carrier
assert "cache=none" not in carrier
assert "cache=none" in installer
assert "cache=none" in root

print("DRIVE_CACHE_POLICY=PASS")
