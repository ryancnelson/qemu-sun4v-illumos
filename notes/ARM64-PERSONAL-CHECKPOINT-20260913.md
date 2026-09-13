# Personal checkpoint and release follow-up

Private local checkpoint; do not upload the personal image, guest disk, or core
to GHCR. The public release must be assembled from the accepted clean bundle.

## Preserved local state

- Container committed as
  `localhost/sparc64-qemu-openindiana-20g:arm64-personal-20260913`.
- Image ID `a62642c3cd31eeec8f54fd4ecbdda14b70da4005cddceebf400b4a8c8bb705e8`.
- Preserved named volume: `oi-arm-personal-saved-20260913`.
- Working volume remains `oi-arm-softint-trial-20260913`.
- The saved root and NVRAM passed `PERSONAL-SHA256SUMS` verification.
- Outside-Podman artifacts under `/var/tmp/niagara-softint-20260913T023438Z/`:
  `arm64-personal-20260913.oci.tar`,
  `arm64-personal-volume-20260913.tar.zst`, and
  `personal-volume.SHA256SUMS`.

This is a disk-based cold-relaunch checkpoint, not a saved RAM session.
It follows an OOM kill and remains crash-consistent until cold-boot verified.
GCC and sysroot downloads were complete and hash-verified; extraction was
interrupted and native compilation is not yet proven.

## OOM evidence and mitigation

At 2026-09-12 20:20:56 PDT, Podman reported exit 137 and `OOMKilled=true`.
Linux logged global OOM killing QEMU PID 265864, anon RSS 3,200,424 KiB.
The VM had 3.5 GiB usable memory and no swap. This is not evidence of a
second softint failure. A native debugger sampling request did not complete;
the OOM process list contains no gdb process.

With explicit user approval, Podman was changed from 3814 to 8192 MiB and
restarted. The final start was issued in tmux `oi-podman-host`; the preceding
start exited again after its command session ended (cause not established).
The user explicitly requested that `basilisk-ci` remain offline; it is stopped.
Only the working OpenIndiana volume is used for the recovery boot.

## Remote capacity

The user authorized cache reclamation and stopping guests on niagara-playbox.
Five historical release-bundle copies (77 through 81) were compared against
their correct cached originals and replaced with verified XFS reflinks.
Free space remained 14 GiB: this yielded no material additional capacity.
No image, guest disk, volume, or evidence was deleted by cache preparation.

Stopped `niagara-smp-arm64-unlimited-82`; its auto-remove container was first
committed to `sparc64-qemu-openindiana-20g:preserved-unlimited-82-20260913`,
image ID `9933b0463cb199d2d17eee9e9a910bec1d48a8a9906a54d31f8868c0b53b2270`.
Its named volume `niagara-smp-arm64-unlimited-82-state` was verified to remain.
Logs and inspect data are under
`/mnt/disk-images/woodpecker/niagara-unlimited-82-preserved-20260913`.
The console socket was absent, so guest sync could not be requested; do not
claim a clean guest shutdown. Solaris 9 remains running. Available RAM rose
to 4.4 GiB. No remote VM resize was performed.

## Build changes under verification

- Atomic softint patch and deterministic actual-helper test in both builds.
- Correct psrinfo path and unmasked CPU gate.
- Assembly and bring-up both select `nameserver 8.8.8.8`; nsswitch uses
  `hosts: files dns` and `ipnodes: files dns`.
- `FETCH_GCC.sh` downloads the two pinned archives during networked assembly.
  It does not claim to install the assembler or complete native GCC setup.
- Networked assembly reuses the existing appliance and guest-command helpers,
  pauses QEMU for a disk checkpoint, and re-sparsifies the exported root.
- A new branch-scoped Woodpecker workflow builds/tests both native host
  architectures against one assembled guest bundle before publishing `latest`.
- Host memory admission gate prevents another 3.8 GB Podman OOM experiment.

The new assembly/release workflow has not yet passed runtime certification.
Nothing has been published to GHCR from this work at this entry.

## Release implementation update

The maintained private CI branch `codex/cross-arch-golden-volume` at
`89baac8` already provides seed assembly, clean-shutdown freezing, two cold
boots per native architecture, and gated multiarch publication. The release
worktree `/var/tmp/qemu-sun4v-release` extends that implementation on
`codex/softint-dualarch-release`. The competing draft orchestration was
discarded; its files were never published. AMD64 build execution moves to
Biggie because ec2cicd has only 1.5 GiB free on Docker's filesystem.

The local working guest subsequently cold-booted successfully with the
8 GiB Podman VM (`recovery-8gb-boot.log`). GCC extraction resumed there.
The private checkpoint volume and OCI archive remain separate from the
clean-source public release.
