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
for f in chan.h guest-chand.c guest-echocli.c; do
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
ln -sf $RC /etc/rc3.d/S99niagchan
ln -sf $RC /etc/rc0.d/K01niagchan

echo "installed:"
ls -l $BIN/guest-chand $BIN/guest-echocli
echo "rc script: $RC  (S99niagchan in rc3.d, channels=$N)"
echo
echo "NOTE: the daemons need the shared region initialised by the host FIRST."
echo "      Prefer 'sudo bash tools/chan/chan-up.sh' from the host, which"
echo "      enforces stop -> init -> guest -> host ordering."
