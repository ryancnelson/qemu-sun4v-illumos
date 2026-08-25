#!/bin/sh
# Runs INSIDE the guest. Answers: can pppd drive /dev/console (qcn)?
#
# All fragile tty work happens here rather than over expect, because pppd leaves
# the line in raw mode -- where CR is no longer translated to NL, so an expect
# `send "cmd\r"` never terminates the line and the session looks dead.
# Results go to the FAT slice for the host to read after a clean shutdown.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
mkdir -p /x
mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null
R=/x/PPPRES.TXT
: > $R

echo "=== uname" >> $R
uname -a >> $R 2>&1

echo "" >> $R
echo "=== termios state of /dev/console BEFORE" >> $R
stty -a < /dev/console >> $R 2>&1

echo "" >> $R
echo "=== ATTEMPT A: pppd /dev/console 115200" >> $R
( sleep 20; pkill pppd ) &
pppd /dev/console 115200 noauth local passive debug nodetach >> $R 2>&1
rc=$?
echo "exitA=$rc" >> $R
stty sane < /dev/console 2>/dev/null

echo "" >> $R
echo "=== ATTEMPT B: pppd on its controlling tty (no device arg)" >> $R
( sleep 20; pkill pppd ) &
pppd 115200 noauth local passive debug nodetach >> $R 2>&1
rc=$?
echo "exitB=$rc" >> $R
stty sane < /dev/console 2>/dev/null

echo "" >> $R
echo "=== ATTEMPT C: notty mode (pppd talks over stdin/stdout)" >> $R
( sleep 20; pkill pppd ) &
pppd notty 115200 noauth local passive debug nodetach >> $R 2>&1
rc=$?
echo "exitC=$rc" >> $R
stty sane < /dev/console 2>/dev/null

echo "" >> $R
echo "=== ifconfig -a" >> $R
ifconfig -a >> $R 2>&1

echo "" >> $R
echo "=== sppp modules loaded" >> $R
modinfo 2>/dev/null | grep sppp >> $R 2>&1

echo "=== DONE" >> $R
sync
cd /
umount /x
sync
init 5
