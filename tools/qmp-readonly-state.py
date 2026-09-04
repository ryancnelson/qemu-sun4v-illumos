#!/usr/bin/env python3
"""Read appliance QMP status/registers without stopping CPUs or writing disks.

Run inside the appliance: docker exec -i NAME python3 - < this-file.py
"""
import json
import socket

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(10)
s.connect('/state/qmp.sock')
f = s.makefile('rb')
print(f.readline().decode(), end='')
for n, (command, arguments) in enumerate([
    ('qmp_capabilities', {}),
    ('query-status', {}),
    ('query-cpus-fast', {}),
    ('query-blockstats', {}),
    ('human-monitor-command', {'command-line': 'info registers -a'}),
]):
    s.sendall((json.dumps({'execute': command, 'arguments': arguments, 'id': n}) + '\n').encode())
    while True:
        response = json.loads(f.readline())
        print(json.dumps({'command': command, 'response': response}), flush=True)
        if response.get('id') == n:
            break
