#!/usr/bin/env python3
"""Unprivileged constrained client for the run-scoped ISP supervisor."""

from __future__ import annotations

import socket

from isp_protocol import MAX_LINE, ProtocolError, parse_request, validate_response


def transact(socket_path: str, command: str, timeout: float = 3.0) -> str:
    # Validate before connecting: the BBS cannot use this as an arbitrary command
    # transport to a privileged process.
    parse_request(command + "\n")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(timeout)
        conn.connect(socket_path)
        conn.sendall(command.encode("ascii") + b"\n")
        data = bytearray()
        while b"\n" not in data:
            chunk = conn.recv(MAX_LINE + 2 - len(data))
            if not chunk:
                raise ProtocolError("supervisor closed without response")
            data.extend(chunk)
            if len(data) > MAX_LINE + 1:
                raise ProtocolError("supervisor response too long")
    if data.count(b"\n") != 1 or not data.endswith(b"\n"):
        raise ProtocolError("invalid supervisor response framing")
    try:
        line = data[:-1].decode("ascii")
    except UnicodeDecodeError as exc:
        raise ProtocolError("non-ASCII supervisor response") from exc
    return validate_response(line)
