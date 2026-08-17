# Current State

Last verified: 2026-08-17. Everything below is backed by a passing test or a
recorded measurement. Claims without evidence are marked UNVERIFIED.

## Test suite: 4/4 passing

```
sudo QEMU_BIN=$PWD/qemu/build/qemu-system-sparc64 bash tests/run-all.sh
  PASS  test-boot-to-login
  PASS  test-disk-writes-persist
  PASS  test-md-roundtrip
  PASS  test-reboot-obp-intact
```

Runs in ~3.5 min. Each VM test clones its own throwaway zvol from
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

3. **No second serial (`ttyb`).** `console@1` gets its unit address from
   `cfg-handle = 0x1` in the MD. A `ttyb` would need a second console node with
   `cfg-handle = 0x4` plus a QEMU-side UART. Now tractable — the MD is text.

4. **`test-reboot-obp-intact` is a weak test.** It matches `"ok"` and then
   `"disk"` in `devalias` output, both of which appear in plenty of unrelated
   output. It passes, but it is not strong evidence OBP is truly healthy after
   a reboot. The guest still prints
   `panic - kernel: prom_reboot: reboot call returned!` on reboot.

5. **`exchange` zvol (569MB) is vestigial.** A FAT32 host/guest exchange
   partition experiment. Solaris never saw it — a second `-drive` isn't visible
   without an MD node. Safe to destroy.

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

1. **`console@4` / ttyb** — add a second console node to `common.pdesc`
   (`cfg-handle = 0x4`, `channel# = 1`), regenerate the MD, add a matching
   UART in `niagara.c`, expose it host-side as a PTY. Gives a second data
   channel usable with `screen` + `sz`/`rz`.
2. **Get a compiler in.** With a working data channel, install gcc4core from
   OpenCSW (`http://mirror.opencsw.org/opencsw/stable/sparc/5.10/`, ~137MB
   compressed) into the 1.6GB free space. Then a locally built `format` that
   ignores the controller name becomes possible.
3. **Strengthen `test-reboot-obp-intact`** so it asserts something real.
