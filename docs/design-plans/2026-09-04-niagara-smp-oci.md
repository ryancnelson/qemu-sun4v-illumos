# Niagara SMP OCI design

## Goal

Build the self-contained `oi-basecamp` Docker image with the QEMU changes that
proved Niagara SMP, boot it automatically with two vCPUs and no KMDB, and make
Woodpecker reject any image that does not expose exactly CPUs 0 and 1 online.

## Constraints

- Keep QEMU base commit `049affb20df67162cf58deeaf74d5ad4b83cbdc3`.
- Apply the source patches preserved by the successful ec2trib run.
- Use the two-CPU guest and hypervisor machine descriptions from Murayama
  distribution commit `3eb7ce6cbda552ff2c03afc5fbb8a2bfede2cdd0`.
- Preserve automatic boot of unit 105 with `boot-file = "-v"`.
- Do not pass `-k`, load KMDB, or accept a console containing KMDB markers.
- Keep the existing self-contained asset volume and network tests.

## Approaches considered

### Apply preserved patches during the image build

Copy the three audited QEMU patches into the appliance build context, verify
their checksums, and apply them after extracting the pinned source archive.
Keep the two-CPU MD input and HV binary beside the appliance firmware builder.
This preserves the exact base commit and makes every delta visible in this
repository.

### Pin a new QEMU source commit

Commit the fixes in a separate QEMU repository and replace the Docker source
archive.  This produces a clean source identity but adds a publication and
archive-generation dependency before the package can be tested.

### Copy the successful ec2trib QEMU binary

Package the existing binary directly.  This would reproduce the experiment
quickly but would not provide a clean container build or an auditable compiler
path.

The image-build patch approach is selected.  It uses the source and firmware
identities already captured in commit `b6e0a19` and can run in the current
Woodpecker build environment.

## Package changes

The base Dockerfile verifies and applies patches 0004, 0005, and 0006 before
building `qemu-system-sparc64`.  The runtime entrypoint validates a fixed guest
CPU count of two, passes `-smp 2`, and records the value in the runtime
manifest.

The release firmware builder verifies the two-CPU guest MD source by hash,
regenerates its baseline binary, applies the existing disk-5 auto-boot and
`-v` policy, and installs the pinned two-CPU HV binary.  The generated guest MD
and copied HV are checked against declared hashes.

## CI contract

After the existing login smoke test, a new appliance command runs `psrinfo`
inside the guest and fails unless exactly processor IDs 0 and 1 report
`on-line`.  It also records `psrinfo -v` and `mpstat` output.  The host side
rejects `Loading kmdb`, `kernel debugger was booted`, a KMDB prompt, or a panic
in the console log.

Woodpecker stages the patch and SMP firmware inputs, builds the self-contained
image, runs the two-CPU/no-KMDB gate, and preserves its transcript with the
existing evidence bundle.

## Acceptance criteria

- The Docker build applies all three recorded QEMU patches to the pinned base.
- Runtime metadata reports `smp_cpus=2` and QEMU is launched with `-smp 2`.
- Firmware metadata reports the expected two-CPU guest MD and HV hashes.
- OpenBoot automatically boots disk 5 with `-v` and no `-k`.
- The guest command gate proves exactly CPUs 0 and 1 are online.
- The console contains no KMDB or panic signature.
- The existing login, interactive-console, storage, and network checks pass.

