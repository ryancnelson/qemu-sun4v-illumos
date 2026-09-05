# Ethernet over a disk, on a virtual T2000

On September 4, 2026, an OpenIndiana SPARC guest running on QEMU Niagara sent
ordinary IP packets through a shared-disk channel. ARP worked. Pings succeeded
in both directions. A TCP connection sent 65,536 bytes to Linux and received
an identical echo. PPP had no active interface on either side.

The guest was already booted, with two CPUs online. It stayed running through
the experiment. The Linux endpoint was inside Docker on Biggie; no TAP,
bridge, or NAT rule was added to Biggie's host network namespace.

## A plan from August, tested in September

The project's [Ethernet-over-channel design](notes/ETHERNET-OVER-CHANNEL.md)
already described the necessary pieces: an illumos etherstub, two VNICs,
`libdlpi`, a shared-disk byte channel, and a Linux TAP interface. An August 21
Tribblix experiment had created virtual links but failed at IP administration.
The later [OpenIndiana basecamp session](THE-OPENINDIANA-BASECAMP-STORY.md)
used PPP to reach the Internet. Ethernet remained unfinished work.

During the September Solaris 11 installer recovery, disk channels came up
again as a way to move tools into a guest without a working NIC. Ryan wanted
the Ethernet experiment recorded as a project milestone. He supplied a
running OpenIndiana SMP VM in the `smpchanneleth` tmux session so it could be
tested independently of the still-running Solaris 11 guest.

That separation matters: this session proves the Ethernet path on
OpenIndiana Hipster 2025.12, kernel `illumos-31d3d510d0`. It does not establish
Solaris 11 compatibility. The VM uses the project's Niagara stack, building
on Masayuki Murayama's QEMU, firmware, and SMP work; this experiment adds the
userland network path.

## The guest already had a software switch

Temporary `dladm` commands created `ce_stub0`, with `ce_ip0` for the IP stack
and `ce_wire0` for the relay. Their fixed MAC addresses ended in `01` and `02`.
Python's `ctypes` called the guest's native `libdlpi.so.1`; no new guest kernel
driver was needed for the Ethernet portion.

The first test stayed inside the guest. A small probe sent a complete
Ethernet frame from one VNIC to the other, then reversed direction. Both
78-byte frames matched exactly. That established the switch and raw DLPI
operations before adding disk transport.

```text
OpenIndiana IP stack
  -> ce_ip0 -> ce_stub0 -> ce_wire0
  -> Python/libdlpi relay -> guest-chand channel 2
  -> shared disk mailbox -> host-chan channel 2
  -> Python/TAP relay -> Linux IP stack
```

Channel 2 was verified unused, including a zero check of its entire 1 MiB
region, before initialization. Channels 0 and 1 retained their existing PPP
and BBS helpers. In this run the channel region was on unit100, starting at
byte327680, with channel2 at byte2424832. Those are measured trial mappings;
older project launchers use different disk layouts.

A four-byte network-order length precedes each frame on the Unix socket
stream. At 01:56:23 UTC on September 5, still September 4 locally, a frame
crossed into the Linux container. The container exchanged its source and
destination MACs and sent it back. OpenIndiana injected that reply through
`ce_wire0` and received the identical frame at `ce_ip0`. Both endpoints logged
matching hashes. That test proved frame transport, before either side had an
experiment IP address.

## TAP without restarting the VM

The VM container had `CAP_NET_ADMIN`, but only `/dev/ppp` was passed through.
It had no `/dev/net/tun`. Ryan approved arranging container-local TAP access
without restarting the guest or altering the host network.

A separate helper container shared the VM container's network namespace. It
received only `NET_ADMIN`, the TUN device, the channel2 socket, and a read-only
copy of the relay source. It did not receive the VM disks.

The first helper failed before startup: Docker rejected a socket bind through
`/proc/<pid>/root`. Comparing device and inode numbers identified the same
socket through the container's ordinary backing path. A second helper using
that path started successfully. The failed container and error were retained
as evidence. A packaged version should use an explicit shared socket
directory instead of a live Docker overlay path.

Ryan suggested `socat`; the installed build did support TUN. The experiment
kept the small Python relay because Ethernet frame boundaries needed to
survive the existing byte-stream channel. QEMU's TAP and SLIRP backends were
also discussed. They still need a guest NIC frontend and driver path; the
disk channel supplies that connection for this Niagara setup.

## ARP, ping, and a real TCP connection

The helper created `ce_tap0` at `10.77.0.1/24`. OpenIndiana received
`10.77.0.2/24` on `ce_ip0`. TAP used the relay VNIC's MAC, allowing unicast
replies to reach the expected switch port. No guest default route or NAT was
added.

OpenIndiana sent three pings and received all three replies. Average RTT was
184.396 ms. Linux's reverse test also received all three replies, averaging
166.140 ms. The Linux neighbor table resolved the guest's MAC, and relay logs
recorded the ARP and ICMP frames.

A one-shot TCP server listened only on the isolated TAP address. The guest
sent `bytes(range(256)) * 256`, received the echo, and compared every byte.
At guest time 02:06:35 UTC it printed `TCP_64K_ROUNDTRIP_PASS`. The payload
SHA-256 at both ends was:

```text
7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2
```

Interface inspection confirmed that PPP was inactive. Its existing channel0
helper remained untouched. These packets travelled over Ethernet on channel2.

## The next version can be ordinary Ethernet

The selected scope is MTU1500. The first local test left OI at its default
9000 while TAP used1500. Before testing HTTPS, `ifconfig ce_ip0 mtu 1500`
set the guest IPv4 interface to1500. Jumbo frames are out of scope.

The relay is diagnostic source: it logs every frame and exits on a broken
stream. This session did not measure sustained throughput or package automatic
startup. The TCP test's listener closed after its one connection; the relays
and both VMs were left running.

## Out to the Internet

Ryan then asked for outbound networking, with the Solaris11 installer as the
next intended consumer. The OI container already had IPv4 forwarding enabled.
A single container-local MASQUERADE rule covered source10.77.0.2 leaving eth0;
the guest gained a temporary default route through10.77.0.1. Existing PPP
rules and Biggie's host network configuration stayed unchanged.

Public-IP ping received3/3 replies. Ryan supplied another necessary part of
the recipe: the `hosts:` line in `/etc/nsswitch.conf` needed `files dns`.
Readback showed both `hosts: files dns` and `ipnodes: files dns`, with
`nameserver 8.8.8.8` in `/etc/resolv.conf`. A resolver address alone is not
the complete guest DNS configuration.

At02:18:52 UTC, Python resolved example.com and fetched its HTTPS page with
the default certificate-verifying TLS context: HTTP200,559 bytes. This is the
session's outbound application-traffic proof. Solaris11 remained untouched;
its installer still needs its own native-library, channel and networking
checks before reusing the approach.

The [experiment notebook](notes/OPENINDIANA-SMP-CHANNEL-ETHERNET-CHARTER-2026-09-04.md)
contains the identities, exact commands, source hashes, failure record, and
locations and hashes of the privately retained console evidence. Reproduction
source is in [tools/chan](tools/chan/README-ethernet.md). No Oracle binaries or
full vendor-code console captures accompany this publication.
