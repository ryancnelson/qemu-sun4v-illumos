# Niagara continuous build-and-boot conveyor

This directory separates two facts that earlier experiments blurred together:

1. A finalized 192,595,968-byte UFS boot archive must currently be produced by
   a disposable Solaris/OpenIndiana builder guest. Linux does not have writable
   UFS support on the project hosts.
2. Once that archive is published, building and verifying the matching
   2,791,702,528-byte big disk is deterministic, host-only, and fast.

`enqueue-boot-archive.sh` publishes an explicit, hash-pinned request and creates
`INPUT_READY` last. `continuous-artifact-builder.sh` consumes ready requests.
`build-openindiana-release.sh` performs the sector-exact splice, constructs the
Sun VTOC and channel slice, verifies unaffected regions, and publishes an
immutable release. `current` changes only after `READY` exists.

The smoke consumer must resolve `current` once, pin that release directory, and
boot a per-run sparse/reflink clone. QEMU must never receive the immutable
release image itself because the Niagara MAP_SHARED model and channel mailbox
initialization write to their backing files.

The Biggie controller uses blue/green ownership:

- `current` is the newest artifact release that passed host-only tests.
- `green` is the release whose CI-owned QEMU passed smoke tests.
- A new candidate boots in its own tmux session while the prior green guest
  remains available.
- Only after promotion may the controller retire the prior CI-owned QEMU, and
  then only via its recorded PID/run directory. Broad `pgrep` teardown is
  forbidden.
- At most two CI-owned QEMUs may exist during promotion. Manual, basecamp and
  donor VMs are outside the controller's authority.

Recommended triggering is a user `systemd.path` unit watching
`inbox/*/INPUT_READY`, plus a one-minute timer as missed-event recovery. The
oneshot worker and builder are also protected by `flock`, so duplicate triggers
are harmless.

Example user units and a configuration template live under `systemd/` and
`config.env.example`. Install them under `~/.config/systemd/user`, create the
host-specific `~/devel/niagara-ci/config.env`, then enable both the path and
timer. The timer is recovery, not the primary latency path.

## Exabyte worker cloud-init

`exb-cloud-init.yaml` is the non-sensitive base configuration. Render a private
provisioning file that mirrors Biggie's `ryan` UID/GID, password hash, and SSH
authorized keys:

```bash
tools/ci/render-exb-cloud-init.sh work/exb-cloud-init.rendered.yaml biggie
```

The renderer requires `ryan` to remain UID/GID 1000 on the source host. It
creates `ryan` with password-based sudo and keeps `ubuntu` at UID/GID 1001 as a
locked-password provider recovery account. The rendered file is mode 0600 and
must stay under the ignored `work/` directory because it contains the password
hash and public keys. Pass it to `exa machines create --cloud-init`, then delete
it after provisioning. Console login uses `ryan` and the same password as on
Biggie.

## Publish a validated bundle to Exabyte

`publish-exabyte-artifacts.sh` runs on Biggie and transfers the validated boot
archive, unit-103 big disk, unit-100 root template, unit-101 channel disk,
firmware, source ISO and smoke evidence to the mounted Exabyte cache volume.
It validates pinned source hashes, streams only allocated extents with GNU
sparse tar, checks the destination sizes and shape, publishes through a private
partial directory, and creates the bundle-level `READY` marker last. A failed
or interrupted transfer cannot replace `current`.

The Exabyte worker credential is deliberately not stored in this repository.
Pass it with `EXB_IDENTITY` or install it mode 0600 at the default path shown by
the script's usage output.

`smoke-exabyte-bundle.sh` runs on the worker after `bundles/current/READY`.
It verifies the worker-built QEMU, makes writable sparse per-run clones (the
published images remain immutable), launches QEMU in a named tmux session, and
gates OBP, the OpenIndiana banner, and hSIMD units 0, 1, and 3.
