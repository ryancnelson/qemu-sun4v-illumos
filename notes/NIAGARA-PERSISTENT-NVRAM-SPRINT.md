# Niagara persistent NVRAM sprint

## Objective

Give the Niagara machine a run-specific, writable, persistent 8 KiB `nvram1`
file so OpenBoot variables survive separate QEMU processes. Use the proven
sun4m M48TXX work on `ryancnelson/qemu:ss5-persistent-nvram` as the lifecycle
and validation precedent while adapting the mechanism to Niagara's directly
mapped `sun4v.nvram` RAM region.

## Current failure

Niagara initializes anonymous RAM at `NIAGARA_NVRAM_BASE`, then copies the
firmware-directory `nvram1` ROM blob into it with `add_rom_or_fail()`. OpenBoot
can modify the RAM during one process, but the bytes are discarded at exit and
the original blob is loaded again on the next launch. Consequently the proven
boot command remains manual:

```text
boot /virtual-devices@100/disk@4:a -k -v
```

## Safety and scope

- Preserve all accepted, candidate, recovery, and debug disk overlays.
- Develop in a dedicated QEMU branch/worktree and publish the exact commit.
- Use only disposable children of the productive candidate for boot tests.
- Use a run-specific copy of the canonical 8 KiB `nvram1`; never modify the
  firmware template in place.
- Retain QMP and gdbstub, expose no HMP endpoint, and capture the console before
  firmware starts.
- Do not combine this sprint with guest cleanup, GCC installation, HSFS removal,
  or candidate promotion.

## Implementation contract

1. Add an explicit Niagara machine property or equivalent command-line binding
   for a writable NVRAM filename.
2. Require an existing backing file to be exactly `NIAGARA_NVRAM_SIZE` (8192
   bytes), or create it deterministically from an explicitly named template.
3. Map/load that run-specific file so guest firmware writes persist to it. Do
   not reload `nvram1` over a persistent image after mapping.
4. Flush writes sufficiently for persistence across orderly QEMU termination.
5. Fail closed on missing/unwritable/wrong-sized files and report the exact
   path.
6. Preserve compatibility when no persistent filename is supplied unless an
   intentional machine-version decision says otherwise.

## Test stages

### A. Non-live tests

- Build `sparc64-softmmu` on the AArch64 playbox.
- Reject a wrong-sized NVRAM image.
- Verify an exact-size run copy can be opened writable without changing the
  canonical template.
- Confirm the expanded QEMU command names the run-specific NVRAM path.

### B. Controlled firmware canary

1. Launch with console capture enabled before firmware starts.
2. At `ok`, record `printenv` values and the NVRAM hash.
3. Set:

   ```text
   setenv boot-device /virtual-devices@100/disk@4:a
   setenv boot-file -k -v
   setenv auto-boot? true
   ```

4. Read the variables back in OpenBoot and record the changed file hash.
5. Stop at firmware or after a clean guest shutdown; terminate QEMU only when
   firmware is quiescent.

### C. Two-process cold-boot acceptance

- Process 1 starts with the run-specific image and reaches OpenIndiana without
  a typed boot command.
- Shut down cleanly to firmware and terminate the quiescent QEMU.
- Process 2 starts with the same NVRAM and a fresh writable disk child and again
  reaches OpenIndiana without console input.
- Both boots enumerate units 0, 1, 3, and 4; mount the intended ZFS root; retain
  `-k -v`; and preserve the operator's productive candidate lineage.

## Acceptance

PASS only when two separate QEMU processes auto-boot the explicit unit-104 ZFS
root, the three variables read back correctly, the run-specific NVRAM changes
while the canonical template hash does not, console evidence is complete, and
all image/NVRAM ancestry is recorded.

FAIL CLOSED on silent fallback to anonymous RAM, mutation of the canonical
template, missing console capture, manual `boot`, wrong disk enumeration, wrong
root, or any QEMU/NVRAM identity mismatch.

