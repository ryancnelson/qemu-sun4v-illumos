# Self-contained 20 GiB OpenIndiana OCI appliance

Date: 2026-09-01

## Objective

Produce one OCI image that requires no host asset directory, bind mount, or
preexisting Docker volume. It must carry the pinned Niagara QEMU runtime and a
compressed, checksummed copy of every boot asset. A fresh container must
materialize the writable 20 GiB root sparsely, boot it as unit105, and reach
the OpenIndiana console login prompt.

## Design

- Keep the accepted raw root byte-for-byte unchanged inside the existing
  sparse zstd beta bundle.
- Store that compressed bundle in an OCI layer. Do not store a nominal 20 GiB
  raw file directly in an OCI layer because sparse-tar handling is not uniform
  across registries and runtimes.
- On first start, extract only the bundle's `assets/` subtree into a fresh
  anonymous Docker volume using GNU tar sparse support and zstd.
- Verify all five extracted assets against `assets.release.SHA256SUMS` before
  QEMU starts.
- Use the extracted root as writable unit105, recreate unit100 in runtime
  tmpfs, keep unit103 read-only, and copy firmware/NVRAM into container state.
- Treat the anonymous volume as disposable run state. Removing the container
  with its volume restores the immutable OCI seed for the next trial.

## Implementation steps

1. Capture Docker storage and filesystem free-space baselines on `ec2cicd`.
2. Add an embedded-bundle materialization mode to the existing entrypoint.
3. Add a self-contained Dockerfile and appliance commands for build, boot,
   smoke, inspection, and cleanup without host mounts.
4. Build the OCI image and record image ID, total size, unique size, and layer
   history.
5. Start it with no bind mounts and no preexisting volume. Verify the mount
   list, sparse root size/allocation, OpenBoot command, hsimd attach, ZFS root,
   login prompt, pool health, release accounts, and absence of `ryan`.
6. Export the OCI image, checksum it, remove the local tag, reload it from the
   export, and repeat the fresh-volume boot/login gate.
7. Preserve console, materialization, inventory, image, and archive evidence;
   remove disposable test containers and anonymous volumes.

## Acceptance gates

- Docker reports zero bind mounts for both trials.
- First-run extraction verifies all five release assets.
- The root is exactly 21474836480 bytes but remains sparse.
- Console shows `hsimd5`, `root on distpool/ROOT/openindiana fstype zfs`, and
  `oi-basecamp console login:` without a full ZFS device scan or panic.
- `distpool` is ONLINE with zero data errors; `jack` exists and `ryan` does
  not.
- The exported OCI archive reloads successfully and produces the same login
  result from a second new anonymous volume.
