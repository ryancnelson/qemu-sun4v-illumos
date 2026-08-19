/* Trivial AF_UNIX echo client for testing the P2-014 bridge.
 *   /opt/csw/gcc4/bin/gcc -O2 -o guest-echocli guest-echocli.c -lsocket -lnsl
 * Connects to the guest-chand socket and echoes everything back until EOF.
 * This is the "anything that speaks sockets" half of the demonstration: it knows
 * nothing about the shared region, hypercalls, or the disk. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

int main(int argc, char **argv) {
    const char *p = (argc > 1) ? argv[1] : "/tmp/niag0";
    struct sockaddr_un sa;
    char buf[65536];
    long total = 0;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return 1; }
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, p, sizeof sa.sun_path - 1);
    if (connect(fd, (struct sockaddr *)&sa, sizeof sa) < 0) { perror("connect"); return 1; }
    fprintf(stderr, "echocli: connected to %s\n", p);
    for (;;) {
        ssize_t n = read(fd, buf, sizeof buf), off = 0;
        if (n <= 0) break;
        while (off < n) {
            ssize_t w = write(fd, buf + off, n - off);
            if (w <= 0) { perror("write"); return 1; }
            off += w;
        }
        total += n;
        fprintf(stderr, "echocli: echoed %ld bytes (total %ld)\n", (long)n, total);
    }
    fprintf(stderr, "echocli: done, %ld bytes\n", total);
    close(fd);
    return 0;
}
