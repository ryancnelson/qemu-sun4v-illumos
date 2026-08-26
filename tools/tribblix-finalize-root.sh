#!/bin/ksh
# Finalize an already-populated Tribblix UFS alternate root.
# Run on a Solaris donor with ALTROOT mounted from a disposable image copy.
set -u

usage()
{
        echo "usage: $0 altroot pkgdir admin base-list extra-list hsimd channel-dir ppp-dir" >&2
        exit 2
}

[ $# -eq 8 ] || usage
ALTROOT=$1
PKGDIR=$2
ADMIN=$3
BASELIST=$4
EXTRALIST=$5
HSIMD=$6
CHANDIR=$7
PPPDIR=$8
GATE_INSTALLER=$CHANDIR/../install-tribblix-devfsadm-rw-gate.sh
GATE_WRAPPER=$CHANDIR/../tribblix-devfsadm-rw-wrapper.sh

case "$ALTROOT" in
/|""|/a/../*|*/../*)
        echo "ERROR: unsafe alternate root: $ALTROOT" >&2
        exit 1
        ;;
esac

for f in "$ADMIN" "$BASELIST" "$EXTRALIST" "$HSIMD" \
    "$CHANDIR/guest-getty.sh" "$CHANDIR/guest-ttymon.sh" "$CHANDIR/guest-niagchan.init" \
    "$CHANDIR/guest-niaggetty.init" "$CHANDIR/guest-ppp-chan.pl" \
    "$CHANDIR/guest-ppp-supervisor.sh" "$CHANDIR/guest-niagppp.init" \
    "$CHANDIR/../tribblix-resolv.conf" \
    "$GATE_INSTALLER" "$GATE_WRAPPER" \
    "$PPPDIR/pppd64-tribblix" "$PPPDIR/guest-utmp-ttymon" \
    "$PPPDIR/kernel/drv/sparcv9/sppp" \
    "$PPPDIR/kernel/drv/sparcv9/sppptun" "$PPPDIR/kernel/drv/sppp.conf" \
    "$PPPDIR/kernel/drv/sppptun.conf" \
    "$PPPDIR/kernel/strmod/sparcv9/spppasyn" \
    "$PPPDIR/kernel/strmod/sparcv9/spppcomp"
do
        [ -f "$f" ] || { echo "ERROR: missing input $f" >&2; exit 1; }
done

# Install the gate before any newly installed service or subsequent boot can
# invoke devfsadm.  This is also the standalone hook used when ALTROOT is a
# copied boot archive mounted read-write through lofi.
/usr/bin/ksh "$GATE_INSTALLER" "$ALTROOT" "$GATE_WRAPPER" || exit 1
[ -d "$PKGDIR" ] || { echo "ERROR: missing package directory $PKGDIR" >&2; exit 1; }
[ -f "$ALTROOT/etc/vfstab" ] || { echo "ERROR: $ALTROOT is not a system root" >&2; exit 1; }
[ -d "$ALTROOT/var/sadm/pkg" ] || { echo "ERROR: package database absent" >&2; exit 1; }
/usr/sbin/mount | /usr/bin/grep "^$ALTROOT on " >/dev/null 2>&1 || {
        echo "ERROR: $ALTROOT is not a distinct mounted filesystem" >&2
        exit 1
}

install_list()
{
        list=$1
        /usr/bin/grep -v '^#' "$list" | /usr/bin/grep -v '^$' | while read pkg
        do
                if /usr/bin/pkginfo -R "$ALTROOT" "$pkg" >/dev/null 2>&1; then
                        echo "PRESENT $pkg"
                        continue
                fi
                [ -d "$PKGDIR/$pkg" ] || {
                        echo "ERROR: unpacked source is absent for $pkg" >&2
                        exit 1
                }
                echo "INSTALL $pkg from $PKGDIR"
                /usr/sbin/pkgadd -n -a "$ADMIN" -R "$ALTROOT" \
                    -d "$PKGDIR" "$pkg" || exit 1
        done
}

install_list "$BASELIST" || exit 1
install_list "$EXTRALIST" || exit 1

/usr/bin/mkdir -p "$ALTROOT/var/sadm/overlays/installed" || exit 1
/usr/bin/touch "$ALTROOT/var/sadm/overlays/installed/base" || exit 1

if /usr/bin/pkginfo -R "$ALTROOT" TRIBsys-install-media-internal >/dev/null 2>&1; then
        echo "REMOVE TRIBsys-install-media-internal"
        /usr/sbin/pkgrm -n -a "$ADMIN" -R "$ALTROOT" \
            TRIBsys-install-media-internal || exit 1
fi

/usr/bin/rm -f "$ALTROOT/etc/rc2.d/S99auto_install"
/usr/bin/bzip2 -dc "$ALTROOT/usr/lib/zap/repository-installed.db.bz2" \
    > "$ALTROOT/etc/svc/repository.db.new" || exit 1
/usr/bin/chmod 600 "$ALTROOT/etc/svc/repository.db.new" || exit 1
/usr/bin/mv "$ALTROOT/etc/svc/repository.db.new" \
    "$ALTROOT/etc/svc/repository.db" || exit 1

PLATFORM_HSIMD="$ALTROOT/platform/sun4v/kernel/drv/sparcv9/hsimd"
/usr/bin/cp "$HSIMD" "$PLATFORM_HSIMD" || exit 1
/usr/bin/chown root:sys "$PLATFORM_HSIMD" || exit 1
/usr/bin/chmod 755 "$PLATFORM_HSIMD" || exit 1

NIAGBIN="$ALTROOT/opt/niag/bin"
/usr/bin/mkdir -p "$NIAGBIN" || exit 1
/usr/bin/cp "$CHANDIR/guest-getty.sh" "$NIAGBIN/guest-getty.sh" || exit 1
/usr/bin/cp "$CHANDIR/guest-ttymon.sh" "$NIAGBIN/guest-ttymon.sh" || exit 1
/usr/bin/cp "$PPPDIR/guest-utmp-ttymon" "$NIAGBIN/guest-utmp-ttymon" || exit 1
/usr/bin/cp "$CHANDIR/guest-ppp-chan.pl" "$NIAGBIN/guest-ppp-chan.pl" || exit 1
/usr/bin/cp "$CHANDIR/guest-ppp-supervisor.sh" "$NIAGBIN/guest-ppp-supervisor.sh" || exit 1
/usr/bin/chmod 755 "$NIAGBIN/guest-getty.sh" "$NIAGBIN/guest-ttymon.sh" \
    "$NIAGBIN/guest-utmp-ttymon" \
    "$NIAGBIN/guest-ppp-chan.pl" \
    "$NIAGBIN/guest-ppp-supervisor.sh" || exit 1
[ -x "$NIAGBIN/guest-chand" ] || { echo "ERROR: guest-chand absent" >&2; exit 1; }
[ -x "$NIAGBIN/socat" ] || { echo "ERROR: socat absent" >&2; exit 1; }

/usr/bin/cp "$CHANDIR/guest-niagchan.init" "$ALTROOT/etc/init.d/niagchan" || exit 1
/usr/bin/cp "$CHANDIR/guest-niaggetty.init" "$ALTROOT/etc/init.d/niaggetty" || exit 1
/usr/bin/cp "$CHANDIR/guest-niagppp.init" "$ALTROOT/etc/init.d/niagppp" || exit 1
/usr/bin/chmod 755 "$ALTROOT/etc/init.d/niagchan" \
    "$ALTROOT/etc/init.d/niaggetty" "$ALTROOT/etc/init.d/niagppp" || exit 1
echo 4 > "$ALTROOT/etc/niagchan.conf"
/usr/bin/rm -f "$ALTROOT/etc/rc3.d/S99niagchan" \
    "$ALTROOT/etc/rc3.d/S99niagppp"
/usr/bin/ln -sf /etc/init.d/niagchan "$ALTROOT/etc/rc3.d/S98niagchan" || exit 1
/usr/bin/ln -sf /etc/init.d/niaggetty "$ALTROOT/etc/rc3.d/S99niaggetty" || exit 1
/usr/bin/ln -sf /etc/init.d/niagchan "$ALTROOT/etc/rc2.d/S98niagchan" || exit 1
/usr/bin/ln -sf /etc/init.d/niaggetty "$ALTROOT/etc/rc2.d/S99niaggetty" || exit 1
/usr/bin/ln -sf /etc/init.d/niaggetty "$ALTROOT/etc/rc0.d/K01niaggetty" || exit 1
/usr/bin/ln -sf /etc/init.d/niagppp "$ALTROOT/etc/rc0.d/K01niagppp" || exit 1
/usr/bin/ln -sf /etc/init.d/niagchan "$ALTROOT/etc/rc0.d/K02niagchan" || exit 1

# The installed repository can stall before the legacy rc2 transition while
# hardware-network services retry. Start disk-backed management independently.
/usr/bin/ln -sf /etc/init.d/niagchan "$ALTROOT/etc/rcS.d/S98niagchan" || exit 1
/usr/bin/ln -sf /etc/init.d/niagppp "$ALTROOT/etc/rcS.d/S99niagppp" || exit 1
/usr/bin/ln -sf /etc/init.d/niaggetty "$ALTROOT/etc/rcS.d/S99niaggetty" || exit 1

# Solaris 10 PPP kernel runtime plus the Tribblix-built 64-bit pppd. The donor
# 32-bit pppd reaches LCP but fails through the emulated 32-bit socket ABI.
/usr/bin/mkdir -p "$ALTROOT/usr/kernel/drv/sparcv9" \
    "$ALTROOT/usr/kernel/strmod/sparcv9" "$ALTROOT/etc/ppp" || exit 1
/usr/bin/cp "$PPPDIR/pppd64-tribblix" "$ALTROOT/usr/bin/pppd" || exit 1
/usr/bin/cp "$PPPDIR/kernel/drv/sparcv9/sppp" \
    "$PPPDIR/kernel/drv/sparcv9/sppptun" "$ALTROOT/usr/kernel/drv/sparcv9/" || exit 1
/usr/bin/cp "$PPPDIR/kernel/drv/sppp.conf" \
    "$PPPDIR/kernel/drv/sppptun.conf" "$ALTROOT/usr/kernel/drv/" || exit 1
/usr/bin/cp "$PPPDIR/kernel/strmod/sparcv9/spppasyn" \
    "$PPPDIR/kernel/strmod/sparcv9/spppcomp" "$ALTROOT/usr/kernel/strmod/sparcv9/" || exit 1
/usr/bin/chown root:bin "$ALTROOT/usr/bin/pppd" || exit 1
/usr/bin/chmod 4555 "$ALTROOT/usr/bin/pppd" || exit 1
/usr/bin/chown -R root:sys "$ALTROOT/usr/kernel/drv/sppp.conf" \
    "$ALTROOT/usr/kernel/drv/sppptun.conf" \
    "$ALTROOT/usr/kernel/drv/sparcv9/sppp" \
    "$ALTROOT/usr/kernel/drv/sparcv9/sppptun" \
    "$ALTROOT/usr/kernel/strmod/sparcv9/spppasyn" \
    "$ALTROOT/usr/kernel/strmod/sparcv9/spppcomp" || exit 1
/usr/bin/chmod 755 "$ALTROOT/usr/kernel/drv/sparcv9/sppp" \
    "$ALTROOT/usr/kernel/drv/sparcv9/sppptun" \
    "$ALTROOT/usr/kernel/strmod/sparcv9/spppasyn" \
    "$ALTROOT/usr/kernel/strmod/sparcv9/spppcomp" || exit 1
/usr/bin/cp "$CHANDIR/../tribblix-resolv.conf" "$ALTROOT/etc/resolv.conf" || exit 1
/usr/bin/chown root:sys "$ALTROOT/etc/resolv.conf" || exit 1
/usr/bin/chmod 644 "$ALTROOT/etc/resolv.conf" || exit 1

# This appliance's channel getty is a trusted local management path.
/usr/bin/sed 's|^CONSOLE=/dev/console|# CONSOLE=/dev/console|' \
    "$ALTROOT/etc/default/login" > "$ALTROOT/etc/default/login.new" || exit 1
/usr/bin/mv "$ALTROOT/etc/default/login.new" "$ALTROOT/etc/default/login" || exit 1

if ! /usr/bin/grep '^sppp ' "$ALTROOT/etc/name_to_major" >/dev/null 2>&1; then
        /usr/sbin/add_drv -b "$ALTROOT" sppp || exit 1
fi
if ! /usr/bin/grep '^sppptun ' "$ALTROOT/etc/name_to_major" >/dev/null 2>&1; then
        /usr/sbin/add_drv -b "$ALTROOT" sppptun || exit 1
fi

/usr/bin/grep ramdisk "$ALTROOT/etc/system" >/dev/null 2>&1 && {
        echo "ERROR: alternate root still selects a ramdisk" >&2
        exit 1
}
/usr/bin/grep '/dev/dsk/c1d0s0.*ufs' "$ALTROOT/etc/vfstab" >/dev/null 2>&1 || {
        echo "ERROR: persistent root entry missing from vfstab" >&2
        exit 1
}

echo "Updating boot archive"
/sbin/bootadm update-archive -R "$ALTROOT" || exit 1
/usr/sbin/sync
echo "FINALIZE_ROOT_OK"
