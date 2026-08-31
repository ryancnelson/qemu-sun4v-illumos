# What is this disk lunacy, sir?

The Niagara machine does not yet have a conventional virtual NIC or a complete
interrupt-driven communications device.  It does, however, have a working
hSIMD block path.  The channel system deliberately reuses that path as a tiny
shared-memory transport.

QEMU attaches a small raw image as a dedicated hSIMD disk, conventionally unit
101.  A fixed byte range inside the image is divided into channel mailboxes.
Each mailbox contains two directions, sequence state, and bounded payload
storage.  The guest and host alternately poll those fields, copy bytes, and
advance sequence counters.  Neither side interprets those bytes as files or a
filesystem.

On the host, `tools/chan/host-chan.py` maps the image and presents each mailbox
as an ordinary Unix-domain socket.  A host application can therefore use
`socat`, `pppd`, the BBS, a proxy, or a test client without understanding the
disk layout.  In the guest, `guest-chand` performs the corresponding raw-device
polling and presents a local Unix socket or process endpoint.  This produces:

```text
host application
  <-> Unix socket
  <-> host-chan.py
  <-> mailbox bytes in unit 101
  <-> hSIMD block operations
  <-> guest-chand
  <-> guest application
```

It is intentionally a compatibility hack.  The guest already has the hSIMD
driver, QEMU already has the block device, and both directions work without
waiting for a new illumos network driver, PCIe model, LDC/VIO stack, or IRQ
delivery.  The cost is polling latency, needless block-I/O machinery, and
contention when channel traffic shares backing storage with real disks.

The mailbox is disposable runtime state.  It should be deterministically
initialized for every run and may be hosted on tmpfs for lower latency.  Its
image must never overlap boot media or a persistent root pool, and a stale
mailbox must never be promoted as part of a workstation artifact.  The durable
contract is the initializer, offsets, protocol version, unit number, and test
evidence—not the last bytes left by a live session.

Eight mailboxes are cheap insurance.  Provision them before boot so console
recovery, PPP, interactive shells, BBS, proxy experiments, bulk transfer, and
future control paths do not require changing virtual hardware and rebooting
the guest merely because only two endpoints were anticipated.

