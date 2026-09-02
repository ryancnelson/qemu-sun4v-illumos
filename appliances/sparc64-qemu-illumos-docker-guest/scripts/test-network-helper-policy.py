#!/usr/bin/env python3
"""Static guardrails for the release appliance's scoped PPP/NAT helper."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
network = (root / "scripts" / "container-network.sh").read_text()
appliance = (root / "appliance").read_text()
dockerfile = (root / "Dockerfile.self-contained").read_text()
bring_up = (root / "guest-assets" / "BRING_UP_NETWORKING.sh").read_text()
call_bbs = (root / "guest-assets" / "CALL_BBS.sh").read_text()

required_network = (
    "CHANNEL_HOST_BYTE=${NIAGARA_CHANNEL_HOST_BYTE:-327680}",
    'python3 "$TOOLS/host-chan.py" init 0',
    'python3 "$TOOLS/host-chan.py" init 1',
    '"$TOOLS/host-pppd-once.sh" /run/niag0',
    'python3 "$TOOLS/host-bbs.py" /run/niag1',
    'CHAN_TRACE=1 python3 "$TOOLS/host-chan.py" bridge 1',
    '-s "$GUEST_IP/32" -o "$wan" -j MASQUERADE',
    'dnsmasq --keep-in-foreground --bind-dynamic --interface=ppp0',
    'tinyproxy -d -c "$proxy_config"',
    'Allow $GUEST_IP',
    'write_status ready',
    'asyncmap 0',
)

for marker in required_network[:-1]:
    assert marker in network, marker

pppd_path = root / "host-tools" / "host-pppd-once.sh"
if not pppd_path.exists():
    pppd_path = root.parents[1] / "tools" / "chan" / "host-pppd-once.sh"
pppd = pppd_path.read_text()
assert required_network[-1] in pppd
assert "iptables -F" not in network
assert "iptables -t nat -F" not in network

for marker in (
    "--cap-add NET_ADMIN",
    "--device /dev/ppp",
    "--sysctl net.ipv4.ip_forward=1",
    "/jack/BRING_UP_NETWORKING.sh",
    "/jack/CALL_BBS.sh",
    "OCI_GUEST_PPP_NAT=PASS",
):
    assert marker in appliance, marker

for marker in (
    "/opt/niag/bin/guest-chand",
    "/opt/niag/bin/guest-ppp-chan.pl",
    "NETWORKING=PASS",
):
    assert marker in bring_up, marker
assert "/opt/niag/bin/socat" in call_bbs

assert "COPY host-tools /opt/niagara-project/tools/chan" in dockerfile
assert "dnsmasq-base" in dockerfile
assert "tinyproxy" in dockerfile
assert "HEALTHCHECK" in dockerfile
print("NETWORK_HELPER_POLICY=PASS")
