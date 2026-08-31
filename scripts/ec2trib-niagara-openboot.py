#!/usr/bin/python3

import argparse
import re
import socket
import sys
import time


PROMPT = re.compile(rb"(?:^|[\r\n])ok ")


def fail(message: str) -> int:
    print(f"NIAGARA_OPENBOOT_COMMAND=FAIL reason={message}", file=sys.stderr)
    return 1


def receive_until(connection: socket.socket, deadline: float, predicate) -> bytes:
    observed = bytearray()
    while time.monotonic() < deadline:
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
        if predicate(bytes(observed)):
            return bytes(observed)
        if len(observed) > 131072:
            del observed[:-65536]
    raise TimeoutError("console observation timed out")


def run_command(connection: socket.socket, command: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    receive_until(connection, deadline, lambda data: PROMPT.search(data) is not None)
    encoded_command = command.encode("ascii")
    connection.sendall(encoded_command + b"\r")
    receive_until(connection, deadline, lambda data: encoded_command in data)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Send one command after a Niagara OpenBoot ok prompt"
    )
    parser.add_argument("--socket", required=True)
    parser.add_argument("--command", required=True)
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    if not args.command or "\r" in args.command or "\n" in args.command:
        return fail("command must be one non-empty line")
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

        run_command(
            connection,
            args.command,
            timeout=max(0.01, deadline - time.monotonic()),
        )
    except (OSError, RuntimeError, TimeoutError, UnicodeEncodeError) as exc:
        return fail(str(exc))
    finally:
        connection.close()

    print(f"NIAGARA_OPENBOOT_COMMAND=PASS command={args.command}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
