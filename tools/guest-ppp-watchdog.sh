#!/bin/sh
# Watchdog. Returns the console, records the outcome to the FAT slice, and halts
# cleanly. Runs detached so it survives pppd owning stdin/stdout.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
sleep 300
pkill pppd
sleep 2
stty sane < /dev/console 2>/dev/null
mkdir -p /x
mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null
R=/x/PPPUP.TXT
echo "=== ifconfig -a" > $R 2>&1
ifconfig -a >> $R 2>&1
echo "" >> $R
echo "=== netstat -rn" >> $R
netstat -rn >> $R 2>&1
echo "" >> $R
echo "=== guest pppd log" >> $R
cat /tmp/gppp.log >> $R 2>&1
sync
cd /
umount /x 2>/dev/null
sync
init 5
