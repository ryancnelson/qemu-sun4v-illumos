#!/usr/bin/env python3
"""Host-side QA parser/ordering helper; never used inside OpenIndiana."""

from __future__ import annotations

import re
import time
from collections.abc import Callable

READY = re.compile(
    r"^ISP READY id=([0-9a-f]{4,32}) state=READY "
    r"host=10\.0\.5\.1 guest=10\.0\.5\.15 expires=45$"
)


class ReadyError(ValueError):
    pass


def parse_ready(transcript: str) -> tuple[str, str]:
    lines = [line.rstrip("\r") for line in transcript.splitlines()
             if line.rstrip("\r").startswith("ISP ")]
    if len(lines) != 1:
        raise ReadyError("expected exactly one ISP response")
    match = READY.fullmatch(lines[0])
    if not match:
        raise ReadyError("ISP response is not the fixed READY barrier")
    return match.group(1), lines[0]


def prepare_then_launch(prepare: Callable[[], str], launch: Callable[[str], None],
                        monotonic: Callable[[], float] = time.monotonic) -> str:
    started = monotonic()
    request_id, _ = parse_ready(prepare())
    if monotonic() - started >= 45:
        raise ReadyError("ISP READY expired")
    launch(request_id)
    return request_id
