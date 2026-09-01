#!/usr/bin/env python3
"""Regression guard for automatic human and automation console selection."""

from pathlib import Path


entrypoint = Path(__file__).with_name("container-entrypoint.sh").read_text()
smoke = Path(__file__).with_name("smoke-interactive-console.py").read_text()

assert "CONSOLE_MODE=${CONSOLE_MODE:-auto}" in entrypoint
assert "if [[ -t 0 && -t 1 ]]" in entrypoint
assert "CONSOLE_MODE=stdio" in entrypoint
assert "CONSOLE_MODE=socket" in entrypoint
assert "stdio,id=guestconsole,signal=off" in entrypoint
assert "socket,id=guestconsole,path=$STATE_DIR/console.sock" in entrypoint
assert 'console_mode=$CONSOLE_MODE' in entrypoint
assert "io.niagara.appliance-ci=1" in smoke
assert '["docker", "volume", "rm", volume_name]' in smoke

print("CONSOLE_MODE_POLICY=PASS")
