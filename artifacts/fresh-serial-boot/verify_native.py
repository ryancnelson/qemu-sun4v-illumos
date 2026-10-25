"""Verify saved diskless evidence; preserve wrapper failure, no native actions."""
import hashlib
import json
from pathlib import Path
from boot_protocol import COMMANDS, FW

p = Path(__file__).parent / 'native-evidence'
result = json.loads((p/'result.json').read_text())
before = json.loads((p/'before-first-client.json').read_text())
disconnected = json.loads((p/'cleanup-before.json').read_text())
stopped = json.loads((p/'cleanup-final.json').read_text())
preflight = json.loads((p/'preflight.json').read_text())
tx = [json.loads(line) for line in (p/'driver.tx.jsonl').read_text().splitlines()]
raw = (p/'driver.rx.raw').read_bytes()
log = (p/'serial.log').read_bytes()
for item in (before,disconnected,stopped):
    assert item['Id'] == result['cid']
    assert item['Config']['Labels']['sun4u.coldboot.owner'] == result['owner']
assert result['serial_bytes_before_first_client'] == 0
assert before['State']['Running'] and disconnected['State']['Running']
assert not stopped['State']['Running'] and not stopped['State']['OOMKilled']
assert [bytes.fromhex(x['bytes_hex']) for x in tx if x['event']=='SEND_COMPLETED'] == list(COMMANDS)
assert b'Welcome to OpenBIOS v1.1' in raw
assert log == raw
assert result['driver']['outcome'] == 'PANIC'
assert result['driver']['acceptance'] == 'NOT_ESTABLISHED'
assert preflight['firmware_sha256'] == FW
assert all(m['Destination'] != '/installed.qcow2' for m in before['Mounts'])
command=before['Config']['Cmd'][-1]
assert '-m 128' in command and '-smp 1' in command and '-nic none' in command
assert '-drive' not in command and '-cdrom' not in command
assert before['HostConfig']['NetworkMode']=='none'
summary = {'transport_milestones_verified': True, 'original_wrapper_pass': result['smoke_pass'],
    'wrapper_failure': 'expected TIMEOUT assertion; actual deliberate diskless boot exception was PANIC',
    'reconnect_test_executed': False, 'native_reconcile_test_executed': False,
    'first_prompt': True, 'exact_five_commands_acknowledged': True,
    'disconnect_retained_running': True, 'serial_log_equals_raw_capture': True,
    'explicit_smoke_only_stop': True, 'final_running': False,
    'owner':result['owner'],'cid':result['cid'],'firmware_sha256':FW,
    'raw_sha256':hashlib.sha256(raw).hexdigest(), 'installed_os_claim':False}
(Path(__file__).parent/'native-verified.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
