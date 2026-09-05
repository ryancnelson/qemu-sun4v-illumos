#!/usr/bin/env python3
"""One raw Ethernet frame each way across DLPI and a shared-disk byte channel.

guest mode runs on OpenIndiana; host mode runs INSIDE the Linux container.
Length framing is network-order uint32; sockets have bounded diagnostic waits.
"""
import ctypes as C
import hashlib
import json
import socket
import struct
import sys
import time

def report(gate, frame):
    print(json.dumps(dict(gate=gate, bytes=len(frame), frame_hex=frame.hex(),
        sha256=hashlib.sha256(frame).hexdigest(),
        utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))), flush=True)

def exact(s, count):
    result = b''
    while len(result) < count:
        part = s.recv(count-len(result))
        if not part: raise EOFError('channel closed mid-frame')
        result += part
    return result

def receive(s):
    length, = struct.unpack('!I', exact(s, 4))
    if not 14 <= length <= 9018: raise ValueError('invalid Ethernet length')
    return exact(s, length)

def send(s, frame):
    s.sendall(struct.pack('!I', len(frame)) + frame)

mode, path = sys.argv[1:]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(45)
s.connect(path)
try:
    if mode == 'host':
        frame = receive(s)
        assert frame[:14] == bytes.fromhex('02ce0000000202ce0000000188b5')
        assert frame[14:].startswith(b'NIAGARA-ETHERNET-CHANNEL2-')
        report('CONTAINER_RECEIVED_GUEST_ETHERNET', frame)
        reply = frame[6:12] + frame[:6] + frame[12:]
        send(s, reply)
        report('CONTAINER_SENT_REPLY_ETHERNET', reply)
    elif mode == 'guest':
        lib = C.CDLL('libdlpi.so.1', use_errno=True)
        P = C.c_void_p; Z = C.c_size_t
        lib.dlpi_open.argtypes = [C.c_char_p,C.POINTER(P),C.c_uint]
        lib.dlpi_bind.argtypes = [P,C.c_uint,C.POINTER(C.c_uint)]
        lib.dlpi_send.argtypes = [P,P,Z,P,Z,P]
        lib.dlpi_recv.argtypes = [P,P,C.POINTER(Z),P,C.POINTER(Z),C.c_int,P]
        lib.dlpi_close.argtypes = [P]; lib.dlpi_close.restype = None
        lib.dlpi_strerror.argtypes = [C.c_int]; lib.dlpi_strerror.restype = C.c_char_p
        def check(rc):
            if rc != 10000: raise RuntimeError((rc,lib.dlpi_strerror(rc)))
        handles=[]
        try:
            for name in (b'ce_ip0',b'ce_wire0'):
                h=P(); check(lib.dlpi_open(name,C.byref(h),4)); handles.append(h)
                sap=C.c_uint(); check(lib.dlpi_bind(h,0x88b5,C.byref(sap)))
            def tx(h, frame):
                buf=C.create_string_buffer(frame); dst=C.create_string_buffer(frame[:6])
                check(lib.dlpi_send(h,dst,6,buf,len(frame),None))
            def rx(h):
                buf=C.create_string_buffer(2048); n=Z(2048)
                check(lib.dlpi_recv(h,None,None,buf,C.byref(n),5000,None))
                return buf.raw[:n.value]
            frame=bytes.fromhex('02ce0000000202ce0000000188b5') + (
                'NIAGARA-ETHERNET-CHANNEL2-%d'%time.time_ns()).encode().ljust(64,b'.')
            tx(handles[0],frame)
            forwarded=rx(handles[1]); assert forwarded==frame
            send(s,forwarded); report('GUEST_FORWARDED_ETHERNET_TO_CHANNEL2',forwarded)
            reply=receive(s)
            assert reply==frame[6:12]+frame[:6]+frame[12:]
            tx(handles[1],reply)
            delivered=rx(handles[0]); assert delivered==reply
            report('GUEST_RECEIVED_CONTAINER_ETHERNET_VIA_SWITCH',delivered)
            print('ETHERNET_OVER_CHANNEL2_ROUNDTRIP_PASS',flush=True)
        finally:
            for h in reversed(handles): lib.dlpi_close(h)
    else: raise ValueError('mode must be host or guest')
finally:
    s.close()
