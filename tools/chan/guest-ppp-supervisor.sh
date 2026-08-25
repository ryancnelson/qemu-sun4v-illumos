#!/bin/sh
# Keep the guest PPP endpoint available while the host bridge comes and goes.
CH=${1:-0}
IPS=${2:-10.0.5.15:10.0.5.1}

while true; do
        /usr/bin/perl /opt/niag/bin/guest-ppp-chan.pl "$CH" "$IPS"
        sleep 2
done
