import socket
import sys
from pathlib import Path

s = socket.socket(socket.AF_UNIX)
s.settimeout(900)
s.connect(sys.argv[1])
def packet(command):
    data = command.encode()
    s.sendall(b'$' + data + b'#' + ('%02x' % (sum(data) & 255)).encode())
    while s.recv(1) != b'$':
        pass
    response = bytearray()
    while True:
        b = s.recv(1)
        if b == b'#':
            break
        if not b:
            raise RuntimeError('EOF')
        response.extend(b)
    s.recv(2)
    s.sendall(b'+')
    return response.decode()

for command in sys.argv[2:]:
    if command.startswith('mark:'):
        Path(command[5:]).touch()
        continue
    if command == 'snapshot':
        raw = packet('g')
        if not raw.startswith('E'):
            for i in list(range(8, 32)) + [64, 65]:
                print('reg', i, raw[i*16:(i+1)*16], flush=True)
        for addr, size in [(0x18207e8, 48), (0x181d358, 64), (0x1810fa8, 4)]:
            print(hex(addr), packet('m%x,%x' % (addr, size)), flush=True)
        raw = packet('m181d358,20')
        if not raw.startswith('E'):
            data = bytes.fromhex(raw)
            count = int.from_bytes(data[0:8], 'big')
            ptr = int.from_bytes(data[24:32], 'big')
            if 0 < count < 1000:
                raw = packet('m%x,%x' % (ptr, count*16))
                print('virtavail', count, hex(ptr), raw, flush=True)
        continue
    if command == 'mappings':
        raw = packet('g')
        ptr = int(raw[8*16:9*16], 16)
        count = int(raw[9*16:10*16], 16)
        print('translations', hex(ptr), count, flush=True)
        if 0 < count < 10000:
            for i in range(count):
                data = packet('m%x,18' % (ptr + i*24))
                print('translation', i, data, flush=True)
        continue
    if command == 'boost-hblk128':
        raw = packet('g')
        pc = int(raw[64*16:65*16], 16)
        assert pc == 0x1019748, hex(pc)
        old = int(raw[19*16:20*16], 16)
        new = old + 128
        print('diagnostic-only hblk estimate boost', old, new, flush=True)
        result = packet('P13=%016x' % new)
        print('register write', result, flush=True)
        assert result == 'OK'
        continue
    print(command, packet(command), flush=True)
print('detach', packet('D'))
