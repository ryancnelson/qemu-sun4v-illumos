# Phase 2: enforce the runtime SMP contract

## Changes

- Make the container entrypoint fail closed unless the configured guest CPU
  count is two.
- Launch QEMU with two vCPUs and record the count in the runtime manifest.
- Add an appliance command that proves CPUs 0 and 1 online and records activity.
- Reject KMDB and panic signatures in the console log.

## Verification

Run static unit tests that cover the entrypoint arguments, manifest, guest
command, and forbidden console signatures.  Re-run all repository unit tests.

