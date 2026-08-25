#!/bin/sh
# Enable inetd-managed login services so the PPP link is actually usable.
# Runs INSIDE the guest; writes findings to the FAT slice; halts cleanly.
# Solaris /bin/sh: no $(...), use backticks. /bin/grep has no -E, use egrep.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
mkdir -p /x
mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null
R=/x/NETSVC.TXT
: > $R

echo "=== BEFORE: inetd + telnet service state" >> $R
svcs -a 2>&1 | egrep 'inetd|telnet|ftp|shell|login' >> $R 2>&1
echo "" >> $R

echo "=== do the SMF manifests exist?" >> $R
ls -l /var/svc/manifest/network/telnet.xml /var/svc/manifest/network/ftp.xml 2>&1 >> $R
echo "" >> $R

echo "=== legacy inetd.conf entries" >> $R
egrep '^telnet|^ftp|^shell|^login' /etc/inet/inetd.conf 2>&1 | head >> $R
echo "" >> $R

echo "=== enabling inetd, telnet, ftp" >> $R
svcadm enable svc:/network/inetd:default >> $R 2>&1
svcadm enable svc:/network/telnet:default >> $R 2>&1
svcadm enable svc:/network/ftp:default >> $R 2>&1
sleep 25
echo "" >> $R

echo "=== AFTER: service state" >> $R
svcs -a 2>&1 | egrep 'inetd|telnet|ftp' >> $R 2>&1
echo "" >> $R

echo "=== anything LISTENING now?" >> $R
netstat -an -f inet 2>&1 | egrep 'LISTEN|\*\.23|\*\.21' >> $R 2>&1
echo "" >> $R

echo "=== allow root login over the network" >> $R
# root has no password here, and we keep it that way so console auto-login in the
# test harness stays password-free. So CONSOLE= must be commented out (it
# restricts root to the console) and PASSREQ must not demand a password.
cp /etc/default/login /etc/default/login.orig
sed -e 's/^CONSOLE=/#CONSOLE=/' -e 's/^PASSREQ=YES/PASSREQ=NO/' \
    /etc/default/login.orig > /etc/default/login
egrep '^#?CONSOLE|^PASSREQ' /etc/default/login >> $R 2>&1
echo "" >> $R

echo "=== svc.startd log tail (why a service might not come online)" >> $R
tail -25 /var/svc/log/network-telnet:default.log >> $R 2>&1
echo "=== DONE" >> $R
sync
cd /
umount /x 2>/dev/null
sync
init 5
