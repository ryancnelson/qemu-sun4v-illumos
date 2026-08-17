# Current State

## What works

- Solaris 10 boots to login prompt in ~40 seconds (clean, verified)
- Root login, no password
- `/tmp` is tmpfs — writable in-session
- QEMU monitor accessible via `Ctrl-A c`
- `pmemsave` / `dump-guest-memory` from monitor extracts guest RAM to host file
- `zfs rollback primary@clean` resets the zvol (REQUIRED after any QEMU panic)

## What is broken

### 1. Disk writes evaporate (LDC/SAM path broken)
Root cause: fully traced. q.bin handles vdisk writes via SAM API that QEMU
doesn't implement. Writes acknowledged to guest, discarded. Runtime UFS
writes never reach vdisk_ram.

### 2. flatblk — all approaches cause kernel panic (P1-004)
Every attempt to add memory to the Niagara physical address space causes an
identical, deterministic kernel panic:

  BAD TRAP type=10 (illegal instruction) at pc=0x300005e7840
  ufs:fetchbuf+74 during vfs_mountroot

Approaches tried:
- New RAM region at device space (0x1f50000000)
- New RAM region in "safe" zone (0x400000000 = 16GB)
- memory_region_init_ram_ptr (user-supplied buffer, cannot be moved by QEMU)
- Extended vdisk_ram to include flatblk tail

Instrumentation confirmed: vdisk_ram host pointer does NOT move. The panic
is not from QEMU relocating RAM allocations.

**Current hypothesis:** Adding memory changes q.bin's DMA target computation
during vdisk I/O. q.bin writes DMA data to a wrong kernel virtual address,
corrupting a SPARC64 register window, causing an illegal instruction jump.
Blocked on q.bin binary analysis.

**CRITICAL:** atexit fires even on panicked QEMU exit. Always `zfs rollback
primary@clean` after any panicked run or the zvol will be corrupted.

### 3. No networking
Niagara machine has no PCI/virtio bus. No NIC can be attached.

### 4. OBP traps after guest reboot
Must exit QEMU and restart after any guest reboot.

## Data channels (working today)

**Guest → Host:** Write to `/tmp` (tmpfs), then from monitor:
  `pmemsave 0x88000000 0x8000000 /datapool/niagara/dump.bin`
  Search dump for file contents on host.

**Host → Guest:** Modify disk image from host before boot.
  Linux can read-only mount Solaris UFS:
  `sudo mount -t ufs -o ro,ufstype=sun /dev/zvol/.../primary /mnt/sol`

## Environment

- Host: biggie (Linux x86, Xeon E5-2690 v3)
- ZFS: `datapool/niagara/` (base, vms/primary, vms/primary@clean)
- QEMU: `./qemu/build/qemu-system-sparc64` (upstream 8.2.2, no patches)
- Firmware: `/datapool/niagara/base/` (openboot.bin, q.bin, nvram1, etc.)

## Next action

Investigate q.bin binary to understand DMA target computation (P1-004).
Options:
- Disassemble q.bin, find vdisk I/O handling
- Instrument QEMU to log all partition RAM writes during vdisk I/O
- Look at whether illumos/Tribblix avoids this by using a different hypervisor

Parallel track: PPP over serial (add second UART, no q.bin involvement).
