#!/bin/sh
# Watchdog: return the console, record the outcome, halt cleanly.
# Logs each step to the FAT slice so a failure to recover is diagnosable --
# last attempt it never came back and the guest ended in a panic + broken OBP.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
S=/x/WDLOG.TXT
mark() { mkdir -p /x; mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null; echo "$1" >> $S; sync; }
sleep 360
mark "wd: woke"
pkill pppd
sleep 3
mark "wd: pkilled pppd"
pgrep pppd >/dev/null 2>&1 && { pkill -9 pppd; sleep 2; mark "wd: needed SIGKILL"; }
stty sane < /dev/console 2>/dev/null
mark "wd: stty sane done"
R=/x/PPPUP.TXT
echo "=== ifconfig -a" > $R 2>&1
ifconfig -a >> $R 2>&1
echo "" >> $R; echo "=== netstat -rn" >> $R
netstat -rn >> $R 2>&1
echo "" >> $R; echo "=== netstat -s (ICMP/IP counters)" >> $R
netstat -s >> $R 2>&1
echo "" >> $R; echo "=== guest pppd log" >> $R
cat /tmp/gppp.log >> $R 2>&1
sync
mark "wd: results written"
cd /
umount /x 2>/dev/null
sync
mark "wd: about to init 5"
init 5
