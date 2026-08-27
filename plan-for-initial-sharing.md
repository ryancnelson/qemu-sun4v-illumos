# Plan for Initial Sharing

## Goal

Publish a portable OpenIndiana/illumos sun4v VM bundle that another person can
download, verify, and cold boot. Include enough host automation and documentation
for their coding agent to configure the channel, BBS, and PPP support services on
their workstation.

This is a release-preparation plan, not authorization to delete or alter the
current known-good artifacts.

## Current measured inventory

Measured on `niagara-playbox` on 2026-08-27:

| Component | Virtual/apparent size | Allocated size | Release disposition |
| --- | ---: | ---: | --- |
| Known-good root base, `extra-unit104-60g.img` | 60 GiB | about 8.8 GiB | Input to release image |
| Offline-edit root, `root-offline-edit.raw` | 60 GiB | about 14.7 GiB | Do not ship as a duplicate |
| Installer, unit 103 | 2.60 GiB | 2.60 GiB | Ship only if cold boot still requires it |
| Carrier, unit 100 | 1 GiB | almost entirely sparse | Generate or ship as a tiny sparse artifact |
| Channel mailbox, unit 101 | 32 MiB | about 3.1 MiB in the valid template | Generate per run in host tmpfs; temporarily ship the template until generation is proven |
| Known-good qcow2 state | 72 MiB | about 72 MiB | Input to flattening, not a second root disk |
| Current trial overlay | approximately 98 MiB and growing | approximately 98 MiB | Evidence/run state; do not ship |
| AArch64 QEMU and firmware | approximately 38 MiB | approximately 38 MiB | Ship per architecture or build reproducibly |

The current run places its unit-101 channel image under
`/dev/shm/niagara/RUN_ID/channel-unit101.img`; `/dev/shm` is tmpfs. Preserve that
backing design in the shared launcher, but do not mistake RAM backing for valid
disk initialization.

### Unit-101 initialization gap found on 2026-08-27

The debug trial's live tmpfs file was measured at exactly 33,554,432 bytes with
zero allocated blocks. Its first sector was all zero, its hash differed from the
accepted template, and `tools/vtoc.py verify` failed with `bad magic` and invalid
geometry. The persistent template passed VTOC validation and contains nonzero
label and initialization data.

Therefore the current trial proves only that QEMU can use a RAM-backed file. It
does **not** prove that an empty, truncated file is a usable channel disk. Do not
credit this trial with channel, BBS, or PPP acceptance until a correctly seeded
tmpfs unit 101 passes the guest echo gate.

The desired end state remains fully deterministic generation from repository
code. Until that generator is implemented and accepted, the initial bundle must
include the valid sparse unit-101 template and copy it into tmpfs before launch.
The template is a bootstrap input, never the live writable mailbox.

## Proposed initial bundle

Ship the minimum independently bootable set:

1. One cleaned, flattened root image with no dependency on paths outside the
   bundle.
2. The installer disk only if a clean-machine cold-boot test proves it remains
   necessary.
3. A deterministic unit-100 carrier image or a script that creates it.
4. A script that creates and initializes unit 101 in `/dev/shm` for every run.
   Initially it may copy the bundled, hash-pinned sparse template. Replace that
   template with deterministic VTOC/slice/mailbox generation only after the
   generated result passes the same structural and live guest gates.
5. QEMU and firmware downloads for each supported host architecture, or pinned
   and reproducible build instructions.
6. Host-side BBS, channel, ISP-readiness, and PPP service definitions.
7. An agent-readable host setup runbook, a human quick-start, and an uninstall
   procedure.
8. A manifest containing hashes, exact QEMU and firmware identities, disk
   topology, required host capabilities, and the tested launch command.
9. One-command preflight, launch, health-check, and evidence-collection tools.

Do not distribute both the 60 GiB offline-edit raw image and the known-good root
chain. Do not distribute a run-local writable overlay as the canonical release.

### Unit-103/HSFS dependency

The installed system boots unit 104 via `disk@4:a` and has proven a genuine ZFS
root at `rpool/ROOT/openindiana`. That makes removal of the 2.60 GiB unit-103
HSFS installer a realistic release goal. It is not yet a proven fact.

Every accepted workstation launch so far has still attached unit 103 read-only.
The existing launch contract also expects unit-103 slice 0 at `/.cdrom` and the
live-media `/usr` and `/mnt/misc` mounts. No clean cold-boot acceptance run has
yet omitted the disk. Therefore unit 103 remains a required input under the
current evidence, even if those dependencies are now obsolete residue from the
installation environment.

After the current debug trial halts, test this on a disposable root clone:

1. Inventory `mount`, `df`, `zfs list`, `svcs -xv`, and the manifests for
   `filesystem/root:media`, `filesystem/usr`, and related live-media services.
2. Prove that all files required from the old HSFS `/usr` and `/mnt/misc` exist
   in the installed ZFS datasets.
3. Disable only the obsolete live-media services in the disposable clone and
   rebuild the boot archive on unit 104.
4. Cold boot with unit 103 entirely absent from the QEMU command line.
5. Require unattended multi-user login, local `/usr`, healthy required SMF
   services, channel echo, BBS health, PPP, external ping, clean shutdown, and a
   second cold boot.

If both boots pass, remove unit 103 from the release topology and save roughly
2.60 GiB before compression. If either fails, retain the read-only disk in the
initial bundle and record the exact remaining dependency rather than restoring
the broad live-media contract blindly.

## Guest cleanup before image construction

Perform cleanup in a disposable clone, never in the only known-good copy.

- Remove package download caches while preserving the installed package
  database.
- Remove `/tmp`, `/var/tmp`, abandoned installation staging, compiler archives,
  and source/build trees that are not intentional bundle content.
- Remove rotated logs and truncate oversized active logs deliberately.
- Remove core files, crash dumps, and obsolete `savecore` output.
- Remove credentials, tokens, user shell history, and other private material.
- Arrange first-boot regeneration of SSH host keys, host identity, DHCP leases,
  and other machine-unique state.
- Remove unnecessary ZFS snapshots, clones, and boot environments. Snapshots can
  retain deleted blocks and defeat later space reclamation.
- Clear swap and dump contents, or recreate/reinitialize them on first boot where
  practical.
- Keep tools intentionally promised by the image, including the compiler, out of
  the cleanup list and verify them explicitly in acceptance testing.

Record before-and-after `zpool list`, `zfs list -o space`, boot-environment,
package, dump, and filesystem inventories in the release evidence.

## Image compaction strategy

Deleting files inside ZFS does not by itself make an existing raw image compact,
and naively writing zeros is not sufficient when snapshots retain old blocks.
The release process must avoid publishing recoverable private data from free
space as well as avoid wasting download bytes.

Preferred approach:

1. Start from a reflink or otherwise independent clone of the accepted state.
2. Clean the guest and remove unwanted snapshots.
3. Shut down the guest cleanly.
4. Construct a fresh, smaller bootable pool and replicate only the live ZFS
   datasets into it.
5. Preserve and verify the required sun4v partitioning, boot blocks, boot
   archive, dump configuration, and unit number.
6. Convert the completed standalone disk to qcow2 with zero detection and qcow2
   compression.
7. Compress the bundle with `zstd` and publish both compressed and uncompressed
   hashes.

A 20--30 GiB growable virtual root disk is a reasonable initial target if the
live dataset inventory confirms that size has adequate headroom. A smaller fresh
pool is preferable to attempting to sanitize every unused block in the 60 GiB
experimental disk.

Fallback approach, if fresh-pool replication cannot yet preserve bootability:

1. Clean a disposable clone of the existing root chain.
2. Remove snapshots that retain discarded data.
3. Zero free space using a ZFS-aware, bounded procedure that retains operating
   headroom and is tested on a throwaway clone first.
4. Shut down cleanly and flatten the complete backing chain into a standalone
   compressed qcow2 image.
5. Prove that no backing path remains and cold boot the result on a clean host.

Never run a free-space-filling operation against the sole accepted image. Do not
fill a ZFS pool to 100 percent.

## Host support package

The recipient's workstation setup should be declarative and safe for an agent to
execute. It should:

- Check host architecture, virtualization/emulation dependencies, available RAM,
  free disk space, tmpfs capacity, and required privileges.
- Install the channel bridge, BBS service, ISP readiness supervisor, and PPP
  service with pinned configuration.
- Create the run-scoped unit-101 mailbox in tmpfs and verify its exact size,
  layout, and mailbox offset before QEMU starts.
- Fail closed if unit 101 is merely the right length but lacks the expected VTOC,
  slices, initialization data, or clean mailbox state.
- Make `BBS HEALTH` and ISP preparation explicit launch gates.
- Start PPP only after the guest asks the BBS to prepare the imaginary ISP.
- Verify the intended end-user path: start PPP in the guest, then successfully
  ping an external address.
- Use run-scoped sockets, logs, PID files, and cleanup; refuse paths or processes
  belonging to another run.
- Expose restricted QMP and gdbstub debugging endpoints before boot. Ordinary
  tooling must not expose QMP/HMP `quit`, reset, or powerdown operations.
- Provide an idempotent uninstall that removes services and ephemeral state but
  never deletes downloaded VM disks without a separate explicit command.

The runbook should tell another coding agent exactly which commands are
read-only, which modify the host, and which require privilege. It must not embed
credentials or assume the original playbox paths.

## Release acceptance gates

Test the final archive after downloading or copying it into a clean directory on
a host with none of the original backing files.

- Every artifact matches the published manifest.
- The root qcow2 is standalone and reports no external backing file.
- Preflight rejects wrong QEMU, firmware, topology, disk hashes, mailbox paths,
  or insufficient resources.
- Unit 101 is created in tmpfs and channel echo passes.
- BBS health passes and the guest can request ISP readiness.
- The guest reaches unattended multi-user login.
- ZFS root boot and boot-archive loading succeed.
- PPP starts on request and `ping 8.8.8.8` succeeds.
- A clean shutdown and second cold boot both succeed.
- QMP/gdbstub evidence capture works without exposing destructive monitor
  commands.
- No secrets, unique host identity, private logs, crash dumps, or recoverable
  deleted project data are found in the release image.
- Actual archive size, unpacked allocated size, boot time, and minimum host RAM
  are recorded.

## Execution plan after the current trial

Do not modify, stop, snapshot, or repurpose the currently running debug trial for
release construction. Begin this work only after that trial has saved its
required evidence and halted cleanly.

1. Confirm QEMU has exited and record the trial's final run state, hashes, logs,
   and disk chain without mutating them.
2. Preserve the accepted root state and current trial as read-only evidence;
   create independent reflink/copy-on-write working copies under
   `/mnt/disk-images`.
3. Fix the unit-101 launch gate first:
   - copy the accepted sparse template into a run-scoped tmpfs path;
   - verify exact size, template hash before use, VTOC, slice layout, mailbox
     offsets, and clean sequencing state;
   - boot a disposable VM and require channel echo before BBS or PPP;
   - implement a deterministic generator and compare its structural behavior
     against the accepted template;
   - stop shipping the template only after generated-disk cold boots and live
     channel tests pass.
4. Inventory the stopped guest's ZFS datasets, snapshots, boot environments,
   packages, logs, dump configuration, identities, and large files from a
   disposable clone.
5. Decide and record the initial image contents, including whether GCC belongs
   in the base image and whether unit 103 is required after flattening.
6. Clean only the disposable clone and capture before/after evidence.
7. Attempt the preferred smaller fresh-pool replication. If boot preservation is
   not yet proven, use the bounded flatten-and-compact fallback instead.
8. Assemble the host support package and agent-readable setup instructions.
9. Build a candidate archive entirely under `/mnt/disk-images`, where the
   dedicated 70 GiB XFS filesystem had about 41 GiB free at measurement time.
10. Test download/extraction semantics and two cold boots from a clean directory
    with no access to the original backing files.
11. Publish only after every release acceptance gate passes and all hashes and
    measured sizes have been recorded.

## Playbox housekeeping, separate from the bundle

At measurement time, playbox's root filesystem was 96 percent full with about
823 MiB free, while `/mnt/disk-images` was healthy at 42 percent used with about
41 GiB free. Large root-filesystem consumers included an approximately 1.1 GiB
active syslog, old ISOs, NFS staging artifacts, Snap caches, and downloads.

Clean the host root filesystem soon, but treat that as a separate reviewed task.
It must not be conflated with pruning the guest or selecting release artifacts.

## Decisions to resolve

1. Does a clean cold boot require unit 103 after the root image is flattened?
2. Which host architectures receive prebuilt QEMU binaries initially?
3. Can a newly constructed smaller ZFS pool preserve the current boot path and
   boot archive without regression?
4. Which compiler and bootstrap tools are promises of the initial image rather
   than optional NFS content?
5. What first-boot identity regeneration is safe on this illumos build?
6. What license and redistribution notices are required for OpenIndiana, QEMU,
   firmware, and bundled packages?
