/* Guest channel daemon (P2-014): bridge an AF_UNIX socket to the shared region.
 *
 *   guest-chand [socket-path]        default /tmp/niag0
 *
 * Anything in the guest that speaks sockets can now talk to the host:
 *   guest$  guest-chand &  ;  nc -U /tmp/niag0     (or a C client)
 *   host$   host-chand.py bridge    ->  /run/niag0
 *
 * Build in the guest (gcc 4.3.3, verified):
 *   /opt/csw/gcc4/bin/gcc -O2 -o guest-chand guest-chand.c -lsocket -lnsl
 *
 * -lsocket -lnsl ARE REQUIRED on Solaris: socket/bind/listen/accept are not in
 * libc there, unlike Linux. Without them the compile succeeds and the LINK fails
 * with undefined references to socket, bind, listen, accept.
 *
 * DESIGN NOTES, all forced by measurement rather than taste:
 *
 * - FULL DUPLEX WITHOUT LOCKS. The two directions have separate control blocks
 *   and separate data areas, and each has exactly ONE writer. That is the same
 *   property that let P2-012 delete the flush/reload timer, and it means this
 *   single-threaded poll loop is race-free by construction rather than by care.
 *
 * - ONE FRAME IN FLIGHT per direction. The sender may only reuse its data area
 *   once the peer's ack_seq has caught up. A real multi-slot ring is a later
 *   optimisation; the frame is already 1MB, and at the measured ~2 MB/s through
 *   512-byte hypercalls the win would be small.
 *
 * - EVERY raw transfer is 512-byte aligned in BOTH offset and LENGTH. A
 *   misaligned length returns EINVAL (a 200000-byte read did); a short write is
 *   silently dropped (a 17-byte write once reported success and wrote nothing).
 *
 * - pread/pwrite, never lseek+read: `dd skip=` on this device linearly reads
 *   every intervening block, ~254 seconds to reach the region versus 0.1s.
 *
 * - Poll with a real sleep. Four abandoned scans once burned 20% of a core each;
 *   a busy-wait here would do the same while looking like progress.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include "chan.h"

#define DEV      "/dev/rdsk/c0t0d0s3"
#define POLL_US  20000            /* 20ms; one 512B read costs ~0.25ms */

static int   dfd = -1;
static char *sockpath;

static off_t blk_off(long blk) {
    return (off_t)(CHAN_GUEST_BLK + blk) * CHAN_BLK;
}

static size_t pad(size_t n) {
    return (n + CHAN_BLK - 1) / CHAN_BLK * CHAN_BLK;
}

static int rd(int fd, void *buf, size_t n, off_t off) {
    size_t done = 0;
    while (done < n) {
        ssize_t r = pread(fd, (char *)buf + done, n - done, off + done);
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        if (r == 0) return -1;
        done += (size_t)r;
    }
    return 0;
}

static int wr(int fd, const void *buf, size_t n, off_t off) {
    size_t done = 0;
    while (done < n) {
        ssize_t r = pwrite(fd, (const char *)buf + done, n - done, off + done);
        if (r < 0) { if (errno == EINTR) continue; return -1; }
        if (r == 0) return -1;
        done += (size_t)r;
    }
    return 0;
}

/* 0 = good, 1 = uninitialised, 2 = torn (retry). */
static int ctrl_read(long blk, struct chan_ctrl *c) {
    unsigned char b[CHAN_BLK];
    unsigned int seq_end;
    if (rd(dfd, b, sizeof b, blk_off(blk)) != 0) return -1;
    memcpy(c, b, sizeof *c);
    memcpy(&seq_end, b + CHAN_SEQ_END_OFF, sizeof seq_end);
    if (c->magic != CHAN_MAGIC) return 1;
    if (c->seq != seq_end)      return 2;
    return 0;
}

static int ctrl_write(long blk, const struct chan_ctrl *c) {
    unsigned char b[CHAN_BLK];
    memset(b, 0, sizeof b);
    memcpy(b, c, sizeof *c);
    memcpy(b + CHAN_SEQ_END_OFF, &c->seq, sizeof c->seq);
    return wr(dfd, b, sizeof b, blk_off(blk));
}

static void cleanup(int sig) {
    (void)sig;
    if (sockpath) unlink(sockpath);
    _exit(0);
}

int main(int argc, char **argv) {
    int lfd, cfd;
    struct sockaddr_un sa;
    char *inbuf, *outbuf;
    struct chan_ctrl mine, peer;
    unsigned int my_seq = 0, seen_seq = 0;
    unsigned int my_len = 0;   /* len of MY last published frame; see ack note */
    size_t pending = 0;          /* bytes staged in outbuf awaiting a free slot */
    char  *sockout;              /* inbound frame being written to the socket */
    size_t sockout_len = 0, sockout_off = 0;
    int sock_eof = 0;

    sockpath = (argc > 1) ? argv[1] : (char *)"/tmp/niag0";

    inbuf   = malloc((size_t)CHAN_DATA_BYTES + CHAN_BLK);
    outbuf  = malloc((size_t)CHAN_DATA_BYTES + CHAN_BLK);
    sockout = malloc((size_t)CHAN_DATA_BYTES + CHAN_BLK);
    if (!inbuf || !outbuf || !sockout) { fprintf(stderr, "malloc failed\n"); return 1; }

    dfd = open(DEV, O_RDWR);
    if (dfd < 0) { perror("open " DEV); return 1; }

    /* Adopt whatever the region already says, so a restart does not replay old
     * frames or collide with the host's numbering. */
    if (ctrl_read(CHAN_G2H_CTRL_BLK, &mine) == 0) { my_seq = mine.seq; my_len = mine.len; }
    if (ctrl_read(CHAN_H2G_CTRL_BLK, &peer) == 0) seen_seq = peer.seq;

    unlink(sockpath);
    lfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (lfd < 0) { perror("socket"); return 1; }
    memset(&sa, 0, sizeof sa);
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, sockpath, sizeof sa.sun_path - 1);
    if (bind(lfd, (struct sockaddr *)&sa, sizeof sa) < 0) { perror("bind"); return 1; }
    if (listen(lfd, 1) < 0) { perror("listen"); return 1; }
    signal(SIGINT, cleanup); signal(SIGTERM, cleanup); signal(SIGPIPE, SIG_IGN);

    printf("guest-chand: %s  region blk %ld  my_seq=%u peer_seq=%u\n",
           sockpath, CHAN_GUEST_BLK, my_seq, seen_seq);
    fflush(stdout);

    cfd = accept(lfd, NULL, NULL);
    if (cfd < 0) { perror("accept"); return 1; }
    printf("guest-chand: client connected\n"); fflush(stdout);

    /* Non-blocking socket so one loop can serve both directions. */
    fcntl(cfd, F_SETFL, O_NONBLOCK);

    for (;;) {
        int did = 0;

        /* ---- outbound: socket -> g2h ------------------------------------ */
        if (!pending && !sock_eof) {
            ssize_t n = read(cfd, outbuf, (size_t)CHAN_DATA_BYTES);
            if (n > 0)                       pending = (size_t)n;
            else if (n == 0)                 sock_eof = 1;
            else if (errno != EAGAIN && errno != EWOULDBLOCK) sock_eof = 1;
        }
        if (pending) {
            /* Only reuse the data area once the host has consumed the last frame. */
            int st = ctrl_read(CHAN_H2G_CTRL_BLK, &peer);
            if (st == 0 && peer.ack_seq >= my_seq) {
                if (wr(dfd, outbuf, pad(pending), blk_off(CHAN_G2H_DATA_BLK)) != 0) {
                    perror("write data"); break;
                }
                memset(&mine, 0, sizeof mine);
                mine.magic   = CHAN_MAGIC;
                mine.seq     = ++my_seq;
                mine.len     = my_len = (unsigned int)pending;
                mine.ack_seq = seen_seq;
                if (ctrl_write(CHAN_G2H_CTRL_BLK, &mine) != 0) {
                    perror("write ctrl"); break;
                }
                pending = 0; did = 1;
            }
        }

        /* ---- inbound: h2g -> socket ------------------------------------- */
        if (sockout_off >= sockout_len &&
            ctrl_read(CHAN_H2G_CTRL_BLK, &peer) == 0 &&
            peer.seq != seen_seq && peer.len > 0 &&
            peer.len <= (unsigned int)CHAN_DATA_BYTES) {
            unsigned int len = peer.len, want = peer.seq;
            struct chan_ctrl again;

            if (rd(dfd, inbuf, pad(len), blk_off(CHAN_H2G_DATA_BLK)) != 0) {
                perror("read data"); break;
            }
            /* Reject a frame that moved while we were reading it. */
            if (ctrl_read(CHAN_H2G_CTRL_BLK, &again) == 0 && again.seq == want) {
                /* Stage it; the drain below writes it out incrementally.
                 *
                 * THIS USED TO BE A BLOCKING while(off<len) write loop, and that
                 * deadlocked every transfer larger than the socket buffers: with
                 * the peer's buffer full this loop spun in usleep() and never
                 * serviced the OUTBOUND direction, so the peer could not drain us
                 * either. Small frames fit in the buffers and worked, which is
                 * exactly why it looked fine at 256KB and hung at 1MB. */
                memcpy(sockout, inbuf, len);
                sockout_len = len;
                sockout_off = 0;
                seen_seq = want;
                /* Publish the ack so the host may reuse its data area.
                 *
                 * MUST re-publish my_seq AND my_len unchanged. An earlier version
                 * wrote len=0 here, which silently destroyed an outbound frame the
                 * host had not consumed yet: the ack and the outbound frame share
                 * one control block. Only ack_seq changes, so the host's tear check
                 * still sees seq==seq_end and a torn read yields either the old or
                 * new ack, both of which are monotonic and safe. */
                memset(&mine, 0, sizeof mine);
                mine.magic   = CHAN_MAGIC;
                mine.seq     = my_seq;
                mine.len     = my_len;
                mine.ack_seq = seen_seq;
                ctrl_write(CHAN_G2H_CTRL_BLK, &mine);
                did = 1;
            }
        }

        /* ---- drain staged inbound bytes to the socket, non-blocking ------ */
        if (sockout_off < sockout_len) {
            ssize_t w = write(cfd, sockout + sockout_off, sockout_len - sockout_off);
            if (w > 0) { sockout_off += (size_t)w; did = 1; }
            else if (w < 0 && errno != EAGAIN && errno != EWOULDBLOCK) sock_eof = 1;
        }

        if (sock_eof && !pending && sockout_off >= sockout_len) break;
        if (!did) usleep(POLL_US);
    }

    printf("guest-chand: closing\n");
    close(cfd); close(lfd); close(dfd);
    unlink(sockpath);
    return 0;
}
