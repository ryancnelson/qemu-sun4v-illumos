#!/usr/bin/env python3
"""Strict, line-oriented protocol for the run-scoped ISP supervisor."""

from __future__ import annotations

import re
from dataclasses import dataclass

MAX_LINE = 256
ID_RE = re.compile(r"^[0-9a-f]{4,32}$")
STATES = {"IDLE", "CHECKING", "READY", "NEGOTIATING", "ONLINE",
          "EXPIRED", "FAILED"}


class ProtocolError(ValueError):
    pass


@dataclass(frozen=True)
class Request:
    action: str
    request_id: str | None = None


def parse_request(raw: bytes | str) -> Request:
    if isinstance(raw, bytes):
        try:
            raw = raw.decode("ascii")
        except UnicodeDecodeError as exc:
            raise ProtocolError("non-ASCII request") from exc
    try:
        encoded = raw.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ProtocolError("non-ASCII request") from exc
    if len(encoded) > MAX_LINE:
        raise ProtocolError("request too long")
    if "\r" in raw:
        raw = raw.replace("\r\n", "\n")
    if raw.count("\n") > 1 or ("\n" in raw and not raw.endswith("\n")):
        raise ProtocolError("one request per connection")
    line = raw.rstrip("\n")
    if line == "ISP PREPARE":
        return Request("PREPARE")
    match = re.fullmatch(r"ISP (STATUS|ABORT) id=([0-9a-f]+)", line)
    if not match or not ID_RE.fullmatch(match.group(2)):
        raise ProtocolError("invalid request")
    return Request(match.group(1), match.group(2))


def response(kind: str, *, request_id: str = "-", state: str,
             **fields: object) -> str:
    if kind not in {"READY", "STATUS", "ABORTED", "BLOCKED"}:
        raise ProtocolError("invalid response kind")
    if request_id != "-" and not ID_RE.fullmatch(request_id):
        raise ProtocolError("invalid response id")
    if state not in STATES:
        raise ProtocolError("invalid state")
    parts = ["ISP", kind, f"id={request_id}", f"state={state}"]
    for key, value in fields.items():
        if not re.fullmatch(r"[a-z][a-z0-9_]*", key):
            raise ProtocolError("invalid field name")
        text = str(value)
        if not text or re.search(r"\s|[^\x21-\x7e]", text):
            raise ProtocolError("invalid field value")
        parts.append(f"{key}={text}")
    return " ".join(parts)


def validate_response(line: str) -> str:
    try:
        encoded = line.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ProtocolError("non-ASCII response") from exc
    if len(encoded) > MAX_LINE or "\n" in line or "\r" in line:
        raise ProtocolError("invalid response framing")
    tokens = line.split(" ")
    if len(tokens) < 4 or tokens[0] != "ISP":
        raise ProtocolError("invalid response")
    if tokens[1] not in {"READY", "STATUS", "ABORTED", "BLOCKED"}:
        raise ProtocolError("invalid response kind")
    seen = set()
    values = {}
    for token in tokens[2:]:
        if token.count("=") != 1:
            raise ProtocolError("invalid response field")
        key, value = token.split("=", 1)
        if key in seen or not value:
            raise ProtocolError("duplicate or empty response field")
        seen.add(key)
        values[key] = value
    if set(("id", "state")) - seen or values["state"] not in STATES:
        raise ProtocolError("missing or invalid required field")
    if values["id"] != "-" and not ID_RE.fullmatch(values["id"]):
        raise ProtocolError("invalid response id")
    return line
