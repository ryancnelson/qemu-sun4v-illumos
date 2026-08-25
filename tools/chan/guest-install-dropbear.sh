#!/bin/sh
# Make dropbear the guest's boot-time SSH server and retire Sun_SSH.
#   guest#  sh /share/chan/guest-install-dropbear.sh
set -u
mkdir -p /etc/dropbear
cp /share/chan/guest-dropbear-rc.sh /etc/init.d/dropbear
chmod 755 /etc/init.d/dropbear
chown root:root /etc/init.d/dropbear
rm -f /etc/rc3.d/S99dropbear
ln -s /etc/init.d/dropbear /etc/rc3.d/S99dropbear
echo "rc script:"
ls -l /etc/rc3.d/S99dropbear

# Retire Sun_SSH. It is SMF-managed, so disabling the service is the durable way;
# -s waits for the state change rather than returning immediately.
echo "disabling Sun_SSH ..."
/usr/sbin/svcadm disable -s svc:/network/ssh:default 2>/dev/null
/usr/bin/svcs -H -o state,fmri svc:/network/ssh:default 2>/dev/null

echo "sshd processes remaining: `ps -ef | grep sshd | grep -v grep | wc -l`"
echo "dropbear in rc3.d: `ls /etc/rc3.d/ | grep dropbear`"
