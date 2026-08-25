#!/bin/sh
# Build dropbear in the guest: a modern SSH client/server for this 2005 image.
#   guest#  sh /share/chan/guest-build-dropbear.sh
#
# WHY DROPBEAR over OpenSSH: it bundles libtomcrypt/libtommath, so it needs NO
# OpenSSL. Sun_SSH 1.1 (2005) only speaks diffie-hellman-group1-sha1 and ssh-rsa,
# which modern clients refuse by default; dropbear 2022.83 brings curve25519,
# chacha20-poly1305 and ed25519.
#
# EVERY LESSON FROM THE SOCAT BUILD IS APPLIED HERE:
#  - GREP/EGREP point at /usr/xpg4/bin/grep. Stock /usr/bin/grep cannot do -e or
#    long lines and configure rejects it. Do NOT put /usr/xpg4/bin on PATH: those
#    ISO packages are from a later Solaris 10 update and /usr/xpg4/bin/ls dies on
#    libsec.so.1 SUNW_1.2.
#  - Bourne-shell only: no `test -nt`, no `cmd || { ...; }`. Verify with `sh -n` IN
#    THE GUEST, not on the host -- the shells differ and a syntax error here
#    silently kills the build.
#  - Keep every command well under the ~256-byte tty line limit; that is why this
#    is a script rather than a command line.
#  - -R for runpath, not just -L, if any lib outside /usr/lib is used.
set -u
SRC=/var/tmp/dropbear-2022.83
PATH=/opt/csw/gcc4/bin:/opt/csw/sparc-sun-solaris2.9/bin:/usr/bin:/usr/ccs/bin
export PATH
CC=gcc; export CC
GREP=/usr/xpg4/bin/grep; export GREP
EGREP="/usr/xpg4/bin/grep -E"; export EGREP

if [ ! -x /usr/ccs/bin/make ]; then
    echo "installing dev tools (ar, ranlib, nm, strings) ..."
    # Extract into a staging dir, NOT '/'. These tars were built on the host and
    # carry uid/gid 1000. Extracting them at '/' as root re-owned '/' itself to
    # 1000:1000 drwxrwxr-x, which silently broke dropbear's home-directory
    # permission check ("/ must be owned by user or root, and not writable by
    # others") and would break any other tool that audits root's home.
    cd / && tar xf /share/chan/devtools.tar || exit 1
    chown root:root / && chmod 755 /
    chown -R root:root /usr/ccs /usr/sfw 2>/dev/null
fi
# GNU make is REQUIRED, not optional: dropbear's Makefile uses GNU syntax and
# Solaris /usr/ccs/bin/make dies with
#   make: Fatal error in reader: Makefile, line 12: Unexpected end of line seen
# SUNWgmake on CD5 provides /usr/sfw/bin/gmake.
if [ ! -x /usr/sfw/bin/gmake ]; then
    echo "installing GNU make ..."
    cd / && tar xf /share/chan/gmake.tar || exit 1
fi
[ -x /usr/sfw/bin/gmake ] || { echo "no gmake after install"; exit 1; }
MAKE=/usr/sfw/bin/gmake

if [ ! -d "$SRC" ]; then
    cd /var/tmp || exit 1
    tar xf /share/chan/db.tar || exit 1
fi
cd "$SRC" || exit 1

if [ ! -f config.h ]; then
    echo "configuring ..."
    ./configure --disable-zlib --disable-syslog > /var/tmp/dbconf.log 2>&1
    echo "configure exit=$?"
    tail -3 /var/tmp/dbconf.log
fi
[ -f config.h ] || { echo "NO config.h - see /var/tmp/dbconf.log"; exit 1; }

echo "making (this is the long part) ..."
$MAKE PROGRAMS="dbclient dropbearkey" > /var/tmp/dbmake.log 2>&1
echo "make exit=$?"
if [ -x dbclient ]; then
    cp dbclient dropbearkey /opt/niag/bin/ 2>/dev/null
    chmod 755 /opt/niag/bin/dbclient /opt/niag/bin/dropbearkey
    echo "installed /opt/niag/bin/dbclient"
    /opt/niag/bin/dbclient -V 2>&1 | head -2
else
    echo "no dbclient; last errors:"
    grep -i error /var/tmp/dbmake.log 2>/dev/null | tail -6
fi
