#!/bin/sh
# Diagnose why inetd is offline, THEN hand the console to PPP.
# Order matters: diagnostics first, because once pppd owns the console we
# cannot ask the guest anything.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
mkdir -p /x
mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null
R=/x/SMFDIAG.TXT
: > $R
echo "=== svcs -x (what is actually broken)" >> $R
svcs -x >> $R 2>&1
echo "" >> $R
echo "=== svcs -l network/inetd:default" >> $R
svcs -l svc:/network/inetd:default >> $R 2>&1
echo "" >> $R
echo "=== inetd dependencies" >> $R
svcs -d svc:/network/inetd:default >> $R 2>&1
echo "" >> $R
echo "=== milestone manifests on disk" >> $R
ls /var/svc/manifest/milestone/ >> $R 2>&1
echo "=== DONE" >> $R
sync
umount /x 2>/dev/null

# Now PPP. Watchdog returns the console and halts cleanly.
nohup /tmp/wd.sh >/dev/null 2>&1 &
stty raw -echo < /dev/console
exec pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff 10.0.5.15:10.0.5.1 nodetach debug 2>/tmp/gppp.log
