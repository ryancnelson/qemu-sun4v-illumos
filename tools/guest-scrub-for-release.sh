#!/bin/sh
# Scrub the guest image of operator-specific data before distribution.
#   guest#  sh /opt/niag/bin/guest-scrub-for-release.sh
#
# Run this LAST, from the CONSOLE, not over ssh -- it removes authorized_keys and
# therefore your own way in. Afterwards, flush and snapshot from the host:
#   guest#  lockfs -f / ; sync
#   host$   sudo kill -USR2 <qemu-pid> ; <snapshot/copy> ; verify with peek.sh
#
# WHY THE HOST KEYS GO. Shipping /etc/dropbear/* and /etc/ssh/ssh_host_* means every
# person who downloads this shares one host identity: identical fingerprints, and a
# trivial man-in-the-middle. That is a security defect, not a privacy nicety. Deleting
# them is safe because /etc/init.d/dropbear regenerates any missing key at boot.
set -u

echo "=== removing operator credentials ==="
if [ -f /.ssh/authorized_keys ]; then
    rm -f /.ssh/authorized_keys
    echo "  /.ssh/authorized_keys removed"
fi
rm -f /.ssh/known_hosts /.ssh/id_* 2>/dev/null

echo "=== removing host identities (regenerated on next boot) ==="
rm -f /etc/dropbear/dropbear_*_host_key
rm -f /etc/ssh/ssh_host_*key /etc/ssh/ssh_host_*key.pub
echo "  dropbear + Sun_SSH host keys removed"

echo "=== removing shell and admin history ==="
rm -f /.bash_history /.sh_history /root/.bash_history 2>/dev/null
for f in /var/adm/sulog /var/adm/messages /var/adm/wtmpx /var/adm/utmpx \
         /var/adm/lastlog /var/log/syslog /var/log/authlog; do
    [ -f "$f" ] && : > "$f"
done
echo "  histories and logs truncated"

echo "=== removing build scratch ==="
# Build trees are large and full of absolute paths from the machine that built them.
rm -rf /var/tmp/dropbear-2022.83 /var/tmp/socat-1.7.3.4 2>/dev/null
rm -f /var/tmp/*.log /var/tmp/c[0-9].log /var/tmp/ec[0-9].log 2>/dev/null
rm -f /var/tmp/dial*.log /var/tmp/get.out /var/tmp/*.out 2>/dev/null
echo "  scratch removed"

echo "=== what remains that is operator-specific ==="
# Report rather than assume: anything listed here is a deliberate decision.
for f in /etc/hosts /etc/defaultrouter /etc/nodename; do
    [ -f "$f" ] && echo "  $f:" && sed 's/^/    /' "$f"
done

echo "=== verification ==="
printf "  authorized_keys : "; [ -f /.ssh/authorized_keys ] && echo "STILL PRESENT" || echo "gone"
printf "  dropbear keys   : "; ls /etc/dropbear/ 2>/dev/null | wc -l
printf "  bash_history    : "; [ -f /.bash_history ] && echo "STILL PRESENT" || echo "gone"
echo
echo "Now, on the console: lockfs -f / ; sync    then snapshot from the host."
