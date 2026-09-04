#!/usr/bin/python3

import argparse
import re
import socket
import sys
import time


PROMPT = re.compile(rb"(?:^|[\r\n])(?:\{[0-9a-fA-F]+\} )?ok ")
TERMINAL_FAILURES = (
    ("kernel panic", re.compile(rb"(?:^|[\r\n])panic(?:\[cpu[0-9]+\])?(?:/|:)")),
    ("returned OpenBoot prompt", PROMPT),
    (
        "maintenance shell",
        re.compile(
            rb"Enter user name for system maintenance"
            rb"|Type control-d to proceed with normal startup"
            rb"|Requesting System Maintenance Mode"
        ),
    ),
)


def fail(message: str) -> int:
    print(f"NIAGARA_LOGIN_GATE=FAIL reason={message}", file=sys.stderr)
    return 1


def receive_until(
    connection: socket.socket,
    deadline: float,
    predicate,
    failures=(),
    initial=b"",
) -> bytes:
    observed = bytearray(initial)
    while time.monotonic() < deadline:
        snapshot = bytes(observed)
        for label, pattern in failures:
            if pattern.search(snapshot):
                raise RuntimeError(f"terminal failure: {label}")
        if predicate(snapshot):
            return snapshot
        connection.settimeout(min(1.0, max(0.01, deadline - time.monotonic())))
        try:
            chunk = connection.recv(4096)
        except TimeoutError:
            continue
        if not chunk:
            raise RuntimeError("console disconnected")
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        observed.extend(chunk)
        if len(observed) > 131072:
            del observed[:-65536]
    raise TimeoutError("console observation timed out")


def run_command_until(
    connection: socket.socket,
    command: str,
    success_marker: str,
    timeout: float,
) -> None:
    deadline = time.monotonic() + timeout
    receive_until(connection, deadline, lambda data: PROMPT.search(data) is not None)
    encoded_command = command.encode("ascii")
    connection.sendall(encoded_command + b"\r")
    echo_stream = receive_until(
        connection,
        deadline,
        lambda data: encoded_command in data,
    )
    command_end = echo_stream.find(encoded_command) + len(encoded_command)
    post_echo = echo_stream[command_end:]
    encoded_success = success_marker.encode("ascii")
    receive_until(
        connection,
        deadline,
        lambda data: encoded_success in data,
        failures=TERMINAL_FAILURES,
        initial=post_echo,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Boot Niagara at OpenBoot and require a guest success marker"
    )
    parser.add_argument("--socket", required=True)
    parser.add_argument("--command", required=True)
    parser.add_argument("--success-marker", required=True)
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()

    if not args.command or "\r" in args.command or "\n" in args.command:
        return fail("command must be one non-empty line")
    if (
        not args.success_marker
        or "\r" in args.success_marker
        or "\n" in args.success_marker
    ):
        return fail("success marker must be one non-empty line fragment")
    if args.timeout <= 0:
        return fail("timeout must be positive")

    deadline = time.monotonic() + args.timeout
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        while True:
            try:
                connection.connect(args.socket)
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if time.monotonic() >= deadline:
                    return fail("console socket did not accept a connection")
                time.sleep(0.1)

        run_command_until(
            connection,
            args.command,
            args.success_marker,
            timeout=max(0.01, deadline - time.monotonic()),
        )
    except (OSError, RuntimeError, TimeoutError, UnicodeEncodeError) as exc:
        return fail(str(exc))
    finally:
        connection.close()

    print(f"NIAGARA_OPENBOOT_COMMAND=PASS command={args.command}")
    print(f"NIAGARA_LOGIN_GATE=PASS marker={args.success_marker}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
