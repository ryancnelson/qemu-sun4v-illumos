# Solaris 9 QEMU LANCE network version test, 2026-08-28

## Result

Solaris 9 reached the QEMU user-network gateway under QEMU 7.2.0 with both the
legacy network arguments and modern `-nic` syntax. The same guest failed under
QEMU 9.1.0 and QEMU 11.1.0 with `le0` transmitting but receiving no packets.

This bounds the first bad release to the interval after QEMU 7.2.0 and no later
than QEMU 9.1.0. It does not identify the responsible commit yet.

## Hypothesis and falsifier

Hypothesis: Solaris 9 networking works when QEMU 7.2.0 uses the historical
`-net nic` and `-net user` configuration.

The hypothesis would be disproved if `ping 10.0.2.2 5` received no reply or if
the `le0` receive counter remained unchanged.

## Test identity

| Field | Value |
| --- | --- |
| Host | `ec2trib`, Tribblix x86 |
| QEMU | `/tink/builds/qemu-ss5-v7.2/build-amd64/qemu-system-sparc` |
| Guest | Solaris 9, SunOS 5.9 Generic, 32-bit |
| Runner | `/tink/sun4m-solaris9/run-qemu.sh` |
| Run | `/tink/runs/sun4m-solaris9/20260828T155533Z-17861` |
| PID | `17861` |
| Console | `/tink/runs/sun4m-solaris9/20260828T155533Z-17861/console.sock` |
| Network arguments | `-net nic,model=lance,macaddr=4E:B0:83:C6:5F:67 -net user` |

The legacy QEMU command was generated with:

```text
QEMU=/tink/builds/qemu-ss5-v7.2/build-amd64/qemu-system-sparc
CONSOLE_MODE=socket
PERSISTENT_NVRAM=0
NETWORK_MODE=legacy
```

This QEMU 7.2.0 build does not contain Ryan's persistent-NVRAM patch. The VM
did not autoboot and required `boot disk0` at OpenBoot. That difference was
held outside the network test.

## Guest command and output

```text
# netstat -in; ping 10.0.2.2 5; netstat -in
Name  Mtu  Net/Dest      Address        Ipkts  Ierrs Opkts  Oerrs Collis Queue
lo0   8232 127.0.0.0     127.0.0.1      28     0     28     0     0      0
le0   1500 10.0.2.0      10.0.2.15      3      0     9      0     0      0

10.0.2.2 is alive
Name  Mtu  Net/Dest      Address        Ipkts  Ierrs Opkts  Oerrs Collis Queue
lo0   8232 127.0.0.0     127.0.0.1      28     0     28     0     0      0
le0   1500 10.0.2.0      10.0.2.15      5      0     11     0     0      0
```

The gateway replied. `le0` received two packets and transmitted two packets.
The hypothesis is supported.

## Modern syntax control

QEMU 7.2.0 was restarted with the same host, binary, firmware, disks, MAC
address, and guest configuration. Only `NETWORK_MODE` changed:

```text
NETWORK_MODE=modern
```

The second run was:

| Field | Value |
| --- | --- |
| Run | `/tink/runs/sun4m-solaris9/20260828T160106Z-18311` |
| PID | `18311` |
| Network arguments | `-nic user,model=lance,mac=4E:B0:83:C6:5F:67` |

The identical guest command produced the identical result:

```text
10.0.2.2 is alive
le0: Ipkts 3 -> 5, Opkts 9 -> 11
```

The modern syntax works in QEMU 7.2.0. Argument syntax does not explain the
QEMU 11.1.0 failure.

## Comparison evidence

| QEMU and host | Network form | Result |
| --- | --- | --- |
| QEMU 11.1.0 GCC, ec2trib | modern `-nic user,model=lance` | failed; `le0` RX stayed zero |
| QEMU 11.1.0 Clang, ec2trib | modern `-nic user,model=lance` | failed; `le0` RX stayed zero |
| QEMU 11.1.0, Teddeck | modern and legacy forms | failed; `le0` RX stayed zero |
| QEMU 9.1.0, ec2trib | modern `-nic user,model=lance` | failed; `le0` RX stayed zero |
| QEMU 8.2.0, ec2trib | modern `-nic user,model=lance` | failed; `le0` RX stayed zero |
| QEMU 8.0.0, ec2trib | modern `-nic user,model=lance` | failed; `le0` RX stayed zero |
| QEMU 7.2.0, ec2trib | legacy `-net nic` plus `-net user` | passed; gateway alive |
| QEMU 7.2.0, ec2trib | modern `-nic user,model=lance` | passed; gateway alive |
| ec2trib x86 QEMU with CirrOS | user networking with virtio-net | passed DHCP, gateway ping, and HTTP |

The CirrOS control shows that ec2trib's QEMU user-network backend and outbound
host networking work. The GCC/Clang comparison excludes the QEMU compiler as
the cause. The Teddeck comparison excludes Tribblix as the sole cause.

## QEMU 9.1.0 midpoint

QEMU 9.1.0 was built on ec2trib from tag `v9.1.0`. The source worktree and
binary are:

```text
/tink/builds/qemu-ss5-v9.1
/tink/builds/qemu-ss5-v9.1/build-amd64/qemu-system-sparc
```

QEMU 9.1 required Tribblix package `TRIBdistlib-python-313`. Its configure
script also uses the `local` shell extension, so `scripts/ec2trib-sun4m-lab.sh`
now invokes configure with Bash instead of Tribblix `/bin/sh`.

The upstream QEMU 9.1 build ignored `-prom-env auto-boot?=false`,
`-prom-env boot-device=disk0`, and `-boot order=c`. HMP `sendkey stop-a` did not
interrupt the headless serial firmware path. The persistent-NVRAM change from
Ryan Nelson's QEMU commit `59e94e01b5` was adapted for QEMU 9.1 and saved as:

```text
patches/qemu-v9.1-persistent-nvram-backport.patch
```

The ec2trib QEMU worktree has the backport on branch
`codex/qemu91-persistent-nvram`, commit `a813d163d9`. The rebuilt binary reports
`v9.1.0-1-ga813d163d9`. It loaded the existing 8192-byte SS-5 NVRAM image with
SHA-256 `9d397c6585a03da0cf4d5718810acaba6be31cf5a489b0b175159dafb4bf18a8`
and booted disk0 automatically.

Test identity:

| Field | Value |
| --- | --- |
| Run | `/tink/runs/sun4m-solaris9/20260828T161811Z-28122` |
| PID | `28122` |
| QEMU | `v9.1.0-1-ga813d163d9` |
| Network arguments | `-nic user,model=lance,mac=4E:B0:83:C6:5F:67` |

The identical gateway test failed:

```text
# netstat -in; ping 10.0.2.2 5; netstat -in
le0   1500 10.0.2.0      10.0.2.15      0      0     18     0     0      0

no answer from 10.0.2.2
le0   1500 10.0.2.0      10.0.2.15      0      0     24     0     0      0
```

QEMU 9.1 transmitted six more packets and received none.

### Launcher correction

The first lab launcher revision forced `PERSISTENT_NVRAM=0` for every tagged
comparison run. That override made a patched binary stop at OpenBoot exactly
like an unpatched build, even though the runner itself defaulted persistence
on. `scripts/ec2trib-sun4m-lab.sh` now inspects the selected source tree for
the M48T59 `filename` property and automatically enables the NVRAM backing file
when the backport is present. It prints the resulting setting before launch.
An explicit `PERSISTENT_NVRAM=0` or `1` still overrides detection.

## QEMU 8.2.0 midpoint

QEMU 8.2.0 was built from tag `v8.2.0`, then given a version-specific
persistent-NVRAM backport on ec2trib branch
`codex/qemu82-persistent-nvram`, commit `5f80d9104f`. The versioned patch is:

```text
patches/qemu-v8.2-persistent-nvram-backport.patch
```

The rebuilt binary reports `v8.2.0-1-g5f80d9104f`. The corrected launcher
printed `Persistent NVRAM: 1`, and the guest reached the Solaris console login
without any console input.

Test identity:

| Field | Value |
| --- | --- |
| Run | `/tink/runs/sun4m-solaris9/20260828T162756Z-36123` |
| PID | `36123` |
| QEMU | `v8.2.0-1-g5f80d9104f` |
| Network arguments | `-nic user,model=lance,mac=4E:B0:83:C6:5F:67` |

The identical gateway test failed:

```text
# netstat -in; ping 10.0.2.2 5; netstat -in
le0   1500 10.0.2.0      10.0.2.15      0      0     18     0     0      0

no answer from 10.0.2.2
le0   1500 10.0.2.0      10.0.2.15      0      0     24     0     0      0
```

This moves the first known failure boundary from QEMU 9.1 down to QEMU 8.2.

## QEMU 8.0.0 boundary test

QEMU 8.0.0 was built from tag `v8.0.0`. The QEMU 8.2 NVRAM patch applied
unchanged and was committed on ec2trib branch
`codex/qemu80-persistent-nvram`, commit `903d4808ca`. The rebuilt binary reports
`v8.0.0-1-g903d4808ca`, printed `Persistent NVRAM: 1`, and reached the Solaris
login prompt without console input.

Test identity:

| Field | Value |
| --- | --- |
| Run | `/tink/runs/sun4m-solaris9/20260828T163428Z-44441` |
| PID | `44441` |
| QEMU | `v8.0.0-1-g903d4808ca` |
| Network arguments | `-nic user,model=lance,mac=4E:B0:83:C6:5F:67` |

The gateway test again failed with `le0` receive packets fixed at zero while
transmit packets rose from 18 to 24. The first release-level failure interval
is therefore QEMU `v7.2.0` good to `v8.0.0` bad.

## Separate OpenBoot observation

Before booting from disk, OpenBoot tried the LANCE device and reported:

```text
Internal loopback test -- Wrong packet length; expected 36, observed 64
```

Solaris networking still worked after boot. Keep this observation separate
from the QEMU 11.1.0 receive failure until a test connects them.

## Next discriminator

Run a commit-level bisect between QEMU `v7.2.0` and `v8.0.0`, starting with
commits that touched the LANCE/PCnet device, SPARC DMA, or sun4m machine.

### Commit bisect

The release interval contains 2,973 ancestry-path commits. The first Git-bisect
candidate was:

```text
2d89cb1fe5c778f51b5fdc6878adacdb0d908949
Merge tag 'for-upstream' of https://repo.or.cz/qemu/kevin into staging
```

It built as QEMU `7.2.50` with the NVRAM backport temporarily applied. Run
`/tink/runs/sun4m-solaris9/20260828T164210Z-52749`, PID `52749`, auto-booted
normally. The identical gateway test failed with `le0` RX fixed at zero and TX
rising from 18 to 24, so this candidate is bad. Git estimated approximately
1,505 revisions remained on the good side of this split before the next test.

The second candidate was:

```text
7ec8aeb6048018680c06fb9205c01ca6bda08846
Merge tag 'pull-tpm-2023-01-17-1' of https://github.com/stefanberger/qemu-tpm into staging
```

It built as QEMU `7.2.50`. Run
`/tink/runs/sun4m-solaris9/20260828T164739Z-59281`, PID `59281`, auto-booted
normally. The identical test again left RX at zero while TX rose from 18 to
24, so this candidate is also bad. The first bad change is therefore within
the first 755 ancestry-path commits after QEMU `v7.2.0`.

## Persistent lab shells

`scripts/lab-host` manages dedicated SSH-backed tmux sessions on Minnie:

| Name | tmux session | Destination |
| --- | --- | --- |
| `ec2trib` | `lab-ec2trib` | `root@ec2trib` |
| `playbox` | `lab-playbox` | `niagara@niagara-playbox` |
| `teddeck` | `lab-teddeck` | `ryan@teddeck` |

Example:

```bash
scripts/lab-host ensure all
scripts/lab-host run ec2trib 'uname -n; pgrep -fl qemu-system-sparc'
```

The first measured `ec2trib` command completed in 1.138 seconds end to end;
the remote command itself took 780 milliseconds. These sessions are separate
from the human-facing `trib` and `playbox` sessions.

## QEMU 11 persistent M48T08 NVRAM

The QEMU 7.x persistent-NVRAM feature was redeveloped against exact upstream
QEMU `v11.0.0` in the isolated ec2trib worktree:

```text
/tink/builds/qemu-ss5-nvram-v11-tdd
branch: codex/qemu11-nvram-tdd
commit: 2b8f90dfba61b31bb23d04e55fc9c57b7a52ae63
patch: patches/qemu-v11-persistent-nvram-tdd.patch
```

The final contract matches the original feature. The `filename` property on
`sysbus-m48t08` loads an exact-size image, creates a missing 8192-byte image,
and writes guest changes back immediately. When an existing image was loaded,
sun4m treats it as authoritative and does not rebuild it from `-prom-env`.

Six qtests cover load, writeback across restart, conflicting `-prom-env`, file
creation, and preservation of the historical QEMU 7.x byte layout. The real
Solaris 9 seed auto-booted the SCSI disk on QEMU 11 without the console probe
typing `boot disk0`. A discarded intermediate design attempted to translate
the saved bytes into CHRP partitions; the Sun PROM rejected that image's
configuration checksum, proving that translation was not compatible with the
original feature.

Biggie Woodpecker pipeline 15 completed successfully with QEMU
`v11.0.0-15-g2b8f90dfba`; all six qtests passed and the boot step emitted
`SOLARIS9_NVRAM_AUTO_BOOT_TEST=PASS` at the Solaris login prompt.

Keep NVRAM acceptance separate from the LANCE regression. With the saved
authoritative NVRAM, Solaris reached login but the known symptom returned:
`le0` transmitted packets while receiving zero. When the invalid intermediate
image caused the PROM to reset its configuration defaults, the same QEMU 11
binary received packets and reached `10.0.2.2`. This makes PROM/NVRAM state a
new discriminator for the network investigation; it does not make NVRAM
persistence itself a networking failure.
