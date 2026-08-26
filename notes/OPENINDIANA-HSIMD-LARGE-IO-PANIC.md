# OpenIndiana installer: hSIMD large-I/O panic

## Incident

The `warm-openindiana-exa-02` installer reached installation, labelled the
unit-100 destination, created `rpool`, and began populating `/etc`.  ZFS then
sent hSIMD a `0xa6800`-byte (666 KiB) request.  The guest panicked at:

```text
assertion failed: sz <= 128*1024
file: build-output-isolated/hsimd.patched.c, line: 821
```

After the unattended panic path attempted to reboot, QEMU encountered a fatal
MAXTL trap and aborted.  That secondary QEMU failure destroyed the most useful
live debugging state.

## Mandatory KMDB policy

Every candidate boot that exercises a new or changed kernel, hSIMD driver,
storage topology, ZFS installation path, or previously unpassed kernel gate
must boot with KMDB enabled and verbose output (`-k -v`).  The run manifest and
console log must prove those flags before the destructive test begins.

On panic, stop in KMDB and capture at least the panic text, stack, registers,
current thread, relevant arguments, and any useful driver state before allowing
a reboot.  Do not rely on an automatic reboot to preserve evidence.

A non-KMDB boot is appropriate only after the exact candidate has passed the
same kernel/storage gate under KMDB and the run is explicitly classified as a
normal cold-boot acceptance test.

## Current diagnosis

ZFS aggregates adjacent vdev I/O up to 1 MiB and calls `ldi_strategy()`
directly.  It therefore does not constrain this request using hSIMD's
`DKIOCINFO.dki_maxtransfer` value.  hSIMD advertises 128 KiB but its IOV fast
path asserts that limit instead of accepting or segmenting a larger strategy
request.  QEMU provisions 129 IOV entries for up to 1 MiB, so the immediate
guest assertion is inconsistent with the paired transport implementation.

The lowest-risk first fix is to route requests larger than 128 KiB through the
existing non-IOV path, which already divides transfers into page-sized
hypercalls.  A subsequent optimized fix can segment the IOV request into
bounded chunks.  A temporary installer-only workaround is to set
`zfs:zfs_vdev_aggregation_limit` to `0x20000`; that does not replace the driver
fix.

## Next-run storage gate

Before starting the installer, provide a fresh 20--32 GiB writable unit-100
destination, boot to the shell under KMDB, create or import the intended pool,
write/sync/read a canary, and explicitly exercise an I/O larger than 128 KiB.
Only return to the installer menu after those gates pass.
