#!/usr/bin/env python3
"""probe-softint-wakeup.py -- reassert CPU0's missing STIMER wakeup under GDB.

Reconstructed from notes/ARM64-SOFTINT-INCIDENT-20260913.md (H1 result), whose
one-incident tooling was never committed. That note records:

    "probe-softint-wakeup.py validated CPU0's unchanged comparator, absent
     timer and zero softint, then set only softint 0x10000 and
     CPU_INTERRUPT_HARD 2 while GDB had all host threads stopped.
     Detached without reset or inferior function calls."

Root cause is fixed by qemu-patches/0007-sparc-atomic-softint-updates.patch
(non-atomic softint RMW races the timer thread and loses its STIMER bit).
This script only clears the *sustaining* condition of an already-hung guest;
it is not a fix and must not be presented as one.

Safety:
  - read-only by default; mutation requires --apply
  - never calls inferior functions, never resets the CPU
  - always detaches (gdb -batch detaches on exit)
"""
import argparse
import subprocess

SOFTINT_STIMER = 0x10000
CPU_INTERRUPT_HARD = 2


def gdb(commands, pid=1):
    argv = ["gdb", "-q", "-batch", "-p", str(pid)]
    for c in commands:
        argv += ["-ex", c]
    out = subprocess.run(argv, capture_output=True, text=True, timeout=300)
    return out.stdout + out.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pid", type=int, default=1)
    ap.add_argument("--apply", action="store_true",
                    help="actually set softint/interrupt_request (default: read-only)")
    args = ap.parse_args()

    # first_cpu is a QEMU global; CPUSPARCState hangs off the ArchCPU.
    read = [
        "set pagination off",
        "set confirm off",
        "p first_cpu->cpu_index",
        "p ((SPARCCPU *)first_cpu)->env.softint",
        "p first_cpu->interrupt_request",
        "p/x ((SPARCCPU *)first_cpu)->env.pc",
        "p/x ((SPARCCPU *)first_cpu)->env.pstate",
    ]
    print("=== PRE ===")
    print(gdb(read, args.pid))

    if not args.apply:
        print("(read-only; pass --apply to reassert the wakeup)")
        return

    mutate = [
        "set pagination off",
        "set confirm off",
        # Reassert ONLY the timer softint bit and the hard interrupt request.
        f"set ((SPARCCPU *)first_cpu)->env.softint = {SOFTINT_STIMER}",
        f"set first_cpu->interrupt_request = {CPU_INTERRUPT_HARD}",
        "p ((SPARCCPU *)first_cpu)->env.softint",
        "p first_cpu->interrupt_request",
    ]
    print("=== APPLY ===")
    print(gdb(mutate, args.pid))


if __name__ == "__main__":
    main()
