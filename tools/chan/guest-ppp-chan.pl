#!/usr/bin/perl
# Run pppd over a P2-014 channel instead of the console.
#
#   guest#  perl guest-ppp-chan.pl [channel] [guest-ip:host-ip]
#
# WHY PERL AND NOT socat/netcat: pppd is invoked with `notty`, so it speaks
# stdin/stdout rather than a tty. Attaching a socket to fd 0/1 is a dup2, which
# perl does natively -- no pty, no socat, no compile. Solaris 10 has neither socat
# nor nc, and getting them would mean fighting the SUNW_1.22.1 libc ceiling for
# machinery we do not need. perl 5.8.4 is already in the image and already runs
# tools/guest-pinetd.pl.
#
# WHY THIS MATTERS: PPP previously ran on /dev/console, so networking and an
# interactive console were mutually exclusive and `init 5` afterwards landed in a
# broken OBP. On a channel, the console stays free.
#
# ASYNCMAP: the console needs `asyncmap 0xffffffff` because qcn is not 8-bit
# clean.  This script is only for the dedicated hSIMD channel, which passed a
# 65,536-byte random echo and PPP/outbound-ping gates with symmetric asyncmap 0
# in term4code-02.  Escaping all control bytes on this byte-exact transport made
# negotiation fail, so keep the channel-specific value explicit here.

use strict;
use Socket;

my $ch   = defined $ARGV[0] ? $ARGV[0] : 0;
my $ips  = defined $ARGV[1] ? $ARGV[1] : '10.0.5.15:10.0.5.1';
my $path = "/tmp/niag$ch";
my $log  = "/tmp/gppp-chan$ch.log";
my $ppplog = "/tmp/gpppd-chan$ch.log";

# RETRY, do not die: at boot the guest reaches this long before the host bridge
# exists, and a one-shot connect would leave the machine with no networking until
# someone noticed. Wait indefinitely but log, so a genuinely absent host is
# diagnosable rather than silent.
open(my $W, '>>', "/tmp/gppp-chan$ch.wait");
my $S;
my $tries = 0;
while (1) {
    socket($S, PF_UNIX, SOCK_STREAM, 0) or die "socket: $!\n";
    last if connect($S, sockaddr_un($path));
    close($S);
    $tries++;
    print $W "waiting for $path (try $tries)\n" if $tries % 30 == 1;
    sleep 2;
}
print $W "connected after $tries retries\n";
close($W);

# pppd inherits the socket as stdin/stdout; stderr goes to a file so a broken
# link cannot silently swallow the diagnosis.
open(STDIN,  '<&', $S) or die "dup stdin: $!\n";
open(STDOUT, '>&', $S) or die "dup stdout: $!\n";
open(STDERR, '>',  $log);

exec('/usr/bin/pppd', 'notty', 'noauth', 'local',
     'noccp', 'nodeflate', 'nobsdcomp', 'novj',
     'asyncmap', '0', 'defaultroute', 'logfile', $ppplog,
     'persist', 'maxfail', '0',
     $ips, 'nodetach', 'debug')
    or die "exec pppd: $!\n";
