#!/bin/sh
# Guest end of the PPP link over the qcn console.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
nohup /tmp/wd.sh >/dev/null 2>&1 &
# notty does NOT set terminal modes; without this the guest tty echoes the host's
# bytes and host pppd receives its own frames back, then dies with
# "LCP: timeout sending Config-Requests".
stty raw -echo < /dev/console
# asyncmap 0xffffffff: escape ALL control characters. The qcn console is NOT
# 8-bit clean -- with asyncmap 0x0 anything carrying 0x11/0x13/0x0d in its
# payload was mangled, so ICMP <=16B replied but >=32B failed FCS and vanished.
# stdout IS the link here, so pppd's own logging must be redirected.
exec pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff 10.0.5.15:10.0.5.1 nodetach debug 2>/tmp/gppp.log
