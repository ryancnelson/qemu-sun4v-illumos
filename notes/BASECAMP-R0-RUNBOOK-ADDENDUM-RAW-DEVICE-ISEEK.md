# R0 runbook addendum: raw character-device offset invariant

## Process defect recorded, 2026-08-25

On Solaris/illumos raw character devices (`/dev/rdsk/...`), `dd`'s `skip=`
option performs a SEQUENTIAL READ-AND-DISCARD of every block up to the
target offset -- it does NOT seek. For a target block far into a large
disk (e.g. sector 1015808 = ~520MB in), this reads and discards ~520MB of
real device I/O before returning the first payload block. On the emulated
hsimd path this manifests as sustained 100% QEMU vCPU with no console
output for a long interval -- easily mistaken for a hang.

**Invariant, going forward for all R0/R1/R2 raw-device offset proofs:**

Always use `iseek=` (input seek), not `skip=`, when reading a specific
block from a Solaris raw character device:

```
dd if=/dev/rdsk/c4d0s2 bs=512 iseek=1015808 count=1 | <digest>
```

`skip=` remains correct only for regular files / block devices with a
real seekable offset (e.g. the host-side ISO file read via a normal Linux
path), which is why the host-side half of every host/guest comparison in
this project has used `skip=` correctly and the guest-side half needs
`iseek=` instead.

No Ctrl-C or other console interrupt was sent while this defect was
discovered; QEMU was allowed to complete the sequential read undisturbed.
