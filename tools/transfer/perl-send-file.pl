#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;

@ARGV == 3 or die "usage: $0 HOST PORT FILE\n";
my ($host, $port, $path) = @ARGV;

open my $input, '<', $path or die "open $path: $!\n";
binmode $input;

my $socket = IO::Socket::INET->new(
    PeerAddr => $host,
    PeerPort => $port,
    Proto     => 'tcp',
) or die "connect $host:$port: $!\n";
binmode $socket;

my ($buffer, $total) = ('', 0);
while (my $read = sysread($input, $buffer, 1024 * 1024)) {
    my $offset = 0;
    while ($offset < $read) {
        my $written = syswrite($socket, $buffer, $read - $offset, $offset);
        defined $written or die "write socket: $!\n";
        $written > 0 or die "write socket: short write\n";
        $offset += $written;
    }
    $total += $read;
}
defined $total or die "read $path: $!\n";
close $socket or die "close socket: $!\n";
close $input or die "close $path: $!\n";
print "$total bytes sent\n";
