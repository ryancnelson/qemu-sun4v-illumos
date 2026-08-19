#!/usr/bin/env python3
"""The ISP / BBS on a virtual serial port (P2-020).

A 2005 Solaris guest dials a channel, gets CONNECT, lands in character mode at a
prompt, and can either ask an oracle for things or type STARTPPP to flip that same
line into PPP -- exactly the dial-up terminal-server model.

    guest#  socat - UNIX-CONNECT:/tmp/niag1
    ATDT18005551212
    CONNECT 2400
    ... banner ...
    isp> ASK which library has nanosleep on solaris 10
    isp> GET libiconv sparc solaris 8
    isp> STARTPPP

WHY THIS IS NOT A TOY. Every wall this project hit was a knowledge problem, not a
compute problem: libssp was misplaced rather than missing, nanosleep lives in librt,
/bin/grep has no -E, gmake 3.80 is too old for libtommath, and CSW SunOS5.10 builds
breach this image's SUNW_1.22.1 libc ceiling. A guest that can ask a question over
/dev/term/b answers those in one line instead of one build cycle. GET matters even
more: choosing a CSW package requires checking a version ceiling against the running
image, which is tedious for a person and trivial for a model with internet.

STARTPPP also solves the guest-initiated-networking problem for free: the caller
decides when to switch, so nothing on the host has to be run by hand after a reboot.

DESIGN NOTES
  * Line protocol, CRLF, ASCII, wrapped to 72 columns. The guest side may be `cat`,
    `socat`, or a tip-style session; none of them handle long lines well.
  * One caller at a time, with an accept loop so the daemon survives hangups. The
    channel daemons enforce single-writer, and so does this.
  * No third-party imports: this has to run anywhere on the host without a venv.
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import textwrap
import time
import urllib.error
import urllib.request

LLM_URL = os.environ.get("BBS_LLM_URL", "http://100.87.104.29:8317/v1/chat/completions")
LLM_MODEL = os.environ.get("BBS_LLM_MODEL", "gemini-3-flash")
DELIVERY = os.environ.get("BBS_DELIVERY", "/export/solaris/chan")

SYSTEM = """You are the oracle behind a dial-up BBS in 2005, answering a sysadmin \
logged in from a Solaris 10 SPARC machine (SunOS 5.10, Generic_118822-23, gcc 4.3.3, \
libc version ceiling SUNW_1.22.1, no OpenSSL, /bin/sh is real Bourne, /bin/grep has \
no -E, GNU make 3.80 only).

Answer in plain ASCII, no markdown, no bullets with special characters, under 15 \
lines. Be specific and actionable: name exact paths, libraries and flags. If a \
library seems missing on Solaris 10, consider that it is probably MISPLACED \
(/usr/sfw/lib, /opt/csw/lib) rather than absent. Prefer answers that work within the \
constraints above."""


def wrap(text: str, width: int = 72) -> list[str]:
    out: list[str] = []
    for para in text.replace("\r", "").split("\n"):
        out.extend(textwrap.wrap(para, width) or [""])
    return out


def ask_llm(prompt: str, system: str = SYSTEM, timeout: int = 90) -> str:
    body = json.dumps({
        "model": LLM_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
    }).encode()
    req = urllib.request.Request(
        LLM_URL, data=body, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.load(r)
        return data["choices"][0]["message"]["content"].strip()
    except urllib.error.URLError as e:
        return f"ERROR: oracle unreachable ({e.reason})"
    except (KeyError, IndexError, json.JSONDecodeError) as e:
        return f"ERROR: malformed oracle reply ({e})"


class Session:
    """One caller. Writes CRLF, reads lines, never raises at the caller."""

    def __init__(self, conn: socket.socket, chan_path: str):
        self.conn = conn
        self.chan_path = chan_path
        self.buf = b""
        self.online = False

    def send(self, *lines: str) -> None:
        payload = "".join(f"{ln}\r\n" for ln in lines)
        try:
            self.conn.sendall(payload.encode("ascii", "replace"))
        except OSError:
            pass

    def readline(self, timeout: float = 300.0) -> str | None:
        self.conn.settimeout(timeout)
        while b"\n" not in self.buf:
            try:
                chunk = self.conn.recv(4096)
            except (socket.timeout, OSError):
                return None
            if not chunk:
                return None
            self.buf += chunk
        line, _, self.buf = self.buf.partition(b"\n")
        return line.decode("ascii", "replace").strip()

    # --- commands -----------------------------------------------------------

    def cmd_ask(self, arg: str) -> None:
        if not arg:
            self.send("Usage: ASK <question>")
            return
        self.send("...thinking, this is a 2400 baud oracle...")
        for ln in wrap(ask_llm(arg)):
            self.send(ln)

    def cmd_get(self, arg: str) -> None:
        """Have the oracle name a URL, fetch it here, and report the local path."""
        if not arg:
            self.send("Usage: GET <what you need>")
            return
        self.send("...searching...")
        prompt = (
            f"The user needs: {arg}\n\n"
            "Reply with ONE line only: a single direct download URL, nothing else, no "
            "prose. It must be compatible with Solaris 10 SPARC and must not require a "
            "libc newer than SUNW_1.22.1 (so prefer SunOS5.8 or SunOS5.9 builds from "
            "http://mirror.opencsw.org/opencsw/allpkgs/ over SunOS5.10 ones). If you "
            "cannot name one, reply exactly: NONE"
        )
        url = ask_llm(prompt, system="You reply with a bare URL or NONE.").split()
        url = url[-1] if url else "NONE"
        if not url.startswith("http"):
            self.send("No candidate found. Try ASK to narrow it down first.")
            return
        self.send(f"URL: {url}", "fetching...")
        os.makedirs(DELIVERY, exist_ok=True)
        name = os.path.basename(url.split("?")[0]) or "download.bin"
        dest = os.path.join(DELIVERY, name)
        rc = subprocess.run(
            ["curl", "-sSL", "-m", "300", "-o", dest, url],
            capture_output=True, text=True,
        )
        if rc.returncode != 0 or not os.path.exists(dest):
            self.send(f"FETCH FAILED: {rc.stderr.strip()[:200]}")
            return
        size = os.path.getsize(dest)
        cks = subprocess.run(["cksum", dest], capture_output=True, text=True).stdout.split()
        self.send(
            f"DELIVERED {size} bytes",
            f"  host path : {dest}",
            f"  guest path: /share/chan/{name}   (mount -F nfs 10.0.5.1:/export/solaris /share)",
            f"  cksum     : {cks[0] if cks else '?'}",
        )

    def cmd_startppp(self) -> bool:
        """Flip this line to PPP by exec'ing pppd on the caller's fd."""
        self.send("Entering PPP mode. Local 10.0.5.1, remote 10.0.5.15.", "")
        fd = self.conn.fileno()
        os.dup2(fd, 0)
        os.dup2(fd, 1)
        os.execv("/usr/sbin/pppd", [
            "pppd", "notty", "noauth", "local",
            # Solaris sppp implements neither CCP (logs 'unknown protocol 0xfd') nor VJ.
            "noccp", "nodeflate", "nobsdcomp", "novj",
            "persist", "maxfail", "0",
            "asyncmap", "0xffffffff",
            "10.0.5.1:10.0.5.15", "nodetach",
        ])
        return False  # not reached

    # --- main loop ----------------------------------------------------------

    BANNER = (
        "",
        "+----------------------------------------------------------------+",
        "|  T H E   S U N S E T   B B S              node 1, 2400 baud    |",
        "|  'all the news and warez a sun4v could want'                   |",
        "+----------------------------------------------------------------+",
        "",
        "Welcome. This line is a terminal until you say otherwise.",
        "",
        "  ASK <question>   ask the oracle anything",
        "  GET <thing>      have a file fetched and delivered to /share/chan",
        "  TIME [zone]      current time",
        "  HELP             this list",
        "  STARTPPP         switch this line to networking mode",
        "  BYE              hang up",
        "",
    )

    def run(self) -> None:
        # Modem phase. Accept any AT command; answer a dial with CONNECT.
        while not self.online:
            line = self.readline(timeout=120)
            if line is None:
                return
            up = line.upper()
            if not up:
                continue
            if up.startswith("ATD"):
                time.sleep(1.2)  # the handshake you remember
                self.send("CONNECT 2400")
                self.online = True
            elif up.startswith("AT"):
                self.send("OK")
            else:
                self.send("Type ATDT<number> to dial.")

        self.send(*self.BANNER)
        while True:
            self.send("isp> ")
            line = self.readline()
            if line is None:
                return
            cmd, _, arg = line.partition(" ")
            cmd, arg = cmd.upper(), arg.strip()
            if cmd in ("BYE", "ATH", "QUIT", "EXIT"):
                self.send("NO CARRIER")
                return
            elif cmd == "HELP":
                self.send(*self.BANNER)
            elif cmd == "TIME":
                zone = arg or "UTC"
                self.cmd_ask(f"What is the current time in {zone}? One line.")
            elif cmd == "ASK":
                self.cmd_ask(arg)
            elif cmd == "GET":
                self.cmd_get(arg)
            elif cmd == "STARTPPP":
                self.cmd_startppp()
                return
            elif cmd:
                self.send(f"Unknown command '{cmd}'. Type HELP.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("socket", nargs="?", default="/run/niag1",
                    help="unix socket to serve (default /run/niag1)")
    ap.add_argument("--listen", action="store_true",
                    help="bind and listen instead of connecting to an existing socket")
    args = ap.parse_args()

    if args.listen:
        # Test mode: we own the socket. Real mode connects to the channel bridge.
        if os.path.exists(args.socket):
            os.unlink(args.socket)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(args.socket)
        os.chmod(args.socket, 0o666)
        srv.listen(1)
        print(f"bbs: listening on {args.socket}", flush=True)
        while True:
            conn, _ = srv.accept()
            print("bbs: caller connected", flush=True)
            try:
                Session(conn, args.socket).run()
            finally:
                conn.close()
                print("bbs: caller gone", flush=True)
    else:
        # Channel mode: the bridge already owns the socket; we are its client.
        while True:
            conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                conn.connect(args.socket)
            except OSError as e:
                print(f"bbs: cannot connect {args.socket}: {e}", flush=True)
                return 1
            print("bbs: attached to channel", flush=True)
            try:
                Session(conn, args.socket).run()
            finally:
                conn.close()
            time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
