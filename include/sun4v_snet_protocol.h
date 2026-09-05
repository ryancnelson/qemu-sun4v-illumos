/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef SUN4V_SNET_PROTOCOL_H
#define SUN4V_SNET_PROTOCOL_H

#define SNET_RECORD_MAGIC       0x534eU
#define SNET_RECORD_VERSION     1U
#define SNET_HEADER_MAGIC_SHIFT 48
#define SNET_HEADER_VER_SHIFT   32
#define SNET_HEADER_LENGTH_MASK 0xffffffffU
#define SNET_FRAME_MIN          14U
#define SNET_FRAME_MAX          1518U
#define SNET_WORD_SIZE          8U

#define SNET_HEADER(length) \
    (((uint64_t)SNET_RECORD_MAGIC << SNET_HEADER_MAGIC_SHIFT) | \
    ((uint64_t)SNET_RECORD_VERSION << SNET_HEADER_VER_SHIFT) | \
    ((uint64_t)(length) & SNET_HEADER_LENGTH_MASK))

#define SNET_PADDED_LENGTH(length) (((length) + 7U) & ~7U)

#endif

