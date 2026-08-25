#!/bin/sh
# Build illumos pppd as SPARC V9. Tribblix's shipped 32-bit socket consumers
# fail through this QEMU/illumos compatibility path, while 64-bit AF_INET is
# verified working. Run inside the illumos pppd source directory.
set -eu

CC=${CC:-gcc}
COPT=${COPT:--O2}

exec "$CC" -m64 "$COPT" \
    -D__nonstring= \
    -DPLUGIN -DSVR4 -DSOL2 -DINET6 \
    -DNEGOTIATE_FCS -DCBCP_SUPPORT -DALLOW_PAM -DHAS_SHADOW \
    -DHAVE_MMAP -DCOMP_TUNE -DMUX_FRAME \
    -DHAVE_CRYPT_H -DUSE_CRYPT -DHAVE_LIBMD \
    -DCHAPMS -DMSLANMAN -DCHAPMSV2 \
    auth.c ccp.c chap.c chap_ms.c demand.c fsm.c ipcp.c ipv6cp.c \
    lcp.c magic.c main.c options.c sys-solaris.c upap.c utils.c \
    multilink.c cbcp.c \
    -o pppd64 -lpam -lmd -lsocket -lnsl -ldlpi
