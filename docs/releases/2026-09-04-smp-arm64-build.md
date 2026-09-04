# Native ARM SMP preview build

The ARM extension runs through Biggie Woodpecker on branch
`codex/niagara-smp-arm64`, with native compilation and guest tests on
`root@niagara-playbox` (`100.112.174.2`). Its workflow is
`.woodpecker/niagara-smp-arm64.yml`; implementation is
`appliances/sparc64-qemu-illumos-docker-guest/scripts/ci-smp-arm64.sh`.

Initial run: [71](http://biggie.lynx-eagle.ts.net:8110/repos/2/pipeline/71),
commit `cd92c6249feb2339ed78058b23972ff98cb80d45`. Staging passed; preparation
stopped at the 14 GiB free-space gate. Build, boot, CPU verification and
publication were skipped. Scoped cleanup passed. The published preview remains
amd64-only.

## Inputs and isolation

The guest bundle is reused from Playbox's verified cache, SHA-256
`70c406af6b8780a31eab865dffcbac5863d4efaa1fd3261c529e8afc7d0d7384`.
Firmware is copied without executing a guest from the already tested amd64
image on ec2cicd:
`ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g@sha256:343d2a755d03352645d0c3ea63b3f687468a8390d2710e941b34feafac6663bc`.
The image's firmware checksum manifest is copied and checked on Playbox.
The pinned QEMU archive is verified against `sources/SHA256SUMS`; patches
0004, 0005 and 0006 are applied by the existing Dockerfile. Compilation uses
two jobs to limit memory consumption on the 6 GiB builder.

Every run has a distinct directory, image tags, container and volume:

```text
/mnt/disk-images/woodpecker/niagara-smp-arm64-<pipeline>/
sparc64-qemu-illumos-guest:niagara-smp-arm64-<pipeline>
sparc64-qemu-openindiana-20g:niagara-smp-arm64-<pipeline>
niagara-smp-arm64-<pipeline>
niagara-smp-arm64-<pipeline>-state
```

The ongoing `solaris9-playbox-timing` container and all other experiment
containers/volumes remain outside this run's cleanup scope.

## Capacity preparation

Initial inventory: root filesystem 126 MiB free; XFS Docker filesystem 7.5 GiB
free. Historical complete bundles held repeated identical data. The preparation
phase compares each selected bundle byte-for-byte, checks that it has no open
users, creates a same-filesystem reflink, compares it again, then replaces the
old file. All paths and successful comparisons are logged in Woodpecker.
It does not delete partial archives, experiment disks, logs or Docker volumes.
`apt-get clean` removes regenerable package downloads from the root filesystem.

Run 71 preserved every selected bundle byte-for-byte, but XFS ended with only
10 GiB available (root: 522 MiB). Some old extents were already shared; summing
`du` sizes overstated the potential reclamation. A proposed build-context
hardlink explanation was disproved by a full filename/inode/link-count inventory.
Do not use that explanation as a diagnosis.

An unreferenced anonymous Docker volume occupies 11 GiB:
`e80fc11e82958cc5060281f9453e94909c70502c0aeb39c37756a7d9c89ccbd1`.
`docker ps -a --filter volume=<exact-name>` returned no containers. Its contents
have not been proved disposable and it has not been removed. Reclaiming that
volume requires Ryan's approval, or the builder needs additional capacity.

The exact conversion command sequence is in the script's `prepare` phase:

```sh
cmp --silent "$source" "$target"
# Proceed only after fuser returns exactly 1 (no users).
replacement=$(mktemp "${target}.reflink.XXXXXX")
cp --reflink=always --preserve=all "$source" "$replacement"
cmp --silent "$target" "$replacement"
mv -f -- "$replacement" "$target"
```

Capacity gates require 14 GiB available on XFS and 256 MiB on root before
starting compilation. Temporary build-driver files live in the run directory
on XFS. New source/bundle copies also use reflinks.

## Verification and publication

Build uses `REBUILD_RELEASE_FIRMWARE=0 REBUILD_GUEST_RELEASE=2` through the
existing self-contained assembly helper. Native ARM image metadata is checked
before starting a cold boot with a fresh named volume. Login and both CPU rows
must pass separately; the full console is retained. The CPU-row check also
catches a weakness in the earlier command list where a successful `mpstat`
could mask a failed preceding assertion.

Only after these gates may the existing Woodpecker `ghcr_token` secret flow
through stdin to a temporary Docker authentication directory. The ARM image
is pushed under a versioned preview tag. The exact pushed descriptor must
match the tested local Docker 29 descriptor. Publication then creates a
versioned multi-arch index and updates `smp-preview`, combining that ARM digest
with the immutable amd64 digest above. Anonymous verification requires exactly
linux/amd64 and linux/arm64 and their expected digests.

`latest` and the existing architecture release tags are unchanged. This does
not certify full networking: the earlier compound resolver assertion remains
unresolved and is an accepted preview caveat. Cleanup preserves console and
image metadata evidence before removing only this run's guest and volume.
