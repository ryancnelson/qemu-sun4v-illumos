/* Guest side of the P2-014 channel: echo one frame, then exit.
 *
 * Proves the framing works end to end before any socket plumbing exists:
 *   wait for an h2g frame  ->  validate it  ->  copy it into g2h  ->  ack
 *
 * Build IN THE GUEST (gcc 4.3.3 is installed, 262 headers, verified):
 *   /opt/csw/gcc4/bin/gcc -O2 -o guest-echo guest-echo.c
 *
 * Deliberately uses only pread/pwrite on /dev/rdsk/c0t0d0s3 -- no ioctls, no
 * mmap, no threads. hsimd's ioctl path is missing entries (fmthard and format(1M)
 * both fail on it), so anything clever risks the same dead end.
 *
 * WHY pread AND NOT dd skip=: identical reason, one level down. lseek to the
 * region is instant; reading through to it takes ~254 seconds.
 *
 * WHY 512-byte-aligned EVERYTHING: /dev/rdsk is a character device with no
 * partial-block support. A 17-byte write once reported success and wrote nothing.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include "chan.h"

#define DEV "/dev/rdsk/c0t0d0s3"

static off_t blk_off(long blk) {
    return (off_t)(CHAN_GUEST_BLK + blk) * CHAN_BLK;
}

/* Full-length pread/pwrite: short transfers are legal and must be looped. */
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

/* Read a control block, rejecting a torn one. seq is stored twice: at the head
 * and at CHAN_SEQ_END_OFF. They disagree only mid-write. */
static int ctrl_read(int fd, long blk, struct chan_ctrl *c) {
    unsigned char b[CHAN_BLK];
    unsigned int seq_end;

    if (rd(fd, b, sizeof b, blk_off(blk)) != 0) return -1;
    memcpy(c, b, sizeof *c);
    memcpy(&seq_end, b + CHAN_SEQ_END_OFF, sizeof seq_end);

    if (c->magic != CHAN_MAGIC) return 1;   /* not initialised yet */
    if (c->seq != seq_end)      return 2;   /* torn; caller retries */
    return 0;
}

static int ctrl_write(int fd, long blk, const struct chan_ctrl *c) {
    unsigned char b[CHAN_BLK];
    memset(b, 0, sizeof b);
    memcpy(b, c, sizeof *c);
    memcpy(b + CHAN_SEQ_END_OFF, &c->seq, sizeof c->seq);
    return wr(fd, b, sizeof b, blk_off(blk));
}

int main(int argc, char **argv) {
    int fd, tries;
    unsigned int want_seq = (argc > 1) ? (unsigned int)atoi(argv[1]) : 1u;
    struct chan_ctrl in, out;
    char *data;

    data = malloc((size_t)CHAN_DATA_BYTES + CHAN_BLK);
    if (!data) { fprintf(stderr, "malloc failed\n"); return 1; }

    fd = open(DEV, O_RDWR);
    if (fd < 0) { perror("open " DEV); return 1; }

    /* Wait for the host's frame. Poll interval is one 512-byte read, ~0.25ms at
     * the measured 4000 blocks/sec, so a tight-ish loop is affordable; sleep
     * anyway so a stuck peer does not burn a core the way four abandoned dd
     * scans did. */
    for (tries = 0; tries < 600; tries++) {
        int st = ctrl_read(fd, CHAN_H2G_CTRL_BLK, &in);
        if (st == 0 && in.seq == want_seq && in.len > 0 &&
            in.len <= (unsigned int)CHAN_DATA_BYTES) {
            unsigned int len = in.len;
            /* Raw character devices reject a transfer LENGTH that is not a
             * multiple of the block size, not just a misaligned offset. Reading
             * exactly in.len (200000) returned EINVAL; round up to 512 and use
             * only the first len bytes. The same rule that makes a 17-byte write
             * silently write nothing makes a 200000-byte read fail outright. */
            size_t padded = ((size_t)len + CHAN_BLK - 1) / CHAN_BLK * CHAN_BLK;
            struct chan_ctrl again;

            if (rd(fd, data, padded, blk_off(CHAN_H2G_DATA_BLK)) != 0) {
                perror("read data"); return 1;
            }
            /* Re-validate: if the host advanced seq while we were reading, the
             * payload we just read is a mix of two frames. */
            if (ctrl_read(fd, CHAN_H2G_CTRL_BLK, &again) == 0 &&
                again.seq != in.seq) {
                continue;   /* frame moved underneath us; wait for the next */
            }

            /* Echo it back, DATA FIRST, then publish. */
            if (wr(fd, data, padded, blk_off(CHAN_G2H_DATA_BLK)) != 0) {
                perror("write data"); return 1;
            }
            memset(&out, 0, sizeof out);
            out.magic   = CHAN_MAGIC;
            out.seq     = in.seq;      /* echo carries the same seq */
            out.len     = len;
            out.ack_seq = in.seq;      /* and acks what we consumed */
            if (ctrl_write(fd, CHAN_G2H_CTRL_BLK, &out) != 0) {
                perror("write ctrl"); return 1;
            }
            printf("ECHOED seq=%u len=%u\n", out.seq, out.len);
            close(fd);
            return 0;
        }
        sleep(1);
    }
    fprintf(stderr, "timed out waiting for h2g seq=%u (last magic=%08x seq=%u)\n",
            want_seq, in.magic, in.seq);
    close(fd);
    return 2;
}
