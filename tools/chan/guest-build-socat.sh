#!/bin/sh
# Build socat in the guest with no external library deps.
#   guest#  sh /share/chan/guest-build-socat.sh
#
# WHY FROM SOURCE and not a CSW package: the SunOS5.8 CSW socat needs
# libreadline.so.6 and libssl.so.0, and the 5.8-era CSW packages only provide
# libreadline.so.5 with no libssl0 at all. Disabling both here yields a binary
# needing only libc/libsocket/libnsl/libresolv, all in the base image -- so it
# cannot trip the SUNW_1.22.1 libc ceiling.
#
# WHY A SCRIPT and not a command line: the Solaris tty canonical input buffer caps
# a line near 256 bytes and SILENTLY truncates, dropping the CR. A ~230-char
# configure invocation came back as "working directory cannot be determined" with
# exit 137, which looks like a crash and is really a mangled command.
#
# XPG4 is required: stock /usr/bin/grep cannot do -e or long lines, and configure
# rejects it outright. SUNWxcu4/SUNWxcu6 supply /usr/xpg4/bin/grep.

set -u
SRC=/var/tmp/socat-1.7.3.4
# DO NOT put /usr/xpg4/bin first in PATH. The SUNWxcu4/xcu6 packages on the ISOs
# are from a LATER Solaris 10 update than this installed image, so some of their
# binaries need newer libraries than the image has:
#   ld.so.1: ls: fatal: libsec.so.1: version `SUNW_1.2' not found
#            (required by file /usr/xpg4/bin/ls)
# /usr/xpg4/bin/grep is fine (Jan 2005) but ls is not (Oct 2007). With xpg4 ahead of
# /usr/bin, configure broke on `ls` and reported "working directory cannot be
# determined" -- the same SUNW version ceiling that bit the OpenCSW packages, this
# time from Sun's own media.
PATH=/opt/csw/gcc4/bin:/opt/csw/sparc-sun-solaris2.9/bin:/usr/bin:/usr/ccs/bin
export PATH
CC=gcc; export CC
# autoconf takes these directly, so we get a working grep without a broken ls.
GREP=/usr/xpg4/bin/grep;  export GREP
EGREP="/usr/xpg4/bin/grep -E"; export EGREP

if [ ! -d "$SRC" ]; then
    cd /var/tmp || exit 1
    tar xf /share/chan/socat.tar || exit 1
fi
cd "$SRC" || exit 1

if [ ! -f config.h ]; then
    echo "configuring (slow: hundreds of compile tests on an emulated CPU) ..."
    ./configure --disable-openssl --disable-readline > /var/tmp/sconf.log 2>&1
    echo "configure exit=$?"
    tail -3 /var/tmp/sconf.log
fi
[ -f config.h ] || { echo "NO config.h - see /var/tmp/sconf.log"; exit 1; }


# No make needed: compile the sources directly. SUNWbtool is not installed, and
# socat is a flat set of .c files with no generated sources beyond config.h.
# EXCLUDE *_main.c: socat ships procan_main.c and filan_main.c, each with its own
# main(), so a naive `gcc *.c` compiles for ten minutes and THEN dies at link with
# duplicate main. socat's own Makefile builds those into separate binaries.
#
# Compile per-file so progress is visible. The one-shot version produced no
# intermediate output at all, which made a running build indistinguishable from a
# hung one -- exactly the ambiguity that has cost time repeatedly here.
echo "compiling ..."
: > /var/tmp/sbuild.log
# INCREMENTAL. An earlier version did `rm -f *.o` here, so every relink recompiled
# all 57 files -- roughly ten minutes to fix a one-line link error. Skip any object
# newer than its source.
n=0
for f in *.c; do
    case "$f" in *_main.c) continue ;; esac
    o=`echo "$f" | sed 's/\.c$/.o/'`
    # Plain -f, NOT -nt: Solaris /bin/sh is the original Bourne shell and its test
    # has no -nt. Sources do not change between runs here, so "object exists" is a
    # sufficient skip condition. Also avoid `cmd || { ...; }` -- that brace group is
    # what produced `line 75: `fi' unexpected` under this shell, and it silently
    # killed the build while my polling watched a corpse.
    if [ -f "$o" ]; then
        n=`expr $n + 1`
        continue
    fi
    gcc -O2 -I/usr/sfw/include -c "$f" >> /var/tmp/sbuild.log 2>&1
    if [ $? -ne 0 ]; then
        echo "FAILED on $f"
        tail -6 /var/tmp/sbuild.log
        exit 1
    fi
    n=`expr $n + 1`
    echo "  compiled $n: $f" >> /var/tmp/sprogress.log
done
# Two Solaris 10 gaps the link exposes:
#   nanosleep  -> lives in librt, not libc
#   strndup    -> does NOT EXIST in Solaris 10 libc (POSIX-2008; gcc warned about the
#                 implicit declaration during compile, which was the early hint).
# Supply strndup ourselves rather than patching socat's sources.
if [ ! -f compat_strndup.c ]; then
cat > compat_strndup.c <<'CEOF'
#include <stdlib.h>
#include <string.h>
char *strndup(const char *s, size_t n) {
    size_t len = 0;
    char *p;
    while (len < n && s[len]) len++;
    p = malloc(len + 1);
    if (!p) return NULL;
    memcpy(p, s, len);
    p[len] = '\0';
    return p;
}
CEOF
    gcc -O2 -c compat_strndup.c >> /var/tmp/sbuild.log 2>&1 \
        && echo "  built compat_strndup.o" >> /var/tmp/sprogress.log
fi

echo "linking $n objects ..."
# -I/usr/sfw/include: config.h has HAVE_LIBWRAP (not WITH_LIBWRAP, which is what an
# earlier attempt tried to unset), and tcpd.h DOES exist -- at /usr/sfw/include,
# off the default search path. Without the -I, xio-tcpwrap.c fails on undeclared
# RQ_CLIENT_SIN/RQ_SERVER_SIN/RQ_DAEMON. libwrap.so.1 is already present in
# /usr/sfw/lib from the Sun_SSH work, so keeping the feature costs nothing.
# -R/usr/sfw/lib bakes the RUNPATH in. -L alone only satisfies the LINKER; at run
# time ld.so.1 does not search /usr/sfw/lib and the binary dies with
#   ld.so.1: socat: fatal: libwrap.so.1: open failed
# Baking the path in beats requiring LD_LIBRARY_PATH at every call site.
gcc -O2 -o socat *.o -L/usr/sfw/lib -R/usr/sfw/lib \
    -lsocket -lnsl -lresolv -lwrap -lrt >> /var/tmp/sbuild.log 2>&1
rc=$?
echo "compile exit=$rc"
[ $rc -ne 0 ] && tail -12 /var/tmp/sbuild.log
if [ -x socat ]; then
    cp socat /opt/niag/bin/socat && chmod 755 /opt/niag/bin/socat
    echo "installed /opt/niag/bin/socat"
    /opt/niag/bin/socat -V 2>&1 | head -2
fi
