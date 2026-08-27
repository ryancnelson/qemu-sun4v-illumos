#!/usr/bin/perl
use strict;
use Socket;
use Digest::SHA qw(sha256_hex);
use Fcntl qw(:DEFAULT);

my $socket = $ENV{NIAG_BBS_SOCKET} || "/tmp/niag4";
my $tool = $ENV{NIAG_GKERMIT} || "/usr/local/bin/gkermit";
my $root = "/rpool/kermit";
@ARGV == 1 or die "usage: guest-kermit-get.pl URL\n";
my $url = $ARGV[0];
$url =~ m{^https?://[^\s]+$} or die "direct http(s) URL required\n";
-x $tool or die "verified gkermit is not installed at $tool\n";
-d $root && !-l $root or die "$root is missing or unsafe\n";

socket(my $s, PF_UNIX, SOCK_STREAM, 0) or die "socket: $!\n";
connect($s, sockaddr_un($socket)) or die "connect: $!\n";
print $s "ATDT1\r\n";
my $ready;
my $line = "";
while (1) {
    my $ch;
    my $n = sysread($s, $ch, 1);
    defined($n) or die "read BBS response: $!\n";
    last if $n == 0;
    $line .= $ch;
    length($line) <= 4096 or die "BBS response line too long\n";
    next unless $ch eq "\n";
    $line =~ s/[\r\n]+$//;
    if ($line =~ /^isp>\s*$/) {
        print $s "KERMIT-GET $url\r\n";
    } elsif ($line =~ /^KERMIT READY /) {
        $ready = $line;
        last;
    } elsif ($line =~ /^KERMIT (?:BLOCKED|FAILED) /) {
        die "$line\n";
    }
    $line = "";
}
defined $ready or die "BBS closed before KERMIT READY\n";
$ready =~ /^KERMIT READY name=([A-Za-z0-9][A-Za-z0-9._-]{0,126}) size=([0-9]+) sha256=([0-9a-f]{64}) timeout=45$/
    or die "malformed KERMIT READY\n";
my ($name, $size, $sha) = ($1, $2, $3);
my $final = "$root/$name";
my $temp = "$root/.kermit-$name-$$.part";
!lstat($final) && !lstat($temp) or die "destination exists or is ambiguous\n";

my $pid = fork(); defined $pid or die "fork: $!\n";
if (!$pid) {
    open(STDIN, "<&", $s) && open(STDOUT, ">&", $s)
        or die "socket handoff: $!\n";
    exec($tool, "-X", "-q", "-i", "-r", "-a", $temp);
    die "exec gkermit: $!\n";
}
my $deadline = time + 45;
while (1) {
    my $done = waitpid($pid, 1);
    last if $done == $pid;
    if (time >= $deadline) {
        kill "TERM", $pid;
        my $term_deadline = time + 5;
        while (waitpid($pid, 1) == 0 && time < $term_deadline) { sleep 1; }
        if (kill 0, $pid) { kill "KILL", $pid; waitpid($pid, 0); }
        unlink($temp);
        die "Kermit receive timeout\n";
    }
    sleep 1;
}
$? == 0 or do { unlink($temp); die "Kermit receive failed\n"; };
my @st = lstat($temp); @st && -f _ && !-l _ && $st[7] == $size
    or do { unlink($temp); die "received metadata mismatch\n"; };
open(my $fh, "<", $temp) or die "open received file: $!\n";
binmode($fh); my $ctx = Digest::SHA->new(256); $ctx->addfile($fh); close($fh);
$ctx->hexdigest eq $sha or do { unlink($temp); die "received checksum mismatch\n"; };
open($fh, "+<", $temp) or die "reopen received file: $!\n";
eval { require POSIX; POSIX::fsync(fileno($fh)); }; close($fh);
rename($temp, $final) or do { unlink($temp); die "atomic rename: $!\n"; };
print "$final $size $sha\n";
