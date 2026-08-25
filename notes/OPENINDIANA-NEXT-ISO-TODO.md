# OpenIndiana next-ISO TODO: fast development boot and guarded reset modes

Date: 2026-08-24

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

1. On the older QEMU stack, use a normal fresh `boot disk` and take the first
   responsive installer/maintenance shell; do not wait on the known blocking
   `-s` tty path.
2. Start the existing Niagara helper immediately when that shell appears.
3. Confirm channel 1 and PPP before spending time in the installer.
4. Inspect the installer and storage state from the responsive channel shell.
5. Use the findings to build the SMF channel service and measured fast profile
   into the next ISO.
6. Separately retest `-s` and `-m milestone=single-user` on Murayama's stack,
   where the UART and interrupt design differs.
