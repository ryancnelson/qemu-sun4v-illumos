"""Opt-in retention. Never stops, kills, removes, or declares a guest PASS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import stat
import time


def durable(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("x") as f:
        json.dump(value, f, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temporary, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def fingerprint(obj):
    fields = json.loads(json.dumps({k: obj[k] for k in ("Id", "Image", "Config", "HostConfig", "Mounts")}))
    # Exact native fixture: Docker changes false -> null on start. Both mean
    # no OOM-killer disable request. True and every other field remain distinct.
    host = fields["HostConfig"]
    if "OomKillDisable" in host and (host["OomKillDisable"] is False or host["OomKillDisable"] is None):
        host["OomKillDisable"] = False
    return fields


def prepare(c, evidence, token):
    cid, obj = c.owned(evidence, token)
    log = obj["HostConfig"]["LogConfig"]
    if (obj["State"]["Running"] or obj["Image"] != c.IMAGE
            or log != {"Type": "json-file", "Config": {"max-size": "64m", "max-file": "1"}}
            or obj["Config"]["OpenStdin"] or obj["Config"]["StdinOnce"]
            or obj["Config"]["AttachStdin"] or obj["Config"]["Tty"]):
        raise ValueError("retention configuration mismatch")
    for name in ("owned.cid", "preflight.json"):
        with (evidence / name).open("rb") as f:
            os.fsync(f.fileno())
    record = {"cid": cid, "owner": token, "transport": "qemu-unix-serial-v1",
              "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
              "preflight_sha256": hashlib.sha256((evidence / "preflight.json").read_bytes()).hexdigest(),
              "fingerprint": fingerprint(obj),
              "policy": "retain on all controller exits; operator clean shutdown required",
              "console": "QEMU /run/sun4u/serial.sock and persistent serial.log; Docker logs are startup diagnostics only"}
    durable(evidence / "retention.json", record)
    return cid


def inspect_retained(c, evidence, token):
    record = json.loads((evidence / "retention.json").read_text())
    if record.get("transport") != "qemu-unix-serial-v1":
        raise ValueError("retention transport mismatch")
    if record["owner"] != token or record["boot_id"] != Path("/proc/sys/kernel/random/boot_id").read_text().strip():
        raise ValueError("retention owner/host boot mismatch")
    if hashlib.sha256((evidence / "preflight.json").read_bytes()).hexdigest() != record["preflight_sha256"]:
        raise ValueError("preflight changed")
    item = c.owned(evidence, token)
    if item is None:
        raise ValueError("retained CID missing; no name fallback")
    cid, obj = item
    if cid != record["cid"] or fingerprint(obj) != record["fingerprint"]:
        raise ValueError("retained identity/configuration changed")
    return cid, obj


def watch(c, evidence, token, deadline):
    end = time.monotonic() + deadline
    while time.monotonic() < end:
        _, obj = inspect_retained(c, evidence, token)
        if not obj["State"]["Running"]:
            return {"outcome": "RETAINED_EXIT_UNVERIFIED", "inspect": obj}
        time.sleep(min(1, max(0, end - time.monotonic())))
    return {"outcome": "RETAINED_DEADLINE_UNVERIFIED"}


def reconcile(c, evidence, token):
    """Read-only Docker actions. Export to regular files; no attached client/PIPE."""
    cid, obj = inspect_retained(c, evidence, token)
    stamp = str(time.time_ns())
    result = {"outcome": "RETAINED_RUNNING_UNVERIFIED" if obj["State"]["Running"] else "RETAINED_EXIT_UNVERIFIED",
              "inspect": obj, "console_completeness": "UNVERIFIED_QEMU_LOGFILE",
              "serial_log": str(evidence / "serial.log"), "serial_socket": str(evidence / "serial.sock")}
    try:
        info = (evidence / "serial.log").lstat()
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("serial.log must be a regular file, not a symlink")
        result["serial_bytes_observed"] = info.st_size
    except (OSError, ValueError) as exc:
        result.update(outcome="RETAINED_SERIAL_LOG_INCOMPLETE", serial_error=repr(exc))
    with (evidence / ("docker-" + stamp + ".log")).open("xb") as out, (evidence / ("logs-" + stamp + ".stderr")).open("xb") as err:
        try:
            r = subprocess.run(c.DOCKER + ["logs", "--timestamps", cid], stdout=out, stderr=err, timeout=30)
            result["logs_exit"] = r.returncode
            if r.returncode:
                result["outcome"] = "RETAINED_LOG_ERROR_INCOMPLETE"
        except (OSError, subprocess.TimeoutExpired) as exc:
            result.update(outcome="RETAINED_LOG_ERROR_INCOMPLETE", error=repr(exc))
    # Recheck identity/state after export. Running exports are explicitly nonfinal.
    _, result["inspect_after"] = inspect_retained(c, evidence, token)
    durable(evidence / ("reconcile-" + stamp + ".json"), result)
    return result


def cli(c, argv):
    p = argparse.ArgumentParser(description="Inspect/export retained exact owner; never stop or PASS")
    p.add_argument("--evidence", required=True)
    p.add_argument("--owner", required=True)
    a = p.parse_args(argv)
    c.host_check()
    evidence = Path(a.evidence)
    if not evidence.is_absolute() or evidence.resolve() != evidence:
        raise ValueError("canonical absolute evidence path required")
    print(json.dumps(reconcile(c, evidence, a.owner), indent=2))
    return 2
