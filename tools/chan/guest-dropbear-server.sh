#!/bin/sh
# Build + start the dropbear SSH SERVER in the guest, retiring the telnet path.
#   guest#  sh /share/chan/guest-dropbear-server.sh
#
# Same four walls as the client apply; see guest-build-dropbear.sh and
# guest-link-dropbear.sh. The only addition here is host keys and startup.
#
# PORT 2222, not 22: Sun_SSH may be enabled via SMF and we do not want to fight it
# for the port. Nothing about dropbear needs 22.
set -u
SRC=/var/tmp/dropbear-2022.83
PATH=/opt/csw/gcc4/bin:/opt/csw/sparc-sun-solaris2.9/bin:/usr/bin:/usr/ccs/bin
export PATH
LDFLAGS="-L/opt/csw/gcc4/lib -R/opt/csw/gcc4/lib -lssp -lrt"
export LDFLAGS

cd "$SRC" || exit 1
if [ ! -x dropbear ]; then
    echo "building server ..."
    /usr/sfw/bin/gmake dropbear LDFLAGS="$LDFLAGS" > /var/tmp/dbsrv.log 2>&1
    echo "gmake exit=$?"
fi
if [ ! -x dropbear ]; then
    echo "no dropbear binary; errors:"
    grep -i 'undefined\|Error' /var/tmp/dbsrv.log | tail -4
    exit 1
fi
cp dropbear /opt/niag/bin/ && chmod 755 /opt/niag/bin/dropbear
echo "installed /opt/niag/bin/dropbear"

# Host keys. ed25519 is the point of this exercise; RSA for older clients.
mkdir -p /etc/dropbear
for t in ed25519 rsa; do
    k=/etc/dropbear/dropbear_${t}_host_key
    if [ ! -f "$k" ]; then
        echo "generating $t host key ..."
        /opt/niag/bin/dropbearkey -t "$t" -f "$k" > /var/tmp/key_$t.log 2>&1
    fi
    ls -l "$k" 2>&1 | tail -1
done

# -E logs to stderr, -F stays in foreground; we want neither for a daemon.
/opt/niag/bin/dropbear -p 2222 \
    -r /etc/dropbear/dropbear_ed25519_host_key \
    -r /etc/dropbear/dropbear_rsa_host_key \
    > /var/tmp/dropbear.log 2>&1
echo "dropbear started rc=$?"
sleep 3
netstat -an 2>/dev/null | grep '2222' | head -2
