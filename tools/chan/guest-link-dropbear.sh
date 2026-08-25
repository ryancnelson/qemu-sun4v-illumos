#!/bin/sh
# Finish dropbear: link against libssp for the stack protector runtime.
#
# WHY: configure enables -fstack-protector, so every object references
#   undefined reference to `__stack_chk_fail'
# glibc provides that in libc; Solaris 10's libc does NOT. gcc ships it in libssp,
# which on this image lives at /opt/csw/gcc4/lib/libssp.so -- MISPLACED, not missing,
# which is the recurring rule for this image (tcpd.h, libwrap, SMF manifests, libssp).
#
# Keeping the hardening and adding -lssp is better than -fno-stack-protector: the
# library is already on disk, and -R bakes the runpath so ld.so.1 finds it without
# LD_LIBRARY_PATH. -L alone satisfies the linker but NOT the runtime linker.
set -u
SRC=/var/tmp/dropbear-2022.83
PATH=/opt/csw/gcc4/bin:/opt/csw/sparc-sun-solaris2.9/bin:/usr/bin:/usr/ccs/bin
export PATH
cd "$SRC" || exit 1
LDFLAGS="-L/opt/csw/gcc4/lib -R/opt/csw/gcc4/lib -lssp -lrt"
export LDFLAGS
/usr/sfw/bin/gmake dbclient dropbearkey LDFLAGS="$LDFLAGS" \
    > /var/tmp/dblink.log 2>&1
echo "gmake exit=$?"
if [ -x dbclient ]; then
    cp dbclient dropbearkey /opt/niag/bin/
    chmod 755 /opt/niag/bin/dbclient /opt/niag/bin/dropbearkey
    echo "INSTALLED /opt/niag/bin/dbclient"
    ldd /opt/niag/bin/dbclient 2>&1 | grep -i 'not found' | head -3
else
    echo "no dbclient; errors:"
    grep -i 'undefined\|Error' /var/tmp/dblink.log | tail -4
fi
