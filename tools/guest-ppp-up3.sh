#!/bin/sh
# Goal: Solaris up, networked, telnetd listening.
# Order is deliberate -- everything that needs the console happens BEFORE pppd
# takes it over, because after that we cannot ask the guest anything.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
mkdir -p /x
mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null
R=/x/SMFDIAG.TXT
: > $R

echo "=== why is inetd offline?" >> $R
svcs -x >> $R 2>&1
echo "" >> $R
echo "=== inetd dependencies" >> $R
svcs -d svc:/network/inetd:default >> $R 2>&1
echo "" >> $R

echo "=== starting the perl mini-inetd for telnet" >> $R
cp /x/PINETD.PL /usr/local/bin/pinetd 2>/dev/null || cp /x/PINETD.PL /tmp/pinetd
[ -f /usr/local/bin/pinetd ] && P=/usr/local/bin/pinetd || P=/tmp/pinetd
chmod +x $P
nohup /usr/bin/perl $P 23 /usr/sbin/in.telnetd > /tmp/pinetd.log 2>&1 &
sleep 5
cat /tmp/pinetd.log >> $R 2>&1
echo "" >> $R
echo "=== is 23 LISTENING?" >> $R
netstat -an -f inet 2>&1 | sed -n '/\.23 /p' >> $R 2>&1
echo "" >> $R
echo "=== login policy (must allow root, no password)" >> $R
sed -n '/^#*CONSOLE/p;/^PASSREQ/p' /etc/default/login >> $R 2>&1
echo "=== DONE" >> $R
sync
cd /
umount /x 2>/dev/null
sync

# NO WATCHDOG. It existed only to claw the console back before telnet worked,
# and it was actively killing live sessions: `sleep 360; pkill pppd` tore down
# the link every six minutes while someone was using it. Shut down instead with
# `tools/net-down.sh`, or keep work with `tools/checkpoint.sh`.
stty raw -echo < /dev/console
exec pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff 10.0.5.15:10.0.5.1 nodetach debug 2>/tmp/gppp.log
