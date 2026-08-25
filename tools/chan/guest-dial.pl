#!/usr/bin/perl
# Dial the host BBS from the guest, then optionally hand the line to pppd.
#
#   guest#  perl /opt/niag/bin/guest-dial.pl 1                 # interactive terminal
#   guest#  perl /opt/niag/bin/guest-dial.pl 1 --ppp 10.0.6.15:10.0.6.1
#
# This is the 1995 dial-up sequence, faithfully: talk to the modem, get CONNECT, land
# in character mode at the ISP prompt, then say STARTPPP and let the SAME file
# descriptor become a PPP link. Nothing on the host has to be started by hand, which is
# the whole point -- the caller decides when networking begins.
#
# WHY PERL. Solaris 10 has perl 5.8.4 with Socket/sockaddr_un (verified), and no
# python at all. socat exists now but cannot do the read-then-exec handoff on one fd.
use strict;
use Socket;

my $chan = shift @ARGV;
die "usage: $0 <channel> [--ppp local:remote] [--number N]\n" unless defined $chan;

my ($ppp, $number) = (undef, "18005551212");
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '--ppp')    { $ppp = shift @ARGV }
    elsif ($a eq '--number') { $number = shift @ARGV }
    else                     { die "unknown option $a\n" }
}

my $path = "/tmp/niag$chan";
socket(my $S, PF_UNIX, SOCK_STREAM, 0) or die "socket: $!\n";
connect($S, sockaddr_un($path))        or die "connect $path: $!\n";
$| = 1;
select((select($S), $| = 1)[0]);

# Read until a pattern appears or we time out. select() rather than alarm() so a
# partial line cannot wedge us -- the failure mode that made every earlier expect
# script in this project unreliable.
# One buffer shared by every await(). A per-call buffer LOSES data: the banner and the
# 'isp>' prompt arrive in the SAME read as CONNECT, so a second await with a fresh
# buffer waits forever for text it already threw away. That bug cost a test cycle.
my $PENDING = "";

sub await {
    my ($want, $secs) = @_;
    return (1, $PENDING) if $PENDING =~ /$want/;
    my $buf = $PENDING;
    my $deadline = time + $secs;
    while (time < $deadline) {
        my $rin = ''; vec($rin, fileno($S), 1) = 1;
        next unless select(my $r = $rin, undef, undef, 1);
        my $chunk = "";
        my $n = sysread($S, $chunk, 4096);
        return (0, $buf) unless $n;      # carrier dropped
        $buf .= $chunk;
        $PENDING = $buf;
        print $chunk;
        return (1, $buf) if $buf =~ /$want/;
    }
    return (0, $buf);
}

print "dialing $number on channel $chan ...\n";
syswrite($S, "ATDT$number\r\n");

my ($ok, $seen) = await('CONNECT', 30);
unless ($ok) {
    print "\nNO CARRIER (no CONNECT within 30s)\n";
    exit 1;
}
($ok, $seen) = await('isp>', 30);
unless ($ok) {
    print "\nconnected but no prompt within 30s\n";
    exit 1;
}

unless (defined $ppp) {
    # Interactive: shuttle the terminal both ways until either side hangs up.
    print "\n[connected - type commands, ^D to hang up]\n";
    while (1) {
        my $rin = '';
        vec($rin, fileno($S), 1)     = 1;
        vec($rin, fileno(STDIN), 1)  = 1;
        select(my $r = $rin, undef, undef, undef);
        if (vec($r, fileno($S), 1)) {
            my $c = ""; my $n = sysread($S, $c, 4096);
            last unless $n;
            print $c;
        }
        if (vec($r, fileno(STDIN), 1)) {
            my $c = ""; my $n = sysread(STDIN, $c, 4096);
            last unless $n;
            $c =~ s/\n/\r\n/g;
            syswrite($S, $c);
        }
    }
    print "\nNO CARRIER\n";
    exit 0;
}

# --- PPP handoff ----------------------------------------------------------------
my ($local, $remote) = split /:/, $ppp, 2;
die "--ppp wants local:remote\n" unless $local && $remote;

print "\nrequesting PPP mode ...\n";
syswrite($S, "STARTPPP\r\n");
# The host prints a line or two before it execs pppd. Give it a moment; pppd tolerates
# leading garbage before LCP, exactly as a real modem session did.
await('PPP mode', 15);
sleep 1;

my $pppd = -x '/usr/bin/pppd'  ? '/usr/bin/pppd'
         : -x '/usr/sbin/pppd' ? '/usr/sbin/pppd'
         : die "no pppd found\n";

open(STDIN,  '<&', $S) or die "dup stdin: $!\n";
open(STDOUT, '>&', $S) or die "dup stdout: $!\n";
# noccp/nodeflate/nobsdcomp/novj: Solaris sppp implements none of them, and offering
# them logs 'sppp: unknown protocol 0xfd' for every frame.
exec($pppd, 'notty', 'noauth', 'local',
     'noccp', 'nodeflate', 'nobsdcomp', 'novj',
     'persist', 'maxfail', '0',
     'asyncmap', '0xffffffff',
     "$local:$remote", 'nodetach') or die "exec pppd: $!\n";
