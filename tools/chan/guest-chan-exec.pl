#!/usr/bin/perl
# Attach a P2-014 channel socket to a program's stdin/stdout and exec it.
#
#   guest#  perl guest-chan-exec.pl <channel> <program> [args...]
#
# This is the general form of guest-ppp-chan.pl. Anything that speaks stdin/stdout
# inetd-style works:
#
#   channel 0   pppd notty ...              IP
#   channel 1   /usr/sbin/in.telnetd        interactive login with a real pty
#
# in.telnetd is the right choice for a login session rather than exec'ing a shell
# directly: it allocates the pty and runs /bin/login, so you get job control, line
# editing and authentication. Exec'ing a bare shell on a socket gives none of that
# because there is no controlling terminal. Same reason tools/guest-pinetd.pl uses
# it for TCP telnet.
#
# RECONNECTS: when the session ends the program exits, so this loops and waits for
# the next host-side connection. Without that a single logout would kill the getty
# for good -- the same defect the channel daemons had before their accept loops.

use strict;
use Socket;
use POSIX ":sys_wait_h";

my $ch   = shift;
defined $ch or die "usage: guest-chan-exec.pl <channel> <program> [args...]\n";
my @cmd  = @ARGV;
@cmd or @cmd = ('/usr/sbin/in.telnetd');
my $path = "/tmp/niag$ch";
my $log  = "/tmp/chanexec$ch.log";

open(my $L, '>>', $log);
select((select($L), $| = 1)[0]);

while (1) {
    my $S;
    unless (socket($S, PF_UNIX, SOCK_STREAM, 0) &&
            connect($S, sockaddr_un($path))) {
        print $L "waiting for $path: $!\n";
        sleep 2;
        next;
    }
    print $L "connected $path -> @cmd\n";

    my $pid = fork();
    if (!defined $pid) { print $L "fork failed: $!\n"; sleep 2; next; }
    if ($pid == 0) {
        open(STDIN,  '<&', $S) or exit 1;
        open(STDOUT, '>&', $S) or exit 1;
        open(STDERR, '>&', $S) or exit 1;
        exec(@cmd) or exit 1;
    }
    close($S);
    waitpid($pid, 0);
    print $L "session ended (status $?), waiting for the next\n";
    sleep 1;
}
