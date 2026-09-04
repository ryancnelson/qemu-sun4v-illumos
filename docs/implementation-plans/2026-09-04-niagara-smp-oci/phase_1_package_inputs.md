# Phase 1: package source and firmware inputs

## Changes

- Add the three QEMU patch files to the appliance build context with checksums.
- Add the pinned two-CPU guest MD source and HV binary with provenance.
- Update the Dockerfile and firmware preparation script to verify and consume
  those inputs.
- Add static policy tests for the pinned identities and patch application.

## Verification

Run the appliance policy tests, shell syntax checks, Python compilation, and
the repository unit suite.  The remote Docker build must complete from the
pinned QEMU archive without using the ec2trib working tree.

