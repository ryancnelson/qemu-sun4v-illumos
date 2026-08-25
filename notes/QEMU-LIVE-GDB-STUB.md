# Live guest debugging through the QEMU monitor

## Why this matters

QEMU's guest GDB stub can be enabled **after the VM has started**. A VM that
was launched without `-s` or `-gdb` does not need to be restarted, and the host
QEMU process does not need to be ptraced.

This was verified on 2026-08-21 against a running UTM SPARCstation 5 VM whose
Solaris 9 kernel had stopped making visible progress immediately after:

```text
SunOS Release 5.9 Version Generic_32-bit
Use is subject to license terms.
```

The same technique is useful for the Niagara/sun4v rigs whenever their QEMU
human monitor is reachable.

## Enable the stub on a running VM

At the QEMU human-monitor `(qemu)` prompt, enter:

```text
gdbserver tcp:127.0.0.1:1234
```

QEMU starts a GDB remote-protocol listener without restarting the guest. Bind
to `127.0.0.1`, not every interface, unless remote debugger access is
deliberately required.

For UTM, configure a serial device with its target/source set to **QEMU
Monitor**. UTM presents that HMP channel in a second terminal window. This is
also the channel where `sendkey stop-a` can break a SPARC guest back to OBP.

Confirm the listener from the host:

```bash
lsof -nP -iTCP:1234 -sTCP:LISTEN
```

## Connect with a SPARC-capable debugger

Use GNU GDB built with SPARC target support:

```text
gdb -q
(gdb) set architecture sparc
(gdb) set endian big
(gdb) target remote 127.0.0.1:1234
(gdb) info registers
(gdb) x/16i $pc
(gdb) detach
(gdb) quit
```

Connecting stops the emulated CPU. Always `detach` (or explicitly continue)
when evidence collection is complete so a failed batch command does not leave
the guest paused.

If kernel symbols are available, load the matching unstripped Solaris or
illumos kernel before connecting. Register and raw-PC inspection still work
without symbols. Setting big-endian mode explicitly matters: without it, the
Solaris/SPARC register values can appear byte-swapped.

## Solaris 9 case study: finding the real interrupt source

This method turned the apparently featureless 2026-08-21 Solaris 9 boot hang
into a specific emulated-device failure. GNU GDB showed the guest spinning at
`0xf0041c84` through `0xf0041c98`, with:

```text
psr = 0x04400fc3     PIL 15
tbr = 0xf00401f0     interrupt level 15 trap
%l4 = 15
%l6 = 0x30
%o3 = 0
```

The loop searched an active high-level-interrupt mask for a lower-priority
bit. Its shifting mask had reached zero, so it could never match. Sampling
`%o2` twice showed it changing by millions of iterations: this was an actual
infinite loop, not merely slow emulation.

GDB can also forward commands to QEMU's human monitor. That let us inspect
physical device registers without attaching a debugger to the hardened host
process:

```text
(gdb) monitor xp /4wx 0x71e00000
(gdb) monitor xp /8wx 0x71e10000
```

The SLAVIO interrupt controller reported per-CPU PIL 14 and 15 pending, and
master IRQ 30 asserted. In the SS-5 machine, IRQ 30 is the sun4m IOMMU fault
line. Reading the IOMMU asynchronous fault registers at `0x10001000` and
`0x10001004` returned:

```text
AFSR = 0xc0860000
AFAR = 0xffe18000
```

Reading AFSR acknowledges the interrupt in QEMU, so this was an intentional,
state-changing diagnostic. Afterward, master IRQ 30 and PIL 15 cleared, while
the ordinary PIL 14 timer remained pending. That confirmed a valid DMA-read
fault at DVMA address `0xffe18000`, rather than a generic CPU or timer hang.

Further physical-register inspection identified the ESP/SCSI DMA engine as
active and LANCE as idle. The IOMMU page-table entry QEMU computed for the
faulting DVMA address was zero. The evidence therefore narrows the bug to a
late or stale ESP DMA operation after Solaris removed the DVMA mapping, or to
an ESP/IOMMU timing or indexing error. It does not yet distinguish those
possibilities.

The resulting reusable investigation pattern is:

1. Capture `pc`, `npc`, `psr`, `tbr`, registers, and nearby instructions.
2. Sample changing registers to distinguish a tight loop from a stopped CPU.
3. Use `monitor xp` for physical interrupt-controller and device state.
4. Identify and acknowledge a source only after recording its pending state.
5. Trace the asserted interrupt back through the QEMU machine wiring.
6. Inspect the responsible DMA engine and the guest's IOMMU translation.
7. `detach` explicitly; do not leave a long-booting guest silently stopped.

In this case, the already-entered Solaris software loop did not recover merely
because the hardware interrupt was acknowledged. We deliberately did not
rewrite the guest PC or registers; doing so would have been a separate,
high-risk recovery experiment.

## macOS and UTM findings

Attaching LLDB directly to UTM's host `QEMULauncher` failed even under `sudo`.
macOS logged the exact reason: the process uses hardened runtime and does not
carry the `get-task-allow` entitlement. This is an application-signing policy,
not a Unix privilege problem.

Apple's LLDB could connect to the QEMU remote stub, but the installed build did
not understand the SPARC register description. It stopped the guest, then
failed at `register read`. Because LLDB batch mode stopped processing commands
after that error, a second connection with only `process detach` was required
to resume the VM.

Therefore:

1. Do not expect `sudo lldb -p <QEMULauncher-pid>` to bypass UTM hardening.
2. Prefer the QEMU guest GDB stub over host-process attachment.
3. Use a SPARC-capable GNU GDB, not Apple's LLDB, for register-level work.
4. Put detach/resume handling in a trap or a separate cleanup step when
   automating debugger captures.

## What this gives the project

This creates a low-friction debugging loop for firmware and early-kernel
failures:

1. Boot normally until progress stops.
2. Enable `gdbserver` dynamically from HMP.
3. Capture the guest PC, registers, instructions, and memory.
4. Compare the stopped state with a known-good QEMU/OpenBIOS or kernel build.
5. Detach and let the same VM continue, or stop it deliberately for the next
   experiment.

It is especially valuable for long-booting Solaris and Tribblix guests because
the decision to debug no longer has to be made before boot.
