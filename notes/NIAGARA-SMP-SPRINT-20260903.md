# Niagara SMP sprint evidence ledger

Date: 2026-09-03 through 2026-09-04 PDT

Status: SMP proved for the installed `oi-basecamp` root.  illumos brought CPUs
0 and 1 online and scheduled work on both.  The successful boot loaded KMDB but
did not enter it or require debugger intervention.  A no-KMDB Docker/Woodpecker
acceptance run remains to be implemented.

## Successful two-CPU boot

The successful run is preserved on `ec2trib`:

```text
tmux session: niagara-smp-mondo-fix-20260904-04
run directory: /tink/runs/niagara-smp-mondo-fix-20260904-04
QEMU PID at audit: 35294
QEMU base commit: 049affb20df67162cf58deeaf74d5ad4b83cbdc3
QEMU binary SHA-256: ff4c9e40b0032ce9a33f18f93aeb3a672271a75f63d451e48621fd4df6ba0b8f
```

The binary contains the changes in patches 0004, 0005, and 0006.  Each saved
patch passed `git apply --reverse --check` against the live source tree during
the capture audit.  Patch 0005 adds observability only; patches 0004 and 0006
are the behavior changes required by this run.

The boot used the two-CPU machine descriptions from Murayama distribution
commit `3eb7ce6cbda552ff2c03afc5fbb8a2bfede2cdd0`.  The binaries in that commit
are byte-identical to the successful run:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `md.bin` | 10,603 | `e5d0dfa0cef98daef762ed48a19ace9c372e4bc46342bc03200eb1cf219379ac` |
| `hv.bin` | 3,960 | `e9b63c8084a5a124253659c200709dc9de8281e66d3c8c349bef2faa4b065099` |
| `q.bin` | recorded in run | `47ddae19e1d4ee0143326991ffc71eca71b5d7b0383cd3947187171bbb2eaee3` |
| `nvram.bin` | 8,192 | `e1cf2fe5626d9c69b1ef62f90ab035f5f5761b7f7e62c6de744782ac6aebe47a` |

The run used `-smp 2` and the login-proven 64,424,509,440-byte unit-104 ZFS
root.  OpenBoot received:

```text
boot /virtual-devices@100/disk@4:a -k -v
```

The console recorded both processor attachments and reached a root shell:

```text
cpu0: UltraSPARC-T1 (chipid 0, clock 1000 MHz)
cpu1: UltraSPARC-T1 (chipid 0, clock 1000 MHz)
The illumos Project     illumos-31d3d510d0      December 2025
root@oi-basecamp:~#
```

Guest CPU inventory supplied the decisive proof:

```text
root@oi-basecamp:~# psrinfo
0       on-line   since 09/03/2026 01:47:11
1       on-line   since 09/03/2026 01:47:13
```

Three one-second `mpstat` samples showed activity on both processors.  CPU 0
spent each sample in system work while CPU 1 split time between user and system
work.  This proves scheduler-visible execution on both CPUs, beyond firmware
enumeration or QEMU thread creation.

### QEMU root causes

`ASI_CMT_STRAND_ID` returned physical strand zero for every QEMU vCPU.  The
sun4v hypervisor uses this ID for per-strand state, so the secondary vCPU
aliased strand zero.  Patch 0004 returns the QEMU CPU index in the physical
strand field.

QEMU also cleared `CPU_INTERRUPT_HARD` at the start of
`sparc_cpu_exec_interrupt()`.  The Niagara hypervisor can queue a guest mondo
and assert that request before its vector handler executes `retry`.  Clearing
the bit while the vCPU was still in hypervisor mode lost the guest mondo.
Patch 0006 preserves the request until QEMU can take the vector trap or deliver
the interrupt after returning to guest mode.

### Console transport finding

The tmux console was initially attached with plain `socat - UNIX-CONNECT:...`.
Its pane pseudo-terminal retained canonical input and local echo, so both the
pane line discipline and illumos processed keystrokes.  Commands appeared
twice, editing was inconsistent, and terminal-identification replies reached
the guest.  The live pane was corrected without restarting QEMU by setting its
tty to raw/no-echo mode.  Future interactive attachments must encode that in
the process invocation:

```text
socat -,rawer,echo=0 UNIX-CONNECT:/path/to/console.sock
```

The SSH login shell and a stale tmux client also briefly shared `/dev/pts/8`.
The stale client was detached and the competing shell was stopped.  QEMU's
console socket and `socat` pane remained separate throughout that repair.

### Remaining validation

This run proves two-CPU operation with KMDB loaded via `-k`; KMDB was never
entered.  It does not yet prove the Docker package because that entrypoint is
still pinned to the pre-fix QEMU and `-smp 1`.  The next acceptance test must
build the patched QEMU, use the matched two-CPU MD/HV pair, boot with `-v`
only, reject KMDB signatures, and require both CPU IDs to be online.

## Live experiment checkpoint

The first coherent two-CPU launch ran on `ec2trib` as QEMU PID `10421` in:

```text
/tink/runs/niagara-smp-probe-20260903
```

Its manifest records `smp_cpus=2`, the expected two-CPU `md.bin` and `hv.bin`
hashes, KMDB boot command `boot /virtual-devices@100/disk@4:a -k -v`, and
run-scoped QMP and GDB sockets.  Before OpenBoot, the hypervisor log parsed both
CPU nodes and configured vCPU 0 and vCPU 1:

```text
Virtual cpu 0 in guest 0 (pid 0)
Virtual cpu 1 in guest 0 (pid 1)
```

OpenBoot then reached:

```text
{0} ok
```

This proves the matched QEMU/MD/hypervisor topology reaches firmware with two
configured vCPUs.  It does not yet prove that illumos enumerates or starts CPU
1, because the boot command was not sent.

That run was later terminated by its exact recorded PID after the operator
authorized continuation.  It exited cleanly, its NVRAM hash was unchanged, its
tmpfs carrier was removed, and the disposable ZFS child still reported zero
bytes written.

### Preflight failures localized

Two empty pre-QEMU attempt directories were preserved.  The actual launcher
failure was an environment mismatch: Tribblix's default `PATH` selected GNU
`df`, while the safety check used the illumos-only `df -n` option.  The launcher
now calls `/usr/sbin/df` explicitly for both filesystem type and capacity.

The OpenBoot injector also recognized only a plain `ok ` prompt.  SMP OpenBoot
prefixes it with the selected CPU (`{0} ok `), so the injector correctly sent
nothing and waited.  Its local next-run matcher now accepts either form, with a
focused regression test.  It has not been restaged into or applied to the
current run.

The next boot must be launched visibly in a dedicated tmux owner/console
session from the outset; do not retrofit the current process.

### Next-run observation layout

Use a dedicated tmux session with separate `owner`, `console`, `host-dtrace`,
and `evidence` windows.  The console window must own the serial Unix socket
from QEMU startup onward so the operator sees and controls the entire boot.
Pause at the SMP-prefixed OpenBoot prompt, start the bounded host DTrace probes,
then boot with `-kdv`.  In the checked illumos source, `-k` corresponds to
`RB_KMDB`, while `-d` sets `RB_DEBUGENTER`; `mlsetup()` calls `kmdb_enter()`
before normal kernel initialization when the latter is present.  This gives us
a debugger stop early enough to set breakpoints on `cpu_setup_common()`,
`start_other_cpus()`, `promif_start_cpu()`, and `slave_startup()`.

The deployed ec2trib binary is unstripped and supports pid-provider probes for
at least `cpu_exec`, `cpu_exec_start`, `sparc_cpu_exec_interrupt`,
`main_cpu_reset_sun4v`, and `niagara_init`.  Host DTrace reports Sun D 1.14.
The deployed source identity is local commit `049affb20df67162cf58deeaf74d5ad4b83cbdc3`,
which is a descendant of Murayama `879fee341ad8307f8f0a0110b4a7dc6d6853d639`
with three known local commits: illumos-host disk support, a large-TTE flush
fix, and persistent Niagara NVRAM backing.

### KMDB gate checklist for the next boot

At the initial `-d` debugger entry, set breakpoints before continuing:

```text
cpu_setup_common::bp
start_other_cpus::bp
start_cpu::bp
promif_start_cpu::bp
hv_cpu_start::bp
slave_startup::bp
```

At `start_other_cpus`, `cpu_setup_common()` has completed, so capture
`boot_ncpus`, `use_mp`, the first two `cpunodes[]` entries (especially `cpuid`
and `nodeid`), `cpu_bringup_set`, and `cpu_ready_set`.  At `start_cpu`, require
the selected ID to be 1 and record `proxy_ready_set` before the PROM call.  At
`promif_start_cpu`, inspect the client-interface cells for CPU ID, PC, and
argument.  At `hv_cpu_start`, the SPARC output arguments are the CPU ID,
landing-pad physical address, RTBA, and CPU argument; capture them and the
returned hypervisor status.  A hit on `slave_startup` on CPU 1 is the decisive
landing-pad/slave-entry proof.  Then record `proxy_ready_set` before the master
releases CPU 1 and `cpu_ready_set` afterward.

Use `::nm -P`/`::dis` first if any static symbol is not accepted by `::bp`, and
capture `::status`, `::stack`, and `$<regs` at every unexpected stop.  Do not
make source changes until this sequence identifies the first missing gate.

## Two-CPU KMDB run: preserved debugger fault

The next run was launched visibly in tmux session:

```text
niagara-smp-kmdb-20260903-01
```

Windows are `owner`, `host-dtrace`, `console`, and `evidence`; the interactive
console is window `2`.  QEMU PID is `22549`, and the fresh disposable dataset
is `tink/qemu-sun4v-illumos-ci/smp-kmdb-20260903-01`.

Passed gates:

1. QMP returned two `Sun-UltraSparc-T1-sparc64-cpu` objects, indices 0 and 1.
2. Host LWP sampling showed QEMU vCPU LWPs 4 and 5 each consuming about 49%
   CPU during early boot.
3. `boot -kdv` entered KMDB in `mlsetup()` before normal initialization.
4. illumos reached `cpu_setup_common()` and later `start_other_cpus()`.
5. At `start_other_cpus`, KMDB reported `boot_ncpus = 2` and `use_mp = 1`.
6. `cpunodes[0]` was `(cpuid=0, nodeid=1, clock=1GHz)` and `cpunodes[1]` was
   `(cpuid=1, nodeid=2, clock=1GHz)`.
7. Before bring-up, `cpu_ready_set` contained only bit 0 and both
   `cpu_bringup_set` and `proxy_ready_set` were empty, matching function-entry
   state.
8. illumos printed both CPU identities and reached `start_cpu()`:

```text
cpu0: UltraSPARC-T1 (chipid 0, clock 1000 MHz)
cpu1: UltraSPARC-T1 (chipid 0, clock 1000 MHz)
kmdb: stop at start_cpu
```

The stop condition was then an instrumentation failure, not an observed SMP
failure.  An incorrectly escaped attempt to use the adb `$<regs` macro was
rejected harmlessly.  The fallback `::regs` dcmd triggered a KMDB debugger
fault in `gelf64_sym_search+0x20`; the console is preserved at:

```text
kmdb: (p)anic, or (d)ebug with self?
```

The guest had not yet entered `promif_start_cpu()` or `hv_cpu_start()`, so this
run neither proves nor disproves CPU 1 startup.  The disposable ZFS child has
2.12 MiB written from early boot.  The earlier high-overhead trace was preserved
separately as
`host-dtrace-hotpath.log`; it proved two executing vCPU LWPs but probing
`sparc_cpu_exec_interrupt` was too hot for continued use.

The exact guest `kmdbmod` was mounted read-only from the matching disk image and
copied under the run's `offline/` directory.  Its disassembly shows that the
fault at `gelf64_sym_search+0x20` is the second load: KMDB reads `asmap[46]`
successfully, then faults dereferencing that entry to obtain `st_value`.  With
`aslen == 93` and `addr == 0`, this is an invalid symbol-entry pointer in the
map, not a bad address argument.  The guest identifies as
`illumos-31d3d510d0`.

A retry set KMDB's undocumented numeric-only address mode (`1>_`) before
installing the SMP breakpoints.  It passed `cpu_setup_common()` and continued
past the initial debugger stop, but never reached `start_other_cpus()` or
emitted further kernel progress; both QEMU vCPU LWPs remained active at about
49% each.  That second run was stopped at this next failure boundary and
finalized cleanly.

## Question

Does Murayama's `mp snapshot 0.2` Niagara stack merely construct and describe
multiple SPARC CPUs, or does an illumos guest successfully enumerate, start,
and schedule work on CPU 1?

## Prior experiment correction

The historical `term4code-herm-smp4-01` launch used `-smp 4`, but retained the
firmware directory from the one-CPU/3 GiB run.  The preprocessed guest machine
description preserved at:

```text
/tink/firmware-term4code-02-proven/2c8t_guest.pp.bak
```

contains only the `cpu0` node.  Its `cpus` node points only to `cpu0`.  The
observed one-CPU OpenIndiana guest was therefore the expected result of the
machine description and is not evidence against Murayama's coherent SMP stack.

The QEMU, `q.bin`, OpenBoot, and reset-firmware identities in that directory
match Murayama's distribution.  The guest and hypervisor MD binaries differ
from the checked-in two-CPU binaries.

| Artifact | One-CPU ec2trib bytes | One-CPU SHA-256 | Two-CPU upstream bytes | Two-CPU SHA-256 |
| --- | ---: | --- | ---: | --- |
| `md.bin` | 10,075 | `b5d160f6f55a30d2ed56b5e24f9b1158180bb6a84d71fe222b4476945bd5b823` | 10,603 | `e5d0dfa0cef98daef762ed48a19ace9c372e4bc46342bc03200eb1cf219379ac` |
| `hv.bin` | 3,784 | `1c3d9dc2a5dace6e33b7443c1cae07b4ee235109ca29b9d6c54c3171b968ee27` | 3,960 | `e9b63c8084a5a124253659c200709dc9de8281e66d3c8c349bef2faa4b065099` |

The two-CPU descriptors were preprocessed with `NCPUS=2` and independently
counted: two guest `cpu` nodes and two hypervisor `cpu` nodes.

## Pinned source identities

```text
Murayama QEMU:       879fee341ad8307f8f0a0110b4a7dc6d6853d639  mp snapshot 0.2
Murayama hypervisor: a30011e462a4af69bb42be541c99063aae46ca32
Murayama OpenBoot:   7c3ab581b1b0c482df6bb87a8eb28b357a721bec
Murayama dist:       3eb7ce6cbda552ff2c03afc5fbb8a2bfede2cdd0
illumos-gate:        364e599f664b367ea10b0fb1c950afb4471b9fcc
```

Sparse source checkouts live under the ignored `work/` tree and are not release
artifacts.

## Static CPU path

### 1. QEMU constructs the requested CPUs

`hw/sparc64/niagara.c:niagara_init()` loops from zero to
`machine->smp.cpus - 1` and calls `sparc64_cpu_devinit_sun4v()` for each CPU.
The sun4v reset path supplies every CPU with the hypervisor address, guest
memory geometry, and a strand-start mask derived from `machine->smp.cpus`.

Important uncertainty: Murayama's reset path deliberately leaves secondary
QEMU CPUs unhalted, with comments showing earlier halted/stopped alternatives.
This may be correct for OpenSPARC reset/hypervisor startup, but it is an early
live observation point rather than a fact to change speculatively.

### 2. The machine descriptions map physical strands to guest vCPUs

The hypervisor descriptor emits CPU nodes conditionally from `NCPUS`, with
matching physical ID (`pid`), virtual ID (`vid`), and resource ID.  The guest
descriptor emits matching `cpu` nodes with `id` and `pid`, and links them from
the `cpus` node.  The distribution launcher generates both descriptors with
the same `NCPUS` value that it passes to QEMU `-smp`.

### 3. illumos enumerates CPUs from the guest MD

`usr/src/uts/sun4v/os/fillsysinfo.c:cpu_setup_common()` scans forward `cpu`
nodes from the MD root, assigns that count to `boot_ncpus`, and calls
`fill_cpu()` for each node.  This is the first guest-side gate.

### 4. illumos prepares and starts CPU 1

`usr/src/uts/sun4/os/mp_startup.c:start_other_cpus()` iterates populated
`cpunodes[]`, skips the boot CPU, runs `setup_cpu_common()` and
`common_startup_init()`, then calls `start_cpu()`.

`start_cpu()` calls the `SUNW,start-cpu-by-cpuid` PROM interface and waits for
CPU 1 to set its bit in `proxy_ready_set`.  A timeout panics with:

```text
cpu1 failed to start (2)
```

### 5. sun4v converts the PROM call to a hypercall

`usr/src/uts/sun4v/promif/promif_cpu.c:promif_start_cpu()` creates the landing
pad, then invokes `hv_cpu_start(cpuid, landing_pad_pa, rtba, cpuid)`.  The
assembly wrapper issues hypervisor service `HV_CPU_START` (`0x10`).

### 6. The hypervisor schedules the stopped vCPU

`hypervisor/src/common/src/hcall_core.s:hcall_cpu_start()` validates the guest
vCPU, requires `CPU_STATE_STOPPED`, records the landing-pad PC/RTBA/argument,
marks it `CPU_STATE_STARTING`, and sends `HXCMD_SCHED_VCPU` to the target
strand.  A successful request returns `H_EOK`.

### 7. CPU 1 checks in and becomes ready

The slave executes the landing pad in
`usr/src/uts/sun4v/ml/mach_proc_init.S`, enters `slave_startup()`, joins
`proxy_ready_set`, waits for the master to add it to `cpu_ready_set`, enables
interrupts, updates its OS signature, and exits the startup thread.

## First live experiment

Run a matched two-CPU stack on `ec2trib`:

- Murayama QEMU commit `879fee...` with `-smp 2`;
- the verified two-CPU `md.bin` and `hv.bin` above;
- matching upstream `q.bin`, OpenBoot, and reset firmware;
- a fresh disposable child of the login-proven unit-104 image;
- `boot /virtual-devices@100/disk@4:a -k -v`;
- QMP and a per-run SPARC gdbstub;
- bounded host DTrace plus KMDB/guest DTrace evidence.

The first classification is intentionally simple:

1. Does QMP show two vCPUs?
2. Does KMDB show `boot_ncpus == 2` and a populated `cpunodes[1]`?
3. Does `hv_cpu_start(1, ...)` return `H_EOK`?
4. Does CPU 1 join `proxy_ready_set` and `cpu_ready_set`?
5. Does `psrinfo` report both CPUs online?
6. Can two processor-bound guest workloads execute simultaneously?

No source fix is permitted until the first failed gate is observed.
