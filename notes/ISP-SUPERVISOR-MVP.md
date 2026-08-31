# Run-scoped ISP supervisor MVP

This is repository-only packaging. Do not copy units, create accounts, or start
the supervisor against an existing run. The first live acceptance belongs to a
fresh run whose channel 0 passes the clean-carrier and clean-mailbox gates.

## Components and installation boundary

Install reviewed copies of `isp_supervisor.py` and `isp_protocol.py` into a
root-owned, non-writable `/usr/local/libexec/niagara` tree. Install
`host-bbs.py`, `isp_client.py`, and `isp_protocol.py` for the dedicated
unprivileged `niagara-bbs` account. The supervisor refuses a profile or manifest
that is not root-owned and non-writable.

The unit templates under `tools/chan/systemd` contain literal
`NIAGARA_BBS_UID` and `NIAGARA_BBS_GID` placeholders. Packaging must replace
them with the dedicated account's numeric IDs. They must never be substituted
from a guest request or BBS input.

Create a root-owned profile from `tools/chan/isp-profile.example`. Record the
channel-0 bridge PID and `/proc/PID/stat` start-time field after the bridge is
started. Copy the run manifest into the root-owned supervisor state directory;
do not point privileged validation at a user-writable manifest.

The ordering contract is:

```text
run manifest and mailbox -> channel bridges -> ISP supervisor -> channel-4 BBS
guest ISP PREPARE -> ISP READY -> immediate bounded guest PPP on channel 0
```

`niagara-channels@RUN.target` is only an operator-confirmed ordering marker; it
does not start bridges or claim they are healthy. Start it only after the actual
run-owned bridge processes and sockets pass their readiness checks. The
supervisor independently revalidates channel 0 on every PREPARE.

The BBS service has no capabilities and can reach the supervisor only through
the group-owned `0660` control socket. The supervisor authenticates its numeric
UID with `SO_PEERCRED`. Its mount namespace hides every run socket except
channel 4. The supervisor's namespace hides every run socket except channel 0.
Neither service unit initializes a mailbox.

## Guest use

Install `guest-isp-prepare.pl` as `/lib/niag/guest-isp-prepare.pl`. It requires
already-running `/tmp/niag4` and `/tmp/niag0` guest bridges. It dials the BBS on
channel 4, sends exactly `ISP PREPARE`, accepts exactly one fixed-address READY
line with `expires=45`, closes channel 4, and immediately execs finite pppd on
channel 0. It does not use the historical persistent PPP supervisor.

```text
/usr/bin/perl /lib/niag/guest-isp-prepare.pl
```

BLOCKED, duplicate, malformed, unterminated, unexpected-address, and timed-out
responses exit nonzero before channel 0 is opened.

## Evidence and status

The authoritative root-owned ledger is:

```text
/var/lib/niagara-isp/RUN_ID/ledger.jsonl
```

Use `ISP STATUS id=ID` over channel 4. Host ONLINE means pppd logged IPCP local
and remote addresses and `ppp0` exposes the exact fixed addresses. Guest ping and
route checks remain separate acceptance gates.

## Explicit run teardown

Stopping `niagara-bbs@RUN` and `niagara-isp-supervisor@RUN` must not remove
forwarding or firewall rules. Those are run-owned rather than service-owned.

At explicit authorized run teardown:

1. Save the supervisor ledger and pppd logs.
2. Send `ISP ABORT id=ID` for a nonterminal request, or stop only the ledgered
   PID after verifying its `/proc/PID/stat` start time and exact argv.
3. Stop the BBS and supervisor units, then the run's channel bridges.
4. Delete only the three exact iptables rules whose comments are
   `niagara-RUN_ID-out`, `niagara-RUN_ID-return`, and `niagara-RUN_ID-nat`, using
   exact `iptables -C` followed by exact `iptables -D`. Never flush a chain.
5. Restore the recorded prior `net.ipv4.ip_forward` value only if the ledger says
   this run changed it and an operator has proved no other run or workload needs
   forwarding.
6. Do not reset or remove the mailbox until its evidence disposition is explicit.

There is intentionally no automatic teardown command in this MVP: conditional
forwarding restoration requires an operator's cross-run check and must not be
hidden in `ExecStop`.
