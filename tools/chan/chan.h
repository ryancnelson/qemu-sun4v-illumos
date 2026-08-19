/* Host <-> guest channel layout (P2-014).  CANONICAL SOURCE OF TRUTH.
 *
 * The host side parses the CHAN_* defines out of this file with a regex rather
 * than duplicating them, so the two ends cannot drift. Do not restate these
 * numbers anywhere else -- a hardcoded 2668003328, wrong by 832 blocks, is
 * already part of this project's history.
 *
 * WHERE THIS LIVES
 *   The 16MB tail of VTOC slice 3, outside any filesystem: the pcfs filesystem on
 *   s3 was deliberately made 496MB inside its 512MB slice.
 *
 *   guest: /dev/rdsk/c0t0d0s3   at block CHAN_GUEST_BLK
 *   host:  images/primary.img   at byte  CHAN_HOST_BYTE
 *
 *   Both are the SAME PAGES since P2-012 (MAP_SHARED). Verified live, both
 *   directions, cksums 1178759309 and 1095390573.
 *
 * MEASURED CONSTRAINTS THAT SHAPED THIS
 *   ~4000 single-block hypercalls/sec, ~2 MB/s at bs=512. So: few large transfers
 *   beat many small ones, and a poll must cost exactly one 512-byte read.
 *
 *   USE dd iseek=/oseek=, NEVER skip=/seek=. skip= linearly reads every
 *   intervening block: 254 SECONDS to reach this region versus 0.1s for iseek.
 *
 * TEARING, and why the sequence numbers are doubled
 *   A 512-byte control write is NOT atomic with respect to the other side's
 *   reads -- it is a memcpy inside a hypercall, and the reader may sample it
 *   half-updated. So `seq` is written at the START of the control block and again
 *   at the END. A reader accepts the block only when the two copies agree.
 *
 *   Ordering, which matters as much as the doubling:
 *     writer: write DATA, then write CONTROL with the new seq
 *     reader: read CONTROL (seq==seq_end), read DATA, re-read CONTROL and
 *             confirm seq is unchanged -- otherwise the data moved underneath.
 *
 * STARTUP ORDER IS LOAD-BEARING. Run `host-chan.py init` BEFORE starting either
 * daemon, and restart both after an init. Both adopt seq/ack from the region at
 * startup, so an init underneath a running daemon leaves it holding a stale seq
 * and the peer then replays a leftover frame as new. MEASURED: a 262144-byte
 * transfer came back 274176 bytes, and the trace showed the surplus was exactly
 * one stale frame (`IN seq=54 len=12032`) with the guest numbering from 54 because
 * it had adopted a pre-init seq. Correct order gives surplus 0 and frames from
 * seq=1.
 *
 * KNOWN LIMITATION: each daemon serves ONE client and exits when it disconnects.
 * There is no accept loop yet, so a test that opens a second connection fails with
 * ENOENT rather than reconnecting.
 *
 * PROTOCOL (deliberately one frame in flight, not a full ring)
 *   Each direction is single-producer/single-consumer, so no locking is needed --
 *   the same property that let P2-012 delete the flush/reload timer entirely.
 *   The sender waits for the receiver's ack_seq to catch up before reusing the
 *   data area. A real ring is a later optimisation; correctness first.
 */

#ifndef CHAN_H
#define CHAN_H

#define CHAN_MAGIC        0x4E494147u   /* 'NIAG' */
#define CHAN_BLK          512

/* Region placement. Keep in sync with `tools/exchange.sh scratch`, which is the
 * runtime authority; these must equal SCRATCH_GUEST_S3_BLK and SCRATCH_BYTE. */
#define CHAN_GUEST_BLK    1015808L        /* block within s3 */
#define CHAN_HOST_BYTE    2667577344LL    /* absolute byte in the image */
#define CHAN_REGION_BYTES 16777216LL      /* 16MB */

/* Layout: 16 INDEPENDENT CHANNELS of 1MB each, exactly filling the 16MB region.
 *
 * WHY 16 AND NOT 1: the single-channel version was one consumer away from
 * repeating the console mistake. PPP squatting on the only console is what made
 * networking and interactive use mutually exclusive; putting IP on the only
 * channel would recreate that with better throughput and the same lockout. Build
 * the fan-out BEFORE the first heavy consumer arrives, not after it has to be
 * evicted.
 *
 * Per channel, in 512-byte blocks relative to the channel base:
 *     +0                h2g control   (host writes, guest reads)
 *     +1                g2h control   (guest writes, host reads)
 *     +2    .. +1024    h2g data      1023 blocks = 523776 bytes
 *     +1025 .. +2047    g2h data      1023 blocks = 523776 bytes
 *
 * Channels are fully independent: separate control blocks, separate data areas,
 * one writer per area. Channel N cannot stall channel M.
 */
#define CHAN_COUNT        16
#define CHAN_STRIDE_BLKS  2048L                     /* 1MB per channel */
#define CHAN_DATA_BLKS    1023L
#define CHAN_DATA_BYTES   (CHAN_DATA_BLKS * CHAN_BLK)   /* 523776 */

/* Base block of channel `ch`, relative to the region start. */
#define CHAN_BASE_BLK(ch)     ((long)(ch) * CHAN_STRIDE_BLKS)
#define CHAN_H2G_CTRL_BLK(ch) (CHAN_BASE_BLK(ch) + 0L)
#define CHAN_G2H_CTRL_BLK(ch) (CHAN_BASE_BLK(ch) + 1L)
#define CHAN_H2G_DATA_BLK(ch) (CHAN_BASE_BLK(ch) + 2L)
#define CHAN_G2H_DATA_BLK(ch) (CHAN_BASE_BLK(ch) + 2L + CHAN_DATA_BLKS)

/* The whole set must fit the region the shrunken FAT left behind. */
#if (CHAN_COUNT * CHAN_STRIDE_BLKS * CHAN_BLK) > CHAN_REGION_BYTES
#error "channel set exceeds the 16MB scratch region"
#endif

/* Control block. Occupies one 512-byte block; only the head is meaningful, but
 * seq_end lives at a fixed tail offset so a torn write is detectable. */
#define CHAN_SEQ_END_OFF  (CHAN_BLK - 4)

struct chan_ctrl {
    unsigned int magic;     /* CHAN_MAGIC */
    unsigned int seq;       /* bumped for each frame this side sends */
    unsigned int len;       /* valid bytes in this side's data area */
    unsigned int ack_seq;   /* highest seq this side has CONSUMED from the other */
};

#endif /* CHAN_H */
