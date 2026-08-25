#!/bin/sh
# Getty on a P2-014 channel: respawn a login session forever.
#   guest#  /opt/niag/bin/guest-getty.sh <channel> &
#
# socat's EXEC child exits when the remote end disconnects, so a bare
#   socat UNIX-CONNECT:/tmp/niagN EXEC:/bin/login,pty,setsid,stderr
# serves exactly ONE login and then the channel goes dead. That is the same defect
# the channel daemons had before their accept loops. A real getty respawns; so does
# this.
#
# pty,setsid: /bin/login calls isatty() and refuses a bare socket, and without a
# session leader there is no job control or signal delivery. This is the one job that
# actually needed socat rather than perl -- perl 5.8.4 here has no IO::Pty.
CH=${1:-1}
SOCK=/tmp/niag$CH
while true; do
    /opt/niag/bin/socat UNIX-CONNECT:$SOCK \
        EXEC:/opt/niag/bin/guest-ttymon.sh,pty,setsid,ctty,stderr \
        >> /var/tmp/getty$CH.log 2>&1
    sleep 1
done
