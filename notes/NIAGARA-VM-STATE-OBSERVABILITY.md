# Niagara VM State Observability

## Purpose

The project needs to answer a small operational question without opening every
console: is each VM that is supposed to be running healthy, progressing,
waiting for an operator, blocked on host I/O, spinning, stalled, or crashed?

This is intent-aware monitoring. Every managed VM declares its desired state,
assigned Run, expected semantic stage, next milestone, and progress budget.
An intentionally stopped or completed rehearsal must not alert merely because
it is not running.

## Host-side classifier

`tools/ci/classify-niagara-vm.py` produces one stable enum. It uses two process
samples, QEMU monitor responsiveness, semantic console evidence, the declared
intent, and state retained across invocations. High TCG CPU or a growing log is
not accepted as progress by itself.

Example from a Biggie root shell:

```sh
sudo /home/ryan/devel/masa-sun4v/tools/ci/classify-niagara-vm.py \
  --run-dir /home/ryan/devel/masa-sun4v/ci/candidates/tribblix-hsimd-v1-20260825T2255Z/run \
  --tmux-pane tribcons:0.0 \
  --tmux-user ryan \
  --desired running \
  --expected single-user \
  --json
```

The first live deployment returned `WAITING_DEGRADED`: QEMU and its monitor
were alive, the process was sleeping in the host poll loop, the guest had
reached single-user mode, and that transition followed the repeated RBAC
service failure into maintenance. That is neither a crash nor successful
installer progress.

Exit codes are `0` for good/progressing, `1` for attention required, and `2`
for crashed or fundamentally incorrect state.

## Classification precedence

1. Compare actual existence with the declared desired state.
2. Verify the QEMU process and monitor.
3. Recognize terminal console evidence: current-epoch panic, maintenance,
   prompt, or expected stage.
4. A QEMU process remaining in Linux `D` state is `HOST_IO_BLOCKED`.
5. A new semantic stage is `PROGRESSING`.
6. Retain stage and console ages across invocations.
7. After the stage budget expires, high CPU with negligible host disk I/O is
   `SPIN_SUSPECTED`; otherwise the state is `STALLED`.
8. A cleanly reached expected stage is `READY`.

The current enums are `READY`, `PROGRESSING`, `OBSERVING`, `WAITING_INPUT`,
`WAITING_DEGRADED`, `STALLED`, `SPIN_SUSPECTED`, `HOST_IO_BLOCKED`, `PAUSED`,
`MONITOR_UNRESPONSIVE`, `GUEST_CRASHED`, `CRASHED`, `STOPPED_EXPECTED`, and
`UNEXPECTED_RUNNING`.

## Evidence still needed

The host cannot reliably distinguish a quiet healthy guest from a guest whose
kernel still executes but whose services are dead. A small control-channel
heartbeat should therefore publish a boot ID, monotonic sequence, guest stage,
root writability, hSIMD unit map, and channel/PPP/NFS canaries.

The QEMU binary used by the first classifier test has `CONFIG_EBPF` and links
libbpf, but that facility is not an observability probe set. It was built with
only the `log` trace backend, contains no USDT notes, and has no hSIMD trace
events. The executable is unstripped and has debug information, so bounded
eBPF uprobes can be attached now.

When the classifier reports `SPIN_SUSPECTED`, collect a bounded ten-second
uprobe/stack sample and refine the diagnosis to TCG execution, hSIMD activity,
host syscall/I/O blocking, or another hot path. Do not run expensive profiling
continuously. A durable successor build should enable QEMU's DTrace/USDT trace
backend and add named hSIMD and SPARC TLB events that `bpftrace` can consume.

## Dashboard contract

The private dashboard should show, for every managed VM: desired state, primary
enum, evidence and confidence, current semantic stage, age of last milestone,
QEMU/monitor state, guest heartbeat age, channel/PPP/NFS gates, assigned Run,
and next check. Repeated errors count as activity but not progress. The public
dashboard remains a separate positive allowlist and must not expose private
identities, paths, sockets, PIDs, or command lines.

