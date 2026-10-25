#!/usr/bin/env python3
"""Disk-only operator cold boot. Never creates a disk; never declares boot PASS."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shlex
import signal
import stat
import struct
import subprocess
import sys
import time
import uuid

IMAGE = "sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f"
FW = "0fe3be7270fe52e64085c690b05474e0063f9d184c35a3dd7d15406a15e38343"
QEMU = "1d5d578dd82a402be1a56d1eb52b29d59e50e7c4674a571a0ac4e3505e3e5abe"
DOCKER = ["docker", "--host", "unix:///var/run/docker.sock"]
LIMIT = 64 * 1024 * 1024

def call(args, timeout=30):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout).stdout.strip()

def digest(path):
    with open(path, "rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()

def regular(path):
    p = Path(path)
    if not p.is_absolute() or any(c in str(p) for c in ",\r\n") or p.resolve() != p:
        raise ValueError("require canonical absolute path without symlinks/comma/newline")
    if not stat.S_ISREG(p.stat().st_mode):
        raise ValueError("not an existing regular file")
    return p

def identity(p):
    s = p.stat()
    return f"{s.st_dev}:{s.st_ino}:{s.st_size}"

def qcow_header(p):
    with p.open("rb") as f:
        h = f.read(104)
    if len(h) < 104 or h[:4] != b"QFI\xfb":
        raise ValueError("existing qcow2 required")
    version, backing, backing_len = struct.unpack_from(">IQI", h, 4)
    if version not in (2, 3) or backing or backing_len:
        raise ValueError("unsupported qcow2 or backing chain")
    if struct.unpack_from(">Q", h, 24)[0] != 8 * 1024**3:
        raise ValueError("expected installed 8 GiB target")
    if version == 3 and struct.unpack_from(">Q", h, 72)[0]:
        raise ValueError("dirty/corrupt/unsupported qcow2 incompatible features")

def no_openers(p, proc=Path("/proc")):
    """Refuse even readers; permission/inspection errors fail closed. No process signals."""
    target = p.stat()
    for process in proc.iterdir():
        if not process.name.isdigit() or int(process.name) == os.getpid():
            continue
        try:
            for fd in (process / "fd").iterdir():
                try:
                    s = fd.stat()
                except FileNotFoundError:
                    continue  # descriptor closed or process exited
                if (s.st_dev, s.st_ino) == (target.st_dev, target.st_ino):
                    raise ValueError(f"disk open by PID {process.name}, fd {fd.name}")
        except FileNotFoundError:
            if process.exists():
                raise ValueError("cannot establish complete process fd visibility")

def host_check():
    if sys.platform != "linux" or os.geteuid() != 0:
        raise ValueError("requires root on local Linux Docker host, not client/VM")
    if Path("/proc/self/ns/pid").readlink() != Path("/proc/1/ns/pid").readlink():
        raise ValueError("PID namespace mismatch")
    status = Path("/proc/self/status").read_text()
    ns = re.search(r"^NSpid:\s*(.*)$", status, re.M)
    if not ns or len(ns[1].split()) != 1:
        raise ValueError("nested/unknown PID namespace")
    if any(os.environ.get(k) for k in ("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH")):
        raise ValueError("Docker environment override forbidden")
    # host pid 1 must be visible; this is an operator host contract, not hostile isolation proof.
    if Path("/proc/1/comm").read_text().strip() not in ("systemd", "init"):
        raise ValueError("cannot establish host PID namespace")
    mounts = [line.split() for line in Path("/proc/mounts").read_text().splitlines()]
    proc_mount = [m for m in mounts if m[1] == "/proc" and m[2] == "proc"]
    if len(proc_mount) != 1 or any(o.startswith("hidepid=") and o not in ("hidepid=0", "hidepid=off")
                                 for o in proc_mount[0][3].split(",")):
        raise ValueError("hidden/unknown proc visibility")

def qemu_argv(keep_running=False):
    args = ["/usr/bin/qemu-system-sparc64", "-M", "sun4u", "-m", "1088", "-smp", "1",
            "-boot", "c", "-vga", "none", "-bios", "/firmware.bin",
            "-drive", "file=/installed.qcow2,if=ide,index=0,format=qcow2,file.locking=on",
            "-global", "cmd646-ide.x-b134-status-compat=on",
            "-prom-env", "input-device=ttya", "-prom-env", "output-device=ttya",
            "-prom-env", "auto-boot?=false", "-display", "none",
            "-monitor", "unix:/run/sun4u/monitor.sock,server=on,wait=off",
            "-gdb", "unix:/run/sun4u/debug.sock,server=on,wait=off", "-serial", "stdio"]
    if keep_running:
        args[-2:] = ["-chardev", "socket,id=owner_serial,path=/run/sun4u/serial.sock,server=on,wait=off,logfile=/run/sun4u/serial.log,logappend=on",
                     "-serial", "chardev:owner_serial"]
    return args

def create_argv(disk, firmware, binary, evidence, token, boot_id, disk_id, keep_running=False):
    # All substitutions quoted; no user-provided shell command/extra QEMU flags.
    checks = ["set -eu", f"test \"$(cat /proc/sys/kernel/random/boot_id)\" = {shlex.quote(boot_id)}",
              f"test \"$(stat -c '%d:%i:%s' /installed.qcow2)\" = {shlex.quote(disk_id)}",
              f"echo '{FW}  /firmware.bin' | sha256sum -c -",
              f"echo '{QEMU}  /usr/bin/qemu-system-sparc64' | sha256sum -c -",
              "/usr/bin/qemu-system-sparc64 --version",
              "exec " + shlex.join(qemu_argv(keep_running))]
    args = DOCKER + ["create", "--pull=never", "--name", "sun4u-coldboot-" + token,
                     "--label", "sun4u.coldboot.owner=" + token, "--cidfile", str(evidence / "owned.cid"),
                     "--cpus", "1", "--memory", "2048m", "--network", "none", "-i"]
    for src, dst, ro in [(disk, "/installed.qcow2", False), (firmware, "/firmware.bin", True),
                         (binary, "/usr/bin/qemu-system-sparc64", True), (evidence, "/run/sun4u", False)]:
        args += ["--mount", f"type=bind,src={src},dst={dst}" + (",readonly" if ro else "")]
    if keep_running:
        args.remove("-i")  # Serial ownership is the QEMU Unix socket, never Docker stdin.
        args += ["--log-driver", "json-file", "--log-opt", "max-size=64m", "--log-opt", "max-file=1"]
    return args + ["--entrypoint", "/bin/sh", IMAGE, "-c", "\n".join(checks)]

def owned(evidence, token):
    cidfile = evidence / "owned.cid"
    if not cidfile.exists():
        return None
    cid = cidfile.read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{64}", cid):
        raise ValueError("invalid owned cid")
    obj = json.loads(call(DOCKER + ["inspect", cid]))[0]
    if obj["Id"] != cid or obj["Config"]["Labels"].get("sun4u.coldboot.owner") != token:
        raise ValueError("container ownership mismatch")
    return cid, obj

def stop_owned(evidence, token):
    item = owned(evidence, token)
    if item is None:
        return {"created": False}
    cid, obj = item
    errors = []
    if obj["State"]["Running"]:
        try:
            call(DOCKER + ["stop", "--time", "10", cid], 20)
        except Exception as e:
            errors.append(str(e))
        # Verify convergence, never assume docker stop success means stopped.
        _, obj = owned(evidence, token)
        if obj["State"]["Running"]:
            try:
                call(DOCKER + ["kill", cid], 10)
            except Exception as e:
                errors.append(str(e))
            _, obj = owned(evidence, token)
    return {"created": True, "inspect": obj, "errors": errors,
            "stopped": not obj["State"]["Running"]}

def session(cid, console, deadline):
    # Raw stdin is owned by operator; no installation/menu keystrokes or guessed alias.
    proc = subprocess.Popen(DOCKER + ["start", "-a", "-i", cid], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    end = time.monotonic() + deadline
    size = 0
    try:
        with console.open("xb", buffering=0) as log:
            while time.monotonic() < end:
                for key, _ in sel.select(min(1, max(0, end - time.monotonic()))):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        code = proc.wait(timeout=5)
                        return {"outcome": "UNVERIFIED_SESSION_END" if code == 0 else "CLIENT_ERROR_INCOMPLETE",
                                "client_exit": code}
                    log.write(data)
                    size += len(data)
                    if size >= LIMIT:
                        return {"outcome": "CONSOLE_CAP_INCOMPLETE", "bytes": size}
                # Console retained to file; operator can tail it separately.
            return {"outcome": "DEADLINE_INCOMPLETE"}
    finally:
        sel.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)

def main():
    if sys.argv[1:2] == ["reconcile"]:
        import retention
        return retention.cli(sys.modules[__name__], sys.argv[2:])
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("disk", "firmware", "qemu", "evidence"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--offline-clean-shutdown-confirmed", action="store_true", required=True)
    parser.add_argument("--exclusive-host-confirmed", action="store_true", required=True,
                        help="operator excludes concurrent disk/path changes and runs on daemon host")
    parser.add_argument("--deadline", type=int, default=2100)
    parser.add_argument("--keep-running", action="store_true",
                        help="owner accepts persistent guest on ALL exits; Unix serial socket/logfile, never automatic stop")
    a = parser.parse_args()
    evidence = Path(a.evidence)
    if not evidence.is_absolute() or evidence.resolve() != evidence or any(c in str(evidence) for c in ",\r\n"):
        parser.error("evidence bind requires canonical absolute path without symlinks/comma/newline")
    evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
    token = uuid.uuid4().hex
    result = {"outcome": "PREFLIGHT_INCOMPLETE", "owner": token}
    lock = None
    def cancel(sig, frame):
        raise KeyboardInterrupt(f"signal {sig}")
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, cancel)
    try:
        if not 1 <= a.deadline <= 2100:
            raise ValueError("deadline must be 1..2100")
        host_check()
        disk, fw, binary = map(regular, (a.disk, a.firmware, a.qemu))
        # Sidecar only, never open disk for writing/create. Native QEMU lock closes QEMU-writer race.
        lock = os.fdopen(os.open(str(disk) + ".coldboot.lock",
                         os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600), "a")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        no_openers(disk)
        qcow_header(disk)
        if call(["stat", "-f", "-c", "%T", str(disk)]) not in ("ext2/ext3", "xfs", "btrfs"):
            raise ValueError("unreviewed filesystem locking semantics")
        if digest(fw) != FW or digest(binary) != QEMU or not os.access(binary, os.X_OK):
            raise ValueError("firmware/QEMU pin or executable mismatch")
        image = json.loads(call(DOCKER + ["image", "inspect", IMAGE]))[0]
        if image["Id"] != IMAGE:
            raise ValueError("image pin mismatch")
        disk_id = identity(disk)
        boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        args = create_argv(disk, fw, binary, evidence, token, boot_id, disk_id, a.keep_running)
        (evidence / "preflight.json").write_text(json.dumps({"argv": args, "disk": str(disk),
            "disk_identity": disk_id, "boot_id": boot_id, "firmware_sha256": FW,
            "qemu_sha256": QEMU, "image": IMAGE, "operator_clean_shutdown": True}, indent=2))
        no_openers(disk)
        if identity(disk) != disk_id:
            raise ValueError("disk identity changed during preflight")
        call(args)
        cid, _ = owned(evidence, token)
        no_openers(disk)
        if identity(disk) != disk_id:
            raise ValueError("disk identity changed before start")
        result.update(started_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), cid=cid)
        (evidence / "start.json").write_text(json.dumps(result, indent=2))
        if a.keep_running:
            import retention
            retention.prepare(sys.modules[__name__], evidence, token)
            # Record durable identity BEFORE start. A timed-out start is ambiguous:
            # retain and reconcile, never compensate by stopping a possibly mounted guest.
            call(DOCKER + ["start", cid])
            result.update(retention.watch(sys.modules[__name__], evidence, token, a.deadline))
        else:
            result.update(session(cid, evidence / "console.log", a.deadline))
    except BaseException as e:
        result.update(outcome="CANCELLED_INCOMPLETE" if isinstance(e, KeyboardInterrupt) else "ERROR_INCOMPLETE",
                      error=repr(e))
    finally:
        # Evidence-write failure cannot skip exact-owner cleanup. Ignore repeat cancellation during bounded stop.
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, signal.SIG_IGN)
        try:
            if a.keep_running:
                result["observation_outcome"] = result["outcome"]
                result["outcome"] = "RETAINED_UNVERIFIED"
                result["cleanup"] = {"policy": "NO_AUTOMATIC_STOP", "reconciliation_required": True}
                import retention
                if (evidence / "retention.json").exists():
                    result["retention"] = retention.reconcile(sys.modules[__name__], evidence, token)
                else:
                    result["outcome"] = "RETENTION_PREFLIGHT_INCOMPLETE"
            else:
                result["cleanup"] = stop_owned(evidence, token)
                if result["cleanup"].get("created") and (not result["cleanup"].get("stopped") or result["cleanup"].get("errors")):
                    result["outcome"] = "STOP_INCOMPLETE"
        except BaseException as e:
            result.update(outcome="RETENTION_RECONCILE_INCOMPLETE" if a.keep_running else "STOP_INCOMPLETE", cleanup_error=repr(e))
        if lock:
            lock.close()
        try:
            (evidence / "outcome.json").write_text(json.dumps(result, indent=2))
        finally:
            print(json.dumps(result), flush=True)
    return 2  # human review required; there is intentionally no automatic PASS

if __name__ == "__main__":
    sys.exit(main())
