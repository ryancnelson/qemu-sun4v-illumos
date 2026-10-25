"""Bounded offline boot-driver core; live admission is deliberately fail-closed.

No socket, Docker, subprocess, credentials, or guest-stop operations exist here.
Pinned QEMU queues connections, so an ordinary connect is not ownership proof.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

FW = '1537670b70680bfe286969a6e246142aff29ab13cd90405d1787a601295e9a5e'
COMMANDS = (
    b'dev /pci@1f,0/pci@1,1/ebus@1/power@14,7240\r',
    b'" interrupts" delete-property\r',
    b'dev /pci@1f,0/pci@1,1/ebus@1/fdthree@0,0\r',
    b'" fdthree-disabled" device-name\r',
    b'boot disk -v\r',
)
LIMIT = 1024 * 1024
PROMPT = re.compile(rb'(?:^|[\r\n])0 > $')
ROOT = b'root on rpool/ROOT/opensolaris fstype zfs'
LOGIN = re.compile(rb'^opensolaris console login: ?$', re.M)


def admission(enabled):
    if not enabled:
        return 'DISABLED'
    raise ValueError('REFUSED_CONSOLE_EXCLUSIVITY_UNPROVEN: pinned server queues connections')


def check_identity(record, actual, owner, cid, firmware_sha):
    """Offline checks only. Saved inspect is NOT fresh/live ownership proof."""
    if not re.fullmatch(r'[0-9a-f]{32}', owner) or not re.fullmatch(r'[0-9a-f]{64}', cid):
        raise ValueError('invalid exact identity')
    if (record['owner'] != owner or record['cid'] != cid or actual['Id'] != cid
            or actual['Config']['Labels'].get('sun4u.coldboot.owner') != owner
            or record['transport'] != 'qemu-unix-serial-v1'
            or actual['State']['Running'] is not True or firmware_sha != FW):
        raise ValueError('owner/CID/firmware/state mismatch')
    mounts = actual['Mounts']
    targets = [m['Destination'] for m in mounts]
    if len(targets) != len(set(targets)):
        raise ValueError('duplicate mount')
    firmware = [m for m in mounts if m['Destination'] == '/firmware.bin']
    if len(firmware) != 1 or firmware[0]['RW'] is not False or firmware[0]['Type'] != 'bind':
        raise ValueError('firmware mount mismatch')


def observations(raw):
    text = raw.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    flags = []
    if ROOT in text.splitlines():
        flags.append('ROOT_MOUNT')
    if LOGIN.search(text):
        flags.append('LOGIN')  # prompt only; never authenticated-login proof
    if re.search(rb'(?m)^(?:panic\[|panic:|Unhandled Exception |Stopping execution)', text):
        flags.append('PANIC')
    return flags


class ReplayDriver:
    """Deterministic test-only state machine. Returns proposed TX, never sends it.

    Each command requires a fresh bare prompt. Each prep command additionally
    requires exact echoed command plus `  ok`. Old logfile prompts cannot be
    substituted for freshly received data in a future live implementation.
    """
    def __init__(self, deadline=60, limit=LIMIT):
        if not 0 < deadline <= 2100 or not 0 < limit <= LIMIT:
            raise ValueError('invalid bounds')
        self.deadline, self.limit = deadline, limit
        self.raw = bytearray()
        self.pending = bytearray()
        self.sent = []
        self.outcome = None
        self.boot_offset = None
        self.last_time = 0

    def feed(self, data, elapsed):
        if self.outcome:
            raise ValueError('replay already finished')
        if elapsed < self.last_time:
            raise ValueError('nonmonotonic replay time')
        self.last_time = elapsed
        if elapsed >= self.deadline:
            self.outcome = 'TIMEOUT'
            return None
        remaining = self.limit - len(self.raw)
        self.raw.extend(data[:remaining])
        if len(data) > remaining:
            self.outcome = 'CAP_INCOMPLETE'
            return None
        self.pending.extend(data)
        if 'PANIC' in observations(bytes(self.raw)):
            self.outcome = 'PANIC'
            return None
        if self.boot_offset is not None:
            return None  # absolutely no post-boot input or login attempts
        if not PROMPT.search(self.pending):
            return None
        if self.sent:
            expected = self.sent[-1][:-1] + b'  ok'
            lines = bytes(self.pending).replace(b'\r', b'\n').splitlines()
            if expected not in lines and b'0 > ' + expected not in lines:
                self.outcome = 'PREP_ACK_INCOMPLETE'
                return None
        elif b'Welcome to OpenBIOS v1.1' not in self.pending:
            self.outcome = 'PROMPT_UNVERIFIED'
            return None
        command = COMMANDS[len(self.sent)]
        self.sent.append(command)
        self.pending.clear()
        if len(self.sent) == len(COMMANDS):
            self.boot_offset = len(self.raw)
        return command

    def finish(self, reason):
        if reason not in ('EOF', 'CANCELLED', 'TIMEOUT'):
            raise ValueError('invalid finish reason')
        self.outcome = self.outcome or reason
        postboot = bytes(self.raw[self.boot_offset:]) if self.boot_offset is not None else b''
        return {'outcome': self.outcome, 'observations': observations(postboot),
                'acceptance': 'NOT_ESTABLISHED', 'authenticated_login': False,
                'transcript_sha256': hashlib.sha256(self.raw).hexdigest(),
                'transcript_bytes': len(self.raw), 'commands_proposed': len(self.sent),
                'scope': 'OFFLINE_REPLAY_ONLY', 'capture_complete': False}

    def save(self, directory, reason):
        directory = Path(directory)
        directory.mkdir(mode=0o700)  # fresh only; never overwrite evidence
        (directory / 'rx.raw').write_bytes(self.raw)
        (directory / 'tx.proposed.raw').write_bytes(b''.join(self.sent))
        (directory / 'outcome.json').write_text(json.dumps(self.finish(reason), indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--enable-serial-boot', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps({'outcome': admission(args.enable_serial_boot), 'acceptance': 'NOT_ESTABLISHED'}))
        return 0
    except ValueError as exc:
        print(json.dumps({'outcome': str(exc), 'acceptance': 'NOT_ESTABLISHED'}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
