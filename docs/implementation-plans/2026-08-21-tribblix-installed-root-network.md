# Tribblix installed-root and network bootstrap implementation plan

Design: `docs/design-plans/2026-08-21-tribblix-installed-root-network.md`.

## 1. Freeze the build manifest

- Record input image size, allocation, SHA-256, VTOC, root offset
  (`1421440 * 512`), and root length (`2793472 * 512`).
- Extract the exact 48 missing `base` package names from `base.pkgs`.
- Locate and hash every required `.zap`, `TRIBsys-lib-c-runtime`, the plain
  ENOTTY `hsimd`, channel binaries, and init/service files.
- Fail before mutation if any input is missing or ambiguous.

## 2. Implement the offline finalizer

- Add a repository script that accepts explicit input, output, staging, and
  mounted-root paths; it must refuse `/`, a mounted live QEMU disk, and an
  output identical to the input.
- Make a sparse/reflink disposable image and extract its UFS root extent.
- On the Solaris 10 donor, attach only that disposable root with `lofiadm` and
  mount it at a dedicated alternate root.
- Install the frozen package list with `pkgadd -R` and the audited admin file.
- Remove the live-media package with `pkgrm -R`, seed the installed SMF
  repository, patch the sun4v driver path, install channel startup, and run
  `bootadm update-archive -R`.
- Unmount, detach, run `fsck -F ufs -m`, and produce hashes and a file-level
  mutation manifest.

## 3. Prove the artifact before boot

- Read the root back independently and verify package registrations, overlay
  markers, absent live startup, repository hash, driver hash, channel service,
  `/etc/system`, and `/etc/vfstab`.
- Verify the VTOC, s7 bytes, HSFS prefix, and every byte outside the intended
  root/boot-archive changes.
- Copy only the accepted sparse image to playbox after checking free space.

## 4. Boot once and run the installed-root acceptance gates

- Shut down the current guest cleanly with `init 5`; never kill a mounted UFS
  guest.
- Boot the accepted image and run all ten gates in the design document.
- Take a checkpoint only after `lockfs`, guest sync, host vdisk flush, and
  exact-PID stop/continue handling.

## 5. Establish management and service channels

- Channel 0: PPP-over-channel, with a retrying guest supervisor.
- Channel 1: restore and verify the BBS with the known Minnie LLM endpoint.
- Channel 2: verify respawning login/getty.
- Channel 3: reserve for bulk/bootstrap transfers; do not multiplex unframed
  services on one channel.
- Verify a small HTTP fetch and an NFSv4 mount before transferring a full gate.

## 6. Retest and implement native Ethernet

- Retest loopback, `ipadm`, `ifconfig`, `dladm`, and network SMF milestones on
  the installed repository.
- If IP management works, implement the guest `libdlpi` raw-frame relay and
  Linux TAP relay described in `notes/ETHERNET-OVER-CHANNEL.md`.
- Prove ARP, ICMP, TCP, DNS, and NFS through the Ethernet path, then compare
  throughput and reliability with the service tunnels.

## 7. Review and history

- Run unit tests for BBS/session changes and relay framing.
- Review the finalizer for target validation, cleanup traps, and reproducible
  hashes.
- Commit only scoped files; preserve the unrelated README/GDB and `qemu-new`
  worktree changes.
- Update `CURRENT-STATE.md` and the persistent-UFS history with measured boot
  results, including failures.
