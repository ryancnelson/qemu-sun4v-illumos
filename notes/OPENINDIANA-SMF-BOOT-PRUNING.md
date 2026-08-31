# OpenIndiana conservative SMF boot-pruning plan

This is an offline planning artifact, not permission to change the installed
system.  It uses committed boot logs, run notes, and prior SMF evidence only.
It has not queried either live guest.

## Scope and hypothesis

Hypothesis: three observed, non-basecamp services can be disabled one at a
time after the cold-reboot acceptance gate without weakening storage,
console/login, channel PPP, NFS, networking, or observability.  The predicted
distinguishing observation is reduced service delay with every protected
capability and the complete cold-reboot acceptance harness still passing.

The conservative candidates are:

- `svc:/application/opengl/ogl-select:default` on the headless serial VM;
- `svc:/network/inetd-upgrade:default`, a documented one-shot migration;
- `svc:/system/keymap:default` on the proven No Keyboard topology.

Each candidate has an exact synchronous `svcadm disable -s` proposal and the
mechanical inverse `svcadm enable -s` rollback.  Apply at most one candidate
per measured batch.  RBAC, name-service cache, netmask, routing setup, and
IPsec algorithms remain out of the manifest because the existing evidence is
not sufficient to exclude dependencies needed by developer tooling or the
accepted network path.

## Fail-closed protected policy

The versioned manifest explicitly protects these capability families, and the
checker contains the same non-overridable policy:

- Niagara channel/PPP services and any FMRI containing channel, PPP, or sppp;
- NFS client and RPC services;
- console login, tty/utmp, cryptosvc/sysconfig, multi-user milestones, and SSH;
- devices, devfs, and local device enumeration;
- every filesystem/root/single-user, boot-archive, identity, and ZFS service;
- physical/IP interface, initial network, routing, netmask, varpd, DNS client,
  loopback, name-services, and network-service milestones;
- SMF restarter, system logging, management, and audit observability.

An exact protected-policy mismatch, protected candidate, unknown action,
non-canonical FMRI, duplicate, missing evidence, or non-mechanical rollback is
a terminal checker failure.

## Offline dry run

Run only on the host repository:

```sh
python3 tools/openindiana/check-smf-boot-pruning.py
```

The command reads
`tools/openindiana/openindiana-smf-boot-pruning-v1.json` and emits canonical
JSON.  Success is `SMF_PRUNING_DRY_RUN_PASS`, `apply_allowed` is always false,
and candidate output is sorted by FMRI.  The checker has no apply mode and
does not run `svcadm`, inspect a guest, or contact a QEMU endpoint.

For a separately staged manifest, pass its path as the sole argument.  This is
still validation only:

```sh
python3 tools/openindiana/check-smf-boot-pruning.py /path/to/candidate.json
```

## Authority and eventual acceptance

Application requires explicit Ryan approval, and only after the currently
pending cold reboot has independently reached installed-root multi-user/login
and passed channel PPP, default route, NFSv3/TCP, smoke marker, developer tools,
and observability gates.  Before an approved first change, capture the service
state, dependencies/dependents, restarter log, and baseline timing.  Snapshot
the accepted BE, disable one candidate, rerun all non-regression gates, record
timing, and retain the exact rollback command.  A reboot for timing also needs
separate lifecycle approval.

Sources: `notes/OPENINDIANA-NEXT-ISO-TODO.md` (observed candidate and protected
lists), `notes/OPENINDIANA-INSTALLED-MULTIUSER-MILESTONE-20260826.md` (SMF
cycle, inetd-upgrade rationale, preservation rules),
`notes/BIGGIE-TERM4CODE-OPENINDIANA-RUN.md` (accepted channel/PPP/NFS startup
requirements), and `notes/SHELL-2-PROGRESS.md` (observed service failures).

## Offline verification evidence

On 2026-08-26 PDT, the focused unit suite passed all 14 tests.  It exercised
rejection for channel/PPP, NFS, console/login, devfs, filesystem, ZFS,
networking, and observability FMRIs; it also proved that reversing manifest
candidate order produces byte-equivalent canonical JSON data and that the
manifest cannot weaken the embedded protection policy.  The real manifest
dry run returned `SMF_PRUNING_DRY_RUN_PASS`, three candidates in FMRI order,
and `apply_allowed:false`.  The combined pruning and cold-reboot harness unit
selection passed all 31 tests.  No guest, QEMU endpoint, service, or disk was
read or changed by either command.
