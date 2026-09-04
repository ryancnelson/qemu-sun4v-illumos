# EXP-20260903-53 preserved tooling

These are the exact lab scripts used to inventory, mutate, reopen, and boot-test
the B134 hSIMD boot archive during EXP-20260903-53. They are evidence and a
reproducible starting point, not yet a portable command-line product: paths,
container names, disk targets, run numbers, and artifact names are deliberately
fixed to the recorded experiment.

The workflow was:

1. Create a reflink named `candidate-hsimd-tools.raw` from the accepted hSIMD
   carrier.
2. Start the Solaris 9/SPARC workbench with
   `run-solaris9-b134-toolbox-builder.sh`. Targets 0-4 are snapshot workbench
   disks, target 5 is the writable candidate, target 6 is a read-only payload,
   and target 7 is unused.
3. Run `solaris9-b134-toolbox-inventory.py` against the workbench serial
   socket.
4. Run `solaris9-b134-toolbox-inject.py`; it mounts the outer UFS filesystem,
   attaches and mounts the inner UFS boot archive, installs the tools and their
   exact Solaris 9 runtime, executes chroot canaries, cleanly unmounts both
   layers, and checks both UFS filesystems.
5. Restart the workbench with target 5 read-only and run
   `solaris9-b134-toolbox-verify.py` for an independent reopen/compare pass.
6. Freeze the candidate by hash as
   `candidate-proven-hsimd-toolbox-v3-b134.raw`.
7. Launch the Niagara test with `niagara-b134-toolbox-qemu.sh` and execute the
   in-guest acceptance commands with `niagara-b134-toolbox-test.py`.

`/usr/bin/hexdump` in this experiment is intentionally a small compatibility
wrapper around `od -Ax -tx1c`; Solaris 9 did not provide a native `hexdump` in
the inspected paths. `hostname` is the Solaris 9 script with only its shebang
adapted from `/usr/bin/sh` to B134's `/sbin/sh`.

The authoritative narrative, hashes, commands, failures, and acceptance gates
are in `../../EXPERIMENT-NOTEBOOK-2026-08-30.md`, entry EXP-20260903-53.
