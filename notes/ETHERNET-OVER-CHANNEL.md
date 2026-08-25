# Ethernet over a shared-disk channel

## The epiphany

PPP is not required to give Tribblix ordinary networking.  illumos already has
the two kernel facilities needed on the guest side:

- VNICs and etherstubs provide a software Ethernet switch.
- DLPI lets a userland program send and receive complete Ethernet frames.

The existing `niag` shared-disk channel can carry those frames to a Linux TAP
interface.  This avoids importing Solaris 10 PPP kernel modules, which proved
unsafe on Tribblix m34, and requires no new illumos kernel driver.

```text
Tribblix IP stack
      |
    vnic0
      |
   estub0             illumos virtual Ethernet switch
      |
    wire0
      |
 DLPI frame relay
 /tmp/niag2
      |
 shared-disk channel
      |
 /run/niag2
      |
 Linux frame relay
      |
    tap0
      |
 Linux routing, NAT, bridge, or DHCP
```

`vnic0` belongs to the Tribblix IP stack.  `wire0`, on the same etherstub,
belongs to a small userland DLPI relay.  The implicit switch between them makes
`wire0` the guest-facing Ethernet port for the channel.

## Guest link construction

The intended temporary experiment is:

```sh
dladm create-etherstub -t estub0
dladm create-vnic -t -l estub0 vnic0
dladm create-vnic -t -l estub0 wire0

ipadm create-ip vnic0
ipadm create-addr -T static -a 10.77.0.2/24 vnic0/v4
```

Measured on the Tribblix checkpoint on 2026-08-21: both `dladm` creations
succeeded.  `proxy_stub0` and `proxy_vnic0` appeared `up` with a generated MAC.
IP configuration did not succeed: `ipadm` reported `Could not open handle to
library - Operation failed`, while legacy `ifconfig ... plumb` aborted with
`Address family not supported by protocol family` because the image's IPv6/IP
administration substrate is incomplete.  Therefore the first prerequisite is
to diagnose and restore `ipmgmtd` / `svc:/network/ip-interface-management` and
the socket-provider configuration.  The VNIC data-link layer itself works.

## Guest DLPI relay

Implement a small C program using `libdlpi`:

1. Open `wire0` and bind it for raw Ethernet access.
2. Enable the appropriate raw/promiscuous mode, including physical-level
   reception so broadcasts and frames for the TAP-side MAC are visible.
3. Receive complete frames with `dlpi_recv()`.
4. Write a length prefix followed by the Ethernet frame to `/tmp/niag2`.
5. Read framed packets in the other direction and inject them with
   `dlpi_send()`.

The relay must handle partial socket reads/writes, EOF and reconnects.  Enforce
a maximum frame size derived from the configured MTU plus Ethernet/VLAN headers.
There must remain exactly one channel reader/writer in each direction.

Initial framing can be deliberately boring:

```text
uint32 network-order frame_length
frame_length bytes of raw Ethernet frame
```

For the first experiment, explicitly coordinate MAC addresses.  The simplest
choice is to give `wire0` and Linux `tap0` the same MAC.  Otherwise the relays
must preserve source addresses and the virtual switch must learn that the TAP
MAC is reachable through `wire0`.

## Linux relay

The host-side program connects `/run/niag2` to a TAP file descriptor:

- TAP frame -> length prefix + frame -> channel socket
- channel socket -> validate length -> TAP frame

Once `tap0` receives frames, Linux can assign `10.77.0.1/24`, route and
masquerade, bridge the TAP to another link, or run DHCP.  Tribblix then sees
normal Ethernet and can use ARP, IPv4, IPv6, ICMP, TCP, NFS and SSH without
special handling in applications.

## Validation order

1. Repair illumos IP administration and assign `10.77.0.2/24` to `vnic0`.
2. Prove local switching between `vnic0` and a DLPI probe on `wire0`.
3. Prove one Ethernet frame in each direction through channel 2.
4. Create `tap0`, assign Linux `10.77.0.1/24`, and prove ARP.
5. Ping `10.77.0.1` from Tribblix.
6. Add Linux forwarding/NAT and test DNS plus HTTP.
7. Test SSH, NFS, loss, MTU and sustained throughput.
8. Only after the live proof, batch the relays and service definitions into an
   image build.

Use a fresh or explicitly reinitialised channel with both old endpoints stopped
before each failed-test retry.  Channel 2 is preferred so channel 0 remains
available for historical PPP work and channel 1 for the BBS.

## Why this is preferable to PPP

The Solaris 10 PPP payload loaded once but became unsafe: `pppd` entered a rapid
failure/spawn loop, and the modified Tribblix image was not suitable for the
next boot.  Ethernet over DLPI uses native illumos interfaces and keeps all new
code in userland.

It also removes PPP negotiation, async framing and `asyncmap 0xffffffff` byte
escaping.  The shared channel remains the throughput ceiling, but Ethernet
frames should approach its measured hundreds-of-KiB/s range much more closely
than NFS over the existing escaped PPP link.

## Existing transport and bootstrap assets

- `tools/chan/host-chan.py` and `guest-chand` provide the byte stream.
- The BBS on channel 1 can fetch or mailbox guest relay sources and binaries
  without working IP networking.
- The guest already contains GCC 7 at `/usr/versions/gcc-7/bin/gcc` through the
  `/usr/bin/gcc` symlink, plus the channel C sources.
