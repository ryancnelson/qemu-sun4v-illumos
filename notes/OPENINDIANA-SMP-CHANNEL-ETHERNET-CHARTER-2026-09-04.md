# OpenIndiana SMP Ethernet-over-channel: charter and first-success notebook

## Historical intent

Ryan identified Ethernet-over-shared-disk-channel as a major project goal, not an incidental Solaris installer workaround. Preserve firsts and failed hypotheses explicitly. Prior architecture and Tribblix observations are in `notes/ETHERNET-OVER-CHANNEL.md`; existing OpenIndiana PPP transport is documented separately. Do not describe Ethernet relay as already proven.

Solaris11.4 trial33 remains running on Biggie and OUT OF SCOPE for this first Ethernet test. Its successful driver/media recovery motivated this experiment but is not Ethernet evidence.

## Authorized test lane and baseline

Ryan supplied Biggie tmux `smpchanneleth`, ready at the OpenIndiana root console. Linux transport endpoint is Docker container `openindiana-smp-demo`, NOT Biggie's host network namespace.

- Container ID `4906862b99386b857d9170c756cc7bc07a43a830296722c02e3ded58ce66a824`; started2026-09-05T01:27:00.546341357Z.
- Image `ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:smp-preview`; launch console reported digest `sha256:343d2a755d03352645d0c3ea63b3f687468a8390d2710e941b34feafac6663bc`.
- QEMU host PID4137461, niagara, -smp2,3072MiB. Guest `illumos-31d3d510d0`, sun4v SPARC, platform SUNW,Sun-Fire-T200. Both CPUs online.
- Guest dladm show-link and show-etherstub empty; ipadm only lo0 IPv4/IPv6 loopback; no non-loopback route. ip-interface-management online.
- Container bridge networking, eth0=172.17.0.7/16, CAP_NET_ADMIN, privileged=false. Only explicit device pass-through is /dev/ppp. /dev/net/tun and /dev/net absent.
- Persistent Docker volume `openindiana-smp-demo` mounted read/write at /var/lib/illumos-appliance. Guest unit100 writable channel carrier `/run/unit100/carrier-unit100.raw`; unit103 read-only installer; unit105 writable20GiB installed root. Do not reinitialize the carrier or alter source installer.
- Existing container helpers: host-chan bridge0 /run/niag0 and bridge1 /run/niag1; PPP supervisor on0 and BBS on1. Guest has no active PPP interface at capture. Preserve both helper lanes regardless.

## Proposed architecture and gates

Guest IP VNIC -> etherstub -> relay VNIC -> guest DLPI frame relay -> a separately verified unused disk channel -> container frame relay -> container-local TAP. No Biggie host TAP/bridge/NAT changes implied.

1. Capture exact binaries/configuration and channel ownership. Verify an unused channel and its byte ranges from chan.h and both endpoints; do not assume channel2 is free solely from process names.
2. Temporary guest etherstub/two-VNIC creation and local Ethernet frame exchange. Record names, MACs, frame hashes, counters, timestamps and cleanup instructions. No external network needed for this gate.
3. One Ethernet frame crosses the disk channel in each direction, with payload identity verified. Exactly one reader/writer per channel direction.
4. Container-local TAP, then ARP and bounded ping between guest and container. TAP device access is a current prerequisite requiring an explicit safe resolution; CAP_NET_ADMIN alone does not provide /dev/net/tun or device-cgroup access.
5. TCP transfer with end-to-end hash. Only then consider routing beyond the container, throughput/reliability tests, or application demonstrations.

Every gate separates observed evidence from inference. Record unsuccessful commands and first successful timestamp. Preserve baseline and transcripts before any networking mutation. No restarting either VM, replacing existing PPP/BBS helpers, broad host network changes, disk formatting, or installation as an incidental step.

## Current checkpoint

Gates 1–5 PASS: temporary guest links, local raw Ethernet, bidirectional Ethernet over disk channel2, container-local TAP/ARP/IPv4 pings, and a64KiB TCP round-trip. First channel round-trip passed at **2026-09-05T01:56:23Z**; TCP completed at **02:06:35Z guest UTC**. Later authorized NAT, default route and DNS/NSS setup passed public-IP ping and certificate-verified HTTPS at **02:18:52Z**. IPv4 MTU1500 is applied. Sustained reliability and throughput remain unmeasured; jumbo frames are out of scope. Both VMs remain running. Channel0/1 helpers remain untouched.

## Execution record: first Ethernet round-trip

Durable evidence on Biggie: `/home/ryan/vms/oi-smp-channel-ethernet-20260905-01/` (mode0700). Runtime Linux endpoint is inside `openindiana-smp-demo`. Guest files are under `/tmp/ce-experiment/`. Times below are UTC, hence September5 while the notebook filename uses Ryan's September4 local date.

Command routing exception: the previously inspected tmux wrappers were unavailable/broken; individual tmux invocations use `GUARDRAIL_BYPASS=1`. Remote shell transport uses `ssh -o ControlMaster=no -o ControlPath=none -o ForwardAgent=no biggie`. No agent forwarding.

### Channel ownership and exact geometry

The container's `/opt/niagara-project/tools/chan/chan.h` defines16 channels of1MiB each, starting at byte327680 in unit100. Guest base is sector640. Channel2 starts at byte2424832 / sector4736. Its control sectors are relative0/1; H2G data sectors2–1024; G2H data1025–2047. Each direction has523776 payload bytes. The frame probe adds a network-order uint32 length to each Ethernet frame. The channel remains a byte stream, not an Ethernet-aware device.

Status showed channels0/1 initialized and channels2–15 zero; process inventory showed existing PPP/BBS helpers on0/1 and no guest chand. The entire channel2 region was checked against zero before initialization:

```sh
docker exec openindiana-smp-demo sh -c 'dd if=/run/unit100/carrier-unit100.raw bs=512 skip=4736 count=2048 status=none | cmp -n 1048576 - /dev/zero'
# Inside the container, only after that successful check:
NIAGARA_IMG=/run/unit100/carrier-unit100.raw NIAG_CHAN_HOST_BYTE=327680 python3 /opt/niagara-project/tools/chan/host-chan.py init 2
NIAGARA_IMG=/run/unit100/carrier-unit100.raw NIAG_CHAN_HOST_BYTE=327680 CHAN_TRACE=1 python3 -u /opt/niagara-project/tools/chan/host-chan.py bridge 2 /run/niag2 > /state/ce-host-channel2.log 2>&1
# Guest, background (PID524):
NIAG_CHAN_DEV=/devices/virtual-devices@100/disk@0:c,raw NIAG_CHAN_GUEST_BLK=640 /lib/niag/guest-chand 2 /tmp/ce-niag2 > /tmp/ce-experiment/guest-channel2.log 2>&1 &
```

Host bridge was launched with `docker exec -d ... sh -c 'exec env ...'`; current container PID4707. Both endpoints reported seq0/peer0 initially; guest confirmed baseblk4736. Never reinitialize this channel while endpoints are running.

### Temporary switch and local-frame gate

Guest commands (successful at01:47:10Z):

```sh
dladm create-etherstub -t ce_stub0 &&
dladm create-vnic -t -l ce_stub0 -m 02:ce:00:00:00:01 ce_ip0 &&
dladm create-vnic -t -l ce_stub0 -m 02:ce:00:00:00:02 ce_wire0
dladm show-link
dladm show-vnic
python3 -u /tmp/ce-experiment/dlpi-local-probe.py
```

All three links up, MTU9000. Python ctypes calls native libdlpi with RAW flag4, bind EtherType0x88b5, send/receive full frames; success code10000. API declarations were checked against the existing Tribblix header at `devel/masa-sun4v/ci/runs/workstation-fix-verify-01/tribblix-toolchain-bundle-audit-20260827/extracted/TRIBsys-header/reloc/usr/include/libdlpi.h` under Ryan's Biggie home. This header provenance is distinct from the running OI library. No guest compiler/header installation was necessary. Attempted upstream header fetches were unavailable; no claim of source/binary equivalence.

At01:49:52Z both78-byte local frames matched exactly:

- ce_ip0 → ce_wire0: `562a49e0cb497504d2c961d7415a996c319a57ac2e7a69e013de95a8b9192525`
- ce_wire0 → ce_ip0: `9d3099a6ff87d497b61c9a2637ba816f93971f64ec14e7d66e143f6139618dfc`

Probe delivery used separate zero-checked carrier scratch ranges, outside all channel queues:10240-byte USTAR at byte134217728 (sector262144) for local probe, and10240 bytes at135266304 (sector264192) for channel probe. Container readback and guest Python SHA-256 matched before extraction. Guest extraction required regular files with the exact expected single filename. Captured source ISOs were not modified.

### First channel round-trip: exact invocation and result

```sh
# Biggie invokes the container endpoint first:
docker exec -d openindiana-smp-demo sh -c 'exec python3 -u /state/ethernet-channel-probe.py host /run/niag2 > /state/ce-roundtrip-host.log 2>&1'
# Then guest via the existing smpchanneleth console:
python3 -u /tmp/ce-experiment/ethernet-channel-probe.py guest /tmp/ce-niag2
echo CE_ROUNDTRIP_STATUS=$?
cat /tmp/ce-experiment/guest-channel2.log
```

At01:56:23Z the guest sent a78-byte Ethernet frame through ce_ip0, received it at ce_wire0, framed it into channel2, and the container verified its MACs/EtherType/payload. The container swapped source/destination MACs and returned the frame; guest verified it, injected at ce_wire0, and received the identical reply at ce_ip0. Both directions were compared byte-for-byte before reporting hashes:

- Outbound (guest and container agree): `6a21ade8b71e8725194760023a2100282cd2cee285bad7e12fed77e239f75f41`
- Reply (container and guest agree): `4a274681e08a5d0d7438b171db8af4593fd71768711ad2d19f8c0b1d318568dc`
- Guest printed `ETHERNET_OVER_CHANNEL2_ROUNDTRIP_PASS`, exit status0.
- Host bridge trace: `IN seq=1 len=82`, `OUT seq=1 len=82`;82 =4 framing bytes +78 frame bytes. Both clients disconnected normally; bridge processes remain available.

This is one synthetic frame each way, not an IP ping, throughput measurement, sustained relay, TAP integration, or Solaris11 compatibility result. No hardware emulated NIC was added. The running OI network stack's virtual switch and native DLPI carried actual Ethernet frames; disk-channel helpers transported them.

### Preserved artifacts and hashes

The console snapshot contains complete guest command echoes, frame hex, transfer hashes and results. Host logs were copied out of the container immediately after the first PASS; live logs remain in `/state/`.

| File in durable Biggie directory | SHA-256 |
| --- | --- |
| console-baseline.log | da1c5adfbb0a32efb3fe39045d26faa7ab8d22184e45c7a08238c815c6fad38f |
| runtime-baseline.txt | 42a978aafdbc5812a39a96c1057b5233c51fe4219cf4361d9928c05d5a7fd41f |
| container-baseline.txt | 26cae77cec49783dc6c8b8108ebc510715118eda2c273e4c7df8fef3bba91884 |
| chan.h | 97839d57e5b1adfa6674afbeeebeb259c521e4af4016c6e032109bcc328560b3 |
| dlpi-local-probe.py | 9f4be92276fd7a97bea50dbed37140a4375f3dc2247da1f47f4ef8e8dee1e7f0 |
| probe.tar | f27d21c67e283286cde4f74f85817d855c7fbed1a9a29f62c1efef8cea195d66 |
| ethernet-channel-probe.py | c5e1d9a11cdd071c85cf60d16a2a618618a53e0d643cc0dca633cc24dd138f55 |
| channel-probe.tar | fea65bc1240d81c2b6ca2e1ca4915ddcbd697f2e905d09811282cc1fd7648fe7 |
| console-roundtrip-pass.log | 4c4a3ff8b296dbf269541fbc477bf297e370f0d0d3d37f320d8755dfe5e2cdcb |
| host-channel2-first-pass.log | ca67aa656af5d1910a16d1e03bfd6c9ca38d157deb312ca96c0c5739b156dea5 |
| roundtrip-host-first-pass.log | ed5166bddf6122c22ea688934353b4d063884ebd2f0e72a138174ff8830e5353 |

Preservation commands: `docker cp openindiana-smp-demo:/state/console.log ~/vms/oi-smp-channel-ethernet-20260905-01/console-roundtrip-pass.log`, with analogous copies for the two host logs, followed by `sha256sum` of the directory files.

### Remaining prerequisite and cleanup boundaries

After PASS, read-only recheck still found no `/dev/net/tun` (test status1). Container routes remain only172.17.0.0/16 on eth0 and default via172.17.0.1. Native container TAP integration requires resolving device exposure without restarting this running guest and without bypassing a device-cgroup denial. No Biggie host bridge/NAT changes are authorized implicitly by this experiment. Seek coordination before that expansion.

Current changes intentionally remain live: three temporary guest links, guest chand PID524, host bridge channel2 PID4707, two staged scratch tars, experiment files. Diagnostic probe clients exited. Do not stop either VM. Future scoped cleanup, only when requested: stop the two identified channel2 helper processes, delete any subsequently created ce_ip0 IP objects first, then `dladm delete-vnic -t ce_wire0`, `dladm delete-vnic -t ce_ip0`, `dladm delete-etherstub -t ce_stub0`. Do not touch channels0/1, source ISOs, or installer disks.

## Authorized TAP and IP continuation

Ryan explicitly approved arranging container-local TAP without restarting the VM or changing Biggie host networking. He suggested socat bridging `/dev/tun`. Installed socat reports WITH_TUN, but an unframed byte bridge would lose Ethernet packet boundaries; the existing channel protocol needs the length-aware relay. A TAP is selected, not layer3 TUN. QEMU TAP/SLIRP backends alone would still need a working guest NIC frontend/driver; this experiment supplies the missing guest-facing path using native OI DLPI and disk transport.

The Systematic Debugging skill kept the initial device failure investigation separate from permission changes: Docker inspect showed only `/dev/ppp`, CAP_NET_ADMIN, no device-cgroup rules, and no `/dev/net/tun`. Host TUN exists as char10:200. `runc update --help` and runtime identities were inspected, but **no runtime resource/cgroup modification was made**. Instead a narrowly scoped helper shares only the target container's network namespace. No original VM container policy change, privileged mode, host network mode, device-all grant or host TAP.

### Relay code and guest delivery

New `tools/chan/ethernet-ip-relay.py` uses Python ctypes/libdlpi on OI and Linux TUNSETIFF on the helper. Guest RAW open, bindSAP0, DL_PROMISC_SAP=2 (verified in the existing Tribblix header), and select on dlpi_fd; no physical promiscuity required for this explicit matched-MAC topology. Host TUNSETIFF0x400454ca, IFF_TAP2 | IFF_NO_PI0x1000 checked against `/usr/include/linux/if_tun.h`. Channel framing is uint32 network order,14–9018 byte bounds, exact reads, SHA-256/header/counter logs. Broken streams terminate the relay rather than silently reconnect mid-frame. No production robustness claim.

- Source SHA: `6bd9983e47611381973675dfba649478bcf2831f228c1506e3d625aee097e91b`
- `ce-ip-relay.tar`,6144 bytes: `4c9e8d3eeaf9d94e33f7c6f370c2bfffaa55cfb3b9b07d7251672b0347bc1aff`
- Local `python3 -m py_compile` succeeded.
- Archive creation: `tar --format ustar -cf /private/tmp/ce-ip-relay.tar -C tools/chan ethernet-ip-relay.py`.
- SCP both files to the durable experiment directory; docker cp tar to `/state/ce-ip-relay.tar`.
- Carrier scratch: byte136314880 / sector266240,12 sectors. `dd ... bs=512 skip=266240 count=12 status=none | cmp -n 6144 - /dev/zero` passed before write. Write with `dd if=/state/ce-ip-relay.tar of=/run/unit100/carrier-unit100.raw bs=512 seek=266240 conv=notrunc,fsync status=none`; readback SHA matched.
- Guest read6144 bytes at136314880 from disk0:c,raw with Python, checked full SHA and exact regular-file member name, then extracted under `/tmp/ce-experiment`; printed `CE_IP_RELAY_TRANSFER_PASS`.

### Helper failure, isolated correction, successful setup

First `oi-channel2-tap-helper` container ID `cf58e2b5a81394963b0ae3b0775e00f3b7432b7d5ccb5fb5372bf0031367f5f5` never started (statecreated, PID0): Docker/runc rejected bind source `/proc/4137461/root/run/niag2` with `invalid argument`. No TAP/IP mutation happened from that attempt. Failed container retained, exact error preserved.

Inspected original container GraphDriver and mountinfo, then compared the `/proc` socket to its ordinary merged-overlay path: both device:inode `5243068:33556998`, type socket. Only the bind source changed; the channel daemon was not restarted/reinitialized. Second helper:

```sh
docker run -d --name oi-channel2-tap-helper-02 \
  --network container:openindiana-smp-demo --read-only \
  --cap-drop ALL --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun:rw \
  --mount type=bind,src=/var/lib/docker/overlay2/6c125168d8bd80e5d0eca41bae89e960d9a33e42feb082dd70ffabaf58def5b8/merged/run/niag2,dst=/run/niag2 \
  --mount type=bind,src=/home/ryan/vms/oi-smp-channel-ethernet-20260905-01/ethernet-ip-relay.py,dst=/relay.py,readonly \
  --entrypoint /usr/bin/python3 \
  sha256:a9077cf8b01daf97f97386797c49d163e48d4e879f30707746d32fd5ad01fe1d \
  -u /relay.py host /run/niag2 ce_tap0
```

Successful helper ID `6ad9562123e0dd231ffd514dfe5df17bc719f1f2248cd3ddf172dafb37cd6c58`. Image is the original container's exact local image ID, distinct from the registry launch digest recorded above. The helper has no disk-carrier or installer mount. The socket bind exposes only channel2. Overlay backing path is a live-experiment expedient, not a portable deployment recipe; future packaging should use an explicit shared socket directory.

Host relay creates nonpersistent `ce_tap0`, MAC02:ce:00:00:00:02 (same as ce_wire0), MTU1500, address10.77.0.1/24; closes with its owning fd/process. The TAP and its connected route live in the shared **container** network namespace. Linux also automatically configured link-local IPv6 `fe80::ce:ff:fe00:2/64` and emitted ND/MLD frames, observed crossing the channel. IPv6 connectivity is not tested.

Guest relay background PID535:

```sh
python3 -u /tmp/ce-experiment/ethernet-ip-relay.py guest /tmp/ce-niag2 ce_wire0 > /tmp/ce-experiment/guest-ip-relay.log 2>&1 &
ipadm create-ip -t ce_ip0 && ipadm create-addr -t -T static -a 10.77.0.2/24 ce_ip0/v4
echo CE_IP_CONFIG_STATUS=$?
ipadm show-addr
/usr/sbin/ping -s 10.77.0.1 56 3
date -u
```

Address creation status0; ce_ip0/v4 static/ok. Preflight guest had only loopback routes; container had172.17.0.0/16/default via172.17.0.1, no10.77/24. No new guest default route, forwarding, NAT, bridge or DNS configuration. Existing container default route remains unchanged.

### First ARP and IPv4 gate

Guest three-packet ping:3 transmitted,3 received,0% loss; RTT min/avg/max125.585/184.396/299.598ms. Guest command ended02:05:29Z. Host frame timestamps run about1second later than guest around this sample, so do not derive subsecond latency by subtracting the two clocks.

Container reverse command: `docker exec openindiana-smp-demo ping -n -c 3 -W 3 10.77.0.2`;3/3 received,0% loss, RTT126.208/166.140/212.865ms. ARP neighbor10.77.0.2 resolved to02:ce:00:00:00:01 REACHABLE. Frame logs contain actual EtherType0x0806 ARP request/reply and0x0800 IPv4 ICMP traffic, not synthetic probe responses.

### First TCP gate

Container launched a one-shot Python TCP listener with `docker exec -d ... sh -c 'exec python3 -u -c ... > /state/ce-tcp-first.log 2>&1'`, bound **only10.77.0.1:17777**, listen backlog1. Accept timeout60seconds, connection timeout30seconds. It read exactly65536 bytes, logged SHA/peer/time, echoed the entire payload with sendall, then closed listener and connection. No public listener left behind.

Guest command, preserved verbatim in console snapshot:

```python
import socket,hashlib,json,time
d=bytes(range(256))*256
s=socket.create_connection(('10.77.0.1',17777),30)
s.sendall(d)
r=b''
while len(r)<len(d):
    p=s.recv(len(d)-len(r))
    if not p: raise EOFError('short TCP echo')
    r+=p
assert r==d
s.close()
print(json.dumps(dict(event='TCP_64K_ROUNDTRIP_PASS',bytes=len(r),
    sha256=hashlib.sha256(r).hexdigest(),
    utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()))))
```

Host received65536 bytes from10.77.0.2:56187 at02:06:34Z. Guest printed PASS at02:06:35Z. Both SHA values `7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2`. Guest compared the entire echoed payload, not only hashes. This is an ordinary TCP connection through the two OS networking stacks.

### PPP independence, current state, limitations

Ryan asked whether PPP was down. Live `ipadm show-if`, `ifconfig -a`, and container `ip -br addr` show **no PPP interface on either side**. Guest onlylo0/ce_ip0; containerlo/eth0/ce_tap0. Existing channel0 socat helper PID383 still advertises pppd with10.0.5.1:10.0.5.15, untouched. Thus the measured10.77 TCP/ICMP cannot be attributed to PPP. Container lacked rg (`sh: rg: not found`) in one process check; retried using grep from the host pipeline.

Original OI QEMU still PID4137461, running. Solaris11 lane untouched. Guest relay535, guest chand524, host channel2 bridge4707, successful TAP helper remain running intentionally. One-shot TCP listener exited. Failed helper remains created for evidence. Do not stop VMs as cleanup. To unwind when explicitly requested: stop only guest relay535 and helper-02 (closing TAP removes its interface/connected route), then remove temporary guest IP with `ipadm delete-ip -t ce_ip0`; preserve logs first. Broader link/channel cleanup is separately described above.

MTU mismatch remains: guest ce_ip0 MTU9000, TAP1500. TCP's successful MSS negotiation does not establish jumbo support; align MTU or test fragmentation deliberately before reliability/performance claims. This relay logs every frame and is a diagnostic implementation, not a performance baseline. No outside-container reachability tested or enabled.

### Preserved IP/TCP evidence

Same durable Biggie directory, copied from runtime immediately after PASS:

| Artifact | SHA-256 |
| --- | --- |
| console-ip-tcp-pass.log | a063d328d035fb22815a0876f23f29f0d78feda1cf0f69258dd103ef917cb76e |
| channel2-ip-tcp-pass.log | 14c3ac8fbac1962751cd977cf5132ee7918bc70526c14964b460c7158b083c86 |
| tap-relay-ip-tcp-pass.log | 1a651fb6917d8f47d2f03a94d03255d40eb205ba5cde6e9c56d8c04cb24651cc |
| tcp-host-first-pass.log | 2aa0f4448bd7add5fed415f69165c9d67ffe29d6e47bc4766097d29fd430e505 |
| tap-helper-first-failure.txt | 1747b5345057e7c3fa666716cfcd02eafebfec7b34b69f8165535dfb86f05155 |
| tap-helper-identity.txt | 6d8a33db07b7db31cb6203fc503d611868744af5e3ecce02fc63d766a3ecbabd |

Guest full per-frame relay log remains `/tmp/ce-experiment/guest-ip-relay.log`; only its early content is included in console snapshot. TAP counterpart log and channel trace are fully preserved at this checkpoint. No claim that every guest log has been exported yet.

## Publication and live-state follow-up

Ryan selected ordinary MTU1500 and explicitly put jumbo frames out of scope.
This is a scope decision, not evidence that the still-running VNIC was
reconfigured: subsequent ifconfig continued to show MTU9000. No live NIC or
helper teardown was performed during documentation/publication work.

When Ryan reported that ping did not work, read-only checks found the original
VM still PID4137461, helper-02 running host PID47154, ce_tap0 present at
10.77.0.1/24, and guest ce_ip0 UP at10.77.0.2/24. A fresh container-to-guest
three-packet test at host02:14:43–02:14:45Z received3/3,0% loss,
RTT108.585/143.677/181.290ms. Frame logs showed corresponding ICMP request and
reply traffic. The reported failing destination/command was not visible in
the console; asked Ryan for it. Do not label his report resolved by a reverse
ping alone. Guest route table still had only loopback and10.77.0.0/24, with
no default route; outside-subnet connectivity was never configured here.

Public write-up: `THE-ETHERNET-OVER-DISK-STORY.md`; existing OpenIndiana story
links to this later experiment without rewriting the August PPP history.
`tools/chan/README-ethernet.md` describes dependencies, framing and diagnostic
limitations. Public publication is based on the public repository's current
main, not a push of private lab ancestry. Only original source/docs and bounded
observations/hashes are selected; raw console captures, guest binaries and
Oracle payloads stay out of the public commit.

## Outbound NAT authorized after the local proof

Ryan clarified that he wanted NAT, then explicitly approved it for this OI
test and eventual reuse in the Solaris11 installer experiment. Solaris11 was
not modified. Preflight inside `openindiana-smp-demo` showed IPv4 forwarding
already1 and filter FORWARD policyACCEPT. Existing PPP-specific forward and
MASQUERADE rules for10.0.5.15 remained intact. No need to change sysctls,
filter policy, or Biggie's host namespace.

Exactly one rule was appended inside the VM container:

```sh
docker exec openindiana-smp-demo iptables -t nat -A POSTROUTING \
  -s 10.77.0.2/32 -o eth0 -m comment --comment ce-channel2-egress -j MASQUERADE
# Guest, nonpersistent route (no -p):
route add default 10.77.0.1
netstat -rn
cat /etc/resolv.conf
/usr/sbin/ping -s 1.1.1.1 56 3
```

Before/after `iptables-save` snapshots are preserved in the experiment
directory. The new NAT rule matched traffic; existing PPP NAT remained at
zero packets at the first readback. This relies on Docker's already-existing
outbound path from eth0; no host rule was added.

At guest02:17:50Z, public-IP ping completed3/3,0% loss, RTT
115.434/150.483/180.046ms min/avg/max. Existing guest resolv.conf already
contained `nameserver 8.8.8.8`; it was not changed. Ryan subsequently typed
`ping ryan.net`, which printed `ryan.net is alive` in the console.

The agreed ordinary-MTU setting was then applied live with
`ifconfig ce_ip0 mtu 1500`. Readback showed IPv4 FIXEDMTU1500; the underlying
VNIC link's jumbo capability is neither required nor a tested feature.

NAT rollback, only if requested: delete exactly the same rule using
`iptables -t nat -D POSTROUTING -s 10.77.0.2/32 -o eth0 -m comment --comment ce-channel2-egress -j MASQUERADE`
inside the VM container, and guest `route delete default 10.77.0.1`. Do not
flush tables, remove PPP rules, or alter the host default route. The active
experiment intentionally retains NAT and the guest route.

For Solaris11 later: inventory its actual network namespace, interface names,
channel ownership, native libdlpi API and ipadm services first; do not reuse
OI channel2 or its live writable carrier. Prove local ARP/ping/TCP before
adding a scoped NAT rule and guest route. Keep the current installer boot
alive and preserve its separate disk mappings. This OI result does not prove
Oracle IPS repository access, package entitlement, or installer completion.

Evidence hashes: `iptables-before-ethernet-nat.txt`
`1b530ae6f11e2d6a13dad71118df8eb1467fee351863fb4d7d0a193f55a284e9`;
`iptables-after-ethernet-nat.txt`
`8fb786d37fc229c8b7154b98ffbf9728a6c0fd99ce3f3d987f3eb8d5d2431d80`.
Early `console-nat-check.log` (captured before HTTPS finished)
`e54b386bc4f208c94156d122221ae4f0949c8129ffd6b77deaaa8da87ef66021`.

At guest02:18:52Z Python resolved example.com and fetched
`https://example.com/` using urllib.request.urlopen(timeout=30) with default
certificate verification (no custom context or verification bypass).
`ETHERNET_NAT_HTTPS_PASS`: status200,559 bytes, body SHA-256
`ff67a9d764d6a2367a187734e697f6a53217db9a21c101d410a113ca871a299d`.
DNS returned104.20.23.154 and172.66.147.243 at this observation, not pinned
service addresses.

Ryan identified his required NSS change: `/etc/nsswitch.conf` hosts must use
`files dns`. Read-only guest capture at02:19:52Z confirmed:

```text
hosts:      files dns
ipnodes:    files dns
nameserver 8.8.8.8
```

The nameserver line is from `/etc/resolv.conf`, not nsswitch.conf. The exact
time/pre-change NSS contents were not captured; credit Ryan's report and the
verified final state, not an agent-performed NSS edit. Both resolver and NSS
configuration belong in the reproduction prerequisites.
Final console evidence `console-nat-https-nss-pass.log` SHA-256
`837faea651ac6cd5df7699e9abb40a92c81bd0e03de01e9495514d51d1b510a5`.
