# Independent sun4u and Niagara SMP CI lanes

Updated 2026-09-04.

| Lane | Owning Codex task | Branch | Workflow | Execution host |
| --- | --- | --- | --- | --- |
| Generic sun4u installer | 01a050c8-366e-7693-afcc-338952e410ca | codex/openbios-sun4u-ci | sun4u-openindiana | root@niagara-playbox |
| Niagara SMP appliance | 01a06a61-0f4c-7bd2-96d7-b46f0da5ae1d | codex/niagara-smp-oci | niagara-smp | root@ec2cicd |

Both use Biggie's Woodpecker repository 2 and the private GitHub CI mirror
`ryancnelson/niagara-qemu-solaris-lab`. Their run numbers share that repository's
sequence. Identify a result by branch, workflow, commit, and pipeline number.
A pipeline's creation age is different from the duration of its selected step.

## Source ownership

The main local checkout is the sun4u branch. The SMP task owns
`.worktrees/niagara-smp-oci`. Reviewing the other lane is read-only unless Ryan
requests a change there. This CI isolation change was explicitly requested for
both lanes; it does not transfer ongoing SMP development ownership.

Push successful checkpoints explicitly to Gitea `origin` and
`private-github`. The remote named `github` is the old public repository.
Do not use its stale tracking state as evidence of private CI synchronization.

## sun4u-openindiana

`.woodpecker/sun4u-openindiana.yml` replaces `openbios-sun4u.yml`.
Only `codex/openbios-sun4u-ci` triggers it, on push or manual runs.
It builds patched OpenBIOS, boots the B134 installer with regular QEMU's
`-M sun4u`, and checks interactive keyboard/language selection and device
configuration. This is an installer progress gate, not an installed-OS login gate.

Each run owns
`/mnt/disk-images/woodpecker/sun4u-openbios-<pipeline>` on playbox,
its OpenBIOS source checkout, firmware, logs, sockets, and
`sun4u-openbios-woodpecker-<pipeline>` container. The installer ISO and
pinned workbench image are verified and used read-only.
An existing run directory is rejected. Cleanup only stops the named test.

## niagara-smp

`.woodpecker/niagara-smp.yml` is exclusive to `codex/niagara-smp-oci`
(push or manual). The legacy self-contained workflow no longer matches this
branch. Neither experimental lane publishes release tags.

Every Niagara run owns
`/srv/woodpecker/niagara-smp/niagara-lab-<pipeline>` on ec2cicd.
The stage step refuses to overwrite an existing directory.
`scripts/ci-niagara-smp.sh` validates its directory, numeric pipeline number,
and full commit hash; a file lock prevents concurrent phases in the same run.

Base/final image tags, guest and helper container names, guest volume, mdgen
build, generated firmware, Docker build contexts, and evidence all include or
live under that run identity. No rsync writes into the persistent appliance
checkout, and no build prunes another run's volumes.

Only original QEMU and OpenSPARC source archives are copied from the existing
host cache. QEMU's source manifest and the firmware builder's archive checksum
remain required. The release bundle is extracted from the existing pinned GHCR
digest and verified against the checked-in release manifest. Only its firmware
is unpacked on the host; the boot test materializes its own writable guest.
No shared root disk is mounted or rewritten.

Visible steps are: static policy; staging; free-space/input preflight; image
build; interactive console; cold boot/login; two CPUs online; PPP/DNS; guest
inventory; evidence capture and cleanup. Boot has a 600-second outer deadline;
CPU checks 360 seconds; networking 900 seconds; inventory 300 seconds.
These bounds report the failing stage without conflating networking with boot.

Preflight requires 20 GiB free on the run filesystem before source preparation
or image building. It fails with `reason=insufficient-disk-space`.
The initial observed ec2cicd free space was only 6.1 GiB; an honest preflight
failure is expected until capacity is reclaimed or added.

Cleanup runs on success or failure and names only this run's containers/volume.
It preserves images and `state/` evidence for inspection. An abruptly killed
agent/SSH connection can bypass cleanup; inspect the recorded exact resources
before recovering that run. A retry should use a new pipeline number.

## Verification

`python3 -m unittest discover -s tests/unit -p test_ci_lane_isolation.py`
exercises two independent run identities, invalid identity, low-disk rejection
before Docker/source copying, commit mismatch, lock contention, scoped cleanup,
and mutually exclusive SMP triggers. The existing SMP policy still applies.
Both branch updates must reach the private GitHub mirror before the new
workflow names appear in Woodpecker.

Woodpecker's workflow names come from the YAML filenames; its status filter
allows an evidence/cleanup step after failure:
https://woodpecker-ci.org/docs/usage/workflow-syntax

## Deployment evidence, 2026-09-04

- sun4u commit `5aee07f`, Woodpecker repository 2 pipeline 67:
  workflow `sun4u-openindiana`; clone, policy, isolated staging, and OpenBIOS
  build passed. Installer boot/input test was still running at this handoff.
- Niagara commit `2a826d0`, pipeline 68: the new workflow was selected, but
  the first static step failed because Biggie's local agent lacks Python.
  Commit `115daa7` moves Python verification to ec2cicd after isolated staging.
- Niagara pipeline 69 at `115daa7`: shell check, staging, SMP policy, and all
  seven isolation tests passed on ec2cicd. Preflight found 6,311,064 KiB free
  against the 20 GiB requirement and reported
  `CI_PREFLIGHT=FAIL reason=insufficient-disk-space`.
  Image/guest stages were skipped, and `smp-capture-and-cleanup` passed.
  Evidence directory: `/srv/woodpecker/niagara-smp/niagara-lab-69/state`.
  New image assembly and runtime phases still require verification after
  enough disk space is available.
- Local repository tests: 100 passed, two external-source tests skipped.
  Both branch checkpoints were pushed to Gitea origin and private GitHub.
  No experimental image was published.

Pipeline links:
[67 sun4u](http://biggie.lynx-eagle.ts.net:8110/repos/2/pipeline/67),
[69 Niagara](http://biggie.lynx-eagle.ts.net:8110/repos/2/pipeline/69).

