#!/usr/bin/env python3
"""Static guardrails for the release appliance's scoped PPP/NAT helper."""

from pathlib import Path


root = Path(__file__).resolve().parents[1]
network = (root / "scripts" / "container-network.sh").read_text()
appliance = (root / "appliance").read_text()
dockerfile = (root / "Dockerfile.self-contained").read_text()

required_network = (
    "CHANNEL_HOST_BYTE=${NIAGARA_CHANNEL_HOST_BYTE:-520093696}",
    'python3 "$TOOLS/host-chan.py" init 0',
    'python3 "$TOOLS/host-chan.py" init 1',
    '"$TOOLS/host-pppd-once.sh" /run/niag0',
    'python3 "$TOOLS/host-bbs.py" /run/niag1',
    '-s "$GUEST_IP/32" -o "$wan" -j MASQUERADE',
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
    "OCI_GUEST_PPP_NAT=PASS",
):
    assert marker in appliance, marker

assert "COPY host-tools /opt/niagara-project/tools/chan" in dockerfile
print("NETWORK_HELPER_POLICY=PASS")
