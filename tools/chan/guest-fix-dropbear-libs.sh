#!/bin/sh
# Build libtommath.a / libtomcrypt.a by hand, then finish dropbear.
#
# WHY: /usr/sfw/bin/gmake is GNU Make 3.80 (2002). libtommath 1.2.x's Makefile needs
# 3.81+ and fails with
#     Makefile:122: *** missing separator.  Stop.
# The COMPILE step is fine -- 408 objects built with zero errors. Only the archive
# step is unreachable, so we run ar/ranlib ourselves instead of building a newer make.
set -u
SRC=/var/tmp/dropbear-2022.83
PATH=/opt/csw/gcc4/bin:/opt/csw/sparc-sun-solaris2.9/bin:/usr/bin:/usr/ccs/bin
export PATH
CFLAGS="-Os -I. -I../ -I./../"

build_ar() {
    dir=$1; lib=$2
    cd "$SRC/$dir" || exit 1
    if [ -f "$lib" ]; then
        echo "$dir/$lib exists"
        return 0
    fi
    n=`find . -name '*.o' | wc -l`
    echo "$dir: $n objects present"
    if [ "$n" -lt 10 ]; then
        echo "$dir: compiling ..."
        for c in `find . -name '*.c' | grep -v _test`; do
            o=`echo "$c" | sed 's/\.c$/.o/'`
            [ -f "$o" ] && continue
            gcc $CFLAGS -c "$c" -o "$o" 2>> /var/tmp/${dir}_cc.log
        done
    fi
    # ar with a huge argv can exceed the exec limit, so append in batches.
    find . -name '*.o' | xargs -n 60 /usr/ccs/bin/ar rcs "$lib"
    /usr/ccs/bin/ranlib "$lib" 2>/dev/null
    ls -l "$lib" 2>&1 | tail -1
}

build_ar libtommath libtommath.a
build_ar libtomcrypt libtomcrypt.a

echo "linking dropbear ..."
cd "$SRC" || exit 1
/usr/sfw/bin/gmake dbclient dropbearkey >> /var/tmp/dbmake.log 2>&1
echo "gmake exit=$?"
if [ -x dbclient ]; then
    cp dbclient dropbearkey /opt/niag/bin/
    chmod 755 /opt/niag/bin/dbclient /opt/niag/bin/dropbearkey
    echo "INSTALLED /opt/niag/bin/dbclient"
else
    echo "still no dbclient; last errors:"
    grep -i 'error\|undefined' /var/tmp/dbmake.log | tail -6
fi
