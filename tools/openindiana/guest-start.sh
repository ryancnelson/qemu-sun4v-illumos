#!/sbin/sh
# Start the OpenIndiana side of the Niagara shared-disk services.

PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH
NIAG=/lib/niag
# The current multi-unit topology reserves unit 101 / hsimd1 for channels.
# OpenIndiana enumerates that device as c4d1 in the validated 100/101/103
# layout.  Keep an explicit override for diagnostic renumbering, but never
# silently fall back to the installation target (c4d0).
DEV=${NIAG_CHAN_DEV:-/dev/rdsk/c4d1s2}

case "${1:-start}" in
start)
	[ -c "$DEV" ] || exit 0
	mkdir -p /tmp

	# Refuse to add a second writer on top of a still-live prior instance.
	# This is the same class of bug as host-up.sh's leaked-bridge problem:
	# "just start another one" silently corrupts the single-writer channel
	# handshake instead of failing loudly.
	existing=$(/usr/bin/pgrep -lf 'guest-chand|guest-rootpty|guest-ppp-chan|pppd' 2>/dev/null)
	if [ -n "$existing" ]; then
		echo "START REFUSED: services already running, run 'stop' first:" >&2
		echo "$existing" >&2
		exit 1
	fi
	/usr/sbin/devfsadm -i sppp -i sppptun >/tmp/niag-devfsadm.log 2>&1

	# The recovered binary's numeric override is not ABI-safe on this userland.
	# This remaster patches its compiled default to block 640 in whole-disk s2:
	# byte 327680, the start of s7 on the dedicated 32 MiB unit-101 disk.
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
	# IDEMPOTENT STOP. The original version only killed pppd/guest-chand/socat
	# and left guest-ppp-chan.pl (a perl wrapper, matched by none of those
	# patterns) and guest-rootpty.sh (a `while true` loop that just respawns
	# socat) running. Repeated start/stop cycles then stacked up duplicate
	# rootpty helpers and duplicate ppp wrappers -- multiple writers on one
	# single-writer channel control block, which is the exact "PPP does not
	# come up after a reboot" symptom this project chased for hours before
	# finding it was a leaked-process bug, not a protocol bug. See
	# notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md, 2026-08-25 incident.
	#
	# Kill the wrapper LOOPS first, or their `sleep 1; retry` bodies will just
	# refork the workers this same pass killed.
	/usr/bin/pkill -9 -f guest-ppp-chan.pl 2>/dev/null
	/usr/bin/pkill -9 -f guest-rootpty.sh 2>/dev/null
	/usr/bin/pkill -9 pppd 2>/dev/null
	/usr/bin/pkill -9 guest-chand 2>/dev/null
	/usr/bin/pkill -9 socat 2>/dev/null

	# Assert, don't assume: a kill that silently failed to land is the exact
	# bug this rewrite exists to prevent. Give it a moment then verify zero.
	sleep 1
	remaining=$(/usr/bin/pgrep -lf 'guest-chand|guest-rootpty|guest-ppp-chan|pppd' 2>/dev/null)
	if [ -n "$remaining" ]; then
		echo "STOP FAILED, still running:" >&2
		echo "$remaining" >&2
		exit 1
	fi
	echo "niagara: stop verified, zero matching processes"
	;;
restart)
	# Compose from the two verified-idempotent primitives above rather than
	# duplicating their logic. Propagate failure instead of masking it.
	"$0" stop || exit 1
	"$0" start || exit 1
	;;
esac

exit 0
