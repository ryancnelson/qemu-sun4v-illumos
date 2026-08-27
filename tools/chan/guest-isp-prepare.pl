#!/usr/bin/perl
# OpenIndiana/Solaris guest launcher for the channel-4 ISP barrier.
# Fixed profile: control ch4, PPP ch0, guest 10.0.5.15, host 10.0.5.1.
use strict;
use Socket;

my $CONTROL = '/tmp/niag4';
my $PPP = '/tmp/niag0';
my $PPPD = '/usr/bin/pppd';
my $HOST = '10.0.5.1';
my $GUEST = '10.0.5.15';
my $TTL = 45;
my $DIAL = '18005551212';

sub fail { print STDERR "guest-isp: $_[0]\n"; return 1 }

sub connect_unix {
    my ($path) = @_;
    socket(my $sock, PF_UNIX, SOCK_STREAM, 0) or return;
    connect($sock, sockaddr_un($path)) or return;
    select((select($sock), $| = 1)[0]);
    return $sock;
}

sub read_until {
    my ($sock, $pattern, $seconds, $buffer_ref) = @_;
    my $deadline = time + $seconds;
    while (time < $deadline) {
        return 1 if $$buffer_ref =~ /$pattern/;
        my $bits = '';
        vec($bits, fileno($sock), 1) = 1;
        next unless select(my $ready = $bits, undef, undef, 1);
        my $chunk = '';
        my $count = sysread($sock, $chunk, 4096);
        return 0 unless defined($count) && $count > 0;
        $$buffer_ref .= $chunk;
        return 0 if length($$buffer_ref) > 32768;
    }
    return $$buffer_ref =~ /$pattern/ ? 1 : 0;
}

sub parse_ready {
    my ($text) = @_;
    $text =~ s/\r//g;
    my @isp = grep { /^ISP / } split(/\n/, $text);
    return unless @isp == 1;
    my $line = $isp[0];
    return unless $line =~ /^ISP READY id=([0-9a-f]{4,32}) state=READY host=10\.0\.5\.1 guest=10\.0\.5\.15 expires=45$/;
    return ($1, $line);
}

sub main {
    return fail("unexpected arguments") if @ARGV;
    return fail("missing executable $PPPD") unless -x $PPPD;

    my $control = connect_unix($CONTROL);
    return fail("cannot connect $CONTROL") unless $control;
    my $seen = '';
    syswrite($control, "ATDT$DIAL\r\n");
    return fail("BBS dial timeout") unless read_until($control, qr/CONNECT 2400/, 10, \$seen);
    return fail("BBS prompt timeout") unless read_until($control, qr/isp> /, 10, \$seen);

    # Discard the modem/banner transcript before parsing the single machine line.
    $seen = '';
    my $prepare_sent = time;
    syswrite($control, "ISP PREPARE\r\n");
    return fail("ISP PREPARE timeout") unless read_until($control, qr/^ISP /m, 10, \$seen);
    # Read through the response newline, but never wait beyond the same bound.
    return fail("unterminated ISP response") unless read_until($control, qr/^ISP [^\r\n]*\r?\n/m, 1, \$seen);
    my ($id, $line) = parse_ready($seen);
    return fail("ISP response blocked or malformed") unless defined $id;
    return fail("ISP READY expired before PPP launch") if time - $prepare_sent >= $TTL;
    close($control);

    my $ppp = connect_unix($PPP);
    return fail("ISP READY id=$id but cannot connect $PPP") unless $ppp;
    open(STDIN, '<&', $ppp) or return fail("dup PPP stdin");
    open(STDOUT, '>&', $ppp) or return fail("dup PPP stdout");
    open(STDERR, '>', '/tmp/gppp-isp.log') or return fail("open PPP log");
    exec($PPPD, 'notty', 'noauth', 'local',
         'noccp', 'nodeflate', 'nobsdcomp', 'novj',
         'asyncmap', '0', 'defaultroute',
         'logfile', '/tmp/gpppd-isp.log',
         'lcp-max-configure', '10', 'lcp-restart', '3',
         "$GUEST:$HOST", 'nodetach', 'debug');
    return fail("exec $PPPD failed");
}

exit(main()) unless caller;
1;
