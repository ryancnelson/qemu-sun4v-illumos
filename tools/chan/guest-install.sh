#!/bin/sh
# Run INSIDE the guest. Installs the channel daemon persistently and adds an rc
# script so channels come up on boot.
#
#   guest#  sh /share/chan/guest-install.sh [nchan]
#
# /var/tmp was where these lived during development, which is fine for a session
# but is not where a service belongs. /opt/niag survives reboots and is outside
# the areas package tools touch.
set -u
N=${1:-4}
BIN=/opt/niag/bin
SRC=/share/chan

mkdir -p $BIN || exit 1
for f in chan.h guest-chand.c guest-echocli.c guest-ppp-chan.pl; do
    [ -f "$SRC/$f" ] || { echo "missing $SRC/$f (is /share mounted?)"; exit 1; }
    cp "$SRC/$f" $BIN/ || exit 1
done

cd $BIN || exit 1
echo "building guest-chand ..."
# -lsocket -lnsl are REQUIRED on Solaris; socket/bind/listen/accept are not libc.
/opt/csw/gcc4/bin/gcc -O2 -o guest-chand guest-chand.c -lsocket -lnsl || exit 1
/opt/csw/gcc4/bin/gcc -O2 -o guest-echocli guest-echocli.c -lsocket -lnsl || exit 1
chmod 755 guest-chand guest-echocli

RC=/etc/init.d/niagchan
cat > $RC <<'RCEOF'
#!/bin/sh
# P2-014 channel daemons. One process per channel.
BIN=/opt/niag/bin
NCHAN=`cat /etc/niagchan.conf 2>/dev/null || echo 4`
case "$1" in
start)
        c=0
        while [ $c -lt $NCHAN ]; do
                $BIN/guest-chand $c > /var/tmp/chand$c.log 2>&1 &
                c=`expr $c + 1`
        done
        echo "niagchan: started $NCHAN channel(s)"
        ;;
stop)
        pkill -9 guest-chand
        echo "niagchan: stopped"
        ;;
*)      echo "usage: $0 {start|stop}"; exit 1 ;;
esac
exit 0
RCEOF
chmod 755 $RC
echo $N > /etc/niagchan.conf

# --- PPP over channel 0 at boot ------------------------------------------------
# This is what frees the console: previously pppd ran on /dev/console, so
# networking and interactive use were mutually exclusive and `init 5` afterwards
# landed in a broken OBP. Started AFTER niagchan (S99 vs S98 ordering) because it
# needs /tmp/niag0 to exist; it retries the connect regardless.
RCP=/etc/init.d/niagppp
cat > $RCP <<'RPEOF'
#!/bin/sh
# IP over P2-014 channel 0.
BIN=/opt/niag/bin
CH=`cat /etc/niagppp.conf 2>/dev/null || echo 0`
case "$1" in
start)
        /usr/bin/perl $BIN/guest-ppp-chan.pl $CH 10.0.5.15:10.0.5.1 \
            > /tmp/gppp-wrap.log 2>&1 &
        echo "niagppp: pppd starting on channel $CH"
        ;;
stop)
        pkill -9 pppd
        echo "niagppp: stopped"
        ;;
*)      echo "usage: $0 {start|stop}"; exit 1 ;;
esac
exit 0
RPEOF
chmod 755 $RCP
echo 0 > /etc/niagppp.conf
ln -sf $RCP /etc/rc3.d/S99niagppp
ln -sf $RCP /etc/rc0.d/K01niagppp

# S98, not S99: niagchan must start BEFORE niagppp (S99), which needs the
# channel sockets. Exactly ONE link -- an earlier version left both S98 and S99
# pointing here, which started two guest-chand per channel and put two writers on
# one control block.
rm -f /etc/rc3.d/S99niagchan
ln -sf $RC /etc/rc3.d/S98niagchan
ln -sf $RC /etc/rc0.d/K01niagchan

echo "installed:"
ls -l $BIN/guest-chand $BIN/guest-echocli
echo "rc scripts: $RC (S98niagchan), $RCP (S99niagppp), channels=$N"
echo
echo "NOTE: the daemons need the shared region initialised by the host FIRST."
echo "      Prefer 'sudo bash tools/chan/chan-up.sh' from the host, which"
echo "      enforces stop -> init -> guest -> host ordering."
