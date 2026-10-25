"""Authorized owned128MiB diskless transport smoke; never an installed OS run."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import socket
import time
import uuid
import coldboot_fresh as c
import fresh_serial as f
import retention

owner = uuid.uuid4().hex
e = Path('/mnt/disk-images/woodpecker') / ('fsb-' + owner)
e.mkdir(mode=0o700)
binary = Path('/home/niagara/devel/macapp-sun4u-001-cmd646-compat/artifacts/qemu-system-sparc64.candidate')
firmware = Path('/mnt/disk-images/woodpecker/firmware132-dad-topology-kestrel/artifacts/openbios-sparc64.candidate')
cid = None
lease = None
result = {'owner': owner, 'evidence': str(e), 'smoke_pass': False, 'installed_os_claim': False}
commands = []
original_call = c.call
def call(args, timeout=20):
    item = {'argv': args}
    commands.append(item)
    try:
        value = original_call(args, timeout)
        item.update(output=value, exit=0)
        return value
    except BaseException as exc:
        item['error'] = repr(exc)
        raise
c.call = call
def inspect(name):
    got, obj = c.owned(e, owner)
    assert got == cid
    (e / (name + '.json')).write_text(json.dumps(obj, indent=2))
    return obj
def alarm(sig, frame):
    raise TimeoutError('native smoke120s deadline')
signal.signal(signal.SIGALRM, alarm)
signal.alarm(120)
try:
    c.host_check()
    assert c.digest(binary) == c.QEMU and c.digest(firmware) == c.FW
    assert json.loads(call(c.DOCKER + ['image', 'inspect', c.IMAGE]))[0]['Id'] == c.IMAGE
    lease = f.acquire(e, owner)
    qemu = ['/usr/bin/qemu-system-sparc64', '-M', 'sun4u', '-m', '128', '-smp', '1',
            '-nodefaults', '-nic', 'none', '-display', 'none', '-bios', '/firmware.bin',
            '-prom-env', 'auto-boot?=false', '-prom-env', 'input-device=ttya',
            '-prom-env', 'output-device=ttya', '-chardev',
            'socket,id=owner_serial,path=/run/sun4u/serial.sock,server=on,wait=on,logfile=/run/sun4u/serial.log,logappend=on',
            '-serial', 'chardev:owner_serial']
    script = 'set -eu\n' + f"echo '{c.FW}  /firmware.bin' | sha256sum -c -\n" + \
             f"echo '{c.QEMU}  /usr/bin/qemu-system-sparc64' | sha256sum -c -\n" + 'exec ' + shlex.join(qemu)
    args = c.DOCKER + ['create', '--pull=never', '--name', 'trellis-fsb-' + owner,
        '--label', 'sun4u.coldboot.owner=' + owner, '--cidfile', str(e/'owned.cid'),
        '--network', 'none', '--cpus', '1', '--memory', '512m',
        '--log-driver', 'json-file', '--log-opt', 'max-size=64m', '--log-opt', 'max-file=1']
    for src, dst, ro in [(binary,'/usr/bin/qemu-system-sparc64',True),
                         (firmware,'/firmware.bin',True),(e,'/run/sun4u',False)]:
        args += ['--mount', f'type=bind,src={src},dst={dst}' + (',readonly' if ro else '')]
    args += ['--entrypoint','/bin/sh',c.IMAGE,'-c',script]
    retention.durable(e/'preflight.json', {'argv': args, 'firmware_sha256': c.FW,
        'qemu_sha256': c.QEMU, 'image': c.IMAGE, 'scope': 'DISKLESS_FIRMWARE_ONLY',
        'exclusive_console_operator': True})
    call(args)
    cid, _ = c.owned(e, owner)
    result['cid'] = cid
    retention.prepare(c, e, owner)
    call(c.DOCKER + ['start', cid])
    until = time.monotonic() + 15
    while not (e/'serial.sock').exists() and time.monotonic() < until:
        time.sleep(.1)
    assert (e/'serial.sock').exists()
    time.sleep(1)
    assert inspect('before-first-client')['State']['Running']
    before = (e/'serial.log').read_bytes()
    result['serial_bytes_before_first_client'] = len(before)
    assert not before, 'wait=on must prevent firmware banner before designated client'
    result['driver'] = f.drive(c, e, owner, cid, 12, lease)
    assert result['driver']['commands_proposed'] == 5
    assert result['driver']['outcome'] == 'TIMEOUT'  # no disk/no OS; intentional
    assert inspect('after-driver-disconnect')['State']['Running']
    prefix = (e/'serial.log').read_bytes()
    assert b'Welcome to OpenBIOS v1.1' in prefix
    assert b'boot disk -v' in prefix
    # Test reconnect AFTER first driver disconnected, under the same operator lease.
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(1)
        sock.connect(str(e/'serial.sock'))
        sock.sendall(b'\rdecimal 24681 . cr\r')
        received = bytearray()
        until = time.monotonic() + 10
        while time.monotonic() < until:
            try:
                part = sock.recv(4096)
                if not part: break
                received.extend(part)
                if received.count(b'24681') >= 2: break
            except socket.timeout: pass
        (e/'reconnect.raw').write_bytes(received)
        assert received.count(b'24681') >= 2
    assert inspect('after-reconnect-eof')['State']['Running']
    assert (e/'serial.log').read_bytes().startswith(prefix)
    result['reconcile'] = retention.reconcile(c, e, owner)['outcome']
    assert result['reconcile'] == 'RETAINED_RUNNING_UNVERIFIED'
    result['smoke_pass'] = True
except BaseException as exc:
    result['error'] = repr(exc)
finally:
    signal.alarm(0)
    # Only this explicitly disposable DISKLESS container; never inherited runtime cleanup.
    if cid:
        try:
            obj = inspect('cleanup-before')
            if obj['State']['Running']:
                call(c.DOCKER + ['stop', '--time', '3', cid], 10)
            obj = inspect('cleanup-after-stop')
            if obj['State']['Running']:
                call(c.DOCKER + ['kill', cid], 10)
            result['stopped'] = not inspect('cleanup-final')['State']['Running']
            result['smoke_pass'] &= result['stopped']
            (e/'docker.log').write_text(call(c.DOCKER + ['logs', '--timestamps', cid]))
        except BaseException as exc:
            result.update(cleanup_error=repr(exc), smoke_pass=False)
    if lease: lease.close()
    (e/'transcript.json').write_text(json.dumps(commands,indent=2))
    (e/'result.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result,indent=2),flush=True)
