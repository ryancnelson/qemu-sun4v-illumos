#!/usr/bin/env python3
"""Read-only QMP/HMP snapshot for a live QEMU Unix socket."""

import argparse
import json
import socket


def exchange(stream, payload):
    stream.write((json.dumps(payload) + "\r\n").encode())
    stream.flush()
    while True:
        reply = json.loads(stream.readline())
        if "event" not in reply:
            return reply


def hmp(stream, command, cpu_index=None):
    arguments = {"command-line": command}
    if cpu_index is not None:
        arguments["cpu-index"] = cpu_index
    return exchange(stream, {
        "execute": "human-monitor-command",
        "arguments": arguments,
    })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket")
    parser.add_argument("--cpu", type=int, action="append",
                        help="vCPU index to inspect (repeatable)")
    parser.add_argument("--command", action="append",
                        help="read-only HMP command to run (repeatable)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(args.socket)
    with sock, sock.makefile("rwb", buffering=0) as stream:
        greeting = json.loads(stream.readline())
        print(json.dumps(greeting, sort_keys=True))
        print(json.dumps(exchange(stream, {"execute": "qmp_capabilities"}),
                         sort_keys=True))
        print(json.dumps(exchange(stream, {"execute": "query-status"}),
                         sort_keys=True))
        commands = args.command or ["info registers", "info tlb"]
        cpus = args.cpu or [0, 1]
        for cpu_index in cpus:
            for command in commands:
                reply = hmp(stream, command, cpu_index)
                print(f"--- {command} cpu={cpu_index} ---")
                print(reply.get("return", json.dumps(reply, sort_keys=True)))


if __name__ == "__main__":
    main()
