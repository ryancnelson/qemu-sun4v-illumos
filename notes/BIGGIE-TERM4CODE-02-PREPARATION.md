# Biggie OpenIndiana `term4code-02` preparation

## Bounded hypothesis

With the exact hSIMD already embedded in `ppp-injected-v2-20260825` held
constant and `/etc/system` containing the exact line
`set zfs:zfs_vdev_aggregation_limit=0x20000`, no hSIMD request will exceed
`0x20000` during dataset create, write, sync, or read.

This preparation must stop at `PRELAUNCH_READY`; Ryan signoff is required
before the trial boots.

## Mechanical pipeline

`tools/openindiana/prepare-term4code-02.py` consumes an explicit JSON config.
It validates the disposable builder identity, tmux/socket ownership, unique
run-local disk units, and the proven PCFS guest device before performing any
command.  Each stage has an argv vector, timeout, expected marker, and run-local
JSONL evidence.  It then requires:

- pinned boot-archive size/hash and unchanged in-archive hSIMD size/hash;
- media fallback V2, slice-zero-first discovery, and disabled DHCP branch;
- exact aggregation-limit readback from the archive reopened read-only;
- writable RAM-root and PPP/channel payload manifest gates;
- a new immutable installer release;
- exact unit101 mailbox size, VTOC, offsets, magic, and sequence evidence;
- exact 60 GiB unit104 VTOC, featureless `tink`, required properties, clean
  export, and detached loop evidence;
- one-vCPU QEMU argv with read-only unit103, writable units101/104, and Unix
  console/monitor sockets.

The enumerated terminal outcomes are:

- `PRELAUNCH_READY` (exit 0): every stage and final manifest passed;
- `BLOCKED_MISSING_BUILDER_TOPOLOGY` (exit 20): no reviewed donor unit/slice
  manifest was supplied;
- `PREPARATION_FAILED` (exit 1): identity, timeout, marker, command, manifest,
  or argv mismatch.  Evidence already captured is preserved.

## Current result

The pinned archive is
`ppp-injected-v2-20260825/boot_archive.ufs`, 192,595,968 bytes, SHA-256
`27b12613805505594cdbfcd2b276c413205070085554ce00505566a8fc6e9676`.
The authoritative hSIMD is the file inside that archive; substituting a newer
driver would invalidate the controlled A/B.

The prior Exabyt builder endpoint was unresolved.  The successful isolated
fallback was `oi-archive-builder-biggie-06`: OpenIndiana itself booted a
writable RAM root from a run-local unit103 clone, recovered `/.cdrom`, `/usr`,
and `/mnt/misc`, and mounted a labelled raw-slice wrapper at unit104 slice3.
Solaris read the `Zcmp` method as expanded text, applied media V2, and read back
the exact literal and unchanged hSIMD.  Failed disposable Tribblix donor
attempts 02--05 are preserved with their root-mount panic evidence.

The finalized boot archive is 192,595,968 bytes, SHA-256
`e547ed68b6656a54a4fdbdced97f73677f4bf0394320f083890fd7d3ceed65df`.
Immutable release `oi-bounded-v2-20260826` has unit103 SHA-256
`e034411aab8fe5118dfdda74806a4a126a6dfc8cd8e08077758d2e1d66d9643c`.
The complete real-evidence pipeline now returns `PRELAUNCH_READY`.
Existing protected Biggie VMs and published inputs were not modified.

Run-local preparation already completed before this blocker includes a fresh
unit101 clone with valid VTOC, slice 7 at byte 327680, `NIAG` magic, zero
sequence field, and source hash
`9cebbadd4f02a79b249f4aef4505f544d65c9432847c17f2f26cddb02838ec8c`.
Fresh unit104 is exactly 60 GiB with valid s0/s2 geometry; `tink` was ONLINE
with zero errors, all 39 feature properties disabled, ashift 9, recordsize 8K,
compression/atime off, sync always, then cleanly exported and detached.  The
60 GiB sparse file was not redundantly hashed.

Fast unit tests cover the typed blocker, duplicate-unit rejection, timeout
validation, media-V2 idempotence, and a mocked complete path ending at
`PRELAUNCH_READY`.
