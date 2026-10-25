ARCH=sparc64
TARGET=sparc64-linux-gnu-
CFLAGS=-Wa,-xarch=v9b -Wa,-64 -m64 -mcpu=ultrasparc -mcmodel=medany -fno-builtin
AS_FLAGS=-Wa,-xarch=v9b -Wa,-64
HOSTARCH?=aarch64
CROSSCFLAGS=-DSWAP_ENDIANNESS -DNATIVE_BITWIDTH_EQUALS_HOST_BITWIDTH
VERSION="1.1"
SRCDIR=/mnt/disk-images/woodpecker/firmware132-tokenfix-trellis/openbios
