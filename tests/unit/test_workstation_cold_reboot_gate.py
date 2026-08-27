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


def drive_arg(path, *, readonly="off"):
    return [f"file={path},if=none,id=target104,unit=104,readonly={readonly}"]


def test_writable_unit104_requires_one_explicit_writable_absolute_path(tmp_path):
    gate = load_gate()
    disk = tmp_path / "target104.img"
    assert gate.writable_unit104(drive_arg(disk), "test") == disk
    with pytest.raises(gate.GateError, match="explicitly writable"):
        gate.writable_unit104(drive_arg(disk, readonly="on"), "test")
    with pytest.raises(gate.GateError, match="exactly one"):
        gate.writable_unit104(drive_arg(disk) * 2, "test")


def test_dataset_separation_binds_live_paths_and_rejects_alias(monkeypatch, tmp_path):
    gate = load_gate()
    target = tmp_path / "target" / "unit104.img"
    protected = tmp_path / "protected" / "unit104.img"
    target.parent.mkdir()
    protected.parent.mkdir()
    target.write_bytes(b"1234567")
    protected.write_bytes(b"1234567")
    monkeypatch.setattr(gate, "TARGET_DISK", str(target))
    monkeypatch.setattr(gate, "PRESERVED_DISK", str(protected))
    monkeypatch.setattr(gate, "TARGET_DATASET", "pool/target")
    monkeypatch.setattr(gate, "PRESERVED_DATASET", "pool/protected")
    monkeypatch.setattr(
        gate,
        "zfs_dataset_for",
        lambda path: (
            ("pool/target", target.parent)
            if path == target
            else ("pool/protected", protected.parent)
        ),
    )
    result = gate.verify_dataset_separation(
        drive_arg(target), drive_arg(protected), expected_size=7
    )
    assert result["target104_dataset"] == "pool/target"
    assert result["protected_target104_dataset"] == "pool/protected"

    monkeypatch.setattr(gate, "PRESERVED_DATASET", "pool/target")
    monkeypatch.setattr(
        gate, "zfs_dataset_for", lambda path: ("pool/target", path.parent)
    )
    with pytest.raises(gate.GateError, match="share dataset"):
        gate.verify_dataset_separation(
            drive_arg(target), drive_arg(protected), expected_size=7
        )


def test_rollback_snapshot_requires_exact_name_path_and_size(monkeypatch, tmp_path):
    gate = load_gate()
    snapshot_name = "cold-reboot-ready-test"
    monkeypatch.setattr(gate, "ROLLBACK_SNAPSHOT", f"pool/target@{snapshot_name}")
    monkeypatch.setattr(
        gate,
        "run_readonly",
        lambda argv, timeout=10: f"pool/target@{snapshot_name}\n",
    )
    relative = Path("runs/target104.img")
    live_target = tmp_path / relative
    snapshot_target = tmp_path / ".zfs" / "snapshot" / snapshot_name / relative
    snapshot_target.parent.mkdir(parents=True)
    snapshot_target.write_bytes(b"1234567")
    result = gate.verify_rollback_snapshot(live_target, tmp_path, expected_size=7)
    assert result["rollback_snapshot"] == f"pool/target@{snapshot_name}"
    assert result["rollback_snapshot_target104_size"] == 7

    monkeypatch.setattr(gate, "run_readonly", lambda argv, timeout=10: "pool/target@other\n")
    with pytest.raises(gate.GateError, match="exact rollback snapshot"):
        gate.verify_rollback_snapshot(live_target, tmp_path, expected_size=7)

    monkeypatch.setattr(
        gate,
        "run_readonly",
        lambda argv, timeout=10: f"pool/target@{snapshot_name}\n",
    )
    with pytest.raises(gate.GateError, match="size/type mismatch"):
        gate.verify_rollback_snapshot(live_target, tmp_path, expected_size=8)


def preflight_state_fixture():
    return {
        "preserved_pid": 2719062,
        "protected_target104_dataset": "pool/protected",
        "protected_target104_path": "/pool/protected/target104.img",
        "protected_target104_size": 64424509440,
        "target_pid": 3063953,
        "target104_dataset": "pool/verification",
        "target104_path": "/pool/verification/target104.img",
        "target104_size": 64424509440,
        "rollback_snapshot": "pool/verification@ready",
        "rollback_snapshot_target104": "/pool/verification/.zfs/snapshot/ready/target104.img",
        "rollback_snapshot_target104_size": 64424509440,
    }


def test_preflight_evidence_record_has_stable_schema_identities_and_gates():
    gate = load_gate()
    record = gate.preflight_evidence_record(
        preflight_state_fixture(), "2026-08-27T04:00:00Z", "2026-08-27T04:00:01Z"
    )
    assert set(record) == {
        "schema",
        "record_type",
        "gate_name",
        "status",
        "run_id",
        "started_at_utc",
        "completed_at_utc",
        "identities",
        "rollback",
        "gates",
    }
    assert record["schema"] == gate.EVIDENCE_SCHEMA
    assert record["gate_name"] == "cold_reboot_preflight"
    assert record["status"] == "PASS"
    assert record["run_id"] is None
    assert record["identities"]["protected"] == {
        "pid": 2719062,
        "dataset": "pool/protected",
        "target104_path": "/pool/protected/target104.img",
        "target104_logical_size": 64424509440,
    }
    assert record["identities"]["verification"]["pid"] == 3063953
    assert record["identities"]["verification"]["dataset"] == "pool/verification"
    assert {item["name"] for item in record["gates"]} == {
        "qemu_pid_dataset_isolation",
        "rollback_snapshot",
        "tmux_topology",
        "channel_bridge",
        "host_ppp",
    }
    assert all(item["status"] == "PASS" for item in record["gates"])
    assert all(item["checked_at_utc"] == "2026-08-27T04:00:01Z" for item in record["gates"])


def test_acceptance_evidence_record_reuses_verified_identities_and_names_gates():
    gate = load_gate()
    preflight = gate.preflight_evidence_record(
        preflight_state_fixture(), "2026-08-27T04:00:00Z", "2026-08-27T04:00:01Z"
    )
    record = gate.acceptance_evidence_record(
        preflight,
        "reboot-test-01",
        "2026-08-27T05:00:00Z",
        "2026-08-27T05:10:00Z",
        "2026-08-27T05:15:00Z",
    )
    assert record["schema"] == gate.EVIDENCE_SCHEMA
    assert record["record_type"] == "cold_reboot_acceptance"
    assert record["gate_name"] == "cold_reboot_acceptance"
    assert record["status"] == "PASS"
    assert record["run_id"] == "reboot-test-01"
    assert record["identities"] == preflight["identities"]
    assert record["rollback"] == preflight["rollback"]
    assert {item["name"] for item in record["gates"]} == {
        "preflight",
        "boot_observation",
        "single_supervisor",
        "guest_ppp",
        "default_route",
        "nfs_v3_tcp",
        "timestamped_smoke_marker",
        "devtools_smoke",
    }


def test_acceptance_record_rejects_incompatible_preflight_schema():
    gate = load_gate()
    with pytest.raises(gate.GateError, match="compatible preflight"):
        gate.acceptance_evidence_record(
            {"schema": "wrong"},
            "reboot-test-01",
            "2026-08-27T05:00:00Z",
            "2026-08-27T05:10:00Z",
            "2026-08-27T05:15:00Z",
        )


def test_source_has_no_process_signal_or_monitor_client():
    source = SCRIPT.read_text(encoding="utf-8")
    assert "os.kill" not in source
    assert "import socket" not in source
    assert "system_reset" not in source
    assert "sendkey" not in source
