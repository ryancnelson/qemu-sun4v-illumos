import sys
from collections import defaultdict

groups = defaultdict(set)
for line in open(sys.argv[1]):
    fields = line.split()
    if len(fields) != 3 or fields[0] != 'translation':
        continue
    raw = bytes.fromhex(fields[2])
    va, size, tte = [int.from_bytes(raw[i:i+8], 'big') for i in (0, 8, 16)]
    if va < 0x1000000:
        continue
    if va in (0x1000000, 0x1800000):
        continue  # Kernel text/data remapped with 4 MiB TTEs beforehand.
    category = 'high heap' if va >= 0x30000000000 else 'low VA'
    for block in range(va // 65536, (va + size + 65535) // 65536):
        groups[category].add(block)
for category, blocks in groups.items():
    print(category, len(blocks))
print('total distinct 64KiB blocks', len(set().union(*groups.values())))
