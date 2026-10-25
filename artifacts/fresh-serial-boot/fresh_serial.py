"""Fresh-launch designated first client under an explicit trusted-host contract.

No existing-guest CLI. Never stops a guest. Lock coordinates cooperating tools;
it cannot exclude privileged/manual bypass or another client ignoring ownership.
"""
import fcntl
import json
import os
from pathlib import Path
import socket
import stat
import time
import retention
from boot_protocol import ReplayDriver, FW, observations


class Lease:
    def __init__(self, evidence, owner, file):
        self.evidence, self.owner, self.file = evidence, owner, file

    def close(self):
        self.file.close()


def acquire(evidence, owner):
    """Called before container creation, within freshly created private evidence."""
    info = evidence.lstat()
    if (not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700
            or info.st_uid != os.geteuid() or evidence.resolve() != evidence):
        raise ValueError('fresh private0700 evidence required')
    file = (evidence / 'console.owner.lock').open('x+b')
    try:
        os.fchmod(file.fileno(), 0o600)
        fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        file.write(json.dumps({'owner': owner, 'controller_pid': os.getpid(),
                              'contract': 'operator exclusive serial client; passive file tails allowed'}).encode())
        file.flush()
        os.fsync(file.fileno())
        return Lease(evidence, owner, file)
    except BaseException:
        file.close()
        raise


def validate(c, evidence, owner, cid, lease):
    if (lease is None or lease.file.closed or lease.evidence != evidence
            or lease.owner != owner):
        raise ValueError('fresh controller lease required')
    fd = os.fstat(lease.file.fileno())
    name = (evidence / 'console.owner.lock').lstat()
    if not stat.S_ISREG(name.st_mode) or (fd.st_dev, fd.st_ino) != (name.st_dev, name.st_ino):
        raise ValueError('console ownership file changed')
    got, obj = retention.inspect_retained(c, evidence, owner)
    if got != cid or not obj['State']['Running'] or c.FW != FW:
        raise ValueError('exact owner/CID/firmware/running mismatch')
    preflight = json.loads((evidence / 'preflight.json').read_text())
    if preflight['firmware_sha256'] != FW:
        raise ValueError('preflight firmware mismatch')
    mounts = obj['Mounts']
    fw = [m for m in mounts if m['Destination'] == '/firmware.bin']
    ev = [m for m in mounts if m['Destination'] == '/run/sun4u']
    if (len(fw) != 1 or fw[0]['RW'] or fw[0]['Type'] != 'bind'
            or len(ev) != 1 or ev[0]['Source'] != str(evidence) or not ev[0]['RW']):
        raise ValueError('firmware/evidence bind mismatch')
    if c.digest(c.regular(fw[0]['Source'])) != FW:
        raise ValueError('mounted firmware hash changed')
    command = obj['Config']['Cmd']
    if not isinstance(command, list) or not any(
            'socket,id=owner_serial,path=/run/sun4u/serial.sock,server=on,wait=on,logfile=/run/sun4u/serial.log,logappend=on'
            in part for part in command):
        raise ValueError('fresh wait=on transport required')
    if any(obj['Config'][k] for k in ('OpenStdin', 'StdinOnce', 'AttachStdin', 'Tty')):
        raise ValueError('attached stdin forbidden')
    return obj


def drive(c, evidence, owner, cid, deadline, lease):
    """One connection, one boot attempt, no reconnect/retry/input after boot.

    Deadline bounds socket loop including connection wait; each inherited Docker
    inspect has its existing bounded30s timeout. No auto-stop on any exception.
    """
    engine = ReplayDriver(deadline=deadline)
    start = time.monotonic()
    sock = None
    result = None
    try:
        # Create evidence before connecting. File failure cannot cause hidden input.
        with (evidence / 'driver.rx.raw').open('xb', buffering=0) as rx, \
                (evidence / 'driver.tx.jsonl').open('x', buffering=1) as tx:
            validate(c, evidence, owner, cid, lease)
            path = evidence / 'serial.sock'
            while not path.exists():
                if time.monotonic() - start >= deadline:
                    raise TimeoutError('serial socket startup deadline')
                time.sleep(min(.1, max(0, deadline - (time.monotonic() - start))))
            if not stat.S_ISSOCK(path.lstat().st_mode):
                raise ValueError('serial path is not a socket')
            validate(c, evidence, owner, cid, lease)
            remaining = deadline - (time.monotonic() - start)
            if remaining <= 0:
                raise TimeoutError('identity preflight exceeded deadline')
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(min(1, remaining))
            sock.connect(str(path))
            while time.monotonic() - start < deadline:
                sock.settimeout(min(.5, max(.001, deadline - (time.monotonic() - start))))
                try:
                    data = sock.recv(4096)
                except socket.timeout:
                    continue
                if not data:
                    result = engine.finish('EOF')
                    break
                before = len(engine.raw)
                command = engine.feed(data, time.monotonic() - start)
                rx.write(engine.raw[before:])
                if command is not None:
                    # Intent is fsynced before send; partial send is explicitly uncertain.
                    tx.write(json.dumps({'event': 'SEND_INTENT', 'elapsed': time.monotonic() - start,
                                         'bytes_hex': command.hex()}) + '\n')
                    tx.flush()
                    os.fsync(tx.fileno())
                    if time.monotonic() - start >= deadline:
                        raise TimeoutError('deadline before send')
                    sock.sendall(command)
                    tx.write(json.dumps({'event': 'SEND_COMPLETED', 'bytes_hex': command.hex()}) + '\n')
                if engine.outcome:
                    result = engine.finish('EOF')
                    break
                postboot = bytes(engine.raw[engine.boot_offset:]) if engine.boot_offset is not None else b''
                if 'LOGIN' in observations(postboot):
                    result = engine.finish('EOF')
                    result['outcome'] = 'LOGIN_PROMPT_OBSERVED'
                    break
            if result is None:
                result = engine.finish('TIMEOUT')
    except BaseException as exc:
        reason = 'CANCELLED' if isinstance(exc, KeyboardInterrupt) else 'TIMEOUT' if isinstance(exc, TimeoutError) else 'EOF'
        result = engine.finish(reason)
        if reason == 'EOF':
            result['outcome'] = 'DRIVER_ERROR_INCOMPLETE'
        result['error'] = repr(exc)
    finally:
        if sock:
            sock.close()  # transport only; QEMU remains retained
        if result is None:
            result = engine.finish('EOF')
        result.update(scope='FRESH_SERIAL_OBSERVATION', owner=owner, cid=cid,
                      cleanup='NO_AUTOMATIC_STOP', send_completion='consult tx journal; intent alone is not delivery')
        (evidence / 'driver-outcome.json').write_text(json.dumps(result, indent=2) + '\n')
    return result
