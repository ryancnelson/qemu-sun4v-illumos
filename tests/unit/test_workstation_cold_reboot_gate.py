import importlib.util
from pathlib import Path

import pytest


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "tools"
    / "openindiana"
    / "workstation-cold-reboot-gate.py"
)


def load_gate():
    spec = importlib.util.spec_from_file_location("workstation_cold_reboot_gate", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_boot_markers_require_fresh_full_progression():
    gate = load_gate()
    text = """OpenBoot
ok
SunOS Release 5.11
root on rpool/ROOT/openindiana fstype zfs
Executing legacy init script "/etc/rc2.d/S99niagara".
oi-basecamp console login:
"""
    markers = gate.boot_markers(text)
    assert all(markers[name] for name in ("obp", "kernel", "root", "multiuser", "login"))
    assert markers["panic"] is False


@pytest.mark.parametrize("terminal", ["panic: test", "kmdb: entering", "[0]>"])
def test_boot_markers_fail_closed_on_terminal_state(terminal):
    gate = load_gate()
    assert gate.boot_markers(f"OpenBoot\n{terminal}\n")["panic"] is True


@pytest.mark.parametrize("run_id", ["../escape", "/absolute", "contains space", ""])
def test_evidence_run_id_rejects_unsafe_paths(run_id):
    gate = load_gate()
    with pytest.raises(gate.GateError):
        gate.evidence_dir(run_id)


def test_overlong_guest_command_fails_before_console_input(tmp_path):
    gate = load_gate()
    with pytest.raises(gate.GateError, match="too long"):
        gate.wait_guest_command(tmp_path, "LONG", "x" * 191, 1)


def test_observe_timeout_is_bounded_before_evidence_lookup():
    gate = load_gate()
    with pytest.raises(gate.GateError, match="between 60 and 3600"):
        gate.observe("valid-id", 3601)


def test_source_has_no_process_signal_or_monitor_client():
    source = SCRIPT.read_text(encoding="utf-8")
    assert "os.kill" not in source
    assert "import socket" not in source
    assert "system_reset" not in source
    assert "sendkey" not in source
