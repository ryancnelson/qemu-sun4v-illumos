#!/bin/sh
# The SMF manifests are on disk but were never imported into the repository, so
# svcadm cannot find svc:/network/telnet:default at all. Import, then enable.
PATH=/usr/bin:/usr/sbin:/sbin
export PATH
mkdir -p /x
mount -F pcfs /dev/dsk/c0t0d0s3:c /x 2>/dev/null
R=/x/NETSVC2.TXT
: > $R

echo "=== manifests available under /var/svc/manifest/network" >> $R
ls /var/svc/manifest/network/ >> $R 2>&1
echo "" >> $R
echo "=== how many services are in the repository at all?" >> $R
svcs -a 2>&1 | wc -l >> $R
echo "=== all of them" >> $R
svcs -aH 2>&1 | awk '{print $1, $3}' >> $R
echo "" >> $R

echo "=== importing inetd, telnet, ftp manifests" >> $R
for m in inetd inetd-upgrade telnet ftp rlogin rexec shell login finger; do
  if [ -f /var/svc/manifest/network/$m.xml ]; then
    echo "-- import $m" >> $R
    svccfg import /var/svc/manifest/network/$m.xml >> $R 2>&1
  fi
done
echo "" >> $R

echo "=== enable them" >> $R
svcadm enable svc:/network/inetd:default >> $R 2>&1
sleep 10
svcadm enable svc:/network/telnet:default >> $R 2>&1
svcadm enable svc:/network/ftp:default >> $R 2>&1
sleep 30
echo "" >> $R

echo "=== AFTER: state" >> $R
svcs -a 2>&1 | egrep 'inetd|telnet|ftp' >> $R 2>&1
echo "" >> $R
echo "=== LISTENING sockets" >> $R
netstat -an -f inet 2>&1 | egrep 'LISTEN' >> $R 2>&1
echo "" >> $R
echo "=== inetd log if it failed" >> $R
tail -20 /var/svc/log/network-inetd:default.log >> $R 2>&1
echo "" >> $R
tail -20 /var/svc/log/network-telnet:default.log >> $R 2>&1
echo "=== DONE" >> $R
sync
cd /
umount /x 2>/dev/null
sync
init 5
