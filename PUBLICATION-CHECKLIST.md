# Public GitHub checklist


Status on 2026-08-24: publication uses a clean, squashed source snapshot at
<https://github.com/ryancnelson/qemu-sun4v-illumos>.  The private Gitea lab
history is deliberately not mirrored wholesale.

## Already addressed in the working tree

- The front page now describes the OpenIndiana result rather than the older
  Solaris-only milestone.
- Verified results and unfinished work are separated explicitly.
- Murayama's QEMU/OpenBoot/hypervisor work is credited and pinned.
- The etherstub/DLPI/channel-2 proposal is surfaced as a direct collaboration
  topic.
- New OpenIndiana build helpers and the TLB experiment have publishable paths
  outside ignored working directories.
- Generated VM images, ISO files, profiler data, and `work/` are ignored.
- Third-party provenance and redistribution risks are inventoried.

## Gates before public publication

- [x] Ryan selected CDDL 1.0 for original project code and documentation;
  third-party files retain their existing licenses.
- [x] Create a clean, squashed publication branch or a new repository; do not
  mirror the existing 205-commit lab history unchanged.
- [x] Omit captured `hsimd`, recovered guest executables, and the redundant
  `openindiana-live-save.tar`, or bundle exact corresponding source and license
  material for anything intentionally distributed.
- [x] Omit full console transcripts containing copied guest source; retain
  bounded excerpts and hashes where they prove the same claim.
- [x] Give the public repository the correctly spelled `niagara` name.
- [x] Run the lightweight syntax, unit, patch, link, and credential checks on
  the exact publication snapshot.
- [ ] Ask Murayama to review the technical claims before promoting the project
  beyond the initial collaboration audience.

## Recommended first publication shape

Use a single squashed source snapshot containing the top-level stories and
state documents, `docs/`, `md/`, `notes/`, `patches/`, `tests/`, and `tools/`.
Keep compact textual evidence and manifests under `captures/`, but exclude
third-party executables, redundant tar archives, raw VM images, ISOs, and perf
data.  Preserve the existing Gitea repository as the private laboratory
history.

A descriptive repository name such as `qemu-sun4v-illumos` avoids the current
`niagra` typo and makes the collaboration target clear.
