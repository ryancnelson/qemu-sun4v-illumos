# Niagara continuous build-and-boot conveyor

The host-level AWS persistence, reboot, artifact, blue/green, and recovery
contract is `notes/AWS-CICD-ENGINE.md`. Do not infer that an enabled package
service or persistent EBS volume makes a worker automatically replayable.

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

## Hard terminal-lifetime policy

Never make QEMU, `tail`, `socat`, an SSH command, or any other transient
workload the owning command of the tmux session that a WezTerm window attaches
to.  The forbidden process chain is:

```text
WezTerm -> ssh -> tmux new-session ... <transient-command>
```

When `<transient-command>` exits, tmux exits; SSH then exits; WezTerm closes.
This destroys the operator's console at exactly the moment failure evidence is
most valuable.

Every watch-along tmux session must instead start with a persistent interactive
shell.  Launch QEMU and other workloads in additional named windows or panes.
Workload exit must leave the session, shell window, console history, and the
operator's WezTerm window alive.  `remain-on-exit` is useful evidence retention,
but it does not replace the persistent-shell owner.  Before declaring a rig
ready, deliberately terminate the workload and verify that tmux, SSH, and the
attached WezTerm window remain open.

## OpenIndiana workstation candidate input

The first installed-root workstation candidate is not the older unit-103
release bundle described above.  Its primary artifact is the sparse 60 GiB
unit-104 ZFS-root image, accompanied by Murayama's QEMU executable and complete
firmware directory, units 100/101/103, and an exact argv manifest.  The current
identity, BE, artifact paths, runtime networking boundary, and AWS-compatible
copy/acceptance contract are recorded in
`notes/OPENINDIANA-WORKSTATION-CANDIDATE-20260826.md`.

Do not point a CI worker at the live writable unit-104 image.  Publish only
from a stable guest-consistent snapshot or cleanly stopped copy, preserve sparse
extents, create a fresh writable clone per run, and regenerate unit 101 from a
clean mailbox template.  A CI PASS requires a fresh-QEMU cold boot; inheriting
the live Biggie guest's BE, PPP processes, or NAT state is not evidence.
