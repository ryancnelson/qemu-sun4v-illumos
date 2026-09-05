# Experimental Ethernet over channel2

These Python3 probes and relays were exercised on a running OpenIndiana
Hipster2025.12 SPARC SMP guest and a Linux container on September4,2026.
Original project code is covered by the repository CDDL1.0 license.

| Program | Purpose |
| --- | --- |
| `dlpi-local-probe.py` | Verify complete frames between ce_ip0 and ce_wire0 through an etherstub |
| `ethernet-channel-probe.py` | Verify one frame each way through the switch and shared-disk channel |
| `ethernet-ip-relay.py` | Relay length-framed Ethernet between native DLPI or Linux TAP and a channel socket |

Read the [notebook](../../notes/OPENINDIANA-SMP-CHANNEL-ETHERNET-CHARTER-2026-09-04.md)
before attempting reproduction. These are diagnostic scripts with explicit
experiment names and addresses, not an automatic network installer. They do
not initialize channels, install guest drivers, create guest VNICs, or select
safe disk offsets. Verify those independently. Never attach another reader
or writer to an occupied channel.

The relay requires an already-working hsimd channel with host-chan and
guest-chand endpoints. Guest requirements are Python3, native libdlpi, root
DLPI privileges, and working dladm/ipadm. Linux needs Python3, iproute2,
/dev/net/tun access and NET_ADMIN in the intended network namespace.

```sh
# After creating temporary ce_stub0, ce_ip0 and ce_wire0 as in the notebook:
python3 dlpi-local-probe.py
# Separate endpoints for the bounded frame test:
python3 ethernet-channel-probe.py host /run/niag2
python3 ethernet-channel-probe.py guest /tmp/ce-niag2
# Once the frame clients have exited, the sustained diagnostic relay:
python3 -u ethernet-ip-relay.py host /run/niag2 ce_tap0
python3 -u ethernet-ip-relay.py guest /tmp/ce-niag2 ce_wire0
```

Host mode creates a nonpersistent TAP at10.77.0.1/24, MAC02:ce:00:00:00:02,
MTU1500. Guest ce_wire0 must use that MAC; ce_ip0 used02:ce:00:00:00:01 and
10.77.0.2/24. Check for route/address conflicts first. No NAT/default route is
configured. Stop only the identified relay/helper to close TAP; never stop
QEMU as network cleanup.

The stream format is a network-order uint32 length followed by that many raw
Ethernet bytes, without a TAP packet-information header. Current parser bounds
are14–9018 bytes, inherited from the initial experiment; the supported target
for subsequent work is ordinary MTU1500, with jumbo support out of scope.
First local-test OI IPv4 MTU remained9000; `ifconfig ce_ip0 mtu 1500` was then
applied and read back before the successful outbound HTTPS test.

Probe checks use Python assertions; do not run probes with `python -O`.
Relays exit on protocol/stream errors, have no reconnect supervisor, and log
every frame. They are not a hardened network service or throughput benchmark.
A local64KiB TCP echo, bounded pings, DNS and outbound HTTPS have passed.

## Optional outbound access, separately authorized

The recorded container already had IPv4 forwarding enabled and FORWARD policy
ACCEPT. Preserve any existing firewall rules. Inside that network namespace,
the additional rule was:

```sh
iptables -t nat -A POSTROUTING -s 10.77.0.2/32 -o eth0 \
  -m comment --comment ce-channel2-egress -j MASQUERADE
# Guest, nonpersistent:
route add default 10.77.0.1
ifconfig ce_ip0 mtu 1500
```

Do not repeat the append blindly; inspect or use `iptables -C` first. Do not
apply this in the host namespace. A different container with forwarding off
or restrictive filters needs its own scoped configuration, not table flushing.
For rollback use the exact rule with `-D`, and `route delete default 10.77.0.1`.

Guest DNS also requires the appropriate NSS configuration. Ryan's working
OI state was `hosts: files dns` and `ipnodes: files dns` in
`/etc/nsswitch.conf`, plus `nameserver 8.8.8.8` in `/etc/resolv.conf`.
Inspect and preserve other entries; do not overwrite either whole file with
this excerpt. Solaris11 may manage these settings through services, so verify
its active configuration independently.
