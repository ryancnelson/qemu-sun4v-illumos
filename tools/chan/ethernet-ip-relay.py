#!/usr/bin/env python3
"""Experimental single-channel DLPI/TAP relay; no routing or NAT.

guest SOCKET LINK or host SOCKET TAP. Length-prefixed Ethernet, no reconnect
inside the relay: exit on a broken stream and let an operator inspect evidence.
"""
import ctypes as C
import hashlib
import json
import os
import select
import socket
import struct
import sys
import time

def log(event, **fields):
    print(json.dumps(dict(event=event, utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',
          time.gmtime()), **fields)), flush=True)

def exact(s, size):
    data = b''
    while len(data) < size:
        part = s.recv(size-len(data))
        if not part:
            raise EOFError('channel disconnected')
        data += part
    return data

def validate(frame):
    if not 14 <= len(frame) <= 9018:
        raise ValueError('invalid frame size: %d' % len(frame))
    return frame

def main():
    mode, path, link = sys.argv[1:]
    cleanup = lambda: None
    if mode == 'host':
        import fcntl
        import subprocess
        fd = os.open('/dev/net/tun', os.O_RDWR)
        cleanup = lambda: os.close(fd)
        # Linux TUNSETIFF, IFF_TAP | IFF_NO_PI. Nonpersistent: closes with fd.
        fcntl.ioctl(fd, 0x400454ca, struct.pack('16sH22x', link.encode(), 0x1002))
        subprocess.run(['ip','link','set',link,'address','02:ce:00:00:00:02',
                        'mtu','1500','up'], check=True)
        subprocess.run(['ip','addr','add','10.77.0.1/24','dev',link], check=True)
        receive = lambda: os.read(fd, 16384)
        def transmit(frame):
            if os.write(fd, frame) != len(frame):
                raise IOError('short TAP write')
    elif mode == 'guest':
        lib = C.CDLL('libdlpi.so.1')
        P=C.c_void_p; Z=C.c_size_t
        lib.dlpi_open.argtypes=[C.c_char_p,C.POINTER(P),C.c_uint]
        lib.dlpi_bind.argtypes=[P,C.c_uint,C.POINTER(C.c_uint)]
        lib.dlpi_promiscon.argtypes=[P,C.c_uint]
        lib.dlpi_send.argtypes=[P,P,Z,P,Z,P]
        lib.dlpi_recv.argtypes=[P,P,C.POINTER(Z),P,C.POINTER(Z),C.c_int,P]
        lib.dlpi_fd.argtypes=[P]
        lib.dlpi_close.argtypes=[P]; lib.dlpi_close.restype=None
        lib.dlpi_strerror.argtypes=[C.c_int]; lib.dlpi_strerror.restype=C.c_char_p
        def check(rc):
            if rc != 10000:
                raise RuntimeError((rc,lib.dlpi_strerror(rc)))
        handle=P(); check(lib.dlpi_open(link.encode(),C.byref(handle),4))
        cleanup=lambda: lib.dlpi_close(handle)
        sap=C.c_uint(); check(lib.dlpi_bind(handle,0,C.byref(sap)))
        check(lib.dlpi_promiscon(handle,2))  # All SAPs, not just IPv4.
        fd=lib.dlpi_fd(handle)
        if fd < 0:
            raise RuntimeError('invalid DLPI fd')
        def receive():
            buf=C.create_string_buffer(16384); size=Z(len(buf))
            check(lib.dlpi_recv(handle,None,None,buf,C.byref(size),1000,None))
            return buf.raw[:size.value]
        def transmit(frame):
            buf=C.create_string_buffer(frame); dst=C.create_string_buffer(frame[:6])
            check(lib.dlpi_send(handle,dst,6,buf,len(frame),None))
    else:
        raise ValueError('mode must be host or guest')
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
    try:
        s.settimeout(15); s.connect(path)
        log('READY',mode=mode,link=link,pid=os.getpid())
        counters={'to_channel':0,'from_channel':0}
        while True:
            ready,_,_=select.select([s,fd],[],[],5)
            if s in ready:
                length,=struct.unpack('!I',exact(s,4))
                if not 14 <= length <= 9018:
                    raise ValueError('invalid declared frame size')
                frame=validate(exact(s,length)); transmit(frame)
                counters['from_channel']+=1
                log('FRAME',direction='from_channel',count=counters['from_channel'],
                    bytes=len(frame),header=frame[:42].hex(),sha256=hashlib.sha256(frame).hexdigest())
            if fd in ready:
                frame=validate(receive())
                s.sendall(struct.pack('!I',len(frame))+frame)
                counters['to_channel']+=1
                log('FRAME',direction='to_channel',count=counters['to_channel'],
                    bytes=len(frame),header=frame[:42].hex(),sha256=hashlib.sha256(frame).hexdigest())
    finally:
        s.close(); cleanup()

if __name__ == '__main__':
    main()
