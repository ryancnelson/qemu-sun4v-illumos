#!/usr/bin/env python3
"""Classify one managed Niagara QEMU from host-side evidence.

The primary result is a stable enum on stdout.  --json includes the evidence
used to reach it.  Repeated invocations share a small state file so that
"quiet" can be distinguished from "not progressing" without guessing from a
single CPU sample.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


HEALTHY = {"PROGRESSING", "READY", "HEALTHY_IDLE", "STOPPED_EXPECTED"}
DEGRADED = {
    "OBSERVING",
    "WAITING_INPUT",
    "WAITING_DEGRADED",
    "PAUSED",
    "STALLED",
    "SPIN_SUSPECTED",
    "HOST_IO_BLOCKED",
    "MONITOR_UNRESPONSIVE",
    "UNEXPECTED_RUNNING",
    "UNKNOWN",
}

STAGES = (
    ("single-user", re.compile(r"SINGLE USER MODE", re.I)),
    ("login", re.compile(r"(?:^|\n)[^\n]{0,50}login:\s*$", re.I)),
    ("configuring-devices", re.compile(r"Configuring devices\.", re.I)),
    ("installer-keyboard", re.compile(r"To select the keyboard layout", re.I)),
    ("hostname", re.compile(r"Hostname:\s*\S+", re.I)),
    ("root-mounted", re.compile(r"root on \S+ fstype", re.I)),
    ("hsimd-attached", re.compile(r"hsimd\d+: hsimd_attach", re.I)),
    ("kernel", re.compile(r"SunOS Release|Copyright .* Sun Microsystems", re.I)),
    ("obp", re.compile(r"OpenBoot|(?:^|\n)ok\s", re.I)),
)

PROMPTS = re.compile(
    r"To select the keyboard layout.*:\s*$|"
    r"Enter physical name of root device.*:\s*$|"
    r"(?:^|\n)[^\n]{0,50}login:\s*$|"
    r"(?:^|\n)Password:\s*$|"
    r"(?:^|\n)ok\s*$|"
    r"(?:^|\n)[^\n]*[#>$]\s*$",
    re.I | re.S,
)


def command(argv: list[str], *, input_text: str | None = None, timeout: int = 3) -> tuple[int, str]:
    try:
        cp = subprocess.run(
            argv,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
        return cp.returncode, cp.stdout
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 124, str(exc)


def proc_sample(pid: int) -> dict[str, object] | None:
    base = Path(f"/proc/{pid}")
    try:
        fields = (base / "stat").read_text().split()
        io_values: dict[str, int] = {}
        for line in (base / "io").read_text().splitlines():
            key, value = line.split(":", 1)
            io_values[key] = int(value.strip())
        try:
            wchan = (base / "wchan").read_text().strip()
        except OSError:
            wchan = "unknown"
        return {
            "state": fields[2],
            "cpu_ticks": int(fields[13]) + int(fields[14]),
            "read_bytes": io_values.get("read_bytes", 0),
            "write_bytes": io_values.get("write_bytes", 0),
            "wchan": wchan,
        }
    except (OSError, ValueError, IndexError):
        return None


def console_text(
    log: Path | None, tmux_pane: str | None, tmux_user: str | None
) -> tuple[str, float | None]:
    if log:
        try:
            data = log.read_bytes()
            return data[-256_000:].decode("utf-8", "replace"), log.stat().st_mtime
        except OSError:
            pass
    if tmux_pane:
        argv = ["tmux", "capture-pane", "-ep", "-t", tmux_pane, "-S", "-2000"]
        if tmux_user and tmux_user != os.environ.get("USER"):
            argv = ["sudo", "-n", "-u", tmux_user, *argv]
        rc, output = command(argv)
        if rc == 0:
            return output, None
    return "", None


def current_epoch(text: str) -> str:
    starts = [m.start() for m in re.finditer(r"OpenBoot|SunOS Release", text, re.I)]
    return text[starts[-1] :] if starts else text


def latest_stage(text: str) -> tuple[str, int]:
    best = ("unknown", -1)
    for name, pattern in STAGES:
        matches = list(pattern.finditer(text))
        if matches and matches[-1].start() > best[1]:
            best = (name, matches[-1].start())
    return best


def monitor_status(path: Path | None) -> tuple[bool, str]:
    if not path or not path.exists():
        return False, "missing"
    rc, output = command(
        ["socat", "-", f"UNIX-CONNECT:{path}"], input_text="info status\n", timeout=2
    )
    clean = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", output).strip()
    if rc != 0:
        return False, clean or f"socat rc={rc}"
    match = re.search(r"VM status:\s*(\w+)", clean, re.I)
    return True, match.group(1).lower() if match else "responsive"


def load_state(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: Path, value: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True) + "\n")
    os.replace(temporary, path)


def classify(args: argparse.Namespace) -> dict[str, object]:
    now = time.time()
    pid = args.pid
    if pid is None and args.run_dir:
        try:
            pid = int((args.run_dir / "qemu.pid").read_text().strip())
        except (OSError, ValueError):
            pid = None

    if args.desired == "stopped":
        status = "UNEXPECTED_RUNNING" if pid and proc_sample(pid) else "STOPPED_EXPECTED"
        return {"status": status, "desired": args.desired, "pid": pid, "reason": "desired state comparison"}
    if pid is None or proc_sample(pid) is None:
        return {"status": "CRASHED", "desired": args.desired, "pid": pid, "reason": "QEMU process absent"}

    first = proc_sample(pid)
    text1, mtime1 = console_text(args.console_log, args.tmux_pane, args.tmux_user)
    time.sleep(args.sample_seconds)
    second = proc_sample(pid)
    text2, mtime2 = console_text(args.console_log, args.tmux_pane, args.tmux_user)
    if second is None:
        return {"status": "CRASHED", "desired": args.desired, "pid": pid, "reason": "QEMU exited during sample"}

    assert first is not None
    hz = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
    cpu_pct = 100.0 * (int(second["cpu_ticks"]) - int(first["cpu_ticks"])) / hz / args.sample_seconds
    io_delta = (
        int(second["read_bytes"]) - int(first["read_bytes"])
        + int(second["write_bytes"]) - int(first["write_bytes"])
    )
    epoch = current_epoch(text2)
    stage, _ = latest_stage(epoch)
    signature = hashlib.sha256(epoch.encode()).hexdigest()
    state = load_state(args.state_file)
    previous_stage = str(state.get("stage", "unknown"))
    previous_signature = str(state.get("console_signature", ""))
    stage_since = float(state.get("stage_since", now)) if previous_stage == stage else now
    console_since = float(state.get("console_since", now)) if previous_signature == signature else now
    console_changed = text1 != text2 or previous_signature != signature
    stage_changed = previous_stage not in ("", "unknown") and previous_stage != stage
    stage_age = now - stage_since
    console_age = now - console_since
    monitor_ok, monitor_state = monitor_status(args.monitor)

    maintenance = bool(re.search(r"transitioned to maintenance|Requesting System Maintenance Mode", epoch, re.I))
    guest_panic = bool(re.search(r"panic\[cpu|vfs_mountroot: cannot mount root", epoch, re.I))
    after_panic_progress = False
    panic_pos = max(epoch.rfind("panic[cpu"), epoch.rfind("vfs_mountroot: cannot mount root"))
    if panic_pos >= 0:
        _, progress_pos = latest_stage(epoch[panic_pos + 1 :])
        after_panic_progress = progress_pos >= 0
    waiting = bool(PROMPTS.search(epoch[-5000:])) or stage == "single-user"

    if str(second["state"]) == "T" or monitor_state == "paused":
        status, reason = "PAUSED", "host process or QEMU monitor reports paused"
    elif guest_panic and not after_panic_progress:
        status, reason = "GUEST_CRASHED", "latest boot epoch ends in guest panic"
    elif maintenance and stage == "single-user":
        status, reason = "WAITING_DEGRADED", "single-user mode followed a service maintenance transition"
    elif waiting:
        status, reason = "WAITING_INPUT", f"recognized prompt at stage {stage}"
    elif str(first["state"]) == "D" and str(second["state"]) == "D":
        status, reason = "HOST_IO_BLOCKED", f"QEMU remained in D state; wchan={second['wchan']}"
    elif not monitor_ok and args.monitor:
        status, reason = "MONITOR_UNRESPONSIVE", f"monitor: {monitor_state}"
    elif stage_changed:
        status, reason = "PROGRESSING", f"semantic stage advanced {previous_stage} -> {stage}"
    elif previous_signature == "":
        status, reason = "OBSERVING", "first observation establishes progress baseline"
    elif stage_age >= args.stall_seconds:
        if cpu_pct >= args.spin_cpu and io_delta <= args.quiet_io_bytes:
            status, reason = "SPIN_SUSPECTED", "stage stale with sustained CPU and negligible host disk I/O"
        else:
            status, reason = "STALLED", "semantic stage exceeded its progress budget"
    elif console_changed:
        status, reason = "PROGRESSING", "console changed within current semantic stage"
    elif args.expected == stage:
        status, reason = "READY", f"expected stage {stage} reached"
    else:
        status, reason = "OBSERVING", "quiet but still inside the stage progress budget"

    save_state(
        args.state_file,
        {
            "observed_at": now,
            "stage": stage,
            "stage_since": stage_since,
            "console_signature": signature,
            "console_since": console_since,
            "status": status,
        },
    )
    return {
        "status": status,
        "desired": args.desired,
        "expected": args.expected,
        "pid": pid,
        "stage": stage,
        "stage_age_seconds": round(stage_age, 1),
        "console_age_seconds": round(console_age, 1),
        "cpu_percent_sample": round(cpu_pct, 1),
        "host_io_bytes_sample": io_delta,
        "process_state": second["state"],
        "wchan": second["wchan"],
        "monitor": monitor_state,
        "console_mtime": mtime2 or mtime1,
        "reason": reason,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--monitor", type=Path)
    parser.add_argument("--console-log", type=Path)
    parser.add_argument("--tmux-pane")
    parser.add_argument("--tmux-user", help="owner of the tmux server when probing as root")
    parser.add_argument("--desired", choices=("running", "stopped", "preserved"), default="running")
    parser.add_argument("--expected", default="any")
    parser.add_argument("--sample-seconds", type=float, default=5.0)
    parser.add_argument("--stall-seconds", type=float, default=600.0)
    parser.add_argument("--spin-cpu", type=float, default=90.0)
    parser.add_argument("--quiet-io-bytes", type=int, default=4096)
    parser.add_argument("--state-file", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.run_dir:
        args.monitor = args.monitor or args.run_dir / "monitor.sock"
        args.console_log = args.console_log or (args.run_dir / "console.log")
        args.state_file = args.state_file or args.run_dir / "classifier-state.json"
    if args.state_file is None:
        parser.error("--state-file is required without --run-dir")
    if args.pid is None and args.run_dir is None:
        parser.error("one of --pid or --run-dir is required")

    result = classify(args)
    print(json.dumps(result, sort_keys=True) if args.json else result["status"])
    status = str(result["status"])
    if status in HEALTHY:
        return 0
    if status in DEGRADED:
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
