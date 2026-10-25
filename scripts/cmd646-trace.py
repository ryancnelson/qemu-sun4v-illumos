#!/usr/bin/env python3
"""Bounded, opt-in regular-file trace observer. Never starts a container."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
import sys

EVENTS = ("ide_ioport_read", "ide_ioport_write", "ide_status_read",
          "bmdma_read_cmd646", "bmdma_write_cmd646", "pci_cfg_read", "pci_cfg_write")
CAP = 64 * 1024 * 1024
DEADLINE = 2100
POLL = 1
ERROR = False
STOP_REQUESTED = False
PREFIX = re.compile(r"^\d+@\d+\.\d+:([a-z0-9_]+) ")
PAYLOAD = {
    "pci_cfg_read": r"\S+ [0-9a-f]+:[0-9a-f]+\.[0-9a-f]+ @0x[0-9a-f]+ -> 0x[0-9a-f]+",
    "pci_cfg_write": r"\S+ [0-9a-f]+:[0-9a-f]+\.[0-9a-f]+ @0x[0-9a-f]+ <- 0x[0-9a-f]+",
    "bmdma_read_cmd646": r"bmdma: readb 0x[0-9a-f]+ : 0x[0-9a-f]+",
    "bmdma_write_cmd646": r"bmdma: writeb 0x[0-9a-f]+ : 0x[0-9a-f]+",
    "ide_ioport_read": r"IDE PIO rd @ 0x[0-9a-f]+ \([^)]+\); val 0x[0-9a-f]+; bus (?:0x[0-9a-f]+|\(nil\)) IDEState (?:0x[0-9a-f]+|\(nil\))",
    "ide_ioport_write": r"IDE PIO wr @ 0x[0-9a-f]+ \([^)]+\); val 0x[0-9a-f]+; bus (?:0x[0-9a-f]+|\(nil\)) IDEState (?:0x[0-9a-f]+|\(nil\))",
    "ide_status_read": r"IDE PIO rd @ 0x[0-9a-f]+ \(Alt Status\); val 0x[0-9a-f]+; bus (?:0x[0-9a-f]+|\(nil\)); IDEState (?:0x[0-9a-f]+|\(nil\))",
}

def failure(root, reason, **details):
    global ERROR
    ERROR = True
    # The first trace failure remains authoritative across finalization.
    path = root / "trace-incomplete.json"
    try:
        with path.open("x") as out:
            json.dump(dict(status="INCOMPLETE", reason=reason, **details), out)
            out.write("\n")
    except FileExistsError:
        pass
    except OSError as exc:
        print("TRACE_INCOMPLETE: evidence write failed: %s" % exc, file=sys.stderr)

def save(root, name, data):
    try:
        (root / name).write_text(data)
    except OSError as exc:
        failure(root, "EVIDENCE_ERROR", detail=str(exc))

def stop_owned(root, cid):
    if not re.fullmatch(r"[0-9a-f]{64}", cid):
        failure(root, "INVALID_OWNER"); return False
    def call(label, args):
        try:
            result = subprocess.run(["docker", *args], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=10, text=True)
            save(root, "trace-"+label+".log", result.stdout)
            save(root, "trace-"+label+".exit", str(result.returncode)+"\n")
            if result.returncode:
                failure(root, "STOP_OR_INSPECT_ERROR", operation=label, exit_code=result.returncode)
                return None
            return result.stdout
        except (OSError, subprocess.TimeoutExpired) as exc:
            failure(root, "STOP_ERROR", detail=str(exc))
            save(root, "trace-"+label+".error", str(exc)+"\n")
            return None
    def stopped(raw):
        try:
            value = json.loads(raw)
            return len(value)==1 and value[0]["Id"]==cid and value[0]["State"]["Running"] is False
        except (ValueError, TypeError, KeyError):
            return False
    call("before", ["inspect", cid])
    call("stop", ["stop", "-t", "5", cid])
    if stopped(call("after", ["inspect", cid])):
        return True
    failure(root, "STOP_UNVERIFIED")
    call("kill", ["kill", cid])
    if stopped(call("after-kill", ["inspect", cid])):
        return True
    failure(root, "STOP_UNRESOLVED")
    return False

def watch(root, cid):
    if not re.fullmatch(r"[0-9a-f]{64}", cid):
        failure(root, "INVALID_OWNER"); return 1
    start = time.monotonic()
    try:
        while not STOP_REQUESTED:
            elapsed = time.monotonic()-start
            path = root / "cmd646.trace"
            size = path.stat().st_size if path.exists() else 0
            reason = ("CAP" if size >= CAP else "DEADLINE" if elapsed >= DEADLINE
                      else "MISSING_TRACE" if elapsed >= 30 and size == 0 else None)
            if reason:
                failure(root, reason, bytes=size, elapsed=elapsed,
                        threshold=CAP, poll_seconds=POLL,
                        overshoot_bytes=max(0, size-CAP))
                stop_owned(root, cid)
                return 1
            time.sleep(POLL)
        return 0
    except Exception as exc:
        failure(root, "OBSERVER_ERROR", detail=str(exc))
        stop_owned(root, cid)
        return 1

def finish(root):
    path = root / "cmd646.trace"
    try:
        if not path.is_file() or path.is_symlink():
            raise ValueError("missing/nonregular trace")
        size = path.stat().st_size
        if size >= CAP:
            failure(root, "CAP", bytes=size, overshoot_bytes=max(0,size-CAP))
            return 1
        count = 0
        with path.open("r", encoding="utf-8", errors="strict") as inp:
            for line in inp:
                m = PREFIX.match(line)
                if (not line.endswith("\n") or not m or m[1] not in EVENTS or
                    not re.fullmatch(PAYLOAD[m[1]], line[m.end():].rstrip("\n"))):
                    raise ValueError("invalid log-backend record at line %d" % (count+1))
                count += 1
        if count == 0:
            raise ValueError("empty trace")
        (root / "trace-summary.json").write_text(json.dumps(dict(
            records=count, bytes=size, threshold=CAP, poll_seconds=POLL,
            overshoot_bytes=max(0,size-CAP)))+"\n")
    except (OSError, UnicodeError, ValueError) as exc:
        failure(root, "INVALID_TRACE", detail=str(exc))
    return 1 if ERROR or (root / "trace-incomplete.json").exists() else 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("watch", "finish", "stop"))
    parser.add_argument("root", type=Path)
    parser.add_argument("cid", nargs="?")
    args = parser.parse_args()
    if args.mode == "watch":
        def request_stop(signum, frame):
            global STOP_REQUESTED
            STOP_REQUESTED = True
        signal.signal(signal.SIGTERM, request_stop)
        raise SystemExit(watch(args.root, args.cid or ""))
    if args.mode == "stop":
        stopped = stop_owned(args.root, args.cid or "")
        raise SystemExit(0 if stopped and not ERROR else 1)
    raise SystemExit(finish(args.root))
