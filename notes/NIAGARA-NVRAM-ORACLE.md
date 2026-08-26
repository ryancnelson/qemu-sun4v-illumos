# Niagara OpenBoot NVRAM oracle

## Durable rule

Do not manufacture a production `nvram1` by guessing or independently
reimplementing OpenBoot's binary record format.  A disposable Niagara QEMU
instance running the project's actual OpenBoot firmware is the canonical NVRAM
encoder, validator, and reference implementation.

Use OpenBoot itself to create every release NVRAM variant:

```text
stock nvram1
    -> boot a disposable QEMU to the OpenBoot `ok` prompt
    -> change variables with OpenBoot `setenv`, `nvedit`, and `nvstore`
    -> verify the literal stored values with `printenv`
    -> use the QEMU monitor to dump 0x2000 bytes at 0x1f11000000
    -> validate the dumped image in a fresh disposable QEMU
    -> publish that dump as the artifact's nvram1
```

The monitor operation is conceptually:

```text
pmemsave 0x1f11000000 0x2000 /path/to/nvram1
```

The exact command must be issued through that run's verified monitor socket.
The destination must be a new per-run file, never the shared firmware template.

## Required gates

Before an oracle-generated image can be attached to an installer run:

1. Preserve the stock `nvram1`; never edit it in place.
2. Record the QEMU binary, firmware-directory, and input-NVRAM hashes.
3. At `ok`, query and capture at least:

   ```text
   printenv use-nvramrc?
   printenv nvramrc
   printenv boot-device
   ```

4. Dump exactly 8,192 bytes from `0x1f11000000`.
5. Start a fresh QEMU with an isolated firmware directory containing the dump.
6. Repeat the `printenv` queries before issuing any boot command.
7. Hash the accepted dump and include it in the same release manifest as its
   boot archive, media image, QEMU binary, and topology description.
8. Fail closed if readback differs, NVRAM is reinitialized, or the image is
   paired with a different artifact/topology identity.

## Current root-selection variant

For the current live installer experiment, OpenBoot must retain the installer
media as the boot source while presenting the RAM root to illumos:

```text
boot medium: /virtual-devices@100/disk@3:d
kernel root: /ramdisk-root:a
```

The proposed NVRAM variant enables `use-nvramrc?` and stores an `nvramrc` that
sets `/chosen/bootpath` to `/ramdisk-root:a`.  This remains a hypothesis until
a fresh-oracle dump passes both `printenv` readback and a cold-boot gate.  Do
not confuse `boot-device` with the kernel root device.

## Diagnostic tooling policy

A decoder may inspect, diff, and validate oracle output.  It may not be the
source of production NVRAM bytes until it has demonstrated byte-identical
output against multiple oracle-generated fixtures.  OpenBoot output wins every
disagreement.

