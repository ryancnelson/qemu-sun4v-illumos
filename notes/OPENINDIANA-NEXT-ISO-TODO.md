# OpenIndiana next-ISO TODO: fast development boot and guarded reset modes

Date: 2026-08-24

## 2026-08-25: patched boot succeeded; startup CI failed

The one-vCPU patched QEMU boot reached a maintenance root prompt and proved a
working channel-1 root shell.  It did **not** prove PPP or SSH on the 6 GiB
install candidate.  That boundary matters because older basecamp runs did
prove PPP/SSH on other images.

Before another installer cycle:

- [ ] Make `S99niagara start/stop/restart` idempotent.  Stop and reap the Perl
  PPP wrapper and rootpty helper as well as pppd/chand/socat; assert exactly one
  process per role after restart.
- [ ] Fix `host-up.sh` QEMU identity matching so sudo wrappers do not make the
  one-worker SIGUSR2 gate fail.
- [ ] Keep `persist maxfail 0` out of host pppd.  Add a bounded retry and a
  zombie/task-count guard that tears PPP down on the first defunct child.
- [ ] Add a deployment preflight that compares local and playbox hashes for
  `host-up.sh`, guest startup payload, QEMU, firmware, and image.
- [ ] Encode the only supported startup order in one watched CI driver:
  initialize mailbox -> start host services -> boot -> run guest service at
  first shell -> prove channel 1 -> prove host ping -> prove actual SSH command.
- [ ] Use `tools/tmux-run.sh`; do not hand-compose long tmux command lines.
- [ ] Reject an inherited dirty/partial pool as an install baseline.  The
  `patched-8ad4fe2e` image is evidence only.

Incident evidence and hashes are in `OPENINDIANA-PERFORMANCE-NOTEBOOK.md`.

## 2026-08-25: media success exposed the blocking-console path

The fresh net-v1 boot did not merely run slowly.  After 1 hour 35 minutes its
last output was:

```text
Niagara hsimd install media: /dev/dsk/c4d0s2
```

The QEMU vCPU remained at 100% of one host core with zero block I/O.  Two
read-only monitor samples placed the guest PC in/near `hv_cpu_yield` and the
level-14 cyclic/interrupt path.  This is consistent with an idle guest waiting
for an event; the old QEMU/hypervisor yield path still burns a host core while
it waits.

A read-only mount and tree comparison found only three net-v1 additions over
the earlier hsimd archive: `/etc/rc2.d/S99niagara`, `/lib/niag`, and the modified
`media-fs-root`.  Console configuration is identical.  The earlier method's
physical bytes appear as a 4,412-byte `Zcmp` object when read through Linux
UFS; that is illumos boot-archive compression, not evidence that the script was
corrupt.  The replacement is an uncompressed 11,477-byte script containing the
original method plus the hsimd-media fallback.

The best current explanation is narrower than “the old archive kept the
serial console polling”: before the hsimd fallback, failure to mount live media
prevented or diverted later text-install initialization.  With media mounting
fixed, the stock `TEXTINSTALL` branch can reach blocking calls including:

```sh
/usr/bin/kbd -s </dev/console >/dev/console 2>&1
/usr/sbin/set_lang </dev/console >/dev/console 2>&1
```

Those reads require the qcn interrupt path that this older QEMU machine lacks.
The installer menus that previously accepted Return were polling, which
explains the apparently contradictory behavior.  This is a strong working
hypothesis, not yet a guest-stack proof of the exact blocked process.

For the next development archive:

- [ ] Add `/dev/msglog` markers before and after `apply_platform_profile`, the
  `/opt` mount, `update_linker_cache`, `kbd`, and `set_lang`.
- [ ] In the development profile, use `kbd -s US-English` and
  `set_lang default` rather than reading `/dev/console`.
- [ ] Preserve the original interactive path in the normal installer profile.
- [ ] Retest the unmodified interactive path on Murayama's coherent UART and
  interrupt stack.

## Playbox capacity update (completed 2026-08-24)

- [x] Stop the two OpenIndiana live-media test QEMUs; neither was the Solaris
  10 donor.
- [x] Power off `niagara-playbox` cleanly and grow its sparse UTM qcow2 from
  30 GiB to 64 GiB.
- [x] Grow `/dev/vda3` and the `ubuntu-vg` physical volume.
- [x] Grow the ext4 root LV from 15 GiB to 20 GiB.  It has approximately
  6.9 GiB free after the change.
- [x] Grow the XFS `images` LV from 11.95 GiB to 40.95 GiB.  It has
  approximately 32 GiB free after the change.
- [x] Recreate the detached `openindiana-console` tmux session with `console`
  and `host-services` windows.
- [x] Recheck the net-v1 ISO after the host reboot.  Its SHA-256 remains
  `d8792b43a92923e42ceb40ee6d07a4e4250966598a22e8c7f63064c985dd0840`.

No nested SPARC QEMU was restarted.  The next OpenIndiana boot can therefore
run alone.  Biggie is a candidate host for the Solaris donor and supporting
build/archive services so that playbox remains dedicated to one interactive
sun4v test guest.

## Provenance and prior art

Ryan requested the factory-reset-on-next-boot feature while at Joyent.  The
SmartOS/Triton implementation is therefore a shipped implementation of Ryan's
request, not merely an unrelated analogous design.

The implementation uses a persistent ZFS property as a one-shot marker:

```text
smartdc:factoryreset=yes
```

`sdc-factoryreset` asks for confirmation, sets the property on the system
pool's `var` dataset, and reboots or powers off.  On the following boot, an
early reset service imports and destroys the pools.  The documented recovery
escape is the boot option `noimport=true`; after booting without pool import,
the operator can clear the property rather than completing the reset.

Primary sources:

- [SmartOS `sdc-factoryreset.sh`](https://github.com/TritonDataCenter/smartos-live/blob/master/src/smartdc/bin/sdc-factoryreset.sh)
- [SmartOS `sdc-factoryreset(1)`](https://github.com/TritonDataCenter/smartos-live/blob/master/man/smartdc/man/man1/sdc-factoryreset.1.md)

illumos already supplies two useful non-destructive boot mechanisms:

- `-s` requests single-user boot.
- `-m milestone=single-user` temporarily restricts the SMF graph to the named
  milestone.  Other documented values include `none`, `multi-user`,
  `multi-user-server`, and `all`.

Primary sources:

- [illumos `kernel(8)`](https://github.com/illumos/illumos-gate/blob/master/usr/src/man/man8/kernel.8)
- [illumos `boot(8)`](https://github.com/illumos/illumos-gate/blob/master/usr/src/man/man8/boot.8)

### SPARC boot-property caveat

The current illumos `boot(8)` synopsis documents `-B prop=value` in the x86
form, but not in the SPARC form.  Do not make a custom mode depend on
`boot ... -B niagara-mode=...` until we have verified that the sun4v boot path
actually transports and exposes such a property.  A SPARC client-program
argument, an OpenBoot property, or an ISO-resident persistent marker may be the
correct mechanism instead.

The operating system supports `-s` and `-m milestone=single-user`, but that is
not currently a usable fast-console path on this project's older QEMU stack.
The guest reaches `SINGLE USER MODE` and then blocks on a tty read that the
unwired emulated UART interrupt cannot wake.  Retest these supported modes on
Murayama's coherent UART/interrupt stack; do not describe them as working here
until input at the prompt is demonstrated.

## Modes to provide

Keep the destructive and non-destructive concepts separate:

1. **normal** -- boot the live installer normally.
2. **development/fast** -- start the Niagara channels early and suppress only
   services demonstrated to be unnecessary for our installer work.
3. **single-user** -- use illumos's existing `-s` or SMF milestone support for
   the shortest supported route to a maintenance shell.
4. **no-import/rescue** -- explicitly prohibit pool import and destructive
   actions.  This is the recovery escape for any future reset mechanism.
5. **factory-reset** -- a future, deliberately armed, one-shot operation.  It
   must never be implied by development/fast or single-user mode.

## Next ISO implementation

- [ ] Replace `/etc/rc2.d/S99niagara` as the primary startup mechanism with a
  real SMF service.  The live-media boot path does not run that rc2 script.
- [ ] Order the channel service after `svc:/system/filesystem/root:media` so
  that the live media, `/usr`, `/lib/niag`, and the helper payload are present.
- [ ] Start both guest-side endpoints automatically:
  - channel 1: `rootpty` maintenance shell
  - channel 0: PPP endpoint
- [ ] Make startup idempotent and make repeated `svcadm restart` useful during
  development.
- [ ] Log enough state to diagnose failures from the serial console: device
  nodes, helper exit status, channel state, and PPP state.
- [ ] Preserve a manual emergency command/script that starts the same endpoints
  when booted with `-s`.

## Fast-boot SMF profile

The following services were directly observed delaying this live-media boot
and are candidates for the development profile:

- `svc:/system/keymap:default`
- `svc:/network/ipsec/ipsecalgs:default`
- `svc:/network/netmask:default`
- `svc:/application/opengl/ogl-select:default`
- `svc:/system/rbac:default`
- `svc:/system/name-service-cache:default`
- `svc:/network/inetd-upgrade:default`
- `svc:/network/routing-setup:default`

- [ ] Disable candidates one at a time in a throwaway archive/profile and
  measure the result.
- [ ] Record whether each service is merely slow, times out, or is a dependency
  of something we need.
- [ ] Stop `routed`/routing setup in the development profile so the known error
  does not recur.
- [ ] Keep the normal installer profile available as a control.

Do **not** disable the following merely to improve boot time:

- `svc:/milestone/devices:default`
- `svc:/system/filesystem/root:media`
- root-minimal/filesystem services
- devfs/device enumeration
- ZFS services needed for inspection or installation
- the minimal network stack required by channel 0 PPP

## Mode transport investigation

- [ ] Trace the sun4v/OpenBoot-to-kernel boot arguments and determine which
  mechanism can carry a custom mode reliably on SPARC.
- [ ] Test whether a harmless custom client-program argument survives into a
  place an early SMF method can read.  Do not assume unknown kernel arguments
  are accepted.
- [ ] Test an OpenBoot property and identify the guest interface that exposes
  it (`devprop`, `/devices`, or another boot-property interface).
- [ ] If neither route is clean, make this development ISO fast-by-default and
  postpone a selectable custom mode until the transport is understood.
- [ ] Once selected, document exact boot commands for normal, development,
  single-user, and rescue boots.

## Guardrails for a future factory-reset mode

- [ ] Require a persistent, explicit one-shot marker; a bare boot flag is not
  sufficient authorization to destroy storage.
- [ ] Require two confirmations when arming it, following the SmartOS design.
- [ ] Provide and test a `no-import` recovery escape before implementing pool
  destruction.
- [ ] Identify reset targets by an explicit pool/disk allowlist.  Never destroy
  every pool discovered by the installer environment.
- [ ] Display and log the exact pool GUIDs and disk paths selected.
- [ ] Clear the one-shot marker only after the intended terminal state is
  reached, with behavior defined for interruption and partial failure.
- [ ] Test reset behavior only with disposable images and retain an untouched
  recovery image.

## Installer investigation after channel access works

- [ ] Boot to a fast shell and start channel 1 immediately.
- [ ] Capture `prtvtoc`/device-node output for `hsimd0` and the emulated disk.
- [ ] Run `zpool import` and test importing an existing disposable pool.
- [ ] Locate the text installer's disk-discovery and validation code.
- [ ] Determine whether it can be taught to accept `hsimd0`, or whether the
  better path is to prepare/import a pool in the shell and hand it to the
  installer.
- [ ] Continue tracing the missing `hsimd` ioctls `0x410` and `0x42a` if they
  block installer disk discovery or media handling.

## Acceptance checks and timing

- [ ] Keep the Solaris 10 donor VM running throughout boot-archive iteration.
- [ ] Run every interactive boot in the `openindiana-console` tmux session.
- [ ] Record elapsed times from QEMU start/kernel banner to:
  - live-media/root mount
  - channel 1 shell
  - channel 0 PPP ping
  - installer menu
- [ ] Compare normal, `-s`, and development-profile boots.
- [ ] Verify that the fast profile still supports media mount, disk inspection,
  ZFS import/create, channel 1 shell, PPP networking, and installer launch.
- [ ] Verify that rescue/no-import mode performs no pool import and no storage
  mutation.

## Immediate next boot

1. Start from the immutable known-good image and create a new raw reflink; do
   not clone the unclean partial-install candidate.
2. Assert the full patched-QEMU build ID and all startup-script hashes.
3. Initialize the mailbox and run the corrected host startup in watched tmux.
4. Boot one CPU with `boot disk -s -v`; the 2026-08-25 run proved this reaches
   an interactive maintenance login on the older stack.
5. At the first root prompt, start the guest service exactly once and prove the
   channel-1 shell.
6. Require zero zombies, host ping to `10.0.5.15`, and an actual SSH command
   response.  Stop immediately on the first failed gate.
7. Only then create a fresh target pool and launch the installer.
8. Retest the same image on Murayama's stack after the OpenIndiana `hsimd`
   driver is rebuilt for its current cmlb ABI.
