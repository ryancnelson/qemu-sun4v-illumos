# ec2trib development, build, and test lifecycle

**Status:** proposed

**Date:** 2026-08-28

## Purpose

This document defines how work on the Niagara lab moves from an idea or bug
report to a recorded result. It covers QEMU development, OpenIndiana driver
development, VM image assembly, test execution, failure capture, and artifact
promotion on `ec2trib`.

The Git repository is the lab notebook and source of project history. The
`/tink` filesystem holds source checkouts, build products, VM images, active
machine state, run artifacts, caches, and large captures. Every consequential
artifact under `/tink` must have an identity and a manifest that connects it to
the repository.

## Current problem

The repository contains useful records under `notes/`, `captures/`, `docs/`,
and several top-level files. Their formats and scope vary. On `ec2trib`, build
and run directories have accumulated through manual work:

```text
/tink/builds/qemu-ryancnelson-github-fork
/tink/builds/qemu-sun4v-879fee-tribblix
/tink/disk-images/workstation-multiuser-raw-20260827T010500Z
/tink/runs/oi-basecamp-20260828T095555Z-37092
```

The current runner records QEMU and firmware hashes, backing images, sockets,
NVRAM state, timestamps, and exit status. It does not identify the repository
experiment, the image-assembly recipe, the source-tree dirty state, the test
being performed, or the conclusion recorded in Git. A directory can therefore
be valuable without being discoverable later.

## Considered recording models

### Manual Markdown only

An operator writes a note after each experiment and pastes paths and hashes
into it. This has low implementation cost. It depends on memory at the moment
when the failure is most distracting, and transcription errors are hard to
detect.

### Lab database

A service stores experiments, builds, images, runs, and test results. It can
provide strong queries and validation. It creates another stateful service,
requires backup and migration work, and makes a running service part of basic
lab operation.

### Git notebook with generated manifests

Markdown records intent, interpretation, and decisions. Commands generate
structured manifests for builds, images, and runs. Git stores the compact
records. `/tink` stores large artifacts. Stable identifiers and hashes connect
the two. This model is selected.

## Record types

The lifecycle uses four records. Each record has a stable ID and a UTC creation
time.

| Record | Purpose | Canonical location |
| --- | --- | --- |
| Experiment | Hypothesis, planned change, test matrix, and conclusion | Git Markdown |
| Build | Source revision, patch state, compiler, configuration, and binary hashes | `/tink` manifest plus Git copy |
| Image | Base image, ordered mutations, filesystem details, and resulting hashes | `/tink` manifest plus Git copy |
| Run | Exact build, firmware, images, command, logs, result, and captures | `/tink` manifest plus Git summary |

IDs use a readable prefix and UTC timestamp:

```text
experiment: EXP-20260828-hsimd-large-read
build:      BLD-20260828T181500Z-qemu-049affb2
image:      IMG-20260828T182200Z-oi-hsimd-test1
run:        RUN-20260828T183000Z-hsimd-zpool-import-01
```

An ID is immutable. Human-friendly labels such as `oi-basecamp-latest` may
point to an ID but never replace it in evidence.

## Repository layout

New lifecycle records live under one top-level notebook directory:

```text
lab-notebook/
  README.md
  experiments/
    EXP-20260828-hsimd-large-read.md
  manifests/
    builds/
      BLD-20260828T181500Z-qemu-049affb2.json
    images/
      IMG-20260828T182200Z-oi-hsimd-test1.json
    runs/
      RUN-20260828T183000Z-hsimd-zpool-import-01.json
  recipes/
    qemu/
    images/
    tests/
  templates/
    experiment.md
```

`lab-notebook/README.md` is the index. It lists active experiments, accepted
baselines, known failures, and the most recent validated run for each supported
guest. It links to detailed records instead of repeating them.

Existing notes remain in place during migration. Each relevant note gains an
experiment ID and an index link. Moving old files is optional and must preserve
Git history when performed.

## ec2trib layout

`/tink` is divided by artifact role:

```text
/tink/lab/
  sources/
    qemu/
  worktrees/
    qemu/<experiment-id>/
    illumos/<experiment-id>/
  builds/
    qemu/<build-id>/
    drivers/<build-id>/
  images/
    <image-id>/
  runs/
    <experiment-id>/<run-id>/
  state/
    <vm-id>/
  cache/
  promoted/
```

Source checkouts and worktrees are separate from build output. An iterative
compile reuses its build directory while its source revision, dirty patch hash,
toolchain, and configuration remain unchanged. A changed source identity or
configuration creates a new build ID.

`cache/` contains rebuildable downloads and compiler caches. Its contents may
be removed after a capacity check. `state/` contains mutable NVRAM and other VM
identity state. Run directories contain fresh overlays and immutable evidence
for one invocation.

The existing `/tink/builds`, `/tink/disk-images`, `/tink/runs`, and
`/tink/vm-state` trees remain untouched until they are inventoried. They are
treated as legacy paths during migration.

## Disk-storage model

Active ec2trib development uses ZFS zvols rather than growing qcow2 backing
chains. A promoted baseline is a named zvol snapshot. Each experiment or run
gets a writable ZFS clone of that snapshot, and QEMU consumes the clone as a
raw block device. Host-side repair uses the same native block device: expose
the applicable Sun-label slice, mount UFS or import ZFS as appropriate, make
the recorded change, unmount or export cleanly, and snapshot the result.

This removes qcow2 flattening from the normal edit/debug loop and gives every
test a cheap, named rollback point. A whole-disk zvol still contains its guest
disk label and slices; tooling must operate on the intended slice rather than
mounting or importing an unverified whole device.

Qcow2 remains the release and interchange format. A cold, accepted zvol
snapshot is exported to a standalone qcow2 image for UTM and other hosts that
do not share ec2trib's ZFS storage. The release bundle records the source zvol
snapshot, conversion command, qcow2 size and SHA-256, firmware identities,
UTM/QEMU configuration, and a cold-boot acceptance run. An optional raw image
or ZFS send stream may be retained for lab recovery, but neither is the public
appliance contract.

Existing known-good qcow2 chains are immutable migration inputs. They are
flattened into a candidate zvol, cold-booted, and compared with the original
baseline before promotion. The project never rebases or converts its only
known-good chain in place.

## Lifecycle

### Open an experiment

Create the experiment Markdown file before changing code or images. Record:

- the symptom or desired behavior;
- the affected layer or competing layers;
- a falsifiable hypothesis;
- the observation that would support or falsify it;
- the starting build and image IDs;
- the planned commands or test recipe;
- safety constraints and rollback state.

The initial status is `planned`. Valid statuses are `planned`, `active`,
`blocked`, `accepted`, and `rejected`.

### Prepare source

Create or select a worktree named for the experiment. Record these values
before the first build:

- repository URL and remote names;
- branch and full commit ID;
- submodule revisions;
- tracked diff hash;
- untracked file list;
- toolchain identity;
- relevant host package versions.

A dirty tree is allowed. Its diff must be captured in the build manifest. A
build described only as "today's QEMU" is invalid.

### Build

The build command consumes a versioned recipe from
`lab-notebook/recipes/`. The recipe defines configure flags, environment
allowlists, expected output paths, and required smoke checks.

The build manifest records:

- build ID and experiment ID;
- source identity and dirty-state hashes;
- recipe path and Git commit;
- host identity and operating-system version;
- compiler, linker, Meson, Ninja, and relevant library versions;
- configure and build commands as argument arrays;
- start time, finish time, and exit status;
- output binary path, size, file type, and SHA-256;
- smoke-test result and log paths.

A build becomes `usable` after its required smoke checks pass. A failed build
keeps its manifest and logs when the failure contributes evidence. Routine
syntax mistakes may be marked `discardable`.

### Assemble an image

Image assembly starts with a named, read-only base. Each mutation is a command
or script committed in the repository. Manual guest changes must be converted
into a recipe before the image can become a baseline.

The image manifest records:

- image ID and experiment ID;
- parent image IDs and hashes;
- container format and virtual size;
- partition, slice, UFS, ZFS, and boot-archive facts as applicable;
- ordered mutation recipe and exit status;
- embedded driver or package versions;
- final file hashes;
- ZFS dataset and snapshot names on the host;
- verification commands and results.

An image may be `scratch`, `candidate`, `baseline`, or `retired`. Promotion to
`baseline` requires a cold boot and the acceptance recipe named in its
manifest.

### Run a test

The runner requires an experiment ID, build ID, image ID, and test recipe. It
creates the run directory and initial manifest before starting QEMU. The
current timestamp-and-PID name remains useful as a display label; the run ID is
the durable identity.

The run manifest records the current fields plus:

- experiment, build, image, firmware, and recipe IDs;
- repository commit containing the runner;
- QEMU source and binary identities;
- complete argument array;
- backing-chain details and hashes;
- host resource limits;
- expected result and timeout;
- console, QMP, debugger, trace, and lifecycle endpoints;
- QEMU PID and start time;
- finish time, exit status, terminating signal, and core path;
- test result and evidence files;
- hashes for retained logs and captures.

Test results use `PASS`, `FAIL`, `INCONCLUSIVE`, or `NOT_RUN`. `PASS` requires
the assertion named by the recipe. Reaching a prompt is evidence only when the
recipe defines that prompt as its assertion.

### Analyze a failure

Preserve the run before starting another investigation. Capture the smallest
set of evidence that allows the failure to be classified:

- final console and QEMU logs;
- manifest and exact command;
- QMP status when available;
- core-file path, size, and hash;
- debugger or host trace output;
- writable-overlay identity;
- NVRAM before and after hashes.

The experiment note separates observations from conclusions. Each conclusion
links to a run ID and evidence file. Competing explanations remain listed until
a discriminating test resolves them.

The hsimd panic on 2026-08-28 is an example of one run producing two findings:
the guest driver asserted on a large disk read, then QEMU aborted in the
Niagara reset path. Those findings require separate bug records even though
they share a run.

### Close or continue

Update the experiment note after each meaningful run. Record the result,
interpretation, next test, and any superseded assumptions. Commit the note and
compact manifests before beginning unrelated work.

An accepted experiment names the build and image promoted as the new baseline.
A rejected experiment records why the change was rejected. A blocked
experiment states the missing dependency or decision.

## Artifact promotion and retention

Ordinary builds, images, and runs remain on `/tink`. ZFS snapshots provide
short-term rollback for mutable datasets. Promotion copies selected artifacts
under `/tink/lab/promoted/` and records their hashes and source IDs.

Promotion is appropriate for:

- a baseline image;
- a QEMU binary used for a published result;
- an irreplaceable installer or firmware input;
- a failure core needed for active debugging;
- evidence referenced by a public project note.

The manifest must identify any second durable copy, such as S3 or a GitHub
release. Git stores small logs and derived reports when they aid review. Large
disk images, cores, and raw traces remain outside Git.

No automated cleanup is enabled until retention periods and durable storage
are configured. Cleanup must read manifests, refuse to remove promoted
artifacts, and print the affected experiment and run IDs before deletion.

## Commands and automation

A future `labctl` command should provide the supported entry points:

```text
labctl experiment new <slug>
labctl build qemu --experiment <id> --recipe <name>
labctl image assemble --experiment <id> --recipe <name>
labctl run --experiment <id> --build <id> --image <id> --test <name>
labctl record <run-id>
labctl promote <artifact-id>
labctl inventory
labctl verify
```

The first implementation can use shell scripts. Manifests use a versioned JSON
schema. Commands write temporary manifests and rename them into place only
after required fields are present. Human-authored interpretation stays in
Markdown.

`labctl verify` checks:

- manifest schema and required fields;
- referenced files and SHA-256 values;
- links between experiments, builds, images, and runs;
- uniqueness of IDs;
- repository references to missing `/tink` artifacts;
- promoted artifacts without durable-copy records;
- active artifacts without an experiment record.

CI validates the notebook and checked-in manifests without requiring access to
ec2trib. Host-side verification adds file existence and hash checks.

## Migration

Migration begins with an inventory and performs no deletion or renaming.

1. Record the existing QEMU checkouts, binaries, firmware, disk images, VM
   state, runs, cores, and ZFS snapshots.
2. Assign IDs to the currently runnable QEMU build, the OpenIndiana base image,
   and the persistent `oi-basecamp` machine state.
3. Backfill manifests for the three `oi-basecamp` runs from their existing
   commands, logs, and hashes.
4. Create an experiment record for the 2026-08-28 hsimd large-read panic and
   QEMU reset abort.
5. Update `run-sun4v.sh` to require lifecycle IDs and emit the expanded run
   manifest.
6. Add the notebook index and manifest validator.
7. Direct new work into `/tink/lab`. Keep legacy paths available through
   explicit manifest references until their dependents are retired.

The migration report assigns each legacy artifact a provenance confidence of
`verified`, `partial`, or `unknown`. Missing history remains unknown rather
than being reconstructed from guesses.

## Acceptance criteria

The lifecycle is operational when:

- a new experiment can create a QEMU build, image, and run without manually
  choosing artifact directories;
- every run identifies its experiment, source, build, image, firmware, command,
  and test assertion;
- a failure leaves enough information to reproduce or classify it after the VM
  stops;
- the notebook index identifies the accepted QEMU and image baselines;
- `labctl verify` detects missing records, broken links, and changed artifacts;
- an operator can determine why any retained `/tink/lab` directory exists by
  reading its manifest.
