#!/usr/bin/env python3
"""Bounded, bidirectional raw Ethernet probe between two isolated guest VNICs.

ctypes signatures follow illumos libdlpi.h. No IP configuration is changed.
"""
import ctypes as C
import hashlib
import json
import time

lib = C.CDLL('libdlpi.so.1', use_errno=True)
ptr = C.c_void_p
size = C.c_size_t
lib.dlpi_open.argtypes = [C.c_char_p, C.POINTER(ptr), C.c_uint]
lib.dlpi_open.restype = C.c_int
lib.dlpi_close.argtypes = [ptr]
lib.dlpi_close.restype = None
lib.dlpi_bind.argtypes = [ptr, C.c_uint, C.POINTER(C.c_uint)]
lib.dlpi_bind.restype = C.c_int
lib.dlpi_send.argtypes = [ptr, ptr, size, ptr, size, ptr]
lib.dlpi_send.restype = C.c_int
lib.dlpi_recv.argtypes = [ptr, ptr, C.POINTER(size), ptr, C.POINTER(size), C.c_int, ptr]
lib.dlpi_recv.restype = C.c_int
lib.dlpi_strerror.argtypes = [C.c_int]
lib.dlpi_strerror.restype = C.c_char_p

def check(operation, result):
    if result != 10000:
        raise RuntimeError('%s: %d %s errno=%d' %
            (operation, result, lib.dlpi_strerror(result).decode(), C.get_errno()))

handles = []
try:
    for name in (b'ce_ip0', b'ce_wire0'):
        h = ptr()
        check('open ' + name.decode(), lib.dlpi_open(name, C.byref(h), 4))
        handles.append(h)
        sap = C.c_uint()
        check('bind', lib.dlpi_bind(h, 0x88b5, C.byref(sap)))
        assert sap.value == 0x88b5
    macs = [bytes.fromhex('02ce00000001'), bytes.fromhex('02ce00000002')]
    for source, target in ((0, 1), (1, 0)):
        payload = ('NIAGARA-ETHERNET-FIRST-LOCAL-%d-%d' %
                   (source, time.time_ns())).encode().ljust(64, b'.')
        frame = macs[target] + macs[source] + b'\x88\xb5' + payload
        tx = C.create_string_buffer(frame)
        dest = C.create_string_buffer(macs[target])
        check('send', lib.dlpi_send(handles[source], dest, 6, tx, len(frame), None))
        rx = C.create_string_buffer(2048)
        length = size(2048)
        check('recv', lib.dlpi_recv(handles[target], None, None, rx,
                                   C.byref(length), 5000, None))
        actual = rx.raw[:length.value]
        assert actual == frame, (actual.hex(), frame.hex())
        print(json.dumps(dict(gate='LOCAL_RAW_ETHERNET_PASS', source=source,
            target=target, bytes=len(frame), sha256=hashlib.sha256(frame).hexdigest(),
            frame_hex=frame.hex(), utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))), flush=True)
finally:
    for h in reversed(handles):
        lib.dlpi_close(h)
