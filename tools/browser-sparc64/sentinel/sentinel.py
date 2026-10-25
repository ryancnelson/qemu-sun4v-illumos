#!/usr/bin/env python3
"""Offline 32 KiB unique-offset sentinels; not bootable media."""
import argparse, hashlib, json, struct, sys

SECTOR_SIZE = 2048
IMAGE_SIZE = 32768
DOMAIN = b'macapp-sun4u-002/sector-sentinel/v1\x00'
OFFSETS = (0, 0x100, 0x7e0, 0x800, 0x900, 0x1800, 0x7800, 0x7fc0)

def image():
    result = bytearray()
    for offset in range(0, IMAGE_SIZE, 32):
        header = b'S4U2SENT' + struct.pack('>QII', offset, offset // 2048, (offset % 2048) // 32)
        result.extend(header + hashlib.sha256(DOMAIN + header).digest()[:8])
    return bytes(result)

def expected(offset, length):
    if offset < 0 or length < 64 or length > 4096 or offset > IMAGE_SIZE - length:
        raise ValueError('require offset>=0, 64<=length<=4096, end<=32768')
    return image()[offset:offset + length]

def verify(data, offset, length):
    want = expected(offset, length)
    if len(data) != length:
        raise ValueError('capture length mismatch: expected %d, got %d' % (length, len(data)))
    if data != want:
        first = next(i for i, (a, b) in enumerate(zip(data, want)) if a != b)
        raise ValueError('wrong bytes at capture +0x%x / requested media 0x%x' % (first, offset + first))
    return dict(verified=True, offset=offset, length=length, capture_sha256=hashlib.sha256(data).hexdigest())

def manifest():
    data = image()
    return dict(format='sun4u-002-sector-sentinel-v1', image_size=IMAGE_SIZE, sector_size=2048,
        sectors=16, sha256=hashlib.sha256(data).hexdigest(), read_only=True, bootable=False,
        runtime_executed=False,
        record_layout='32 bytes: S4U2SENT[8], absolute byte offset BE64, sector BE32, slot BE32, SHA256(domain+header)[:8]',
        sector_sha256=[hashlib.sha256(data[i:i+2048]).hexdigest() for i in range(0, IMAGE_SIZE, 2048)],
        sentinels=[dict(offset=o, offset_hex=hex(o), length=64, hex=expected(o,64).hex()) for o in OFFSETS])

def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    g = sub.add_parser('generate'); g.add_argument('output')
    e = sub.add_parser('expected')
    v = sub.add_parser('verify'); v.add_argument('capture')
    for parser in (e, v):
        parser.add_argument('--offset', type=lambda x:int(x,0), required=True)
        parser.add_argument('--length', type=lambda x:int(x,0), required=True)
    sub.add_parser('manifest')
    a = p.parse_args()
    if a.command == 'generate':
        with open(a.output, 'xb') as f: f.write(image())
        result = manifest()
    elif a.command == 'manifest': result = manifest()
    elif a.command == 'expected': result = dict(offset=a.offset, length=a.length, hex=expected(a.offset,a.length).hex())
    else:
        expected(a.offset,a.length)
        with open(a.capture,'rb') as f: data = f.read(a.length+1)
        result = verify(data,a.offset,a.length)
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    try: main()
    except (ValueError,OSError) as e:
        print('REFUSE: '+str(e),file=sys.stderr);sys.exit(1)
