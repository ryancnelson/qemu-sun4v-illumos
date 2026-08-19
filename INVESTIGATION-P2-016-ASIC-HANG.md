# Investigation: P2-016 Hypervisor Boot Hang

**Goal:** Determine why `greatlakes/ontario/release/q.bin` and `legion/q.bin` hang during boot under QEMU, while our custom `S10image/q.bin` boots successfully to the `ok` prompt. This is the blocker for P2-016 (Fire-enabled hypervisor), which gates P2-015 (PCI/Fire emulation).

## Findings

Both the `release` (Fire-enabled) and `legion` (Fire-disabled) in-tree builds hang **before the UART console is initialized**. They output absolutely nothing to the serial port.

By running QEMU headless with `-d in_asm,cpu` instruction tracing against `release/q.bin`, I identified the exact infinite loop where the hypervisor gets permanently stuck:

```assembly
0x0041de60:  lduh   [ %g5 + 0x20 ], %g4
0x0041de64:  andcc  %g4, 0xf, %g4
0x0041de68:  be,pn  %xcc, 0x41de60
0x0041de6c:  nop 
```

### The Polling Target

The loop reads a 16-bit register at `%g5 + 0x20`, masks the bottom 4 bits (`andcc %g4, 0xf`), and waits for them to become non-zero (`be` = branch if equal to zero). 

Dumping the CPU registers at runtime reveals the base address in `%g5`:
`%g5 = 0x0000001f3fd80000`

This means the hypervisor is polling physical MMIO address `0x1f3fd80020`. 

### The Root Cause of the Hang

QEMU's sun4v emulation (`hw/sparc64/niagara.c`) **does not model any device at `0x1f3fd80000`**. 
Because the memory region is unassigned, QEMU returns `0` for the read. 
`0 & 0xf == 0`, so the branch is taken, and the hypervisor spins forever.

### The Scope of the Problem

To test if we could just bypass this specific check, I hot-patched `q.bin` (replacing the `be,pn` instruction with a SPARC `nop` `0x01000000`) to force the code to fall through. 

After breaking the loop, the hypervisor immediately fell into another polling loop checking a different bit, and subsequent traces showed it attempting to access other ASIC addresses like `0x1f7ffc0000`.

This proves that `release/q.bin` includes a massive hardware state-machine initialization sequence for Sun Fire T1000/T2000 ASICs (likely JBus endpoints, ALOM interfaces, or I2C/power controllers). 

Our custom `S10image/q.bin` works precisely because whoever built it painstakingly stripped out not just `CONFIG_FIRE`, but *all* of these physical motherboard dependencies so it could boot under a minimal emulator.

## Paths Forward to Unblock PCI

To get a Fire-enabled hypervisor booting, we must choose one of two paths:

1. **Hardware Emulation (The QEMU Path):** 
   Identify the ASIC living at `0x1f3fd80000` (and its siblings). Implement a dummy "catch-all" MMIO device in `niagara.c` across the `0x1f00000000` range that blindly returns "ready" status codes (e.g., `0xffff` or matching the expected bitmasks) to trick the hypervisor into thinking the physical ASICs are initialized.
   
2. **Hypervisor Reconfiguration (The Source Path):**
   Examine the `S10image` Makefiles/configs to see exactly which initialization routines were `#ifdef`'d out. Rebuild a new `q.bin` from source that *includes* `CONFIG_FIRE` (so the PCI hypercalls are present) but *excludes* the physical ASIC polling.

*Note for future agents: Focus research on the sun4v architecture, UltraSPARC T1 ASICs, and OpenSPARC T1 hypervisor source code regarding addresses like `0x1f3fd80000`.*
