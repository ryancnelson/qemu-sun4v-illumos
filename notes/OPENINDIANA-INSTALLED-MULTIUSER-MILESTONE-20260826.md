# OpenIndiana installed-root multiuser milestone — 2026-08-26

Scope: `term4code-herm-smp4-01` (SMP/memory experiment clone) and preservation
of `term4code-02` (original protected run). All entries below are dated
2026-08-26, guest-local timestamps unless marked UTC.

## FACT — clone identity and protected targets

- Clone run directory: `/home/ryan/devel/masa-sun4v/ci/runs/term4code-herm-smp4-01`
  on Biggie, tmux session `term4code-herm-smp4-01` (windows `qemu`, `console`).
- Clone QEMU PID: **2189614**, owned via `qemu-owner.sh` (setsid-detached, no
  controlling terminal — survives tmux/session loss).
- Protected original: `term4code-02`, QEMU PID **2156055**, tmux session
  `term4code-02`, console window `19.0`. Confirmed alive at every check
  throughout this work; never sent input, never had its monitor touched, never
  had its live raw image opened for writing.

## FACT — clone provenance and drive mapping

- unit100 (carrier, writable): independent sparse copy of
  `term4code-02/images/carrier-unit100.img`, 1,073,741,824 bytes.
- unit101 (channel, writable): independent sparse copy of
  `term4code-02/images/channel-unit101.img`, 33,554,432 bytes.
- unit103 (installer media, read-only): **directly reused** from
  `term4code-02/images/installer-unit103.img` — not copied, mounted read-only
  in both QEMU instances simultaneously (`readonly=on`).
- unit104 (target/big disk, writable): sparse `cp --sparse=always` from the
  immutable ZFS snapshot
  `/home/.zfs/snapshot/niagara-term4code-02-smf191-20260826T1545Z/.../images/extra-unit104-60g.img`
  (snapshot mount confirmed `ro` at the filesystem level, independent of file
  permission bits) into
  `term4code-herm-smp4-01/images/extra-unit104-60g.img`. Byte size confirmed
  exact match both before and after copy: 64,424,509,440 bytes.
- QEMU binary and firmware directory: reused directly from
  `term4code-02/qemu-system-sparc64` (SHA-256
  `ea9348f2565befef00b7f8628489be01bde5799df842c88cdfe70a25664bba3c`) and
  `term4code-02/firmware/` — unchanged, not copied or modified.

## FACT — QEMU command and the OBP/CPU discrepancy

Launched via:

```
qemu-owner.sh term4code-herm-smp4-01 -- qemu-system-sparc64 \
  -M niagara -L term4code-02/firmware -m 8192 -smp 4 \
  -serial file:/dev/null -serial unix:.../console.sock,server=on,wait=off \
  -monitor unix:.../monitor.sock,server=on,wait=off -nographic \
  -drive id=carrier100,...,unit=100,readonly=off,file=.../carrier-unit100.img \
  -drive id=channel101,...,unit=101,readonly=off,file=.../channel-unit101.img \
  -drive id=installer103,...,unit=103,readonly=on,file=term4code-02/images/installer-unit103.img \
  -drive id=target104,...,unit=104,readonly=off,file=.../extra-unit104-60g.img
```

Boot command issued at OBP: `boot /virtual-devices@100/disk@4:a -v`.

**The QEMU launch arguments requested 8192 MiB and 4 vCPUs (`-m 8192 -smp
4`), but the firmware/MD directory was intentionally left unchanged (per
explicit instruction — same descriptors as `term4code-02`'s 1-vCPU/3 GiB
config). The observed OBP banner and kernel boot printed:**

```
OpenBoot 4.x.build_122***PROTOTYPE BUILD***, 3072 MB memory available, ...
...
mem = 3145728K (0xc0000000)
avail mem = 2984189952
...
cpu0: UltraSPARC-T1 (chipid 0, clock 1000 MHz)
```

i.e. **OBP and the guest kernel exposed only 3072 MB and a single `cpu0`**,
not the requested 8192 MiB / 4 vCPUs. This is recorded as an observed fact of
this trial, not yet diagnosed — the unchanged Machine Description (MD)
firmware almost certainly encodes the 1-vCPU/3GiB topology independently of
QEMU's own `-m`/`-smp` flags, but that is inference, not confirmed by reading
the MD binary in this session.

## FACT — hSIMD enumeration on the clone

```
hsimd4: hsimd_attach: size:0xf00000000, cap:0x5
hsimd4: hsimd_attach: part 0 16065 - 125788950 a 0x0
hsimd4: hsimd_attach: part 2 0 - 125829120 c 0x5
...
virtual-device: hsimd4
hsimd4 is /virtual-devices@100/disk@4
root on rpool/ROOT/openindiana fstype zfs
```

unit104 attached as `hsimd4`, size `0xf00000000` = exactly 64,424,509,440
bytes — matches the cloned image's byte size exactly. Root mounted from
`rpool/ROOT/openindiana`, confirming a genuine installed ZFS root, not
live/installer media.

## FACT — SMF dependency cycle and subsequent progress

```
Aug 26 09:09:09 svc.startd[9]: Transitioning svc:/system/filesystem/root-minimal:default
  to maintenance because it completes a dependency cycle:
  svc:/system/identity:node, svc:/network/physical, svc:/network/physical:default,
  svc:/network/varpd, svc:/network/varpd:default, svc:/system/device/local:default,
  svc:/system/filesystem/usr, svc:/system/filesystem/usr:default,
  svc:/system/boot-archive, svc:/system/boot-archive:default,
  svc:/system/filesystem/root, svc:/system/filesystem/root:media,
  svc:/system/filesystem/root-minimal:default
```
(repeated once, 09:11:08, identical cycle)

Boot continued past this point: `Configuring devices.` → `Hostname:
oi-basecamp` → `svc:/system/rbac:default: Method or service exit timed out.
Killing contract 36` (09:21:34) → `WARNING: svccfg apply
/etc/svc/profile/generic.xml failed` → `Mounting ZFS filesystems: (1/6)` →
**an interactive `root@oi-basecamp` prompt was reached** (reported directly
by the operator monitoring the console; not independently read by this
session, since console access was explicitly withheld once someone else was
observed actively typing in that pane).

## HYPOTHESIS (not yet independently confirmed by this session)

`svc:/system/filesystem/root:media` is the obsolete live-media-installer edge
in the dependency cycle above; on a genuinely installed ZFS root it has
nothing to attach to, and disabling it is expected to let
`root-minimal` clear rather than re-entering maintenance. This mirrors an
already-documented precedent for Tribblix's own installed-root correction
(`docs/design-plans/2026-08-21-tribblix-installed-root-network.md`), where
`system/filesystem/root:media` / `usr:live-media` remaining "online" was
identified as a symptom of an incomplete install-media-to-installed-root
transition — not merely a boot-time nuisance.

## PROPOSED — minimal ordered SMF triage plan (NOT YET EXECUTED)

Console ownership was not confirmed idle at the time this plan was drafted;
none of the following has been run.

1. **`svcadm disable -s svc:/system/filesystem/root:media`**
   Rationale: obsolete live-media edge, root cause of the `root-minimal`
   dependency cycle above.
   Rollback: `svcadm enable -s svc:/system/filesystem/root:media`
   Verify: `svcs -xv` no longer cites this service in `root-minimal`'s cycle;
   `svcs svc:/system/filesystem/root-minimal:default` moves toward `online`.

2. **`svcadm clear svc:/system/filesystem/root-minimal:default`**
   Rationale: already in `maintenance` from the cycle above; needs an
   explicit clear to retry once its blocking dependency is removed. This
   service itself must be preserved, never disabled
   (`notes/OPENINDIANA-NEXT-ISO-TODO.md`'s explicit "do not disable" list).
   Rollback: none needed (idempotent); re-diagnose via `svcs -xv` if it
   re-enters maintenance.
   Verify: reaches `online`.

3. **`svcadm disable -s svc:/network/inetd-upgrade:default`**
   Rationale: named directly in `notes/OPENINDIANA-NEXT-ISO-TODO.md` as an
   observed boot-delay source; a one-shot migration service with no ongoing
   function once complete — does not gate SSH, NFS client, PPP, or channel
   services.
   Rollback: `svcadm enable -s svc:/network/inetd-upgrade:default`
   Verify: service shows `disabled`; confirm `svc:/network/ssh:default` and
   any NFS-client service remain `online` afterward.

4. **`svc:/system/rbac:default` — investigate before disabling.**
   Rationale: repeatedly timing out and being killed (contract 36 here;
   contract 24/26 in the analogous Tribblix run tonight), but boot already
   progressed past its failure without being blocked by it. Disabling RBAC
   outright risks breaking `pfexec`/role-based developer tooling. Leave
   as-is unless it is shown to gate something required.
   If disable becomes necessary: `svcadm disable -s svc:/system/rbac:default`
   Rollback: `svcadm enable -s svc:/system/rbac:default`
   Verify: confirm no required workflow depends on RBAC before disabling.

**Explicit preservation list** (do not disable under this plan):
`svc:/milestone/devices:default`, ZFS pool/filesystem services, channel/PPP
startup chain, `svc:/network/ssh:default`, any NFS-client service, and
`svc:/system/filesystem/root-minimal:default` itself (clear only, never
disable).

**Final verification gate** (after all steps above, once executed):
`svcs -xv` returns clean; boot reaches a stable `login:` or shell prompt
without re-entering maintenance; SSH, NFS-client mount capability, and any
PPP/channel service independently confirmed functional.

## Protected-target confirmation at time of writing

- `term4code-herm-smp4-01` QEMU PID 2189614: alive.
- `term4code-02` QEMU PID 2156055: alive, untouched.

Neither VM's console or monitor was written to while preparing this note.

## Status addendum — workstation candidate, 12:27 PDT

The protected-target section above is historical evidence from the initial
inventory and is superseded for current operations:

- `term4code-02` PID 2156055 was terminated by the SIGUSR2 incident recorded
  in `notes/INCIDENT-TERM4CODE-02-SIGUSR2-20260826.md`; it was not rebooted.
- Its obsolete 24-window tmux session was later removed after confirming that
  the original QEMU was dead and the remaining channel helpers served only its
  stale unit-101 image.  The run directory remains required by the surviving
  candidate and must not be deleted.
- `term4code-herm-smp4-01` was relaunched as PID 2366353, booted its installed
  unit-104 ZFS root to multiuser, and passed manual channel-0 PPP plus routed
  Internet packets.
- A clean operator tmux view named `workstation-candidate` links only the live
  `console`, `bridge0-ppp`, and `ppp0` windows.
- Guest BE `workstation-candidate-20260826` was created successfully but was
  not activated or cold-boot tested.

The canonical current handoff, including the AWS/CI artifact contract and
known omissions, is
`notes/OPENINDIANA-WORKSTATION-CANDIDATE-20260826.md`.
