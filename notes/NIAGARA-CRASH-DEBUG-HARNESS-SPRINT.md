# Niagara crash/debugging harness sprint

## Objective

Before the next OpenIndiana boot, implement and rehearse a capture-first
harness that distinguishes guest illumos code stuck from QEMU host emulation
stuck. Primary success is entering KMDB after a reproduced wedge and recording
useful registers and stacks. Fallback success is a SPARC gdbstub snapshot plus
symbolized host-QEMU thread stacks sufficient to localize guest versus
emulator.

Do not use QEMU migration: Niagara UART/IOB/vdisk VMState coverage is known
incomplete and a restore reached fatal MAXTL.

## Pre-boot prerequisites

Use the verified native QEMU with debug information and symbols. Add:

```
-chardev socket,id=console1,path=RUN/sockets/console.sock,server=on,wait=off
-serial chardev:console1
-qmp unix:RUN/private/qmp.sock,server=on,wait=off
-gdb unix:RUN/private/gdb.sock,server=on,wait=off
-D RUN/logs/qemu-debug.log
-d guest_errors,unimp
```

Boot with `-k -v`. Preserve matching unstripped `unix`, `genunix`, platform,
driver, and KMDB modules. Install and preflight `gdb-multiarch`; playbox's
current `/usr/bin/gdb` is AArch64-only and rejects `sparc:v9`. Reserve at least
12 GiB for evidence. Keep the QMP socket in a service-owned 0700 directory.

## Restricted QMP programs

Implement three clients with no arbitrary command input:

- `niagara-qmp-capture`: `qmp_capabilities`, `query-status`,
  `query-cpus-fast`, `query-block`, `query-blockstats`,
  `query-named-block-nodes`, `query-iothreads`,
  `query-memory-size-summary`, `query-dump-guest-memory-capability`,
  `query-dump`, `x-query-irq`, `x-query-interrupt-controllers`,
  `x-query-jit`, and `x-query-ramblock` only.
- `niagara-qmp-stop`: `stop`, followed by required `query-status=paused`.
- `niagara-qmp-cont`: `cont`, followed by required `query-status=running`.

Mechanically reject `quit`, `system_reset`, `system_powerdown`,
`human-monitor-command`, migration, NMI, send-key, arbitrary break, and block
topology mutation. Do not ship a general HMP client.

A fourth fixed client may issue only `chardev-send-break` for `console1`, but
it is not admitted until a healthy idle `-k -v` boot proves that this exact
Niagara UART path reaches literal KMDB `[0]>`, accepts read-only commands, and
resumes with `:c`. Stop-A, NMI, and serial break were not proven in the prior
run; the qcn interrupt path has known delivery limitations.

## Capture order

Before the risky workload, capture three healthy samples five seconds apart.
After apparent progress loss:

1. Record the trigger, last milestone, timestamps, argv, PID, and hashes.
2. Without pausing, take three five-second samples of restricted QMP state,
   `/proc/PID/io`, per-thread CPU, console/channel log deltas, Unix socket
   queues, and block statistics.
3. Run bounded host sampling:

   ```
   sudo perf record -F 99 -p QEMU_PID -g -- sleep 15
   ```

4. Connect with `gdb-multiarch` only after live deltas are captured. Record
   full SPARC registers, PC/nPC, 32 nearby instructions, and bounded stack and
   suspect memory ranges. Automation must guarantee `detach`; it must never
   forward HMP `monitor` commands.
5. Resume briefly and take a second architectural snapshot to measure actual
   guest progress.
6. Attempt the rehearsed KMDB break once. If `[0]>` appears, capture status,
   registers, current CPU/thread, current stack, all supported CPU stacks,
   panic state, interrupt state, and relevant driver state before recovery.
7. Freeze only after live evidence using the fixed QMP stop client.
8. Attach host GDB to the paused, symbolized QEMU and run `info threads` plus
   `thread apply all bt full`; detach explicitly.
9. Take filesystem reflinks/storage snapshots of the run-local writable top
   overlay and unit-101 mailbox while paused. Validate only copies. This is
   crash-consistent, not guest-synchronized, unless a prior guest sync marker
   exists.

## Memory and crash dumps

Prefer bounded gdbstub range dumps. QEMU advertises `dump-guest-memory`,
`query-dump`, `memsave`, and `pmemsave`, but SPARC ELF guest-memory dumping
must pass a disposable preflight before admission. For 3072 MiB RAM, budget
3.0–3.2 GiB raw and 0.5–3.2 GiB compressed. A host core costs roughly 3–4 GiB
and is a secondary fallback.

Before the workload, record `dumpadm`, `dumpadm -epH`, `zfs list rpool/dump`,
and `svcs svc:/system/dumpadm`. Expected ZFS-root dump storage is
`/dev/zvol/dsk/rpool/dump`. If KMDB is reached, capture all live evidence
first. A forced KMDB panic is destructive and requires explicit authorization.
Preserve the dump zvol before reboot/savecore; if QEMU exits with MAXTL, do
not relaunch automatically.

## Evidence bundle

```
RUN/evidence/wedge-UTC/
  MANIFEST.json              timestamps.jsonl
  argv.txt                   qemu.sha256
  firmware.sha256            disk-chain-before.json
  live-samples/{qmp,proc,threads,sockets,logs}-*
  guest-gdb/{registers,disassembly,stack-memory}-*
  kmdb/{console-transcript,command-manifest}.txt
  host/{perf.data,perf-report.txt,gdb-thread-stacks.txt}
  memory/{guest-memory.elf,dump-status.json}
  disks/{chain.json,overlay-reflink.qcow2,unit101-mailbox.img}
  classification.json        SHA256SUMS
```

## Falsifiable discriminators

- **Guest spin:** guest PC remains in a real illumos loop while registers or
  counters advance; host samples show normal TCG execution. Disproved by
  incoherent/frozen architecture while one QEMU helper loops.
- **QEMU emulation loop:** host vCPU stacks/perf repeat one QEMU helper,
  translator, trap, or MMU path while guest state does not advance coherently.
  Disproved by guest progress through a valid software loop.
- **Blocked interrupt delivery:** guest is idle/polling or at elevated
  interrupt state while a relevant IOB/IRQ source remains pending and the
  expected PIL/trap transition never occurs. Disproved when no source is
  pending or the guest services it.
- **Host I/O deadlock:** vCPU/I/O threads block in coroutine, block, futex, or
  poll paths with outstanding block work and flat counters. Disproved by
  continuous guest execution without outstanding I/O.

A fixed PC alone is never a conclusion; classification requires guest state
plus host stack/perf or device/IRQ evidence.

## Acceptance gates

Primary PASS: rehearsed break reaches KMDB on healthy and wedged runs and
captures useful registers, current thread, and stacks before recovery.

Fallback PASS: SPARC gdbstub capture plus symbolized host stacks/perf and
restricted QMP state support a falsifiable guest-versus-emulator result.

FAIL CLOSED if SPARC GDB is absent, break entry is unproven, QMP dump output is
invalid, any client exposes arbitrary QMP/HMP, evidence capture depends on
migration, or any ordinary harness path can send `quit`.
