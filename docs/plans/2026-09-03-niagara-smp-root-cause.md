# Niagara SMP Root-Cause Investigation Plan

> **For Claude:** Use `${SUPERPOWERS_SKILLS_ROOT}/skills/collaboration/executing-plans/SKILL.md` to implement this plan task-by-task.

**Goal:** Determine whether Murayama's Niagara stack brings a second CPU fully online in illumos, identify the first failing layer if it does not, and preserve a minimal reproducible two-CPU test.

**Architecture:** Run matched one-CPU and two-CPU boots on `ec2trib` using the same QEMU, OpenBoot, hypervisor, NVRAM seed, and installed OpenIndiana disk lineage. Change only the QEMU CPU count and the generated guest/hypervisor machine descriptions. Observe the path at five gates: QEMU CPU creation, guest-MD enumeration, `hv_cpu_start`, `slave_startup`, and final scheduler-visible online state.

**Tech Stack:** Murayama QEMU 10.2 sun4v fork, OpenSPARC T1 OpenBoot/hypervisor/MD, OpenIndiana illumos SPARC, KMDB, guest DTrace/MDB, Tribblix host DTrace, QMP, ZFS/qcow2 disposable clones.

---

## Established facts

- Murayama's distribution launcher defaults to two CPUs, passes that count to both MD generation (`NCPUS`) and QEMU (`-smp`), and documents support for 1--8 processors.
- The checked-in upstream `md.bin` and `hv.bin` contain two CPU/vCPU nodes.
- The `ec2trib` firmware set at `/tink/firmware-term4code-02-proven` was generated with one guest CPU. Its QEMU launcher's historical `-smp 4` therefore did not constitute a coherent SMP test.
- illumos obtains `boot_ncpus` by scanning forward `cpu` nodes from the guest MD root in `cpu_setup_common()`.
- illumos `start_other_cpus()` prepares every described non-boot CPU, then calls `start_cpu()`.
- On sun4v, `promif_start_cpu()` creates a landing pad and calls hypervisor service `HV_CPU_START` (`0x10`).
- The master waits for the new CPU to set its bit in `proxy_ready_set`; failure ends in `panic("cpu%d failed to start (2)")`.
- The slave executes `mach_cpu_startup`, enters `slave_startup()`, joins `proxy_ready_set`, waits for `cpu_ready_set`, enables interrupts, and exits its startup thread.
- Murayama's QEMU creates `machine->smp.cpus` SPARC CPU objects. His matching hypervisor implements `hcall_cpu_start` and schedules the target vCPU onto its strand.

## Evidence boundaries

| Gate | Evidence | Pass condition |
| --- | --- | --- |
| QEMU | QMP `query-cpus-fast`, host threads, QEMU function probes | exactly two live vCPU objects/threads |
| Firmware/MD | preserved preprocessed descriptors and binary hashes; guest `boot_ncpus` in KMDB | exactly CPU IDs 0 and 1 |
| Hypervisor handoff | KMDB around `promif_start_cpu`; hypervisor/QEMU trace correlation | `hv_cpu_start(1, ...)` returns `H_EOK` |
| Slave entry | KMDB/DTrace at `slave_startup`; `proxy_ready_set` | CPU 1 checks in before timeout |
| Online/scheduler | `cpu_ready_set`, `ncpus`, `psrinfo -pv`, `kstat -p cpu_info`, CPU-bound affinity test | CPUs 0 and 1 online and both execute work |

### Task 1: Preserve source and firmware identities

**Files:**

- Create: `notes/NIAGARA-SMP-SPRINT-20260903.md`
- Read: `work/qemu-sun4v-mp/hw/sparc64/niagara.c`
- Read: `work/qemu-sun4v-mp/hw/sparc64/sparc64.c`
- Read: `work/qemu-sun4v-hypervisor-mp/hypervisor/src/common/src/hcall_core.s`
- Read: `work/illumos-gate-smp/usr/src/uts/sun4v/os/fillsysinfo.c`
- Read: `work/illumos-gate-smp/usr/src/uts/sun4/os/mp_startup.c`
- Read: `work/illumos-gate-smp/usr/src/uts/sun4v/promif/promif_cpu.c`

1. Record full Git revisions for QEMU, hypervisor, OpenBoot, distribution, and illumos source.
2. Record SHA-256 and byte size for the one-CPU and two-CPU `md.bin`/`hv.bin` pairs.
3. Count guest and hypervisor CPU nodes from the preprocessed descriptor sources.
4. Record hashes for QEMU, `q.bin`, OpenBoot, reset firmware, NVRAM seed, and the immutable disk parents.
5. Verify `ec2trib` has no live Niagara QEMU before preparing a run.

### Task 2: Add a fail-closed SMP probe launcher

**Files:**

- Create: `scripts/ec2trib-niagara-smp-probe.sh`
- Create: `tests/unit/test_ec2trib_niagara_smp_probe.py`
- Reuse: `scripts/run-sun4v-ec2trib-login-raw-trial.sh`
- Reuse: `scripts/ec2trib-niagara-openboot.py`

1. Write tests requiring an explicit CPU count of `1` or `2`, a matching firmware directory, and a unique run ID.
2. Verify the tests fail before the launcher exists.
3. Implement dry-run validation that counts CPU IDs in the preserved preprocessed guest and hypervisor descriptors.
4. Reject a mismatched pair such as `-smp 2` plus a one-CPU MD before QEMU starts.
5. Require disposable writable disk state and preserve the immutable parent identity.
6. Add QMP and SPARC gdbstub sockets, separate serial logs, `-k -v` OpenBoot command injection, and a bounded timeout.
7. Run unit tests and shell syntax checks.

### Task 3: Run the one-CPU control

**Files:**

- Create remotely: `/tink/runs/niagara-smp-<timestamp>-control1/`
- Append locally: `notes/NIAGARA-SMP-SPRINT-20260903.md`

1. Revalidate that no selected QEMU instance is live.
2. Create fresh disposable writable overlays/clones.
3. Launch with the known one-CPU MD/HV pair and `-smp 1`.
4. Boot the installed root with `boot /virtual-devices@100/disk@4:a -k -v`.
5. Capture QMP CPU inventory, host thread inventory, console CPU messages, KMDB symbols, `psrinfo`, and CPU kstats.
6. Stop only the experiment-owned QEMU through the restricted lifecycle path.
7. Preserve the run manifest and logs as the control bundle.

### Task 4: Run the coherent two-CPU experiment

**Files:**

- Create remotely: `/tink/runs/niagara-smp-<timestamp>-trial2/`
- Append locally: `notes/NIAGARA-SMP-SPRINT-20260903.md`

1. Use the same inputs as the control except for the verified two-CPU MD/HV pair and `-smp 2`.
2. Boot with KMDB enabled and verbose output.
3. Capture QMP `query-cpus-fast` as soon as the monitor socket appears.
4. Use bounded host DTrace probes for QEMU vCPU execution, kicks, interrupt delivery, and strand pause/resume paths.
5. If boot reaches login, capture `psrinfo -pv`, `psradm -v`, `kstat -p cpu_info`, `::cpuinfo`, `ncpus`, `boot_ncpus`, `cpu_ready_set`, and `proxy_ready_set`.
6. Run two CPU-bound processes bound to different processor IDs and prove simultaneous execution with guest kstats/DTrace and host vCPU threads.
7. If the guest panics or stops, preserve KMDB stack/register/state evidence before any restart.

### Task 5: Localize the first failed gate

**Files:**

- Append: `notes/NIAGARA-SMP-SPRINT-20260903.md`

1. If `boot_ncpus == 1`, inspect guest MD traversal and `fill_cpu()` inputs.
2. If `boot_ncpus == 2` but CPU 1 is never prepared, inspect `cpunodes[1].nodeid`, `use_mp`, and `cpu_bringup_set`.
3. If `hv_cpu_start` fails, capture its return status and validate the hypervisor guest-vCPU mapping/status.
4. If `hv_cpu_start` succeeds but `proxy_ready_set` times out, inspect CPU 1's PC, trap level, landing-pad mappings, MMFSA, and strand state.
5. If CPU 1 checks in but fails after release, inspect cross-calls, mondo delivery, IOB dispatch, timer interrupts, and `cpu_ready_set` transitions.
6. State one root-cause hypothesis supported by the first divergent observation. Do not patch yet.

### Task 6: Minimal discriminating change and fix

**Files:**

- Modify only the source file owning the first failed gate.
- Add a focused regression test or scripted assertion under `tests/`.

1. Write the smallest test that reproduces the identified failure.
2. Verify it fails on the pristine two-CPU stack.
3. Make one source change addressing the root cause.
4. Rebuild with a new manifest and binary hash.
5. Repeat the two-CPU run with identical firmware and disks.
6. Require both online-CPU proof and simultaneous guest workload proof.
7. Run the one-CPU control again to check for regression.

## Sprint exit criteria

The sprint ends in one of two defensible states:

- **SMP proved:** two CPUs are enumerated, brought online, accept interrupts/cross-calls, and simultaneously execute guest work; or
- **SMP localized:** the exact first failed gate, inputs, observed state, and minimal next experiment are preserved without claiming that `-smp 2` alone constitutes SMP.
