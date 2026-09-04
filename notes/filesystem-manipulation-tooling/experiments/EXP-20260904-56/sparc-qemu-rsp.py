#!/usr/bin/env python3
"""Inspect or redirect a QEMU SPARC64 CPU using the minimal GDB RSP surface."""

import argparse
import socket


def checksum(payload: bytes) -> bytes:
    return f"{sum(payload) & 0xff:02x}".encode("ascii")


class RSP:
    def __init__(self, path: str):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)

    def command(self, text: str) -> str:
        payload = text.encode("ascii")
        self.sock.sendall(b"$" + payload + b"#" + checksum(payload))
        while True:
            lead = self.sock.recv(1)
            if not lead:
                raise RuntimeError("QEMU closed the debugger connection")
            if lead == b"+":
                continue
            if lead == b"-":
                raise RuntimeError(f"QEMU rejected RSP command {text!r}")
            if lead != b"$":
                continue

            reply = bytearray()
            while True:
                byte = self.sock.recv(1)
                if byte == b"#":
                    break
                if not byte:
                    raise RuntimeError("QEMU closed the debugger reply")
                reply.extend(byte)
            received_sum = self.sock.recv(2)
            expected_sum = checksum(bytes(reply))
            if received_sum.lower() != expected_sum:
                self.sock.sendall(b"-")
                raise RuntimeError(
                    f"bad RSP checksum: received {received_sum!r}, expected {expected_sum!r}"
                )
            self.sock.sendall(b"+")
            return reply.decode("ascii")


def register_offset(register_number: int) -> int:
    """Return the byte offset in QEMU's SPARC64 g packet."""
    if register_number < 32:
        return register_number * 8
    if register_number < 64:
        return 32 * 8 + (register_number - 32) * 4
    return 32 * 8 + 32 * 4 + (register_number - 64) * 8


def read_register(packet: str, register_number: int, size: int = 8) -> int:
    start = register_offset(register_number) * 2
    end = start + size * 2
    return int(packet[start:end], 16)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("socket")
    parser.add_argument("--enter-kmdb", action="store_true")
    args = parser.parse_args()

    rsp = RSP(args.socket)
    stop = rsp.command("?")
    registers = rsp.command("g")
    if len(registers) != 1120:
        raise RuntimeError(
            f"expected 560-byte SPARC64 register packet, got {len(registers) // 2} bytes"
        )

    pc = read_register(registers, 80)
    npc = read_register(registers, 81)
    print(f"RSP_STOP={stop}")
    print(f"RSP_REGISTER_BYTES={len(registers) // 2}")
    print(f"PC_BEFORE=0x{pc:016x}")
    print(f"NPC_BEFORE=0x{npc:016x}")

    if args.enter_kmdb:
        new_pc = 0x0101B230
        new_npc = 0x0101B234
        for number, value, label in (
            (80, new_pc, "PC"),
            (81, new_npc, "NPC"),
        ):
            reply = rsp.command(f"P{number:x}={value:016x}")
            if reply != "OK":
                raise RuntimeError(f"failed to write {label}: {reply}")

        verified = rsp.command("g")
        pc_after = read_register(verified, 80)
        npc_after = read_register(verified, 81)
        print(f"PC_AFTER=0x{pc_after:016x}")
        print(f"NPC_AFTER=0x{npc_after:016x}")
        if (pc_after, npc_after) != (new_pc, new_npc):
            raise RuntimeError("PC/NPC verification failed; leaving VM paused")

    detached = rsp.command("D")
    print(f"RSP_DETACH={detached}")


if __name__ == "__main__":
    main()
