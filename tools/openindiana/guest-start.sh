#!/sbin/sh
# Start the OpenIndiana side of the Niagara shared-disk services.

PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH
NIAG=/lib/niag
DEV=/dev/rdsk/c4d0s2

case "${1:-start}" in
start)
	[ -c "$DEV" ] || exit 0
	mkdir -p /tmp
	/usr/sbin/devfsadm -i sppp -i sppptun >/tmp/niag-devfsadm.log 2>&1

	# The recovered binary's numeric override is not ABI-safe on this userland.
	# This remaster patches its compiled default to block 1258240 in whole-disk
	# s2: the 16 MiB reserved channel region immediately after the source ISO.
	NIAG_CHAN_DEV=$DEV; export NIAG_CHAN_DEV
	NIAG_SOCAT=$NIAG/socat; export NIAG_SOCAT
	nohup "$NIAG/guest-chand" 0 /tmp/niag0 \
	    >/tmp/niag-chand0.log 2>&1 </dev/null &
	nohup "$NIAG/guest-chand" 1 /tmp/niag1 \
	    >/tmp/niag-chand1.log 2>&1 </dev/null &

	# Both clients retry until their corresponding host bridge appears.
	nohup /usr/bin/perl "$NIAG/guest-ppp-chan.pl" 0 10.0.5.15:10.0.5.1 \
	    >/tmp/niag-ppp-wrapper.log 2>&1 </dev/null &
	nohup /sbin/sh "$NIAG/guest-rootpty.sh" 1 \
	    >/tmp/niag-rootpty.log 2>&1 </dev/null &

	if [ ! -s /etc/resolv.conf ]; then
		echo 'nameserver 8.8.8.8' >/etc/resolv.conf
	fi
	;;
stop)
	/usr/bin/pkill -9 pppd 2>/dev/null
	/usr/bin/pkill -9 guest-chand 2>/dev/null
	/usr/bin/pkill -9 socat 2>/dev/null
	;;
esac

exit 0
