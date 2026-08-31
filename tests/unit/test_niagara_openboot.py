import importlib.util
import socket
import threading
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "ec2trib-niagara-openboot.py"
SPEC = importlib.util.spec_from_file_location("niagara_openboot", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_waits_for_prompt_sends_command_and_requires_echo():
    command = "boot /virtual-devices@100/disk@4:a -k -v"
    received = bytearray()
    client, server = socket.socketpair()

    def serve():
        with server:
            server.sendall(b"OpenBoot test firmware\r\n")
            server.sendall(b"ok ")
            while not received.endswith(b"\r"):
                received.extend(server.recv(4096))
            server.sendall(b"ok " + bytes(received))

    thread = threading.Thread(target=serve)
    thread.start()
    with client:
        MODULE.run_command(client, command, timeout=2)
    thread.join(timeout=2)

    assert bytes(received) == command.encode() + b"\r"
    assert "NIAGARA_OPENBOOT_COMMAND=PASS" in HELPER.read_text()
