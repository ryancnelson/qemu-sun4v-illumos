# B134 sun4u console-path experiment

This directory preserves the helper written for EXP-20260904-56. The runtime
evidence remains on `niagara-playbox` under:

```text
/mnt/disk-images/sun4u-b134-installer/runs/008/
...
/mnt/disk-images/sun4u-b134-installer/runs/019/
```

`sparc-qemu-rsp.py` speaks only the QEMU GDB Remote Serial Protocol operations
needed to read the SPARC64 register packet and, when explicitly requested,
redirect PC/NPC to B134's verified `kmdb_enter` trap. It exists because the
installed `gdb-multiarch` expects a 288-byte SPARC V9 register packet while
QEMU 8.2.2 emits the 560-byte layout defined in `target/sparc/gdbstub.c`.

For the pinned B134 kernel used in this experiment:

```text
kmdb_enter       0x0101b230: ta 0x7d
kmdb_enter + 4   0x0101b234: retl
```

The helper verifies the packet length and both written registers before trying
to detach. QEMU returned `E22` for detach in run015, so the recorded procedure
resumed the already-verified state with the HMP `cont` command. Treat such a
run as disposable unless the original PC/NPC and return context are restored.

The successful transient OpenBIOS correction from run019 was:

```forth
dev /
: encode-unit 2drop " 1f,0" ;
: decode-unit 2drop 0 1fe ;

dev /pci@1f,0/pci@1,1/ebus@1
: encode-unit encode-unit-upa ;
: decode-unit decode-unit-upa ;
```

This preserves SABRE's physical `reg` and `ranges` values while making the
firmware paths agree with Solaris:

```text
/pci@1f,0/pci@1,1/ebus@1/su@14,3f8
```

The hard-coded root method was the experiment, not the permanent source fix.
The compiled repair is now recorded in:

```text
patches/openbios/0001-aarch64-host-bitwidth.patch
patches/openbios/0002-sun4u-solaris-device-paths.patch
scripts/build-openbios-sun4u-solaris.sh
```

Run024 proved the compiled path repair with the unchanged B134 ISO. Run026
then independently booted the artifact emitted by the checked-in build script,
accepted keyboard selection `46` and language selection `7`, and advanced into
installer configuration. Their evidence is on `niagara-playbox` under:

```text
/mnt/disk-images/sun4u-b134-installer/runs/024-patched-paths/
/mnt/disk-images/sun4u-b134-installer/runs/025-script-rebuild/
/mnt/disk-images/sun4u-b134-installer/runs/026-script-artifact-boot/
```

The build must use `EXTRACFLAGS=-fno-stack-protector`; otherwise Ubuntu's
SPARC cross-GCC emits a `%g7 + 0x28` TLS canary load into this freestanding
firmware and it traps during `fw_cfg_read_i16()`.
