# Niagara `vdisk` boot-alias workaround

Status: **PROVEN for plain `boot`; not an NVRAM-persistence fix.**

OpenBoot on the Niagara machine currently accepts `setenv` changes only in
the running process.  It reports `Unable to update LDOM Variable`, and neither
the mapped 8 KiB NVRAM file nor a QMP `pmemsave` of the physical NVRAM window
changes.  The upstream-fork bug is tracked as
[ryancnelson/qemu#1](https://github.com/ryancnelson/qemu/issues/1).

The productive workstation NVRAM already contains:

```text
boot-device = vdisk
```

Therefore the bounded workaround is to change the `vdisk` devalias in the
machine description from `/virtual-devices/disk@0` to
`/virtual-devices/disk@4`.  QEMU unit 104 is exposed to OpenBoot as `disk@4`
and contains the installed workstation.

## Proven artifact lineage

The productive runtime does **not** load the older checked-in `md/1up.pdesc`
topology.  It loads `md.bin`, generated from the runtime's preprocessed
`2c8t_guest.pp.bak`.  Regenerating the unmodified input with a native ARM64
build of `mdgen` produced a byte-identical baseline:

```text
b5d160f6f55a30d2ed56b5e24f9b1158180bb6a84d71fe222b4476945bd5b823  md.bin
```

Changing only this source property:

```text
vdisk = "/virtual-devices/disk@0";
```

to:

```text
vdisk = "/virtual-devices/disk@4";
```

and recompiling produced:

```text
1cfa392ad67d74533f24e27a43c37773f03c9ffa8606836ff61e00b7eb230408  md.bin
```

The binary comparison contains exactly one changed byte, at one-based byte
9287: ASCII `0` became ASCII `4`.  No QEMU, hypervisor, OpenBoot, `q.bin`,
NVRAM, or disk bytes were changed.

Playbox staging directory:

```text
/mnt/disk-images/builds/md-vdisk-disk4-20260827/firmware-productive
```

## Cold acceptance result

A cold QEMU was started with the complete proven workstation firmware set,
substituting only the derived `md.bin`, and with reflink copies of the carrier
and preserved workstation disk.  At the fresh OpenBoot prompt:

```text
ok devalias vdisk
vdisk                    /virtual-devices/disk@4
ok printenv boot-device
boot-device =           vdisk
ok boot
Boot device: vdisk  File and args:
OpenIndiana Hipster 2025.12 Version illumos-31d3d510d0 64-bit
```

The disposable acceptance run is:

```text
/mnt/disk-images/runs/nvram-alias-disk4-20260827T223500Z
```

That reduced-topology run proved kernel selection but later encountered the
known SMF root dependency cycle, so it is not evidence of a complete
workstation boot.  A second cold run uses the exact productive four-drive
topology and a fresh reflink of the preserved candidate:

```text
/mnt/disk-images/runs/nvram-alias-fulltopology-20260827T224500Z
```

It independently read back `vdisk` as `/virtual-devices/disk@4` and plain
`boot` loaded the same OpenIndiana kernel.  Multiuser acceptance for that run
was still in progress when this note was committed and must be recorded
separately; do not silently promote kernel-load evidence to a multiuser pass.

This proves that plain `boot` selects and loads the installed workstation.
It does not make `auto-boot?` true: a bare Return or an explicit `boot` is
still required until NVRAM/LDOM-variable persistence is implemented or a
separately validated default is supplied.

## Launch gate

Before using this workaround, require all of the following:

1. The base `md.bin` hash is the exact productive hash above.
2. A clean baseline regeneration is byte-identical to that base.
3. The source transformation replaces exactly one `vdisk` alias.
4. The derived binary has the exact derived hash above.
5. `cmp -l` reports only byte 9287 changing from ASCII `0` to ASCII `4`.
6. The launch uses unit 104 for the intended installed root disk.
7. Fresh-OpenBoot `devalias vdisk` readback passes before `boot`.
