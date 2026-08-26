# OpenIndiana Channel PPP SOP

Status: canonical operator procedure for PPP over the dedicated hSIMD mailbox
channel. Channel 0 carries PPP; channel 1 remains the independent recovery
console.

This procedure turns a known byte-exact channel into a point-to-point link. It
does not authorize a reboot, QEMU signal, mailbox reset, process termination,
or host routing change by itself. Those mutations must belong to the active
bounded Run.

## Non-negotiable rules

1. Protect the QEMU and its writable images. Never use HMP `quit`, never send a
   control character to a QEMU-owning terminal, and never identify a process
   with a broad `pgrep` before signaling it.
2. Establish and test an interactive root shell on channel 1 before touching
   channel 0. There must be exactly one guest-console writer.
3. Rediscover the channel mapping after every disk or topology change. Recorded
   device names and offsets are examples, not identities.
4. One writer per mailbox and one client per bridge. Do not stack a new bridge,
   guest daemon, wrapper, `socat`, or `pppd` on an old one.
5. Pass a byte-exact framed echo before starting either PPP peer.
6. Use symmetric `asyncmap 0` on the dedicated byte-exact channel. The
   `asyncmap 0xffffffff` setting belongs to the non-byte-clean qcn console and
   failed channel negotiation in `term4code-02`.
7. `persist maxfail 0` belongs only on the OpenIndiana guest. The Linux host
   peer is a bounded one-shot. Host persistence previously caused a `pppd`
   zombie/fork storm.
8. Change only the Run's exact NAT rule. Never flush an iptables table, replace
   a default route, or clean unrelated host processes.
9. Never signal QEMU as part of PPP or channel recovery. In particular,
   `SIGUSR2` terminated the pinned `term4code-02` QEMU on 2026-08-26. The
   presence of `msync` functions or an old helper comment is not proof of an
   installed signal handler.

The current byte-exact pair is:

- guest: [`tools/chan/guest-ppp-chan.pl`](../../tools/chan/guest-ppp-chan.pl)
- host: [`tools/chan/host-pppd-once.sh`](../../tools/chan/host-pppd-once.sh)

Do not use the PPP stanza in `tools/chan/host-up.sh`, `boot-net.sh`,
`net-chan-up.sh`, or `basecamp-r0-cold-anchor.sh` as a command source until it
has been reconciled with this SOP; those files still contain the older
`asyncmap 0xffffffff` value and some perform broader cleanup or host mutation.

## 1. Declare the Run identities

Record these values in the active Run before issuing commands. Do not paste the
example values blindly.

```sh
PROJECT=/home/ryan/devel/qemu-sun4v-illumos
RUN_DIR=/path/to/this/run
CHANNEL_IMAGE=/path/to/unit-101-channel.img
CHANNEL_HOST_BYTE=REPLACE_WITH_REDISCOVERED_BYTE_OFFSET
CHANNEL_GUEST_DEV=/dev/rdsk/REPLACE_WITH_REDISCOVERED_WHOLE_DISK_SLICE
CHAN_SOCKET="$RUN_DIR/chan0.sock"
QEMU_PID=REPLACE_WITH_EXACT_RUN_OWNED_WORKER_PID
HOST_IP=10.0.5.1
GUEST_IP=10.0.5.15
```

Also record:

- host, tmux session, and named panes for QEMU, channel-1 getty, channel-0
  bridge, host PPP, and evidence;
- QEMU path/hash, full argv, firmware, CPU count, and writable-image file
  descriptors;
- channel tool hashes on the host and guest;
- unit number, guest raw device, mailbox block/byte offset, and proof that the
  reserved extent does not overlap a label, filesystem, pool, or live data.

Confirm the exact worker without signaling it:

```sh
ps -p "$QEMU_PID" -o pid=,ppid=,lstart=,stat=,args=
kill -0 "$QEMU_PID"
```

Inspect the worker's `/proc/$QEMU_PID/fd` links and expanded argv and prove that
they name `CHANNEL_IMAGE`. A remembered PID or matching command substring is
not sufficient.

## 2. Preflight the recovery console and process scope

On channel 1, prove both input and output with a harmless unique marker, then
leave its getty/root-shell pane visible. Do not count a socket or helper PID as
proof of a console.

Inventory, read-only, the channel-0 process tree on both sides:

```sh
# Linux host
ps -eo pid,ppid,stat,lstart,args | \
  egrep '[h]ost-chan.py bridge 0|[s]ocat.*pppd|[p]ppd.*notty'
ss -H -x -a -p | grep -F "$CHAN_SOCKET"

# OpenIndiana guest
pgrep -lf 'guest-chand|guest-ppp-chan|pppd|guest-echocli'
```

Map every match to this Run. Check for zombies only in those process trees;
unrelated system workloads are out of scope. The gate is:

- no unidentified or duplicate helper;
- no scoped zombie;
- no stale client holding the channel-0 socket;
- exactly one known QEMU owns the channel image;
- channel 1 remains usable.

If an old channel-0 stack exists, do not start another. Stop only its verified
exact PIDs, wrappers before children, and confirm they are gone. A zombie must
be reaped by its exact parent; it cannot be fixed by starting another peer.

## 3. Reset channel 0 only from a quiescent state

Mailbox initialization is destructive to the live handshake. It is permitted
only after the guest channel-0 wrapper/`pppd` and `guest-chand`, and the host
PPP client and bridge, are all confirmed stopped. Do not stop or reset channel
1.

```sh
NIAGARA_IMG="$CHANNEL_IMAGE" \
NIAG_CHAN_HOST_BYTE="$CHANNEL_HOST_BYTE" \
python3 "$PROJECT/tools/chan/host-chan.py" init 0
```

Immediately record status:

```sh
NIAGARA_IMG="$CHANNEL_IMAGE" \
NIAG_CHAN_HOST_BYTE="$CHANNEL_HOST_BYTE" \
python3 "$PROJECT/tools/chan/host-chan.py" status 0
```

Both peers must begin from the newly initialized sequence state. Never reset
one side under a running single-writer handshake.

## 4. Start exactly one bridge and one guest daemon

Run the host bridge visibly in its named tmux window:

```sh
NIAGARA_IMG="$CHANNEL_IMAGE" \
NIAG_CHAN_HOST_BYTE="$CHANNEL_HOST_BYTE" \
python3 "$PROJECT/tools/chan/host-chan.py" bridge 0 "$CHAN_SOCKET" \
  2>&1 | tee "$RUN_DIR/host-chan0.log"
```

From channel 1, start the guest daemon with the rediscovered raw device. Keep
the serial command below 256 bytes and require its launch marker:

```sh
NIAG_CHAN_DEV="$CHANNEL_GUEST_DEV" nohup /opt/niag/bin/guest-chand 0 /tmp/niag0 </dev/null >/tmp/niag-chand0.log 2>&1 & echo CHAND0:$!
```

Record that PID. Verify `/tmp/niag0` is a Unix socket and that exactly one
channel-0 `guest-chand` exists. If the installed payload lives under
`/lib/niag` rather than `/opt/niag/bin`, use the verified installed path and
record the deviation.

## 5. Mandatory byte-exact echo gate

Start exactly one guest echo client from channel 1 and record its PID:

```sh
nohup /opt/niag/bin/guest-echocli /tmp/niag0 </dev/null >/tmp/echocli0.log 2>&1 & echo ECHOCLI:$!
```

Run at least the 65,536-byte random round trip from the host:

```sh
NIAG_CHAN_SOCK="$CHAN_SOCKET" \
python3 "$PROJECT/tools/chan/chan-test.py" 0 65536
```

PASS means the command reports `MATCH`. Preserve its output. On failure, stop:
PPP cannot diagnose or repair a channel that has not passed this gate.

Terminate only the recorded guest echo-client PID and confirm it is gone. The
guest daemon has one client slot, so the PPP wrapper must not start until the
echo client has released it. Confirm the bridge logs the disconnect/return to
accept before proceeding.

## 6. Start the guest PPP peer first

Create the Solaris PPP device nodes:

```sh
/usr/sbin/devfsadm -i sppp -i sppptun
```

Start the current guest wrapper from channel 1:

```sh
nohup /usr/bin/perl /opt/niag/bin/guest-ppp-chan.pl 0 10.0.5.15:10.0.5.1 </dev/null >/tmp/gppp0.log 2>&1 & echo GPPP0:$!
```

Use the Run's recorded addresses if they differ. The wrapper waits for
`/tmp/niag0`, connects it to `pppd`, uses `asyncmap 0`, installs the default
route, and keeps the guest peer available with `persist maxfail 0`.

Before launching the host, prove the guest's actual `pppd` is running; the Perl
wrapper alone is not readiness:

```sh
pgrep -lf 'guest-ppp-chan|pppd'
```

If `pppd` is absent, stop and preserve all four distinct logs if present:

```text
/tmp/gppp0.log
/tmp/gppp-chan0.wait
/tmp/gppp-chan0.log
/tmp/gpppd-chan0.log
```

## 7. Start one bounded Linux peer

Run this visibly in the named host-PPP tmux window. Do not add `persist` or
`maxfail 0`:

```sh
sudo -n env HOST_IP="$HOST_IP" GUEST_IP="$GUEST_IP" \
  "$PROJECT/tools/chan/host-pppd-once.sh" "$CHAN_SOCKET" \
  2>&1 | tee "$RUN_DIR/host-ppp.log"
```

Resolve the connected socket peer from one captured `ss -H -x -p` table and
record the launch wrapper, actual `pppd`, parentage, command line, and socket
inode. Do not infer the worker PID from `$!` through a `sudo`/`socat` chain.

Do not send `SIGUSR1`, `SIGUSR2`, or any other signal to QEMU to accelerate or
synchronize this exchange. An older helper and rehearsal harness described a
`SIGUSR2` msync hook, but the pinned `term4code-02` binary installed no such
system-emulator handler: the default disposition terminated the VM with exit
140. A future signal-based hook may be admitted only after its exact binary is
proved on a disposable QEMU, has an automated runtime-handler test, and the
active Run explicitly pins that passing build.

## 8. Verify the link in layers

Preserve both PPP logs and require LCP and IPCP completion. Then test in this
order:

1. host has the expected point-to-point interface and addresses;
2. host to guest: `ping -c 2 "$GUEST_IP"`;
3. guest to host: `/usr/sbin/ping 10.0.5.1` reports the host is alive;
4. guest has the intended default route;
5. external routing and DNS, if those are part of the Run;
6. NFS/iSCSI or other application-level canary, if required.

Do not let a broken `ifconfig`, `ipadm`, or `dladm` view overrule successful
packet evidence. Conversely, an interface name without successful packets is
not a PASS.

For Internet access, inspect before changing anything:

```sh
sysctl net.ipv4.ip_forward
ip route show default
sudo -n iptables -t nat -C POSTROUTING \
  -s "$GUEST_IP/32" -o "$EGRESS" -j MASQUERADE
```

If the active Run authorizes host routing changes, enable forwarding only if
needed and add only the exact scoped rule:

```sh
sudo -n sysctl -w net.ipv4.ip_forward=1
sudo -n iptables -t nat -C POSTROUTING \
  -s "$GUEST_IP/32" -o "$EGRESS" -j MASQUERADE 2>/dev/null || \
sudo -n iptables -t nat -A POSTROUTING \
  -s "$GUEST_IP/32" -o "$EGRESS" -j MASQUERADE
```

Never delete or replace a pre-existing rule merely to make the command output
look clean. Record whether this Run found or added the rule so teardown owns
only what it created.

## Failure decisions

| Observation | Interpretation | Next action |
| --- | --- | --- |
| Echo fails or never returns | Channel layer is not healthy | Stop before PPP; inspect exact mapping, mailbox status, bridge and guest-daemon logs. |
| Both PPP logs send LCP Configure-Requests but receive none | Usually a retained/stale channel client or unacknowledged frame, not an IP/NAT problem | Do not launch another peer. Inspect socket ownership and mailbox sequence/ack state; return to the quiescent reset gate if necessary. |
| Bridge accepts no new client after the old peer exits | Its one-client slot or pending frame is retained | Preserve logs, stop the exact scoped stack, and reset from quiescence; do not stack clients. |
| Guest wrapper exists but guest `pppd` does not | Guest readiness failure | Read the four guest logs; verify current wrapper and `sppp`/`sppptun` nodes. |
| Host accumulates defunct `pppd` children | Host peer was made persistent or its owner is not reaping | Stop the exact parent/process tree, prove zero scoped zombies, and restore the bounded host invocation before retrying. |
| Host reaches guest but guest cannot reach the Internet | PPP works; forwarding, NAT, or the guest default route does not | Inspect those layers without restarting PPP. |
| `sppptun` or PPP clone node is missing | Guest device namespace is incomplete | Run targeted `devfsadm -i sppp -i sppptun`, then recheck. |
| One side uses `asyncmap 0xffffffff` | Stale/mismatched helper deployment | Stop and deploy/hash-check the current byte-exact pair; do not compensate on the other side. |
| An old note recommends signaling QEMU to flush/synchronize hSIMD | Stale and unsafe procedure | Do not signal QEMU. Use channel sequence/ack evidence and fix coherency in tested code or orchestration. |

One bounded host relaunch without a mailbox reset is allowed only when all of
these are proven: the guest `pppd` is still alive, the old host socket peer is
gone, the bridge has returned to its accept loop, and no unacknowledged frame
remains. Otherwise perform the full quiescent reset rather than guessing.

## Evidence required for PASS

Attach or transcribe into the active Run:

- exact identities and hashes declared in section 1;
- before/after scoped process inventories and zero scoped zombies;
- channel-1 input/output proof;
- `host-chan.py status 0` after initialization;
- byte-exact echo output and echo-client release proof;
- guest wrapper and actual guest `pppd` readiness;
- host bridge and PPP logs, process ancestry, and socket ownership;
- LCP/IPCP evidence and both negotiated addresses;
- bidirectional host/guest ping;
- routing/NAT ownership, external ping, DNS, and NFS canary results when in
  scope;
- exact teardown/recovery command and the next safe gate.

## Provenance

This SOP consolidates:

- the first working manual order in [`BACKLOG.md`](../../BACKLOG.md), P2-017;
- the clean echo-before-PPP and guest-readiness gates in
  [`tools/basecamp-r0-cold-anchor.sh`](../../tools/basecamp-r0-cold-anchor.sh);
- the lifecycle fixes and immutable passing rehearsal in
  [`captures/openindiana-live-20260824/basecamp-hsimd-version1-evidence-note.md`](../../captures/openindiana-live-20260824/basecamp-hsimd-version1-evidence-note.md);
- the dedicated-channel `asyncmap 0` regression assertions in
  [`tests/unit/test_prepare_term4code02.py`](../../tests/unit/test_prepare_term4code02.py);
- the channel/getty/PPP safety drill in
  [`QEMU-DRILL-INSTRUCTOR.md`](../../QEMU-DRILL-INSTRUCTOR.md).
- the `SIGUSR2` termination incident in
  [`notes/INCIDENT-TERM4CODE-02-SIGUSR2-20260826.md`](../../notes/INCIDENT-TERM4CODE-02-SIGUSR2-20260826.md).

The immutable Basecamp rehearsal reached PPP at 170 seconds and NFS at 177
seconds. The later `term4code-02` path proved a 65,536-byte random channel echo,
PPP, and outbound ping with symmetric `asyncmap 0`. These successes establish
the procedure; every new Run must still revalidate its volatile device, offset,
PID, socket, process, and routing identities.
