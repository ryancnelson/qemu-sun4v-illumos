import importlib.util
import socket
import threading
import time
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "ec2trib-niagara-openboot.py"
SPEC = importlib.util.spec_from_file_location("niagara_openboot", HELPER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


COMMAND = "boot /virtual-devices@100/disk@4:a -k -v"
LOGIN = "oi-basecamp console login:"


def run_fake_console(
    after_echo: bytes,
    hold_seconds: float = 0,
    prompt: bytes = b"ok ",
):
    received = bytearray()
    client, server = socket.socketpair()

    def serve():
        with server:
            server.sendall(b"OpenBoot test firmware\r\n" + prompt)
            while not received.endswith(b"\r"):
                chunk = server.recv(4096)
                if not chunk:
                    return
                received.extend(chunk)
            server.sendall(b"ok " + bytes(received))
            server.sendall(after_echo)
            time.sleep(hold_seconds)

    thread = threading.Thread(target=serve)
    thread.start()
    return client, thread, received


def test_waits_for_prompt_sends_command_and_requires_login():
    client, thread, received = run_fake_console(
        b"\r\nroot on rpool/ROOT/openindiana fstype zfs"
        b"\r\nTransitioning root-minimal to maintenance because it completes a dependency cycle"
        b"\r\n" + LOGIN.encode()
    )
    with client:
        MODULE.run_command_until(client, COMMAND, LOGIN, timeout=2)
    thread.join(timeout=2)

    assert bytes(received) == COMMAND.encode() + b"\r"


def test_accepts_cpu_prefixed_openboot_prompt_from_smp_firmware():
    client, thread, received = run_fake_console(
        b"\r\n" + LOGIN.encode(),
        prompt=b"{0} ok ",
    )
    with client:
        MODULE.run_command_until(client, COMMAND, LOGIN, timeout=2)
    thread.join(timeout=2)

    assert bytes(received) == COMMAND.encode() + b"\r"


def test_command_echo_alone_cannot_pass():
    client, thread, _ = run_fake_console(b"")
    with client, pytest.raises(RuntimeError, match="console disconnected"):
        MODULE.run_command_until(client, COMMAND, LOGIN, timeout=2)
    thread.join(timeout=2)


def test_command_echo_without_terminal_result_times_out():
    client, thread, _ = run_fake_console(b"", hold_seconds=0.2)
    with client, pytest.raises(TimeoutError, match="observation timed out"):
        MODULE.run_command_until(client, COMMAND, LOGIN, timeout=0.05)
    thread.join(timeout=2)


@pytest.mark.parametrize(
    "terminal",
    [
        b"\r\npanic[cpu0]/thread=deadbeef: test panic\r\n",
        b"\r\nok ",
        b"\r\nEnter user name for system maintenance: ",
    ],
)
def test_terminal_failure_markers_fail_before_login(terminal):
    client, thread, _ = run_fake_console(terminal)
    with client, pytest.raises(RuntimeError, match="terminal failure"):
        MODULE.run_command_until(client, COMMAND, LOGIN, timeout=2)
    thread.join(timeout=2)


def test_helper_emits_distinct_login_gate_marker():
    text = HELPER.read_text()

    assert "NIAGARA_OPENBOOT_COMMAND=PASS" in text
    assert "NIAGARA_LOGIN_GATE=PASS" in text
