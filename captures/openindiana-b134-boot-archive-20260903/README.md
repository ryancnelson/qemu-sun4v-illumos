# OpenIndiana b134 boot-archive contract capture

This directory contains three files read from the immutable b134 SPARC boot
archive and their portable, expanded forms. The source archive was never
mounted read/write.

Source identities:

```text
95f2ca0fdb3b3fd1206e98694d4aa1fa720ed4c0e058cc63a946f2d3278a70c7  boot_archive.b134.ufs
607a63e3f10c6c95e242f42616944aa6019822de961601844c694f46b496d570  b134-layout-carrier.iso
```

The archive was carried read-only into Solaris 9/SPARC. Solaris 9 mounted the
carrier as HSFS, attached the archive with `lofiadm`, and mounted the resulting
UFS read-only. Because Solaris 9 lacks the newer DCFS layer, reading these
files returned their physical `Zcmp` representation. Each small object was
sent over the serial console with `uuencode` and decoded without modification.

The successful guest sequence was:

```sh
/etc/init.d/volmgt stop
mount -F hsfs -o ro /dev/dsk/c0t6d0s0 /mnt/carrier
LOFI=`/usr/sbin/lofiadm -a /mnt/carrier/B134.UFS`
mount -F ufs -o ro $LOFI /mnt/b134
/usr/bin/uuencode /mnt/b134/lib/svc/method/media-fs-root MEDIA-FS-ROOT.ZCMP
/usr/bin/uuencode /mnt/b134/etc/vfstab B134-VFSTAB.ZCMP
/usr/bin/uuencode /mnt/b134/etc/system B134-SYSTEM.ZCMP
umount /mnt/b134
/usr/sbin/lofiadm -d $LOFI
umount /mnt/carrier
```

Run identity:

```text
host=niagara-playbox
guest=Solaris 9 Generic May 2002, sun4m SS-5
qemu=8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18), aarch64 host
run=/mnt/disk-images/solaris9-sun4m-trial/runs/20260903T233950Z
start=2026-09-03T23:39:50Z
root-login=2026-09-03T23:40:21Z
result=SOLARIS9_B134_EXTRACT_TEST=PASS
```

Native x86 Tribblix `fiocompress -d` rejected the SPARC-native header with:

```text
bad magic (0x706d635a00000000/0x5a636d70)
```

`tools/openindiana/decompress-fiocompress.py` therefore parses the format's
native-endian 64-bit fields explicitly and validates every block boundary and
expanded length. Its format references are the upstream illumos
`fiocompress.c` and `sys/fs/decomp.h` implementations.

Reproduce the expansion with:

```sh
python3 tools/openindiana/decompress-fiocompress.py \
    captures/openindiana-b134-boot-archive-20260903/physical/media-fs-root.zcmp \
    /tmp/media-fs-root
```

`SHA256SUMS` records both the physical and expanded files. The expanded source
is subject to the CDDL notices contained in the files.
