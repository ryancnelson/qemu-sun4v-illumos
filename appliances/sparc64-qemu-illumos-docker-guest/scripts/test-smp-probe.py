#!/usr/bin/env python3
"""Execute the actual guest probe with controlled command results."""
import shlex
import subprocess
from pathlib import Path

appliance = (Path(__file__).resolve().parents[1] / 'appliance').read_text()
section = appliance.split('self-smp)\n', 1)[1].split('self-network)', 1)[0]
line = next(line for line in section.splitlines() if '--command ' in line)
probe = shlex.split(line)[1]
probe = probe.replace('/usr/sbin/psrinfo', 'probe_psrinfo')
probe = probe.replace('/usr/bin/awk', 'awk').replace('/usr/bin/mpstat', 'probe_mpstat')
for name, rows, psr_rc, mpstat_rc, expected in [
    ('two CPUs', '0 on-line\n1 on-line', 0, 0, True),
    ('one CPU', '0 on-line', 0, 0, False),
    ('CPU offline', '0 on-line\n1 off-line', 0, 0, False),
    ('extra CPU', '0 on-line\n1 on-line\n2 on-line', 0, 0, False),
    ('psrinfo fails with plausible output', '0 on-line\n1 on-line', 1, 0, False),
    ('mpstat fails', '0 on-line\n1 on-line', 0, 1, False),
]:
    definitions = (
        'probe_psrinfo() { printf "%s\\n" ' + shlex.quote(rows) + '; return ' + str(psr_rc) + '; }; '
        'probe_mpstat() { return ' + str(mpstat_rc) + '; }; '
    )
    result = subprocess.run(['/bin/sh', '-c', definitions + probe], capture_output=True, text=True)
    assert (result.returncode == 0) == expected, (name, result.returncode, result.stderr)
    print('SMP_PROBE_CASE=PASS ' + name)
