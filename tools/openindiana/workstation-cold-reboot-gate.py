#!/usr/bin/env python3
"""Fail-closed acceptance harness for workstation-fix-verify-01.

This program never performs a reboot and never opens the QEMU monitor.  The
only guest input it can send is a fixed set of read-only acceptance commands
after an operator has logged in and an observe phase has reached login.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


RUNS = Path("/home/ryan/devel/masa-sun4v/ci/runs")
TARGET_NAME = "workstation-fix-verify-01"
TARGET_RUN = RUNS / TARGET_NAME
TARGET_SESSION = TARGET_NAME
PRESERVED_PID = 2719062
PRESERVED_CONSOLE = str(RUNS / "workstation-reboot-01" / "console.sock")
TARGET_CONSOLE = TARGET_RUN / "console.sock"
TARGET_MONITOR = TARGET_RUN / "monitor.sock"
CONSOLE_LOG = TARGET_RUN / "console.log"
BRIDGE_SOCK = TARGET_RUN / "host-chan0.sock"
TARGET_CHANNEL_IMAGE = str(
    RUNS / "workstation-fix-startup-01" / "images" / "channel-unit101.img"
)
TARGET_DISK = (
    "/datapool/workstation-fix-startup-01/ryan/devel/masa-sun4v/ci/runs/"
    "term4code-herm-smp4-01/images/extra-unit104-60g.img"
)
PRESERVED_DISK = (
    "/datapool/workstation-reboot-01/ryan/devel/masa-sun4v/ci/runs/"
    "term4code-herm-smp4-01/images/extra-unit104-60g.img"
)
TARGET_DATASET = "datapool/workstation-fix-startup-01"
PRESERVED_DATASET = "datapool/workstation-reboot-01"
ROLLBACK_SNAPSHOT = (
    "datapool/workstation-fix-startup-01@"
    "cold-reboot-ready-a0c09ab-20260827T034757Z"
)
EXPECTED_TARGET_SIZE = 64424509440
GATE_ROOT = TARGET_RUN / "cold-reboot-gates"
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
RUN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")


class GateError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise GateError(message)


def read_pid(path: Path) -> int:
    try:
        raw = path.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[1-9][0-9]*", raw):
            fail(f"invalid PID file {path}: {raw!r}")
        return int(raw)
    except OSError as exc:
        fail(f"cannot read PID file {path}: {exc}")


def proc_cmdline(pid: int) -> list[str]:
    path = Path(f"/proc/{pid}/cmdline")
    try:
        raw = path.read_bytes()
    except OSError as exc:
        fail(f"PID {pid} is not readable/alive: {exc}")
    args = [item.decode("utf-8", "replace") for item in raw.split(b"\0") if item]
    if not args:
        fail(f"PID {pid} has an empty cmdline")
    return args


def proc_environ(pid: int) -> dict[str, str]:
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes()
    except OSError as exc:
        fail(f"cannot inspect environment for PID {pid}: {exc}")
    result: dict[str, str] = {}
    for item in raw.split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            result[key.decode("utf-8", "replace")] = value.decode(
                "utf-8", "replace"
            )
    return result


def require_cmd_contains(pid: int, required: list[str], label: str) -> list[str]:
    args = proc_cmdline(pid)
    joined = " ".join(args)
    missing = [value for value in required if value not in joined]
    if missing:
        fail(f"{label} PID {pid} identity mismatch; missing {missing}: {joined}")
    return args


def run_readonly(argv: list[str], timeout: int = 10) -> str:
    try:
        proc = subprocess.run(
            argv,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"read-only command failed/timed out: {argv}: {exc}")
    if proc.returncode != 0:
        fail(f"read-only command rc={proc.returncode}: {argv}: {proc.stdout.strip()}")
    return proc.stdout


def clean_text(raw: bytes | str) -> str:
    if isinstance(raw, bytes):
        text = raw.replace(b"\0", b"").decode("utf-8", "replace")
    else:
        text = raw
    return ANSI.sub("", text).replace("\r", "")


def tail_bytes(path: Path, limit: int = 16384) -> bytes:
    with path.open("rb") as stream:
        stream.seek(0, os.SEEK_END)
        size = stream.tell()
        stream.seek(max(0, size - limit))
        return stream.read()


def exact_pppd_pids() -> list[int]:
    matches: list[int] = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            args = proc_cmdline(int(entry.name))
        except GateError:
            continue
        joined = " ".join(args)
        if (
            "/usr/sbin/pppd" in joined
            and "10.0.5.1:10.0.5.15" in joined
            and "asyncmap 0" in joined
        ):
            matches.append(int(entry.name))
    return sorted(matches)


def writable_unit104(args: list[str], label: str) -> Path:
    drives = [arg for arg in args if "unit=104" in arg]
    if len(drives) != 1:
        fail(f"{label} must expose exactly one unit104 drive: {drives}")
    fields = drives[0].split(",")
    if "unit=104" not in fields or "readonly=off" not in fields:
        fail(f"{label} unit104 is not explicitly writable: {drives[0]}")
    files = [field.removeprefix("file=") for field in fields if field.startswith("file=")]
    if len(files) != 1 or not Path(files[0]).is_absolute():
        fail(f"{label} unit104 has no single absolute file path: {drives[0]}")
    return Path(files[0])


def zfs_dataset_for(path: Path) -> tuple[str, Path]:
    output = run_readonly(
        ["findmnt", "-T", str(path), "-n", "-o", "SOURCE,FSTYPE,TARGET"]
    ).strip()
    lines = output.splitlines()
    if len(lines) != 1:
        fail(f"cannot uniquely resolve mount for {path}: {output!r}")
    fields = lines[0].split(maxsplit=2)
    if len(fields) != 3 or fields[1] != "zfs":
        fail(f"target is not on one identifiable ZFS dataset: {path}: {output!r}")
    source = fields[0].split("[", 1)[0]
    mountpoint = Path(fields[2])
    try:
        path.relative_to(mountpoint)
    except ValueError:
        fail(f"resolved mountpoint does not contain target: {path}: {mountpoint}")
    return source, mountpoint


def verify_dataset_separation(
    target_args: list[str], preserved_args: list[str], expected_size: int = EXPECTED_TARGET_SIZE
) -> dict[str, object]:
    target_path = writable_unit104(target_args, "verification QEMU")
    preserved_path = writable_unit104(preserved_args, "protected QEMU")
    if str(target_path) != TARGET_DISK:
        fail(f"verification unit104 path mismatch: {target_path}")
    if str(preserved_path) != PRESERVED_DISK:
        fail(f"protected unit104 path mismatch: {preserved_path}")
    for label, path in (("verification", target_path), ("protected", preserved_path)):
        try:
            stat = path.stat()
        except OSError as exc:
            fail(f"{label} unit104 is not stat-able: {path}: {exc}")
        if not path.is_file() or stat.st_size != expected_size:
            fail(
                f"{label} unit104 size/type mismatch: {path}: "
                f"size={stat.st_size} expected={expected_size}"
            )
    target_dataset, target_mountpoint = zfs_dataset_for(target_path)
    preserved_dataset, preserved_mountpoint = zfs_dataset_for(preserved_path)
    if target_dataset != TARGET_DATASET:
        fail(f"verification dataset mismatch: {target_dataset}")
    if preserved_dataset != PRESERVED_DATASET:
        fail(f"protected dataset mismatch: {preserved_dataset}")
    if target_dataset == preserved_dataset:
        fail(f"verification and protected QEMUs share dataset {target_dataset}")
    return {
        "target104_path": str(target_path),
        "target104_size": target_path.stat().st_size,
        "target104_dataset": target_dataset,
        "target104_mountpoint": str(target_mountpoint),
        "protected_target104_path": str(preserved_path),
        "protected_target104_size": preserved_path.stat().st_size,
        "protected_target104_dataset": preserved_dataset,
        "protected_target104_mountpoint": str(preserved_mountpoint),
    }


def verify_rollback_snapshot(
    target_path: Path, target_mountpoint: Path, expected_size: int = EXPECTED_TARGET_SIZE
) -> dict[str, object]:
    snapshot = run_readonly(
        ["zfs", "list", "-H", "-t", "snapshot", "-o", "name", ROLLBACK_SNAPSHOT]
    ).strip()
    if snapshot != ROLLBACK_SNAPSHOT:
        fail(f"exact rollback snapshot absent or ambiguous: {snapshot!r}")
    snapshot_name = ROLLBACK_SNAPSHOT.split("@", 1)[1]
    try:
        relative = target_path.relative_to(target_mountpoint)
    except ValueError:
        fail(f"verification unit104 is outside dataset mountpoint: {target_path}")
    snapshot_target = target_mountpoint / ".zfs" / "snapshot" / snapshot_name / relative
    try:
        stat = snapshot_target.stat()
    except OSError as exc:
        fail(f"rollback snapshot target104 is not stat-able: {snapshot_target}: {exc}")
    if not snapshot_target.is_file() or stat.st_size != expected_size:
        fail(
            f"rollback snapshot target104 size/type mismatch: {snapshot_target}: "
            f"size={stat.st_size} expected={expected_size}"
        )
    return {
        "rollback_snapshot": snapshot,
        "rollback_snapshot_target104": str(snapshot_target),
        "rollback_snapshot_target104_size": stat.st_size,
    }


def preflight() -> dict[str, object]:
    preserved = require_cmd_contains(
        PRESERVED_PID,
        ["qemu-system-sparc64", PRESERVED_CONSOLE, "unit=104"],
        "preserved QEMU",
    )
    target_pid = read_pid(TARGET_RUN / "qemu.pid")
    if target_pid == PRESERVED_PID:
        fail("target PID aliases preserved PID")
    target = require_cmd_contains(
        target_pid,
        [
            "qemu-system-sparc64",
            str(TARGET_CONSOLE),
            str(TARGET_MONITOR),
            "unit=100",
            "unit=101",
            "unit=103,readonly=on",
            "unit=104,readonly=off",
            TARGET_DISK,
        ],
        "target QEMU",
    )
    disk_evidence = verify_dataset_separation(target, preserved)
    snapshot_evidence = verify_rollback_snapshot(
        Path(str(disk_evidence["target104_path"])),
        Path(str(disk_evidence["target104_mountpoint"])),
    )

    for path in (TARGET_CONSOLE, TARGET_MONITOR, BRIDGE_SOCK, CONSOLE_LOG):
        if not path.exists():
            fail(f"required target artifact absent: {path}")
    if not TARGET_CONSOLE.is_socket() or not TARGET_MONITOR.is_socket():
        fail("target console/monitor path is not a Unix socket")

    windows_raw = run_readonly(
        [
            "tmux",
            "list-windows",
            "-t",
            TARGET_SESSION,
            "-F",
            "#{window_name} #{pane_dead} #{pane_pid} #{pane_current_command}",
        ]
    )
    windows = {line.split()[0]: line for line in windows_raw.splitlines() if line}
    required_windows = {"qemu", "console", "monitor", "host-chan0", "host-ppp"}
    if not required_windows.issubset(windows):
        fail(f"target tmux windows missing: {sorted(required_windows - set(windows))}")
    dead = [line for line in windows.values() if line.split()[1] != "0"]
    if dead:
        fail(f"dead target tmux window(s): {dead}")

    bridge_pid = read_pid(TARGET_RUN / "host-chan0.pid")
    require_cmd_contains(
        bridge_pid,
        ["host-chan.py", "bridge", "0", str(BRIDGE_SOCK)],
        "host channel bridge",
    )
    bridge_env = proc_environ(bridge_pid)
    if bridge_env.get("NIAGARA_IMG") != TARGET_CHANNEL_IMAGE:
        fail(f"bridge image mismatch: {bridge_env.get('NIAGARA_IMG')!r}")
    if bridge_env.get("NIAG_CHAN_HOST_BYTE") != "327680":
        fail(f"bridge byte mismatch: {bridge_env.get('NIAG_CHAN_HOST_BYTE')!r}")
    bridge_tail = clean_text(tail_bytes(TARGET_RUN / "host-chan0.log", 4096))
    bridge_events = [line for line in bridge_tail.splitlines() if "ch0 client" in line]
    if not bridge_events or "connected" not in bridge_events[-1] or "gone" in bridge_events[-1]:
        fail(f"bridge client is not connected: {bridge_events[-3:]}")

    ppp_owner_pid = read_pid(TARGET_RUN / "host-ppp-02.pid")
    require_cmd_contains(ppp_owner_pid, ["host-pppd-once.sh", str(BRIDGE_SOCK)], "host PPP owner")
    pppd_pids = exact_pppd_pids()
    if not pppd_pids:
        fail("no exact host pppd 10.0.5.1:10.0.5.15 asyncmap 0 process")
    ip_line = run_readonly(["ip", "-brief", "address", "show", "ppp0"]).strip()
    if "10.0.5.1 peer 10.0.5.15/32" not in ip_line:
        fail(f"host ppp0 mismatch: {ip_line}")

    stat = CONSOLE_LOG.stat()
    tail = clean_text(tail_bytes(CONSOLE_LOG))
    semantic = [line for line in tail.splitlines() if line.strip()][-12:]
    return {
        "status": "PRECHECK_PASS",
        "checked_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "preserved_pid": PRESERVED_PID,
        "preserved_cmd": preserved,
        "target_name": TARGET_NAME,
        "target_pid": target_pid,
        "target_cmd": target,
        "console_inode": stat.st_ino,
        "console_size": stat.st_size,
        "console_mtime_ns": stat.st_mtime_ns,
        "console_tail": semantic,
        "tmux_windows": sorted(windows.values()),
        "bridge_pid": bridge_pid,
        "bridge_last_event": bridge_events[-1],
        "bridge_image": bridge_env["NIAGARA_IMG"],
        "bridge_byte": bridge_env["NIAG_CHAN_HOST_BYTE"],
        "ppp_owner_pid": ppp_owner_pid,
        "pppd_pids": pppd_pids,
        "ppp0": ip_line,
        **disk_evidence,
        **snapshot_evidence,
    }


def evidence_dir(run_id: str) -> Path:
    if not RUN_ID.fullmatch(run_id):
        fail(f"invalid run id: {run_id!r}")
    return GATE_ROOT / run_id


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def arm(run_id: str) -> dict[str, object]:
    state = preflight()
    dest = evidence_dir(run_id)
    if dest.exists():
        fail(f"evidence directory collision: {dest}")
    dest.mkdir(parents=True, mode=0o700)
    os.chmod(dest, 0o700)
    state["run_id"] = run_id
    state["armed_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    state["armed_compact_utc"] = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    write_json(dest / "state.json", state)
    (dest / "console.start.tail").write_bytes(tail_bytes(CONSOLE_LOG))
    return {"status": "ARMED_NO_REBOOT_ACTION", "evidence_dir": str(dest), **state}


def new_console(state: dict[str, object]) -> str:
    stat = CONSOLE_LOG.stat()
    if stat.st_ino != state["console_inode"]:
        fail("console log inode changed; starting offset is no longer trustworthy")
    start = int(state["console_size"])
    if stat.st_size < start:
        fail("console log shrank below armed offset")
    with CONSOLE_LOG.open("rb") as stream:
        stream.seek(start)
        return clean_text(stream.read())


def boot_markers(text: str) -> dict[str, bool]:
    lower = text.lower()
    lines = [line.strip() for line in text.splitlines()]
    return {
        "obp": any(line == "ok" or "openboot" in line.lower() for line in lines),
        "kernel": "sunos release" in lower or "copyright 1983" in lower,
        "root": bool(re.search(r"rpool/ROOT/openindiana.*(?:zfs|root)", text, re.I)),
        "multiuser": (
            'Executing legacy init script "/etc/rc2.d/S99niagara"' in text
            or "milestone/multi-user" in text
        ),
        "login": "oi-basecamp console login:" in text,
        "panic": bool(re.search(r"(^|\n)(panic:|kmdb:|\[[0-9]+\]>)", lower)),
    }


def observe(run_id: str, timeout: int) -> dict[str, object]:
    if timeout < 60 or timeout > 3600:
        fail("observe timeout must be between 60 and 3600 seconds")
    dest = evidence_dir(run_id)
    try:
        state = json.loads((dest / "state.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot load armed state: {exc}")
    target_pid = int(state["target_pid"])
    deadline = time.monotonic() + timeout
    last: dict[str, bool] | None = None
    samples: list[dict[str, object]] = []
    result = "BOOT_TIMEOUT"
    while time.monotonic() < deadline:
        require_cmd_contains(target_pid, [str(TARGET_CONSOLE), TARGET_DISK], "armed target QEMU")
        require_cmd_contains(PRESERVED_PID, [PRESERVED_CONSOLE], "preserved QEMU")
        text = new_console(state)
        markers = boot_markers(text)
        if markers != last:
            sample = {
                "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "markers": markers,
                "console_bytes": len(text.encode("utf-8", "replace")),
            }
            samples.append(sample)
            print(json.dumps(sample, sort_keys=True), flush=True)
            last = markers
        if markers["panic"]:
            result = "BOOT_FAIL_PANIC_OR_KMDB"
            break
        if all(markers[name] for name in ("obp", "kernel", "root", "multiuser", "login")):
            result = "BOOTED_LOGIN"
            break
        time.sleep(5)
    text = new_console(state)
    (dest / "console.reboot.delta").write_text(text, encoding="utf-8")
    outcome = {
        "status": result,
        "finished_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "markers": boot_markers(text),
        "samples": samples,
    }
    write_json(dest / "observe.json", outcome)
    if result != "BOOTED_LOGIN":
        fail(result)
    return outcome


def wait_guest_command(dest: Path, name: str, command: str, timeout: int) -> str:
    if len(command) > 190:
        fail(f"guest command {name} is too long ({len(command)} bytes)")
    sentinel = f"__CRG_{name}_RC:"
    wire = f"{command}; r=$?; echo {sentinel}$r"
    if len(wire) > 240:
        fail(f"wire command {name} is too long ({len(wire)} bytes)")
    start = CONSOLE_LOG.stat().st_size
    run_readonly(["tmux", "send-keys", "-t", f"{TARGET_SESSION}:console", "-l", wire])
    run_readonly(["tmux", "send-keys", "-t", f"{TARGET_SESSION}:console", "Enter"])
    deadline = time.monotonic() + timeout
    output = ""
    while time.monotonic() < deadline:
        with CONSOLE_LOG.open("rb") as stream:
            stream.seek(start)
            output = clean_text(stream.read())
        found = re.search(re.escape(sentinel) + r"([0-9]+)", output)
        if found:
            time.sleep(0.5)
            with CONSOLE_LOG.open("rb") as stream:
                stream.seek(start)
                output = clean_text(stream.read())
            if not re.search(r"root@oi-basecamp:~#\s*$", output):
                fail(f"guest command {name} returned a sentinel without the root prompt")
            (dest / f"guest-{name}.log").write_text(output, encoding="utf-8")
            if int(found.group(1)) != 0:
                fail(f"guest command {name} rc={found.group(1)}")
            return output
        time.sleep(1)
    fail(f"guest command {name} timed out after {timeout}s")


def postlogin(run_id: str) -> dict[str, object]:
    dest = evidence_dir(run_id)
    try:
        state = json.loads((dest / "state.json").read_text(encoding="utf-8"))
        observed = json.loads((dest / "observe.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot load gate evidence: {exc}")
    if observed.get("status") != "BOOTED_LOGIN":
        fail("postlogin requires a completed BOOTED_LOGIN observe phase")
    preflight()
    if not re.search(r"root@oi-basecamp:~#\s*$", clean_text(tail_bytes(CONSOLE_LOG))):
        fail("literal root prompt absent; operator must log in before postlogin")

    outputs: dict[str, str] = {}
    outputs["supervisor"] = wait_guest_command(
        dest,
        "SUPERVISOR",
        'n=$(pgrep -fc niagara-net-supervisor); echo SUPERVISOR_COUNT:$n; test "$n" -eq 1',
        30,
    )
    outputs["sppp"] = wait_guest_command(
        dest,
        "SPPP",
        "ifconfig sppp0 | grep -F '10.0.5.15 --> 10.0.5.1'",
        30,
    )
    outputs["route"] = wait_guest_command(
        dest,
        "ROUTE",
        "netstat -rn | awk '$1==\"default\"&&$2==\"10.0.5.1\"{ok=1}END{exit !ok}'",
        30,
    )
    outputs["nfs"] = wait_guest_command(
        dest,
        "NFS",
        "mount -v | grep -F '10.0.5.1:/export/solaris on /mnt/nfs type nfs' | grep -F 'vers=3/proto=tcp/rsize=8192/wsize=8192'",
        30,
    )
    outputs["marker"] = wait_guest_command(
        dest,
        "MARKER",
        'm=$(ls -t /var/adm/niagara/devtools-smoke.*.PASS 2>/dev/null|head -1); echo SMOKE_MARKER:$m; test -n "$m"',
        30,
    )
    marker_match = re.search(r"SMOKE_MARKER:(\S+\.PASS)", outputs["marker"])
    if not marker_match:
        fail("timestamped smoke PASS marker path was not reported")
    marker_path = marker_match.group(1)
    marker_stamp = re.search(r"devtools-smoke\.(\d{8}T\d{6}Z)\.PASS$", marker_path)
    if not marker_stamp or marker_stamp.group(1) < str(state["armed_compact_utc"]):
        fail(f"smoke PASS marker predates arm point: {marker_path}")
    outputs["marker_read"] = wait_guest_command(dest, "MARKER_READ", f"cat {marker_path}", 30)
    if "PASS " not in outputs["marker_read"]:
        fail("smoke PASS marker content is not PASS")
    outputs["smoke"] = wait_guest_command(
        dest,
        "SMOKE",
        "/usr/bin/timeout -k 15 900 /opt/niag/bin/oi-devtools-smoke",
        930,
    )
    for marker in (
        "DEVTOOLS_DURABLE_WRAPPERS_PASS",
        "PPP_NFS_CANARY_PASS",
        "COMPILE_LINK_RUN_PASS",
    ):
        if marker not in outputs["smoke"]:
            fail(f"oi-devtools-smoke missing marker: {marker}")

    outcome = {
        "status": "COLD_REBOOT_ACCEPTANCE_PASS",
        "finished_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "supervisor_count": 1,
        "smoke_marker": marker_path,
        "checks": sorted(outputs),
    }
    write_json(dest / "postlogin.json", outcome)
    return outcome


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("preflight", help="read-only current-state preflight")
    arm_parser = sub.add_parser("arm", help="create an evidence anchor; never reboots")
    arm_parser.add_argument("run_id")
    observe_parser = sub.add_parser("observe", help="observe new console bytes only")
    observe_parser.add_argument("run_id")
    observe_parser.add_argument("--timeout", type=int, default=1800)
    post_parser = sub.add_parser("postlogin", help="run fixed gates at an existing root prompt")
    post_parser.add_argument("run_id")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.action == "preflight":
            result = preflight()
        elif args.action == "arm":
            result = arm(args.run_id)
        elif args.action == "observe":
            result = observe(args.run_id, args.timeout)
        else:
            result = postlogin(args.run_id)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except GateError as exc:
        print(f"COLD_REBOOT_GATE_FAIL: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
