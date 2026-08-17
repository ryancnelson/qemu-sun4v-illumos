# Current State

Last verified: 2026-08-17. Everything below is backed by a passing test or a
recorded measurement. Claims without evidence are marked UNVERIFIED.

## Test suite: 5 tests

```
sudo QEMU_BIN=$PWD/qemu/build/qemu-system-sparc64 bash tests/run-all.sh
  PASS  test-boot-to-login
  PASS  test-disk-writes-persist
  PASS  test-exchange-channel      <- host->guest bulk data transfer
  PASS  test-md-roundtrip
  PASS  test-reboot-obp-intact     <- FLAKY, see Known gaps #4
```

Runs in ~5-7 min. `test-reboot-obp-intact` intermittently times out waiting for
the login prompt; boots occasionally exceed even the 180s timeout under load
because each one loads 2-2.5GB into RAM and writes it back on exit. Each VM test clones its own throwaway zvol from
`primary@clean-2gb` and destroys it on exit, so tests cannot corrupt each
other or the daily driver.

## What works

- **Solaris 10 boots** to a login prompt in ~40s. Root, no password.
- **Disk writes persist.** Verified end-to-end: write to `/etc`, clean exit,
  canary found in the raw zvol, then a *second boot* reads the file back and
  the image is still bootable. This is `test-disk-writes-persist`.
- **2GB disk**, 1.9GB UFS, ~1.6GB free.
- **Machine Descriptions are editable as text.** `1up-md.bin` / `1up-hv.bin`
  regenerate byte-identically from `.pdesc`/`.hdesc` source via a locally
  built `mdgen`. Guarded by `test-md-roundtrip`.
- OBP survives a guest `reboot` far enough to answer `devalias`
  (`test-reboot-obp-intact`). Note this is a weak assertion — see Known gaps.
- Perl 5.8.4 is present in the guest (`/usr/bin/perl`). No python.
- **Bulk host -> guest data channel** via a raw VTOC slice. Verified
  byte-for-byte: a 256KB random binary transfers with a matching `cksum`
  (`test-exchange-channel`). See "Data channel" below.

## How storage actually works

Guest writes go:

```
UFS -> hcall_disk_write (0xf1) -> q.bin -> vdisk_ram (host RAM)
                                              |
                          QEMU atexit handler | pwrite in 64MB chunks
                                              v
                                    zvol (persistent)
```

Confirmed by direct measurement: after a guest write, the canary is present
in QEMU's `vdisk_ram` region read live from `/proc/<pid>/mem` (the 2GB
writable mapping whose first bytes are the `SUN...` disk label).

q.bin uses **direct hypercalls (0xf0 read / 0xf1 write), not LDC.** There is
no LDC implementation in the hypervisor source. This resolves the old open
question in the backlog (P1-005).

### EXIT PROCEDURE — not optional

```
lockfs -f / && sync        (inside Solaris)
Ctrl-A c , quit            (QEMU monitor)
```

`lockfs -f /` commits the UFS logging (LUFS) journal. Skip it and the atexit
writeback persists an image with a dirty journal; the next boot panics
replaying it:

```
BAD TRAP type=10  ufs:fetchbuf -> readlog -> lufs_read_strategy -> vfs_mountroot
```

Recover with `./run-solaris.sh reset`.

## Known gaps

1. **No networking.** The Niagara machine has no PCI or virtio bus. OBP lists
   `net -> /virtual-devices/network@0` in `devalias` but no such node exists in
   the device tree and QEMU backs nothing. `iscsi` and `scsi_vhci` are loaded
   and force-attached in the guest, waiting for a network that isn't there.

2. **`format(1M)` refuses the disk.** It reports
   `controller name (SUNW,sun4v-virtual) is invalid`. `format` validates
   against a compiled-in controller table containing only `SCSI`, `ata`,
   `pcmcia`; this cannot be fixed via `/etc/format.dat` (the `ctlr` field there
   is a controller *class*, not a name). `iostat -En` is also blank for the same
   reason. Use `fmthard`, `newfs`, `prtvtoc`, and `dd`, which don't consult it.

3. **No second serial (`ttyb`) — blocked in the guest, not fixable from here.**
   Adding a `console@4` node to the MD works: OBP enumerates it
   (`show-devs` lists `/virtual-devices@100/console@4`). But Solaris will not
   bind a driver to it — `prtconf` shows `console (driver not attached)` and
   `/dev/term/` still has only `a`. Cause, from illumos
   `usr/src/uts/sun4v/io/qcn.c`: line 347 *"There is only once instance of this
   driver"*, and line 87 `static qcn_t *qcn_state;` — one global, not
   per-instance. `qcn` is a singleton by construction. Fixing it means
   rebuilding the guest driver, which needs a compiler in the guest, which is
   circular. The node stays in `md/common.pdesc`, documented, and the
   regenerated MD is deliberately NOT installed. Superseded by the exchange
   slice below.

4. **`test-reboot-obp-intact` is weak AND flaky.** It intermittently times out
   waiting for the login prompt (seen once in five runs). It matches `"ok"` and then
   `"disk"` in `devalias` output, both of which appear in plenty of unrelated
   output. It passes, but it is not strong evidence OBP is truly healthy after
   a reboot. The guest still prints
   `panic - kernel: prom_reboot: reboot call returned!` on reboot.

5. **`exchange` zvol (569MB) is vestigial.** An early FAT32 attempt that used a
   second `-drive`, which Solaris cannot see without an MD node (and q.bin
   tracks only one disk anyway — a single `disk_pa` in `vdev_simdisk.s`). Safe
   to destroy; superseded by the exchange *slice*.

## Data channel (host -> guest bulk transfer)

q.bin serves the whole vdisk, and its size comes from VTOC slice 2's `nblk` at
offset 0x1d0. Slices are just byte offsets into that same disk — so an unused
slice is readable in the guest as `/dev/rdsk/c0t0d0sN` with **no new MD node,
no new QEMU device, no q.bin change and no new driver.**

```
s0  blocks       0 .. 4194295   2048MB  root UFS (untouched)
s3  blocks 4194304 .. 5242879    512MB  exchange, raw, no filesystem
s2  blocks       0 .. 5242879   2560MB  whole disk -> q.bin's served size
```

Host:
```bash
tools/exchange.sh setup datapool/niagara/vms/primary   # grow + lay out s3
tar cf payload.tar -C payload .
tools/exchange.sh push  datapool/niagara/vms/primary payload.tar
```
Guest:
```
dd if=/dev/rdsk/c0t0d0s3 bs=512 count=<blocks> 2>/dev/null | tar xvf -
```

Slice 2 MUST cover the exchange slice or q.bin will not serve those blocks —
`tools/vtoc.py verify` checks exactly that. `tools/vtoc.py` also recomputes the
label checksum at 0x1fe on every write; OBP validates it and rejects the disk
with "Bad checksum in disk label" if it is wrong, while QEMU does not check it.

Cost: the served size is allocated as anonymous host RAM, so a 2560MB disk uses
2560MB per running VM and moves that much on every boot and every clean exit.

Solaris `/bin/sh` is not POSIX — no `$(...)`. Use backticks in payload scripts.

## Environment

- Host: biggie (Linux x86_64, Xeon E5-2690 v3)
- QEMU: `./qemu/build/qemu-system-sparc64`, upstream 8.2.2 +
  `patches/0001-niagara-vdisk-writeback.patch`
- Firmware: `/datapool/niagara/base/` (openboot.bin, q.bin, nvram1, 1up-*.bin)
- Hypervisor + MD source: `~/vms/opensparc/`
- MD source of record: `~/vms/opensparc/legion/src/config/niagara/{1up,common}.pdesc`
- Repo: `http://biggie:3000/ryan/niagra-qemu-solaris-project`

### ZFS layout

```
datapool/niagara/base                    firmware ROMs (filesystem)
datapool/niagara/vms/primary             daily driver zvol
datapool/niagara/vms/primary@clean       pristine 512MB original image
datapool/niagara/vms/primary@clean-2gb   1.9GB UFS, 1.6GB free   <-- baseline
datapool/niagara/vms/test-<name>-<pid>   ephemeral test clones
```

`zfs rollback` reverts `volsize` to the snapshot's value. `@clean-2gb` was
taken at `volsize=2G` with a matching 2GB VTOC, so it is self-consistent and
needs no re-grow. `primary` is currently 3G (grown during the FAT32
experiment); `./run-solaris.sh reset` returns it to 2G.

## Operating it

```bash
./run-solaris.sh            # boot primary (takes the zvol lock)
./run-solaris.sh status     # zvol/snapshot state + lock holder
./run-solaris.sh reset      # rollback primary to @clean-2gb
sudo bash tests/run-all.sh          # full suite
sudo bash tests/reap-orphans.sh     # reclaim leaked test clones
bash tools/build-mdgen.sh           # build the MD compiler
bash tools/gen-md.sh src.pdesc out.bin
```

## Next actions

1. **Get a compiler in.** The channel exists and is tested. Fetch gcc4core +
   deps from OpenCSW (`http://mirror.opencsw.org/opencsw/stable/sparc/5.10/`,
   ~137MB compressed) — note the 512MB exchange slice holds it, but check the
   installed size against the 1.6GB free. Then `pkgadd -d` from the extracted
   payload. First thing to build once it works: a `format(1M)` that does not
   reject the `SUNW,sun4v-virtual` controller name (Known gaps #2).
2. **Strengthen and de-flake `test-reboot-obp-intact`** so it asserts something
   real and stops timing out.
3. `ttyb` is parked — blocked on the qcn singleton (Known gaps #3).
