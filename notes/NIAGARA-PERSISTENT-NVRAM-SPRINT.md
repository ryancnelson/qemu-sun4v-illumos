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

## Sprint result -- 2026-08-27

Status: **BLOCKED AT THE FIRMWARE/LDOM PROVIDER BOUNDARY; DO NOT CLAIM PASS.**

The persistence defect is filed as
[ryancnelson/qemu#1](https://github.com/ryancnelson/qemu/issues/1).  A separate,
proven boot-selection workaround leaves NVRAM untouched and redirects the
existing `vdisk` machine-description alias to the installed `disk@4`; see
`notes/NIAGARA-VDISK-ALIAS-WORKAROUND.md`.  Plain `boot` is proven.  Automatic
boot remains unproven and disabled.

Completed:

- QEMU branch `ryancnelson/qemu:niagara-persistent-nvram` contains
  `89491443f3`, adding the explicit `-M niagara,nvram-file=PATH` property,
  exact-size/read-write validation, MAP_SHARED file backing, and anonymous-RAM
  compatibility fallback.
- Commit `b0c85dc7f8` adds the already-proven SPARC large-TTE range flush so the
  NVRAM build does not regress the productive storage runtime.
- AArch64 build SHA-256
  `8bca2d3fcf0e4c986a3af7b7826fdd3780649073cecac7e70082c64cfba2e4a2`
  completed on playbox.
- Non-live gates rejected an 8,191-byte image and a mode-0444 image, and
  accepted an exact writable 8,192-byte image without mutating it.
- Firmware canary enumerated units 0, 1, 3, and 4 and reached `ok` with console
  capture established before firmware execution.

Falsifying evidence:

- OpenBoot accepted in-process `setenv` values for `boot-device`, `boot-file`,
  and `auto-boot?`, but printed `Unable to update LDOM Variable`.
- The run-specific MAP_SHARED image remained byte-identical to the canonical
  input after `setenv` and after `nvstore`.
- QMP `pmemsave` of exactly 8,192 bytes at physical `0x1f11000000` was also
  byte-identical to the canonical input. OpenBoot is therefore not writing
  these variables to the mapped NVRAM region in this configuration.
- Appending or rebuilding diagnostic token records did not change fresh
  OpenBoot `printenv` values. Those experimental outputs are rejected and must
  not enter any boot or release lineage. The checked-in diagnostic tool was
  restored unchanged.

Conclusion:

The file-backed QEMU plumbing is necessary but not sufficient. This firmware
routes variable updates through an LDOM Variable Updates domain-service
provider that the current machine does not supply. The next implementation
step is to recover/specify and implement that provider protocol, or run the
actual OpenBoot encoder in an environment with a working provider and validate
the resulting image in fresh QEMU. Do not manufacture production bytes from
the partial token decoder.

All canary QEMUs were stopped at firmware. Productive, recovery, and debug root
overlays were not used as writable canary parents and remain preserved.
