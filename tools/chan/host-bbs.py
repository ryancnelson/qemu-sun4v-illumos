#!/usr/bin/env python3
"""The ISP / BBS on a virtual serial port (P2-020).

A 2005 Solaris guest dials channel 4, gets CONNECT, and lands at a prompt.  The
BBS is also the unprivileged client for the separate, run-scoped ISP supervisor;
it never manipulates channel 0, pppd, or host networking itself.

    guest#  socat - UNIX-CONNECT:/tmp/niag1
    ATDT18005551212
    CONNECT 2400
    ... banner ...
    isp> ASK which library has nanosleep on solaris 10
    isp> GET libiconv sparc solaris 8
    isp> ISP PREPARE

WHY THIS IS NOT A TOY. Every wall this project hit was a knowledge problem, not a
compute problem: libssp was misplaced rather than missing, nanosleep lives in librt,
/bin/grep has no -E, gmake 3.80 is too old for libtommath, and CSW SunOS5.10 builds
breach this image's SUNW_1.22.1 libc ceiling. A guest that can ask a question over
/dev/term/b answers those in one line instead of one build cycle. GET matters even
more: choosing a CSW package requires checking a version ceiling against the running
image, which is tedious for a person and trivial for a model with internet.

ISP PREPARE establishes a barrier: only after the privileged supervisor returns
ISP READY does the guest start its bounded PPP peer on channel 0.

DESIGN NOTES
  * Line protocol, CRLF, ASCII, wrapped to 72 columns. The guest side may be `cat`,
    `socat`, or a tip-style session; none of them handle long lines well.
  * One caller at a time, with an accept loop so the daemon survives hangups. The
    channel daemons enforce single-writer, and so does this.
  * No third-party imports: this has to run anywhere on the host without a venv.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import textwrap
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import isp_client
from isp_protocol import ProtocolError

# Any OpenAI-compatible chat-completions endpoint. No default host: this must be the
# operator's own, so nothing private is baked into the repo. BBS_LLM_KEY is optional
# and sent as a bearer token when set.
LLM_URL = os.environ.get("BBS_LLM_URL", "").strip()
LLM_MODEL = os.environ.get("BBS_LLM_MODEL", "gpt-4o-mini")
LLM_KEY = os.environ.get("BBS_LLM_KEY", "").strip()
DELIVERY = os.environ.get("BBS_DELIVERY", "/export/solaris/chan")
ISP_SOCKET = os.environ.get("BBS_ISP_SOCKET", "").strip()
KERMIT_STAGE = os.environ.get("BBS_KERMIT_STAGE", "").strip()
KERMIT_BIN = os.environ.get("BBS_KERMIT_BIN", "gkermit").strip()
KERMIT_TIMEOUT = 45
SAFE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,126}\Z")

# A tiny local model (100-400 MB, CPU) cannot answer Solaris questions and MUST NOT
# pretend to. Selected with BBS_LLM_TINY=1.
#
# MEASURED, and it decides the default: SmolLM2-135M-Instruct-Q4_K_M (101 MB on disk,
# 226 MB resident under llama-server on arm64) IGNORES this prompt completely. Asked
# which library has nanosleep on Solaris 10 it replied:
#
#     The library that has nanosleep is "libniosleep". This is the only library
#     available that supports this behavior. Specifically, I found this line in the
#     documentation for "niosleep": 00000000000000000000...
#
# An invented library, an invented exclusivity claim, a fabricated documentation quote,
# then a degenerate repetition loop. A model that cannot follow "admit you do not know"
# is WORSE than no oracle, because the person asking is on a 2005 box with no easy way
# to check. So 135M is NOT a shippable default. Anything smaller than ~0.5B should be
# assumed to behave the same way until measured otherwise. Turning the limitation into correct
# behaviour beats confident nonsense: it answers what it can, and for anything
# specific it says so and points at the real fix.
SYSTEM_TINY = """You are a very small, not very clever oracle running on the sysop's own \
machine, reached over a 2400 baud modem by someone using Solaris 10 on SPARC.

You are honest about being limited. Rules:
- Answer general questions briefly and plainly, in ASCII, under 8 lines.
- For anything specific about Solaris, SPARC, compilers, libraries, linker errors or \
package names: DO NOT GUESS. Say you are too small a model to answer reliably, and tell \
them to read the man page or the project docs, or to point the BBS at a real endpoint by \
setting BBS_LLM_URL to a proper API.
- Never invent command names, paths, package names, or version numbers.
- If you are unsure, say so in one sentence and stop. A short honest answer is worth \
more here than a long wrong one."""

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


def ask_llm(prompt: str, system: str | None = None, timeout: int = 90) -> str:
    # BBS_LLM_TINY=1 swaps in a prompt that tells a small model to admit ignorance
    # rather than hallucinate Solaris specifics.
    if system is None:
        system = SYSTEM_TINY if os.environ.get("BBS_LLM_TINY") == "1" else SYSTEM
    body = json.dumps({
        "model": LLM_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": prompt},
        ],
    }).encode()
    if not LLM_URL:
        return ("ERROR: no oracle configured. Set BBS_LLM_URL to an "
                "OpenAI-compatible /v1/chat/completions endpoint.")
    headers = {"Content-Type": "application/json"}
    if LLM_KEY:
        headers["Authorization"] = f"Bearer {LLM_KEY}"
    req = urllib.request.Request(LLM_URL, data=body, headers=headers)
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

    def __init__(self, conn: socket.socket, chan_path: str,
                 modem_timeout: float | None = 120.0):
        self.conn = conn
        self.chan_path = chan_path
        self.modem_timeout = modem_timeout
        self.buf = b""
        self.online = False

    def send(self, *lines: str) -> None:
        payload = "".join(f"{ln}\r\n" for ln in lines)
        try:
            self.conn.sendall(payload.encode("ascii", "replace"))
        except OSError:
            pass

    def readline(self, timeout: float | None = 300.0) -> str | None:
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
        direct_url = arg.startswith(("http://", "https://"))
        if direct_url:
            url = arg
        else:
            self.send("...searching...")
            prompt = (
                f"The user needs: {arg}\n\n"
                "Reply with ONE line only: a single direct download URL, nothing else, no "
                "prose. It must be compatible with Solaris 10 SPARC and must not require a "
                "libc newer than SUNW_1.22.1 (so prefer SunOS5.8 or SunOS5.9 builds from "
                "http://mirror.opencsw.org/opencsw/allpkgs/ over SunOS5.10 ones). If you "
                "cannot name one, reply exactly: NONE"
            )
            words = ask_llm(
                prompt, system="You reply with a bare URL or NONE."
            ).split()
            url = words[-1] if words else "NONE"
        if not url.startswith("http"):
            self.send("No candidate found. Try ASK to narrow it down first.")
            return
        self.send(f"URL: {url}", "checking...")
        os.makedirs(DELIVERY, exist_ok=True)
        name = os.path.basename(url.split("?")[0]) or "download.bin"
        dest = os.path.join(DELIVERY, name)

        # HEAD first. Without this a 404 body downloads "successfully" and the caller
        # is told DELIVERED -- which happened on the first real run: a 345-byte error
        # page was handed over as a .pkg.gz.
        head = subprocess.run(
            ["curl", "-sSIL", "-m", "60", "-o", "/dev/null",
             "-w", "%{http_code} %{size_download}", url],
            capture_output=True, text=True,
        )
        code = (head.stdout.split() or ["000"])[0]
        if code != "200":
            self.send(f"NOT AVAILABLE: server said HTTP {code}",
                      "Try ASK to find the right name, then GET again.")
            return

        self.send("fetching...")
        # -f makes curl fail on HTTP errors instead of saving the error body.
        rc = subprocess.run(
            ["curl", "-fsSL", "-m", "300", "-o", dest, url],
            capture_output=True, text=True,
        )
        if rc.returncode != 0 or not os.path.exists(dest):
            self.send(f"FETCH FAILED: {rc.stderr.strip()[:180] or 'curl error'}")
            return

        size = os.path.getsize(dest)
        with open(dest, "rb") as fh:
            magic = fh.read(8)

        # Validate CONTENT, not just exit status. An HTML error page is the failure
        # mode that actually occurs, and it arrives with a 200 from some mirrors.
        looks_html = magic[:1] == b"<" or b"<html" in magic.lower()
        known = {b"\x1f\x8b": "gzip", b"BZh": "bzip2", b"\x7fELF": "ELF",
                 b"GIF87a": "GIF", b"GIF89a": "GIF", b"\x89PNG": "PNG",
                 b"\xff\xd8\xff": "JPEG", b"ustar": "tar",
                 b"# Pack": "Solaris pkg (datastream)"}
        kind = next((v for k, v in known.items() if magic.startswith(k)), None)
        # A URL supplied explicitly is a general-purpose fetch request, not an
        # oracle-guessed package, so preserve its contents regardless of type.
        if not direct_url and (looks_html or (kind is None and size < 4096)):
            os.unlink(dest)
            self.send(f"REJECTED: got {size} bytes of "
                      f"{'HTML' if looks_html else 'unrecognised data'}, not a package.",
                      "Deleted. The URL was wrong; try ASK first.")
            return

        cks = subprocess.run(["cksum", dest], capture_output=True, text=True).stdout.split()
        self.send(
            f"DELIVERED {size} bytes ({kind or 'unknown type'})",
            f"  host path : {dest}",
            f"  guest path: /share/chan/{name}",
            f"  cksum     : {cks[0] if cks else '?'}",
            "  (guest: mount -F nfs 10.0.5.1:/export/solaris /share)",
        )

    def cmd_kermit_get(self, arg: str) -> None:
        """Fetch a direct URL, then hand this connection to G-Kermit."""
        if not arg:
            self.send("KERMIT BLOCKED code=USAGE")
            return
        if not arg.startswith(("http://", "https://")):
            # Unlike legacy GET, this deterministic command never consults ASK.
            self.send("KERMIT BLOCKED code=DIRECT_URL_REQUIRED")
            return
        if len(arg) > 2048 or any(ch.isspace() for ch in arg):
            self.send("KERMIT BLOCKED code=BAD_URL")
            return
        name = os.path.basename(arg.split("?", 1)[0])
        if not SAFE_NAME.fullmatch(name) or name in (".", ".."):
            self.send("KERMIT BLOCKED code=BAD_NAME")
            return
        if self.buf:
            self.send("KERMIT BLOCKED code=PIPELINED_INPUT")
            return
        if not KERMIT_STAGE or not os.path.isdir(KERMIT_STAGE):
            self.send("KERMIT BLOCKED code=NO_STAGE")
            return
        binary = shutil.which(KERMIT_BIN) if "/" not in KERMIT_BIN else KERMIT_BIN
        if not binary or not os.path.isfile(binary) or not os.access(binary, os.X_OK):
            self.send("KERMIT BLOCKED code=NO_TOOL")
            return
        dest = os.path.join(KERMIT_STAGE, name)
        if os.path.lexists(dest):
            self.send("KERMIT BLOCKED code=AMBIGUOUS_DESTINATION")
            return
        try:
            # Match GET's fail-closed fetch path: reject a non-200 response before
            # creating the staged payload, then make curl reject HTTP errors.
            head = subprocess.run(
                ["curl", "-sSIL", "-m", "60", "-o", "/dev/null",
                 "-w", "%{http_code} %{size_download}", "--", arg],
                capture_output=True, text=True,
            )
            code = (head.stdout.split() or ["000"])[0]
            if head.returncode != 0 or code != "200":
                self.send(f"KERMIT BLOCKED code=FETCH_HTTP status={code}")
                return
            rc = subprocess.run(
                ["curl", "-fsSL", "-m", "300", "--output", dest, "--", arg],
                capture_output=True, text=True,
            )
            st = os.lstat(dest)
            if rc.returncode != 0 or not os.path.isfile(dest) or os.path.islink(dest):
                raise OSError("fetch did not produce a regular file")
            digest = hashlib.sha256()
            with open(dest, "rb") as fh:
                for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                    digest.update(chunk)
            sha256 = digest.hexdigest()
            self.send(f"KERMIT READY name={name} size={st.st_size} "
                      f"sha256={sha256} timeout={KERMIT_TIMEOUT}")
            argv = [binary, "-X", "-q", "-i", "-s", dest, "-a", name]
            proc = subprocess.Popen(argv, stdin=self.conn, stdout=self.conn,
                                    stderr=subprocess.PIPE, close_fds=True)
            try:
                _, stderr = proc.communicate(timeout=KERMIT_TIMEOUT)
            except subprocess.TimeoutExpired:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
                self.send("KERMIT FAILED code=TIMEOUT")
                return
            if proc.returncode != 0:
                self.send(f"KERMIT FAILED code=TRANSFER_EXIT status={proc.returncode}")
                return
            self.send(f"KERMIT DONE name={name} size={st.st_size} sha256={sha256}")
        except OSError:
            self.send("KERMIT BLOCKED code=FETCH_INVALID")
        finally:
            try:
                os.unlink(dest)
            except FileNotFoundError:
                pass

    def cmd_isp(self, arg: str) -> None:
        command = f"ISP {arg}".strip()
        if not ISP_SOCKET:
            self.send("ISP BLOCKED id=- state=FAILED code=SUPERVISOR_UNAVAILABLE")
            return
        try:
            self.send(isp_client.transact(ISP_SOCKET, command))
        except ProtocolError:
            self.send("ISP BLOCKED id=- state=FAILED code=BAD_REQUEST")
        except OSError:
            self.send("ISP BLOCKED id=- state=FAILED code=SUPERVISOR_UNAVAILABLE")

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
        "  KERMIT-GET <URL> fetch and transfer a file (KERMET-GET alias)",
        "  TIME [zone]      current time",
        "  HELP             this list",
        "  ISP PREPARE      prepare bounded channel-0 networking",
        "  ISP STATUS id=ID report ISP state",
        "  ISP ABORT id=ID  abort only that request's host peer",
        "  STARTPPP         deprecated; use ISP PREPARE",
        "  BYE              hang up",
        "",
    )

    def answer_dial(self) -> None:
        """Answer a dial string, including one arriving on a stale online session."""
        time.sleep(1.2)  # the handshake you remember
        self.send("CONNECT 2400")
        self.online = True

    def run(self) -> None:
        # Modem phase. Accept any AT command; answer a dial with CONNECT.
        while not self.online:
            line = self.readline(timeout=self.modem_timeout)
            if line is None:
                return
            up = line.upper()
            if not up:
                continue
            if up.startswith("ATD"):
                self.answer_dial()
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
            elif cmd.startswith("ATD"):
                # The shared-disk channel keeps this host socket open when a guest
                # dialer disappears.  Its replacement therefore reaches the old
                # online Session rather than the modem phase.  Treat a new dial as
                # an explicit logical-session reset on that persistent transport.
                self.answer_dial()
                self.send(*self.BANNER)
            elif cmd == "HELP":
                self.send(*self.BANNER)
            elif cmd == "TIME":
                zone = arg or "UTC"
                self.cmd_ask(f"What is the current time in {zone}? One line.")
            elif cmd == "ASK":
                self.cmd_ask(arg)
            elif cmd == "GET":
                self.cmd_get(arg)
            elif cmd in ("KERMIT-GET", "KERMET-GET"):
                self.cmd_kermit_get(arg)
            elif cmd == "ISP":
                self.cmd_isp(arg)
            elif cmd == "STARTPPP":
                self.send("ISP BLOCKED id=- state=FAILED code=USE_ISP_PREPARE")
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
                # A shared-disk channel is a persistent virtual serial cable.
                # The guest may need several minutes to boot before its first
                # dial, so an idle timeout creates a periodic frame-loss race.
                Session(conn, args.socket, modem_timeout=None).run()
            finally:
                conn.close()
            time.sleep(1)


if __name__ == "__main__":
    sys.exit(main())
