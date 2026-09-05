import collections, hashlib, json, os, struct, sys, time

cfg = json.loads(sys.argv[2])
block = cfg['CHAN_BLK']
offset = 327680 + 2 * cfg['CHAN_STRIDE_BLKS'] * block
length = cfg['CHAN_STRIDE_BLKS'] * block
backup = '/tmp/chand-channel2-a9c7.backup'
fd = os.open('/run/unit100/carrier-unit100.raw', os.O_RDWR)

def ctrl(at):
    raw = os.pread(fd, block, at)
    magic, seq, size, ack = struct.unpack_from('>4I', raw)
    end, = struct.unpack_from('>I', raw, cfg['CHAN_SEQ_END_OFF'])
    if magic != cfg['CHAN_MAGIC'] or seq != end:
        return None
    return seq, size, ack

def ack(seq):
    raw = bytearray(block)
    struct.pack_into('>4I', raw, 0, cfg['CHAN_MAGIC'], 0, 0, seq)
    os.pwrite(fd, raw, offset)

mode = sys.argv[1]
if mode == 'init':
    with open(backup, 'xb') as f:
        f.write(os.pread(fd, length, offset))
    os.pwrite(fd, bytes(2 * block), offset)
    ack(0)
    print('backed up and initialized channel 2 only')
elif mode == 'reset':
    os.pwrite(fd, bytes(2 * block), offset)
    ack(0)
elif mode == 'restore':
    raw = open(backup, 'rb').read()
    assert len(raw) == length
    os.pwrite(fd, raw, offset)
    assert os.pread(fd, length, offset) == raw
    print('channel 2 restored byte-for-byte')
elif mode == 'receive':
    wanted = 6144 * 512
    result = bytearray()
    sizes = []
    seen = 0
    start = None
    deadline = time.monotonic() + 120
    while len(result) < wanted:
        if time.monotonic() > deadline:
            raise RuntimeError('receive deadline exceeded')
        value = ctrl(offset + block)
        if value and value[0] != seen and 0 < value[1] <= cfg['CHAN_DATA_BYTES']:
            seq, size, _ = value
            assert seq == seen + 1
            data = os.pread(fd, size, offset + (2 + cfg['CHAN_DATA_BLKS']) * block)
            again = ctrl(offset + block)
            if not again or again[:2] != value[:2]:
                continue
            if start is None:
                start = time.monotonic()
            result.extend(data)
            sizes.append(size)
            time.sleep(0.020)  # identical controlled acknowledgement delay
            ack(seq)
            seen = seq
        else:
            time.sleep(0.001)
    elapsed = time.monotonic() - start
    assert result == b'p' * wanted
    print(json.dumps({'bytes':len(result), 'seconds':elapsed,
          'MiB_per_s':len(result)/1048576/elapsed, 'frames':len(sizes),
          'frame_bytes':dict(collections.Counter(sizes)),
          'sha256':hashlib.sha256(result).hexdigest()}))
os.close(fd)
