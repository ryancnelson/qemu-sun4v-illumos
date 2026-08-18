#!/usr/bin/perl
# Minimal inetd for one service. Solaris 10's inetd is entirely SMF-driven, and
# this image's SMF repository holds only 22 services with no milestone/network,
# so svc:/network/inetd:default stays "offline" on an unsatisfiable dependency.
# Rather than import milestone manifests into a live minimal system, do the one
# thing inetd actually does for telnet: accept, fork, and exec in.telnetd with
# the socket as fd 0/1/2.
use Socket;
$| = 1;
my $port = shift || 23;
my $prog = shift || '/usr/sbin/in.telnetd';
socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')) or die "socket: $!";
setsockopt(S, SOL_SOCKET, SO_REUSEADDR, pack("l",1));
bind(S, sockaddr_in($port, INADDR_ANY)) or die "bind: $!";
listen(S, 5) or die "listen: $!";
print "pinetd: listening on $port -> $prog\n";
$SIG{CHLD} = 'IGNORE';
while (1) {
    my $paddr = accept(C, S);
    next unless $paddr;
    my $pid = fork();
    if (!defined $pid) { close C; next; }
    if ($pid == 0) {
        close S;
        open(STDIN,  "<&C") or exit 1;
        open(STDOUT, ">&C") or exit 1;
        open(STDERR, ">&C") or exit 1;
        exec($prog) or exit 1;
    }
    close C;
}
