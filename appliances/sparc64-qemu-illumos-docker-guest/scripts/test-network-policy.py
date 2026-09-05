#!/usr/bin/env python3
"""Exercise the shipped policy checker on representative guest configurations."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
policy = (root / 'guest-assets/network-policy.env').read_text()
checker = (root / 'guest-assets/NETWORK_POLICY.sh').read_text()
cases = [
    ('current', 'nameserver 10.0.5.1\n', 'hosts: files dns\nipnodes: files dns\n', True),
    ('tabs and comments', 'nameserver 10.0.5.1\n', 'hosts:\tfiles dns # comment\nipnodes: files dns\n', True),
    ('old resolver', 'nameserver 8.8.8.8\n', 'hosts: files dns\nipnodes: files dns\n', False),
    ('missing dns', 'nameserver 10.0.5.1\n', 'hosts: files\nipnodes: files dns\n', False),
    ('wrong order', 'nameserver 10.0.5.1\n', 'hosts: dns files\nipnodes: files dns\n', False),
    ('missing ipnodes', 'nameserver 10.0.5.1\n', 'hosts: files dns\n', False),
    ('duplicate hosts', 'nameserver 10.0.5.1\n', 'hosts: files dns\nhosts: files dns\nipnodes: files dns\n', False),
    ('extra resolver', 'nameserver 10.0.5.1\nnameserver 8.8.8.8\n', 'hosts: files dns\nipnodes: files dns\n', False),
]
with tempfile.TemporaryDirectory() as tmp:
    fixture = Path(tmp)
    (fixture / 'network-policy.env').write_text(policy)
    script = checker.replace('/etc/resolv.conf', str(fixture / 'resolv.conf'))
    script = script.replace('/etc/nsswitch.conf', str(fixture / 'nsswitch.conf'))
    script = script.replace('/usr/bin/nawk', 'awk')
    (fixture / 'NETWORK_POLICY.sh').write_text(script)
    for name, resolv, nss, expected in cases:
        (fixture / 'resolv.conf').write_text(resolv)
        (fixture / 'nsswitch.conf').write_text(nss)
        result = subprocess.run(['/bin/sh', str(fixture / 'NETWORK_POLICY.sh'), 'check'], capture_output=True, text=True)
        assert (result.returncode == 0) == expected, (name, result.stdout, result.stderr)
        assert (fixture / 'resolv.conf').read_text() == resolv
        assert (fixture / 'nsswitch.conf').read_text() == nss
        print('NETWORK_POLICY_CASE=PASS ' + name)
    (fixture / 'network-policy.env').write_text(policy.replace('DNS_IP=10.0.5.1', 'DNS_IP=192.0.2.53'))
    (fixture / 'resolv.conf').write_text('nameserver 192.0.2.53\n')
    (fixture / 'nsswitch.conf').write_text('hosts: files dns\nipnodes: files dns\n')
    subprocess.run(['/bin/sh', str(fixture / 'NETWORK_POLICY.sh'), 'check'], check=True)
    print('NETWORK_POLICY_CASE=PASS checker consumes policy rather than embedded address')
