# Current State

## What works

- Solaris 10 boots to login prompt in ~40 seconds (clean, verified)
- Root login, no password
- `/tmp` is tmpfs — writable in-session
- QEMU monitor accessible via `Ctrl-A c`
- `pmemsave` from monitor extracts guest RAM to host file (guest→host channel)
- Linux can mount the Solaris UFS read-only: `mount -t ufs -o ro,ufstype=sun`

## What is broken and why (fully traced)

### 1. Disk writes evaporate

**Root cause understood from q.bin source code.**

q.bin (`~/vms/opensparc/hypervisor/src/`) implements disk I/O via two direct
hypercalls compiled in under `CONFIG_DISK`:

| Hypercall | Number | Operation |
|-----------|--------|-----------|
| `hcall_disk_read` | 0xf0 | bcopy from vdisk_ram+offset → guest DMA buffer |
| `hcall_disk_write` | 0xf1 | bcopy from guest DMA buffer → vdisk_ram+offset |

q.bin has **no LDC implementation**. The Solaris vdc (virtual disk client) driver
uses LDC channels for runtime disk I/O. LDC requests hit an unimplemented handler
in q.bin and are silently dropped.

The disk size q.bin enforces: reads 4 bytes at offset 0x1d0 in the disk image
(the VTOC slice 2 nblk field). That value is 0x00100000 big-endian = 1,048,576
blocks × 512 bytes = **512MB**. Disk size is correct.

**Open question:** if vdc uses LDC (which q.bin doesn't implement), why do disk
reads work at all during runtime? Possible explanations:
- The disk.s10hw2 kernel uses direct hypercalls (0xf0/0xf1) rather than LDC
- q.bin routes LDC disk requests to hcall_disk_read internally (unknown without
  disassembling the working q.bin binary)
- The kernel's buffer cache masks read failures after initial boot

Next step: read illumos `usr/src/uts/sun4v/io/vdc.c` to determine which path
the kernel uses, or trace hypercall execution with QEMU's GDB server.

### 2. Adding memory to guest physical address space panics the kernel (P1-004)

**Root cause: q.bin DMA target changes when physical address space changes.**

Every attempt to add a flat memory block device (flatblk) at any physical address
causes a deterministic kernel panic in `ufs:fetchbuf` during `vfs_mountroot`:

```
BAD TRAP type=10 (illegal instruction)
pc=0x300005e7840  ← data buffer address executed as code
Stack: fetchbuf → readlog → lufs_read_strategy → vfs_mountroot → main
```

Four approaches tried, all identical panic:
- New RAM region at 0x1f50000000 (device space)
- New RAM region at 0x400000000 (above guest RAM)
- `memory_region_init_ram_ptr` (user-supplied buffer, cannot be moved by QEMU)
- Extended vdisk_ram to 768MB (no new region, same panic)

Instrumentation confirmed: vdisk_ram host pointer does NOT move. The panic is not
from QEMU relocating RAM allocations.

Working hypothesis: q.bin's DMA path in `hcall_disk_write` does
`bcopy(dma_buffer_host, disk_pa + disk_offset, size)`. When the physical address
space changes, something in q.bin's address translation changes the DMA target,
causing a write to a kernel stack frame, corrupting a SPARC64 register window
(`%i7` = return address), producing the illegal instruction jump.

Without q.bin source-level debugging (requires Sun Studio + Solaris/SPARC to
rebuild), this cannot be verified further without binary analysis.

**CRITICAL:** atexit fires on panicked QEMU exit. Always `zfs rollback
datapool/niagara/vms/primary@clean` after any panicked run or the zvol gets
corrupted.

### 3. No networking
Niagara machine has no PCI/virtio bus. No NIC can be attached.
OBP shows `net /virtual-devices/network@0` in devalias but QEMU doesn't back it.

### 4. OBP traps after guest reboot
Must exit QEMU and restart after any guest reboot.

## q.bin provenance

q.bin lives at `~/vms/opensparc/hypervisor/src/greatlakes/ontario/` in multiple
variants. The working binary (`/datapool/niagara/base/q.bin`) is unique — smaller
than all source-tree builds and the only one that works under QEMU:

| Binary | Size | Works under QEMU |
|--------|------|-----------------|
| S10image/q.bin (current) | 163KB | Yes |
| ontario/release/q.bin | 205KB | No (hangs) |
| ontario/legion/q.bin | 190KB | No (hangs) |
| ontario/debug/q.bin | 246KB | No (hangs) |

All non-working variants require SAM/Legion runtime APIs not present in QEMU.
The working binary was pre-built specifically for the QEMU simulation environment.

The hypervisor source is in `~/vms/opensparc/hypervisor/src/`. It requires
`qas` (custom Sun SPARC assembler) and Sun Studio to build — unavailable on
this Linux host. Cross-compilation path not yet attempted.

## Data channels (working today)

**Guest → Host:** Write to `/tmp` (tmpfs), then from QEMU monitor:
```
(qemu) pmemsave 0x88000000 0x8000000 /datapool/niagara/dump.bin
```
Search `dump.bin` for file contents on host.

**Host → Guest:** Modify disk image from host before boot.
```bash
sudo mount -t ufs -o ro,ufstype=sun /dev/zvol/datapool/niagara/vms/primary /mnt/sol
# copy files in (read-only Linux UFS mount — cannot write)
```
For writable injection: not yet solved cleanly. Can stage files in the zvol by
converting the image, but Linux UFS write support for Solaris format is broken.

## Environment

- Host: biggie (Linux x86, Xeon E5-2690 v3)
- ZFS: `datapool/niagara/` — base (firmware ROMs), vms/primary, vms/primary@clean
- QEMU: `./qemu/build/qemu-system-sparc64` (upstream 8.2.2, no patches applied)
- Firmware: `/datapool/niagara/base/` (openboot.bin, q.bin, nvram1, etc.)
- Hypervisor source: `~/vms/opensparc/hypervisor/src/`
- Project repo: `http://biggie:3000/ryan/niagra-qemu-solaris-project`

## How to run a loop (iterate-bot)

1. Read `BACKLOG.md`, pick top item
2. Write the failing test covering it
3. Fix it — in QEMU source, q.bin source (if buildable), or OS source
4. Verify: `sudo QEMU_BIN=./qemu/build/qemu-system-sparc64 bash tests/run-all.sh`
5. **Always** `zfs rollback datapool/niagara/vms/primary@clean` if QEMU panicked
6. Commit with observed evidence, update BACKLOG
7. Repeat

## Next actions (priority order)

1. **Determine disk write path:** Read `usr/src/uts/sun4v/io/vdc.c` in illumos-gate
   to see whether vdc uses direct hypercalls (0xf0/0xf1) or LDC at runtime.
   If direct hypercalls: writes should be reaching vdisk_ram; re-examine atexit.
   If LDC: writes are silently dropped; need to implement LDC in QEMU or patch
   the kernel to use direct hypercalls.

2. **PPP/second serial port:** One `serial_mm_init` call in niagara.c, pppd on
   both sides → IP link → iSCSI over PPP → writable block storage. No q.bin
   involvement anywhere in this path.

3. **Attempt q.bin cross-compilation:** Install `binutils-sparc64-linux-gnu`
   and check if `qas`/`sas` can be replaced with standard SPARC64 assembler.
   If buildable, add printf debug to `hcall_disk_write` and observe.

---

## Disk Status (Updated 2026-08-17)

**2GB disk working.** Snapshot `primary@clean-2gb` = 1.9GB filesystem, 1.6GB free.

To restore after a panic:
```bash
sudo zfs rollback -r datapool/niagara/vms/primary@clean-2gb
sudo zfs set volsize=2G datapool/niagara/vms/primary
# VTOC already correct in snapshot — no Python script needed
```

Key bugs fixed to get here (all documented in commit 2b04712):
- `int` → `int64_t` for blk_getlength (overflows at exactly 2GB = INT_MAX+1)
- blk_pread returns 0 on success in QEMU 8.2, not byte count
- Reset handler loads disk in 64MB chunks — no ROM subsystem, no temp files
- Sun VTOC checksum at 0x1fe must be recomputed after editing nblks (OBP validates it; QEMU does not)
- write() of >2GB in one call may short-write — use chunked 64MB writes
- ZFS rollback race: always rollback BEFORE starting QEMU, never racing with atexit pwrite
- ZFS rollback also reverts volsize — must re-grow after each rollback to @clean

**Next:** pkgadd gcc4core from OpenCSW (http://mirror.opencsw.org/opencsw/stable/sparc/5.10/)
