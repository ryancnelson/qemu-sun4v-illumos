# Booting a ZFS Root on the Virtual Niagara

## Experiment status

This is a live engineering record begun on August 25, 2026. The goal is to
determine whether the current QEMU Niagara machine and Masa Murayama's newer
`hsimd` driver can install and cold-boot a SPARC illumos system from ZFS.

The final result is not assumed in advance. Observations are labelled as facts;
explanations remain hypotheses until a test distinguishes them.

## Why ZFS root matters

The project can already remaster a fixed-size UFS boot archive inside Tribblix
media. That is sufficient for bootstrapping, but it is an awkward way to make
every subsequent change. A bootable ZFS root would turn the installed system
into an ordinary mountable boot environment: update files, rebuild its boot
archive, export the pool, and test again.

ZFS root does not remove the boot archive from the SPARC boot chain. OpenBoot
still loads the boot blocks, kernel, and archive before the kernel can attach
`hsimd` and import the root pool. Consequently the archive must carry the same
storage driver needed to reach the pool.

## Test topology

The test is run on Biggie under QEMU's `niagara` machine with one vCPU and 3 GiB
of guest RAM. QEMU runs inside tmux session `tribcons`, window 0, so the complete
console remains observable.

Three raw files are attached through hSIMD:

| hSIMD unit | Purpose | Size |
| --- | --- | ---: |
| 100 (`disk@0`) | Disposable ZFS installation target | 10 GiB |
| 101 (`disk@1`) | Channel and PPP mailbox disk | 32 MiB |
| 103 (`disk@3`) | Modified Tribblix live boot media | 2.1 GiB |

The known-good installed OpenIndiana disk is not part of this topology.

## Building candidate v4

The first attempted live boot attached the 10 GiB target correctly, then
panicked while trying to mount `/virtual-devices@100/disk@0:a` as UFS. Inspection
of the candidate boot archives found the exact cause: earlier edits had removed
`set root_is_ramdisk=1`. Changing only `rootdev` to `/ramdisk-root:a` did not
activate the ramdisk-root branch early enough.

Candidate v4 restores the original two ramdisk directives without changing the
UFS file length. One padded 46-byte line was replaced by two lines whose total
length is also exactly 46 bytes:

```text
set root_is_ramdisk=1
set ramdisk_size=348160
```

The active tail of `/etc/system` was then read back from a read-only Linux UFS
mount:

```text
set root_is_ramdisk=1
set ramdisk_size=348160
set cu_flags=0
rootfs:ufs
```

The archive contains Masa's 39,296-byte hSIMD module at the platform-specific
path `/platform/sun4v/kernel/drv/sparcv9/hsimd`. A legacy 19,576-byte module also
exists at the generic kernel path; the sun4v platform path is the intended
override.

The 356,515,840-byte archive was inserted at sector 37,564 of a new boot-media
copy. A byte-for-byte comparison of the complete inserted extent passed before
boot.

## Candidate v5 execution & root-path diagnosis

### Non-interactive boot failure (-sv)

Candidate v5 was booted non-interactively with:

```text
ok boot /virtual-devices@100/disk@3:d -sv
```

Observed console output:

```text
hsimd0: hsimd_attach: size:0x280000000, cap:0x5
Cannot assemble drivers for root /virtual-devices@100/disk@0:a
Cannot mount root on /virtual-devices@100/disk@0:a fstype ufs
panic[cpu0]/thread=180e000: vfs_mountroot: cannot mount root
```

### Interactive boot success (-asv)

Candidate v5 was then booted interactively with `-asv`:

```text
ok boot /virtual-devices@100/disk@3:d -asv
```

Console prompt and interactive override:

```text
Enter physical name of root device [/virtual-devices@100/disk@0:a]: /ramdisk-root:a
```

Observed boot progression:

```text
ramdisk0 at root
ramdisk0 is /ramdisk-root
root on /ramdisk-root:a fstype ufs
Loading smf(7) service descriptions: 95/95
Booting to milestone "milestone/single-user:default".
hsimd0: hsimd_attach: size:0x280000000, cap:0x5
hsimd1: hsimd_attach: size:0x2000000, cap:0x5
hsimd3: hsimd_attach: size:0x80a10000, cap:0x5
Hostname: tribblix
Remounting root read/write
```

* **FACT**: All three hSIMD storage units attached in the live guest:
  - Unit 100 (`hsimd0`): 10 GiB installation target (`0x280000000` bytes).
  - Unit 101 (`hsimd1`): 32 MiB dedicated channel disk (`0x2000000` bytes).
  - Unit 103 (`hsimd3`): 2.1 GiB Tribblix live media (`0x80a10000` bytes).
* **FACT**: Overriding the root device to `/ramdisk-root:a` successfully reaches the single-user maintenance shell.

### Root-cause discriminator: Extracted swapgeneric ELF analysis

To determine why `[/virtual-devices@100/disk@0:a]` was defaulted despite `rootdev:/ramdisk-root:a` in `/etc/system`:

1. `kernel/misc/sparcv9/swapgeneric` was extracted directly from `boot_archive.v5.ufs` (SHA-256: `fe97d7b5db8655cbfe965cb29ddee2029e20188d7e546dc1a28aa48c908095a2`).
2. String search on the extracted ELF confirmed the hardcoded `/virtual-devices@100/disk@0:a` patch string is **ABSENT**. The v5 archive contains the unmodified upstream Tribblix module.
3. In illumos source (`usr/src/uts/common/os/swapgeneric.c:522`), `get_bootpath_prop()` calls `BOP_GETPROP(bootops, "bootpath", bootpath)` to query the PROM `/chosen/bootpath` property.
4. **HYPOTHESIS**: Masa's OpenSPARC T1 OBP firmware defaults `/chosen/bootpath` to alias `disk` (`/virtual-devices@100/disk@0:a`) upon machine reset and does not update `/chosen/bootpath` when the user passes an explicit path to `boot /virtual-devices@100/disk@3:d`.

### Reproduced on Exabyt (2026-08-26)

The same candidate-v5 path reproduced the diagnosis in a clean Exabyt run:

```text
ok boot /virtual-devices@100/disk@3:d -asv
Enter physical name of root device [/virtual-devices@100/disk@0:a]: /ramdisk-root:a
ramdisk0 is /ramdisk-root
root on /ramdisk-root:a fstype ufs
```

This is a durable boot invariant, not a one-run workaround: until the OBP
`/chosen/bootpath` behavior or archive boot arguments are fixed, every
interactive candidate-v5 boot must override the misleading `disk@0:a` default
with `/ramdisk-root:a`. Automated smoke tests must fail fast if the prompt is
answered with its default.

### Pre-devfsadm read-write gate

The Exabyt reproduction reached `Remounting root read/write` and then failed
more narrowly:

```text
Configuring devices.
devfsadm: open failed for /etc/dev/.devfsadm_dev.lock: Read-only file system
```

The remaster/finalization payload now installs a wrapper around the preserved
`/usr/sbin/devfsadm` binary.  Immediately before every devfsadm execution it:

1. reads the live Solaris `mount -p` table;
2. attempts to remount every `ro` filesystem as `rw`;
3. reads the mount table again and fails if even one filesystem remains `ro`;
4. creates and removes a canary in `/etc/dev`; and
5. only then executes the preserved real devfsadm binary.

The standalone installer is
`tools/install-tribblix-devfsadm-rw-gate.sh`; it accepts a mounted alternate
root, including a copied UFS boot archive mounted read-write through lofi.
`tools/tribblix-finalize-root.sh` invokes it automatically, and
`tools/stage-tribblix-finalize.sh` includes both installer and wrapper in every
new staging payload.  The acceptance marker is
`NIAGARA_DEVFSADM_RW_GATE_OK`; a remount or canary failure is fatal and leaves
the original devfsadm unexecuted.

This policy is intentionally literal.  A filesystem type such as HSFS cannot
be remounted read-write, so the installer media must not be mounted until
after the first devfsadm gate.  If immutable media is already mounted, the
gate fails and identifies that mount instead of weakening the rule or letting
device configuration run in a partially read-only namespace.

### Minimal next experiment: OBP NVRAM & property override

To test whether non-interactive boot to `/ramdisk-root:a` can be achieved without `-a` interactive typing:

* **Experiment A (OBP NVRAM boot-device override)**:
  ```text
  ok setenv boot-device /virtual-devices@100/disk@3:d
  ok boot -sv
  ```
* **Experiment B (Forth /chosen property injection)**:
  ```text
  ok " /ramdisk-root:a" encode-string " bootpath" /chosen set-property
  ok boot /virtual-devices@100/disk@3:d -sv
  ```
