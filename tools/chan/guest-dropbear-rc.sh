#!/bin/sh
# /etc/init.d/dropbear -- start the dropbear SSH server at boot.
# Installed as /etc/rc3.d/S99dropbear by guest-install-dropbear.sh.
#
# rc3.d ONLY RUNS IF svc:/milestone/multi-user-server IS IMPORTED. On this image the
# SMF repository shipped sparse and that milestone was absent, so /sbin/rc3 never ran
# and nothing in rc3.d executed -- which is why boot automation never worked here.
# Import it with:
#     svccfg import /var/svc/manifest/milestone/multi-user.xml
#     svccfg import /var/svc/manifest/milestone/multi-user-server.xml
DB=/opt/niag/bin/dropbear
KEYDIR=/etc/dropbear
case "$1" in
start)
    [ -x "$DB" ] || exit 0
    # Regenerate host keys only if absent, so fingerprints survive reboots.
    [ -f "$KEYDIR/dropbear_ed25519_host_key" ] || \
        /opt/niag/bin/dropbearkey -t ed25519 -f "$KEYDIR/dropbear_ed25519_host_key" > /dev/null 2>&1
    [ -f "$KEYDIR/dropbear_rsa_host_key" ] || \
        /opt/niag/bin/dropbearkey -t rsa -f "$KEYDIR/dropbear_rsa_host_key" > /dev/null 2>&1
    "$DB" -p 22 \
        -r "$KEYDIR/dropbear_ed25519_host_key" \
        -r "$KEYDIR/dropbear_rsa_host_key" \
        >> /var/tmp/dropbear.log 2>&1
    # Report what is TRUE, not what was attempted. An unconditional "started" echo
    # here reported success while dropbear had actually failed to bind (address
    # already in use), which made boot evidence untrustworthy. Measure, then claim.
    sleep 2
    if /usr/bin/pgrep -f "$DB" > /dev/null 2>&1; then
        echo "dropbear RUNNING on port 22"
    else
        echo "dropbear FAILED - see /var/tmp/dropbear.log"
    fi
    ;;
stop)
    pkill -f "$DB" 2>/dev/null
    ;;
*)
    echo "usage: $0 {start|stop}"
    exit 1
    ;;
esac
exit 0
