# Phase 3: build and test in Woodpecker

## Changes

- Add the feature branch to the self-contained OCI workflow trigger.
- Extend static policy checks for the SMP build and no-KMDB gate.
- Verify and reuse the accepted guest-root release bundle while rebuilding the
  patched QEMU and two-strand firmware.
- Preserve the SMP transcript in the existing CI evidence directory.

## Verification

Push the feature branch to the GitHub repository watched by Woodpecker.  The
pipeline must build the image, boot `oi-basecamp`, prove both CPUs online with
no KMDB markers, and report the resulting local image ID and evidence path.
