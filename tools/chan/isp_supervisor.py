#!/usr/bin/env python3
"""Run-scoped privileged ISP supervisor.

This is intentionally narrow: one fixed profile, one active PPP request, and
three protocol operations.  All host effects live behind HostOperations so the
state machine and failure paths can be tested without privileges.
"""

from __future__ import annotations

import argparse
import dataclasses
import fcntl
import json
import os
import pathlib
import secrets
import signal
import socket
import struct
import subprocess
import time
from typing import Protocol

from isp_protocol import ProtocolError, Request, parse_request, response

READY_TTL = 45
ALLOWED_KEYS = {
    "version", "run_id", "run_dir", "manifest", "mailbox",
    "channel_host_byte", "channel", "channel_socket", "bridge_pid", "bridge_start_id",
    "upstream_interface", "ppp_interface", "host_address", "guest_address",
    "ready_ttl_seconds", "pppd", "iptables",
}


@dataclasses.dataclass(frozen=True)
class Profile:
    run_id: str
    run_dir: str
    manifest: str
    mailbox: str
    channel_host_byte: int
    channel_socket: str
    bridge_pid: int
    bridge_start_id: str = ""
    upstream_interface: str = "enp0s1"
    ppp_interface: str = "ppp0"
    host_address: str = "10.0.5.1"
    guest_address: str = "10.0.5.15"
    pppd: str = "/usr/sbin/pppd"
    iptables: str = "/usr/sbin/iptables"

    @classmethod
    def load(cls, path: str) -> "Profile":
        values: dict[str, str] = {}
        with open(path, encoding="ascii") as stream:
            for number, raw in enumerate(stream, 1):
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.count("=") != 1:
                    raise ValueError(f"profile line {number} is not KEY=VALUE")
                key, value = line.split("=", 1)
                if key not in ALLOWED_KEYS or key in values:
                    raise ValueError(f"profile line {number} has unknown/duplicate key")
                values[key] = value
        required = ALLOWED_KEYS - {"version"}
        if set(values) - ALLOWED_KEYS or required - set(values):
            raise ValueError("profile keys do not match fixed schema")
        if values.get("version", "1") != "1" or values["channel"] != "0":
            raise ValueError("unsupported profile version or channel")
        if values["ready_ttl_seconds"] != str(READY_TTL):
            raise ValueError("READY lifetime must be exactly 45 seconds")
        if (values["upstream_interface"], values["ppp_interface"],
                values["host_address"], values["guest_address"]) != (
                    "enp0s1", "ppp0", "10.0.5.1", "10.0.5.15"):
            raise ValueError("profile differs from fixed allow-list")
        if values["pppd"] != "/usr/sbin/pppd" or values["iptables"] != "/usr/sbin/iptables":
            raise ValueError("tool paths differ from fixed allow-list")
        if not values["run_id"] or any(ch not in "abcdefghijklmnopqrstuvwxyz0123456789-_"
                                       for ch in values["run_id"]):
            raise ValueError("invalid run id")
        run_dir = pathlib.Path(values["run_dir"])
        if not run_dir.is_absolute():
            raise ValueError("run directory must be absolute")
        expected_socket = run_dir / "sockets" / "niag0.sock"
        expected_mailbox = pathlib.Path("/dev/shm/niagara") / values["run_id"] / "channel-unit101.img"
        if pathlib.Path(values["channel_socket"]) != expected_socket:
            raise ValueError("channel socket is outside the fixed run path")
        if pathlib.Path(values["mailbox"]) != expected_mailbox:
            raise ValueError("mailbox is outside the fixed run path")
        if int(values["channel_host_byte"], 0) != 327680:
            raise ValueError("unexpected channel host offset")
        return cls(
            run_id=values["run_id"], run_dir=values["run_dir"],
            manifest=values["manifest"], mailbox=values["mailbox"],
            channel_host_byte=int(values["channel_host_byte"], 0),
            channel_socket=values["channel_socket"],
            bridge_pid=int(values["bridge_pid"]),
            bridge_start_id=values["bridge_start_id"],
            upstream_interface=values["upstream_interface"],
            ppp_interface=values["ppp_interface"],
            host_address=values["host_address"], guest_address=values["guest_address"],
            pppd=values["pppd"], iptables=values["iptables"],
        )


@dataclasses.dataclass(frozen=True)
class GateResult:
    code: str | None = None
    facts: dict[str, object] = dataclasses.field(default_factory=dict)


@dataclasses.dataclass(frozen=True)
class Peer:
    pid: int
    start_id: str
    socket_id: str
    log_path: str = ""


class HostOperations(Protocol):
    def inspect(self, profile: Profile) -> GateResult: ...
    def ensure_run_network(self, profile: Profile) -> GateResult: ...
    def launch_peer(self, profile: Profile, request_id: str) -> Peer: ...
    def peer_ready(self, profile: Profile, peer: Peer) -> bool: ...
    def peer_online(self, profile: Profile, peer: Peer) -> bool: ...
    def peer_negotiating(self, profile: Profile, peer: Peer) -> bool: ...
    def peer_alive(self, peer: Peer) -> bool: ...
    def stop_peer(self, peer: Peer) -> None: ...
    def adopt_peer(self, profile: Profile, peer: Peer) -> bool: ...


class Ledger:
    def __init__(self, path: str, clock=time.time_ns, monotonic=time.monotonic_ns):
        self.path = path
        self.clock = clock
        self.monotonic = monotonic

    def append(self, **record: object) -> None:
        record = {"v": 1, "ts_ns": self.clock(), "mono_ns": self.monotonic(), **record}
        encoded = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode()
        fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, encoded)
            os.fsync(fd)
        finally:
            os.close(fd)

    def records(self) -> list[dict[str, object]]:
        try:
            with open(self.path, encoding="utf-8") as stream:
                return [json.loads(line) for line in stream if line.strip()]
        except FileNotFoundError:
            return []


@dataclasses.dataclass
class Active:
    request_id: str
    state: str
    peer: Peer | None = None
    expires_ns: int | None = None


class Supervisor:
    def __init__(self, profile: Profile, operations: HostOperations, ledger: Ledger,
                 monotonic=time.monotonic_ns, id_factory=lambda: secrets.token_hex(8)):
        self.profile = profile
        self.operations = operations
        self.ledger = ledger
        self.monotonic = monotonic
        self.id_factory = id_factory
        self.active: Active | None = None

    def _new_id(self) -> str:
        used = {str(row.get("id")) for row in self.ledger.records()}
        for _ in range(16):
            candidate = self.id_factory()
            if candidate not in used:
                return candidate
        raise RuntimeError("request id generator did not produce a fresh id")

    def recover(self) -> None:
        """Adopt only a ledger-identifiable, positively verified live child."""
        records = [row for row in self.ledger.records()
                   if row.get("run_id") == self.profile.run_id]
        if not records:
            return
        last = records[-1]
        state = str(last.get("to_state", "FAILED"))
        if state not in {"READY", "NEGOTIATING", "ONLINE"}:
            return
        rid = str(last.get("id", ""))
        try:
            peer = Peer(int(last["pid"]), str(last["pid_start"]), str(last["socket"]),
                        str(last.get("log_path", "")))
        except (KeyError, TypeError, ValueError):
            self._record(rid or "-", state, "FAILED", "restart_not_adopted",
                         code="HOST_PPP_EXITED")
            return
        if not self.operations.adopt_peer(self.profile, peer):
            self._record(rid, state, "FAILED", "restart_not_adopted",
                         code="HOST_PPP_EXITED", pid=peer.pid)
            self.active = Active(rid, "FAILED", peer)
            return
        expires = last.get("expires_ns")
        self.active = Active(rid, state, peer,
                             int(expires) if expires is not None else None)
        self._record(rid, state, state, "restart_adopted", pid=peer.pid,
                     pid_start=peer.start_id, socket=peer.socket_id,
                     log_path=peer.log_path,
                     expires_ns=self.active.expires_ns)

    def _record(self, request_id: str, old: str, new: str, event: str,
                **facts: object) -> None:
        self.ledger.append(run_id=self.profile.run_id, id=request_id,
                           from_state=old, to_state=new, event=event, **facts)

    def handle(self, request: Request) -> str:
        if request.action == "PREPARE":
            return self.prepare()
        if request.action == "STATUS":
            return self.status(request.request_id or "")
        return self.abort(request.request_id or "")

    def prepare(self) -> str:
        if self.active and self.active.state not in {"FAILED", "EXPIRED"}:
            return response("BLOCKED", request_id=self.active.request_id,
                            state=self.active.state, code="BUSY")
        try:
            rid = self._new_id()
        except RuntimeError:
            return response("BLOCKED", state="FAILED", code="INTERNAL")
        self.active = Active(rid, "CHECKING")
        self._record(rid, "IDLE", "CHECKING", "prepare")
        gate = self.operations.inspect(self.profile)
        if gate.code:
            self.active.state = "FAILED"
            self._record(rid, "CHECKING", "FAILED", "gate_blocked",
                         code=gate.code, facts=gate.facts)
            return response("BLOCKED", request_id=rid, state="FAILED", code=gate.code)
        network = self.operations.ensure_run_network(self.profile)
        if network.code:
            self.active.state = "FAILED"
            self._record(rid, "CHECKING", "FAILED", "network_blocked",
                         code=network.code, facts=network.facts)
            return response("BLOCKED", request_id=rid, state="FAILED", code=network.code)
        try:
            peer = self.operations.launch_peer(self.profile, rid)
        except Exception as exc:
            self.active.state = "FAILED"
            self._record(rid, "CHECKING", "FAILED", "peer_launch_failed",
                         code="HOST_PPP_EXITED", detail=type(exc).__name__)
            return response("BLOCKED", request_id=rid, state="FAILED",
                            code="HOST_PPP_EXITED")
        self.active.peer = peer
        if not self.operations.peer_ready(self.profile, peer):
            if self.operations.peer_alive(peer):
                self.operations.stop_peer(peer)
            self.active.state = "FAILED"
            self._record(rid, "CHECKING", "FAILED", "peer_not_ready",
                         code="HOST_PPP_EXITED", pid=peer.pid,
                         pid_start=peer.start_id, socket=peer.socket_id)
            return response("BLOCKED", request_id=rid, state="FAILED",
                            code="HOST_PPP_EXITED")
        self.active.state = "READY"
        self.active.expires_ns = self.monotonic() + READY_TTL * 1_000_000_000
        self._record(rid, "CHECKING", "READY", "peer_ready", pid=peer.pid,
                     pid_start=peer.start_id, socket=peer.socket_id,
                     log_path=peer.log_path,
                     expires_ns=self.active.expires_ns, gate=gate.facts,
                     network=network.facts)
        return response("READY", request_id=rid, state="READY",
                        host=self.profile.host_address, guest=self.profile.guest_address,
                        expires=READY_TTL)

    def _refresh(self) -> None:
        active = self.active
        if not active or active.state not in {"READY", "NEGOTIATING"} or not active.peer:
            return
        if not self.operations.peer_alive(active.peer):
            old = active.state
            active.state = "FAILED"
            self._record(active.request_id, old, "FAILED", "peer_exited",
                         code="HOST_PPP_EXITED", pid=active.peer.pid,
                         pid_start=active.peer.start_id, socket=active.peer.socket_id,
                         log_path=active.peer.log_path)
        elif self.operations.peer_online(self.profile, active.peer):
            old = active.state
            active.state = "ONLINE"
            self._record(active.request_id, old, "ONLINE", "ipcp_online",
                         pid=active.peer.pid, host=self.profile.host_address,
                         guest=self.profile.guest_address,
                         pid_start=active.peer.start_id, socket=active.peer.socket_id,
                         log_path=active.peer.log_path)
        elif active.expires_ns is not None and self.monotonic() >= active.expires_ns:
            self.operations.stop_peer(active.peer)
            old = active.state
            active.state = "EXPIRED"
            self._record(active.request_id, old, "EXPIRED", "ready_expired",
                         pid=active.peer.pid, pid_start=active.peer.start_id,
                         socket=active.peer.socket_id, log_path=active.peer.log_path)
        elif (active.state == "READY" and
              self.operations.peer_negotiating(self.profile, active.peer)):
            active.state = "NEGOTIATING"
            self._record(active.request_id, "READY", "NEGOTIATING", "peer_waiting",
                         pid=active.peer.pid, pid_start=active.peer.start_id,
                         socket=active.peer.socket_id, log_path=active.peer.log_path,
                         expires_ns=active.expires_ns)

    def status(self, request_id: str) -> str:
        if not self.active or self.active.request_id != request_id:
            return response("BLOCKED", request_id=request_id, state="FAILED",
                            code="UNKNOWN_ID")
        self._refresh()
        fields: dict[str, object] = {}
        if self.active.peer:
            fields["pid"] = self.active.peer.pid
        if self.active.expires_ns and self.active.state in {"READY", "NEGOTIATING"}:
            fields["expires"] = max(0, (self.active.expires_ns - self.monotonic()) // 1_000_000_000)
        if self.active.state == "ONLINE":
            fields.update(host=self.profile.host_address, guest=self.profile.guest_address)
        return response("STATUS", request_id=request_id, state=self.active.state, **fields)

    def abort(self, request_id: str) -> str:
        if not self.active or self.active.request_id != request_id:
            return response("BLOCKED", request_id=request_id, state="FAILED",
                            code="UNKNOWN_ID")
        if self.active.state not in {"FAILED", "EXPIRED"}:
            if self.active.peer and self.operations.peer_alive(self.active.peer):
                self.operations.stop_peer(self.active.peer)
            old = self.active.state
            self.active.state = "FAILED"
            facts = {}
            if self.active.peer:
                facts = {"pid": self.active.peer.pid,
                         "pid_start": self.active.peer.start_id,
                         "socket": self.active.peer.socket_id,
                         "log_path": self.active.peer.log_path}
            self._record(request_id, old, "FAILED", "aborted", **facts)
        return response("ABORTED", request_id=request_id, state=self.active.state)


class LinuxHostOperations:
    """Production host adapter. Never resets a mailbox or flushes firewall state."""

    def __init__(self, runner=subprocess.run,
                 forwarding_path="/proc/sys/net/ipv4/ip_forward"):
        self.run = runner
        self.forwarding_path = pathlib.Path(forwarding_path)
        self.children: dict[int, subprocess.Popen] = {}

    @staticmethod
    def _proc_start(pid: int) -> str:
        return pathlib.Path(f"/proc/{pid}/stat").read_text().split()[21]

    def _ss(self, path: str) -> list[str]:
        result = self.run(["/usr/bin/ss", "-xapn"], capture_output=True, text=True,
                          check=True)
        return [line for line in result.stdout.splitlines() if path in line]

    @staticmethod
    def _mailbox(profile: Profile) -> dict[str, int | bool]:
        # Channel zero control blocks are at offsets 0 and 512 from the configured
        # channel base.  seq_end is the final big-endian word of each block.
        facts: dict[str, int | bool] = {}
        with open(profile.mailbox, "rb", buffering=0) as image:
            for name, delta in (("h2g", 0), ("g2h", 512)):
                image.seek(profile.channel_host_byte + delta)
                block = image.read(512)
                if len(block) != 512:
                    raise OSError("short mailbox control block")
                magic, seq, length, ack = struct.unpack_from(">IIII", block)
                seq_end = struct.unpack_from(">I", block, 508)[0]
                facts.update({f"{name}_magic": magic, f"{name}_seq": seq,
                              f"{name}_len": length, f"{name}_ack": ack,
                              f"{name}_torn": seq != seq_end})
        return facts

    def inspect(self, profile: Profile) -> GateResult:
        try:
            for tool in (profile.pppd, profile.iptables, "/usr/bin/ss", "/usr/bin/ping"):
                if not os.path.isfile(tool) or not os.access(tool, os.X_OK):
                    return GateResult("TOOL_MISSING", {"tool": tool})
            manifest = pathlib.Path(profile.manifest).read_text()
            if f"RUN_ID={profile.run_id}\n" not in manifest:
                return GateResult("RUN_MISMATCH")
            argv = pathlib.Path(f"/proc/{profile.bridge_pid}/cmdline").read_bytes().split(b"\0")
            joined = b" ".join(argv).decode(errors="replace")
            if (self._proc_start(profile.bridge_pid) != profile.bridge_start_id or
                    "host-chan.py bridge 0" not in joined or
                    profile.channel_socket not in joined):
                return GateResult("BRIDGE_DOWN")
            lines = self._ss(profile.channel_socket)
            if not any("LISTEN" in line for line in lines):
                return GateResult("BRIDGE_DOWN")
            established = [line for line in lines if "ESTAB" in line]
            if established:
                return GateResult("STALE_CARRIER", {"socket_lines": established})
            queued = []
            for line in lines:
                fields = line.split()
                if len(fields) >= 4:
                    try:
                        if int(fields[2]) or int(fields[3]):
                            queued.append(line)
                    except ValueError:
                        pass
            if queued:
                return GateResult("STALE_CARRIER", {"socket_lines": queued})
            mailbox = self._mailbox(profile)
            if (mailbox["h2g_magic"] != 0x4E494147 or
                    mailbox["g2h_magic"] != 0x4E494147 or
                    mailbox["h2g_torn"] or mailbox["g2h_torn"] or
                    mailbox["h2g_len"] > 523776 or mailbox["g2h_len"] > 523776):
                return GateResult("DIRTY_MAILBOX", mailbox)
            if (mailbox["h2g_seq"] > mailbox["g2h_ack"] or
                    mailbox["g2h_seq"] > mailbox["h2g_ack"]):
                return GateResult("DIRTY_MAILBOX", mailbox)
            if pathlib.Path(f"/sys/class/net/{profile.ppp_interface}").exists():
                return GateResult("DUPLICATE_PEER")
            for cmdline in pathlib.Path("/proc").glob("[0-9]*/cmdline"):
                try:
                    words = cmdline.read_bytes().replace(b"\0", b" ")
                except OSError:
                    continue
                if (b"pppd" in words and
                        f"{profile.host_address}:{profile.guest_address}".encode() in words):
                    return GateResult("DUPLICATE_PEER", {"pid": cmdline.parent.name})
            upstream = self.run(["/usr/bin/ping", "-I", profile.upstream_interface,
                                 "-c", "1", "-W", "2", "8.8.8.8"],
                                capture_output=True, text=True)
            if upstream.returncode:
                return GateResult("NO_UPSTREAM")
            return GateResult(facts=mailbox)
        except (OSError, subprocess.SubprocessError) as exc:
            return GateResult("BRIDGE_DOWN", {"detail": type(exc).__name__})

    def ensure_run_network(self, profile: Profile) -> GateResult:
        tag = f"niagara-{profile.run_id}"
        rules = [
            ([], ["FORWARD", "-s", f"{profile.guest_address}/32", "-i", "ppp0",
                  "-o", profile.upstream_interface, "-m", "conntrack", "--ctstate",
                  "NEW,ESTABLISHED,RELATED", "-m", "comment", "--comment",
                  f"{tag}-out", "-j", "ACCEPT"]),
            ([], ["FORWARD", "-d", f"{profile.guest_address}/32", "-i",
                  profile.upstream_interface, "-o", "ppp0", "-m", "conntrack",
                  "--ctstate", "ESTABLISHED,RELATED", "-m", "comment", "--comment",
                  f"{tag}-return", "-j", "ACCEPT"]),
            (["-t", "nat"], ["POSTROUTING", "-s", f"{profile.guest_address}/32",
                  "-o", profile.upstream_interface, "-m", "comment", "--comment",
                  f"{tag}-nat", "-j", "MASQUERADE"]),
        ]
        adopted, created = [], []
        forwarding_changed = False
        failure_code = "FORWARDING_FAILED"
        try:
            forward = self.forwarding_path.read_text().strip()
            if forward != "1":
                self.forwarding_path.write_text("1\n")
                forwarding_changed = True
            failure_code = "NAT_FAILED"
            for table, rule in rules:
                check = [profile.iptables, *table, "-C", *rule]
                if self.run(check, capture_output=True).returncode == 0:
                    adopted.append(rule[-3])
                    continue
                self.run([profile.iptables, *table, "-A", *rule], check=True,
                         capture_output=True)
                created.append((table, rule))
            return GateResult(facts={"adopted": adopted,
                                     "created": [r[-3] for _, r in created],
                                     "rules": [" ".join([profile.iptables, *table,
                                                          "-A", *rule])
                                               for table, rule in rules],
                                     "forwarding": "adopted" if forward == "1" else "enabled"})
        except (OSError, subprocess.SubprocessError):
            for table, rule in reversed(created):
                self.run([profile.iptables, *table, "-D", *rule], capture_output=True)
            if forwarding_changed:
                try:
                    self.forwarding_path.write_text(f"{forward}\n")
                except OSError:
                    pass
            return GateResult(failure_code)

    def launch_peer(self, profile: Profile, request_id: str) -> Peer:
        conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        conn.connect(profile.channel_socket)
        logdir = pathlib.Path(f"/var/lib/niagara-isp/{profile.run_id}/requests/{request_id}")
        logdir.mkdir(mode=0o700, parents=True, exist_ok=False)
        log = open(logdir / "pppd.log", "ab", buffering=0)
        argv = [profile.pppd, "notty", "noauth", "local", "noccp", "nodeflate",
                "nobsdcomp", "novj", "asyncmap", "0",
                f"{profile.host_address}:{profile.guest_address}", "nodetach", "debug",
                "lcp-max-configure", "10", "lcp-restart", "3"]
        child = subprocess.Popen(argv, stdin=conn, stdout=conn, stderr=log,
                                 close_fds=True)
        self.children[child.pid] = child
        start = self._proc_start(child.pid)
        return Peer(child.pid, start, f"inode:{os.fstat(conn.fileno()).st_ino}",
                    str(logdir / "pppd.log"))

    def peer_alive(self, peer: Peer) -> bool:
        child = self.children.get(peer.pid)
        if child is not None and child.poll() is not None:
            return False
        try:
            return self._proc_start(peer.pid) == peer.start_id and pathlib.Path(
                f"/proc/{peer.pid}").exists()
        except (OSError, IndexError):
            return False

    def adopt_peer(self, profile: Profile, peer: Peer) -> bool:
        if not self.peer_alive(peer):
            return False
        try:
            argv = pathlib.Path(f"/proc/{peer.pid}/cmdline").read_bytes().split(b"\0")
            words = [word.decode(errors="replace") for word in argv if word]
            expected = [profile.pppd, "notty", "noauth", "local", "noccp",
                        "nodeflate", "nobsdcomp", "novj", "asyncmap", "0",
                        f"{profile.host_address}:{profile.guest_address}", "nodetach",
                        "debug", "lcp-max-configure", "10", "lcp-restart", "3"]
            expected_inode = int(peer.socket_id.removeprefix("inode:"))
            fds_match = (os.stat(f"/proc/{peer.pid}/fd/0").st_ino == expected_inode ==
                         os.stat(f"/proc/{peer.pid}/fd/1").st_ino)
            established = [line for line in self._ss(profile.channel_socket)
                           if "ESTAB" in line]
            return words == expected and fds_match and len(established) == 1
        except (OSError, ValueError):
            return False

    def peer_ready(self, profile: Profile, peer: Peer) -> bool:
        time.sleep(0.25)
        established = [line for line in self._ss(profile.channel_socket) if "ESTAB" in line]
        try:
            expected_inode = int(peer.socket_id.removeprefix("inode:"))
            stdin_inode = os.stat(f"/proc/{peer.pid}/fd/0").st_ino
            stdout_inode = os.stat(f"/proc/{peer.pid}/fd/1").st_ino
        except (OSError, ValueError):
            return False
        return (self.peer_alive(peer) and len(established) == 1 and
                stdin_inode == expected_inode == stdout_inode)

    def peer_online(self, profile: Profile, peer: Peer) -> bool:
        try:
            log = pathlib.Path(peer.log_path).read_text(errors="replace")
        except OSError:
            return False
        if (f"local  IP address {profile.host_address}" not in log and
                f"local IP address {profile.host_address}" not in log):
            return False
        if (f"remote IP address {profile.guest_address}" not in log and
                f"remote  IP address {profile.guest_address}" not in log):
            return False
        result = self.run(["/usr/sbin/ip", "-o", "addr", "show", "dev",
                           profile.ppp_interface], capture_output=True, text=True)
        return (result.returncode == 0 and profile.host_address in result.stdout and
                profile.guest_address in result.stdout)

    def peer_negotiating(self, profile: Profile, peer: Peer) -> bool:
        try:
            log = pathlib.Path(peer.log_path).read_text(errors="replace")
        except OSError:
            return False
        return "sent [LCP" in log or "rcvd [LCP" in log

    def stop_peer(self, peer: Peer) -> None:
        if not self.peer_alive(peer):
            return
        os.kill(peer.pid, signal.SIGTERM)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if not self.peer_alive(peer):
                return
            time.sleep(0.05)
        if self.peer_alive(peer):
            os.kill(peer.pid, signal.SIGKILL)


def validate_privileged_inputs(profile_path: str, profile: Profile) -> None:
    """Reject writable/symlinked code inputs before privileged service startup."""
    for value in (profile_path, profile.manifest):
        path = pathlib.Path(value)
        stat_result = path.lstat()
        if path.is_symlink() or stat_result.st_uid != 0 or stat_result.st_mode & 0o022:
            raise SystemExit(f"unsafe privileged input: {path}")
    manifest_run_id = None
    for line in pathlib.Path(profile.manifest).read_text(encoding="ascii").splitlines():
        if line.startswith("RUN_ID="):
            manifest_run_id = line.partition("=")[2]
            break
    if manifest_run_id != profile.run_id:
        raise SystemExit("profile RUN_ID does not match manifest")


def ensure_private_dir(path: pathlib.Path, mode: int) -> None:
    if path.exists() or path.is_symlink():
        stat_result = path.lstat()
        if path.is_symlink() or not path.is_dir() or stat_result.st_uid != 0:
            raise SystemExit(f"unsafe supervisor directory: {path}")
        if stat_result.st_mode & 0o022:
            raise SystemExit(f"writable supervisor directory: {path}")
    else:
        path.mkdir(mode=mode, parents=True)


def serve(profile_path: str, profile: Profile, runtime_dir: str, state_dir: str,
          allowed_uid: int, allowed_gid: int) -> None:
    if os.geteuid() != 0:
        raise SystemExit("isp-supervisor must run as root")
    validate_privileged_inputs(profile_path, profile)
    runtime = pathlib.Path(runtime_dir)
    state = pathlib.Path(state_dir)
    ensure_private_dir(runtime, 0o750)
    ensure_private_dir(state, 0o700)
    lock_fd = os.open(runtime / "prepare.lock", os.O_RDWR | os.O_CREAT, 0o600)
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    sockpath = runtime / "control.sock"
    try:
        sockpath.unlink()
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(sockpath))
    os.chown(sockpath, 0, allowed_gid)
    os.chmod(sockpath, 0o660)
    server.listen(4)
    server.settimeout(0.25)
    supervisor = Supervisor(profile, LinuxHostOperations(), Ledger(str(state / "ledger.jsonl")))
    supervisor.recover()
    while True:
        try:
            conn, _ = server.accept()
        except socket.timeout:
            supervisor._refresh()
            continue
        with conn:
            _, uid, _ = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET,
                                                              socket.SO_PEERCRED, 12))
            if uid != allowed_uid:
                continue
            try:
                raw = bytearray()
                conn.settimeout(2)
                while b"\n" not in raw and len(raw) <= 256:
                    chunk = conn.recv(257 - len(raw))
                    if not chunk:
                        break
                    raw.extend(chunk)
                if not raw.endswith(b"\n"):
                    raise ProtocolError("request is not newline terminated")
                answer = supervisor.handle(parse_request(raw))
            except ProtocolError:
                answer = response("BLOCKED", state="FAILED", code="BAD_REQUEST")
            except Exception:
                answer = response("BLOCKED", state="FAILED", code="INTERNAL")
            conn.sendall(answer.encode("ascii") + b"\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--runtime-dir", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--allowed-uid", required=True, type=int)
    parser.add_argument("--allowed-gid", required=True, type=int)
    args = parser.parse_args()
    profile = Profile.load(args.profile)
    serve(args.profile, profile, args.runtime_dir, args.state_dir,
          args.allowed_uid, args.allowed_gid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
