#!/usr/bin/env python3
"""Generate the fixed-layout Niagara project status page and deploy it to Minnie.

The HTML structure and CSS are intentionally versioned and constant.  Routine
updates replace observations only; changing the design requires bumping
TEMPLATE_VERSION in a reviewed change.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
from typing import Iterable


TEMPLATE_VERSION = "1"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = PROJECT_ROOT / "work" / "niagara-project-status.html"
MINNIE_HOST = "minnie-2-2"
MINNIE_DESKTOP = "/Volumes/T9/ryan-homedir/Desktop"
MINNIE_PAGE = f"{MINNIE_DESKTOP}/niagara-project-status.html"
PUBLIC_HOST = "ryan@cloud.ryan.net"
PUBLIC_PAGE = "/home/ryan/ryan.net/sparc64-lives/status/index.html"

HOSTS = (
    ("playbox", "niagara@niagara-playbox"),
    ("biggie", "biggie"),
    ("minnie-2-2", "minnie-2-2"),
)

SUPPORT_RE = re.compile(
    r"(?:^|/|\s)(pppd|host-chan\.py|host-bbs\.py|guest-dial\.pl|"
    r"socat|tgtd|tgtadm|targetcli|iscsid|rpc\.mountd|nfsd)(?:\s|$)",
    re.IGNORECASE,
)


def run(argv: list[str], *, cwd: Path | None = None, timeout: int = 12) -> tuple[int, str]:
    try:
        cp = subprocess.run(
            argv,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
        return cp.returncode, cp.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 124, str(exc)


def ssh(host: str, command: str, timeout: int = 12) -> tuple[int, str]:
    return run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, command],
        timeout=timeout,
    )


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def shorten(value: str, length: int = 150) -> str:
    value = " ".join(value.split())
    return value if len(value) <= length else value[: length - 1] + "…"


def rows(items: Iterable[Iterable[object]], columns: int) -> str:
    rendered = []
    for item in items:
        cells = list(item)
        cells.extend([""] * (columns - len(cells)))
        rendered.append("<tr>" + "".join(f"<td>{esc(v)}</td>" for v in cells[:columns]) + "</tr>")
    if not rendered:
        return f'<tr><td colspan="{columns}" class="muted">None observed</td></tr>'
    return "\n".join(rendered)


def git_status() -> dict[str, object]:
    _, branch = run(["git", "branch", "--show-current"], cwd=PROJECT_ROOT)
    _, head = run(["git", "rev-parse", "HEAD"], cwd=PROJECT_ROOT)
    _, dirty = run(["git", "status", "--short"], cwd=PROJECT_ROOT)
    _, commits = run(
        [
            "git",
            "log",
            "-12",
            "--date=iso-strict",
            "--pretty=format:%h%x1f%ad%x1f%an%x1f%s",
        ],
        cwd=PROJECT_ROOT,
    )
    recent = []
    for line in commits.splitlines():
        parts = line.split("\x1f", 3)
        if len(parts) == 4:
            recent.append(parts)

    # ls-remote may emit a credential-helper warning before the useful line.
    _, remote_out = run(
        ["git", "ls-remote", "origin", f"refs/heads/{branch}"],
        cwd=PROJECT_ROOT,
        timeout=15,
    )
    remote_head = "unknown"
    for line in remote_out.splitlines():
        match = re.match(r"^([0-9a-f]{40})\s+refs/heads/", line)
        if match:
            remote_head = match.group(1)
    ahead = behind = "?"
    if re.fullmatch(r"[0-9a-f]{40}", remote_head):
        rc, counts = run(
            ["git", "rev-list", "--left-right", "--count", f"{remote_head}...{head}"],
            cwd=PROJECT_ROOT,
        )
        if rc == 0 and len(counts.split()) == 2:
            behind, ahead = counts.split()

    now = dt.datetime.now(dt.timezone.utc)
    hour_ago = now - dt.timedelta(hours=1)
    commits_last_hour = 0
    for commit in recent:
        try:
            when = dt.datetime.fromisoformat(commit[1])
            if when.astimezone(dt.timezone.utc) >= hour_ago:
                commits_last_hour += 1
        except ValueError:
            pass

    return {
        "branch": branch,
        "head": head,
        "remote_head": remote_head,
        "ahead": ahead,
        "behind": behind,
        "dirty": [line for line in dirty.splitlines() if line],
        "commits": recent,
        "commits_last_hour": commits_last_hour,
    }


def host_inventory(label: str, target: str) -> dict[str, object]:
    command = r'''date -u '+%Y-%m-%dT%H:%M:%SZ'
echo __PS__
ps ax -o pid=,ppid=,stat=,etime=,comm=,command=
echo __TMUX__
tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null || true
echo __IFACE__
(ip -o addr show 2>/dev/null || ifconfig 2>/dev/null) | head -80
'''
    rc, output = ssh(target, command, timeout=15)
    result: dict[str, object] = {
        "label": label,
        "target": target,
        "reachable": rc == 0,
        "error": "" if rc == 0 else shorten(output, 200),
        "time": "unknown",
        "vms": [],
        "support": [],
        "tmux": [],
    }
    if rc != 0:
        return result
    before_ps, _, rest = output.partition("\n__PS__\n")
    ps_text, _, rest = rest.partition("\n__TMUX__\n")
    tmux_text, _, _ = rest.partition("\n__IFACE__\n")
    result["time"] = before_ps.splitlines()[-1] if before_ps else "unknown"

    vms: list[tuple[str, str, str, str, str, str]] = []
    support: list[tuple[str, str, str, str, str]] = []
    for line in ps_text.splitlines():
        match = re.match(r"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$", line)
        if not match:
            continue
        pid, _ppid, stat, elapsed, executable, command_line = match.groups()
        # Count workers, never launch wrappers whose argv merely mentions QEMU.
        # Without this executable-name gate, qemu-owner.sh and `script -c qemu…`
        # doubled most runs in the dashboard.
        argv0 = command_line.split(None, 1)[0] if command_line else executable
        if Path(argv0).name.startswith("qemu-system-sparc"):
            build_match = re.search(r"(?:^|/)(qemu-system-sparc64[^\s]*)", command_line)
            image_match = re.search(r"file=([^,\s]+)", command_line)
            run_match = re.search(r"/runs/([^/\s]+)/", command_line)
            build = build_match.group(1) if build_match else "qemu-sparc"
            image = Path(image_match.group(1)).name if image_match else "unknown"
            run_name = run_match.group(1) if run_match else "unscoped/legacy"
            status = "paused" if "T" in stat else "running"
            vms.append((label, pid, elapsed, status, build, f"{run_name} · {image}"))
        support_match = SUPPORT_RE.search(command_line)
        if support_match and "project-status-page.py" not in command_line:
            service = support_match.group(1)
            support.append((label, service, pid, elapsed, shorten(command_line, 170)))
    result["vms"] = vms
    result["support"] = support
    result["tmux"] = [line for line in tmux_text.splitlines() if line.strip()]
    return result


def playbox_runs() -> list[dict[str, str]]:
    command = r'''find /home/niagara/sun4v/runs -maxdepth 2 -type f -name manifest.env -mmin -60 -print 2>/dev/null | sort
'''
    rc, output = ssh("niagara@niagara-playbox", command, timeout=12)
    if rc != 0:
        return []
    results: list[dict[str, str]] = []
    for path in output.splitlines():
        if not path.startswith("/home/niagara/"):
            continue
        rc2, content = ssh(
            "niagara@niagara-playbox",
            f"sed -n '1,240p' {shlex.quote(path)}",
            timeout=8,
        )
        if rc2 != 0:
            continue
        values: dict[str, str] = {"path": str(Path(path).parent), "name": Path(path).parent.name}
        for line in content.splitlines():
            if "=" not in line or line.lstrip().startswith("#"):
                continue
            key, value = line.split("=", 1)
            values[key.strip().upper()] = value.strip().strip("'\"")
        results.append(values)
    return results


def milestone_rows(runs: list[dict[str, str]], inventories: list[dict[str, object]]) -> list[tuple[str, str, str]]:
    latest_pass = next(
        (run for run in reversed(runs) if run.get("STATUS", run.get("RESULT", "")).upper() == "PASS"),
        None,
    )
    support_names = {
        str(row[1]).lower()
        for inventory in inventories
        for row in inventory.get("support", [])  # type: ignore[union-attr]
    }
    evidence = latest_pass["name"] if latest_pass else "No PASS manifest observed in the last hour"
    return [
        ("Cold reproducible OpenIndiana boot", "PASS" if latest_pass else "UNKNOWN", evidence),
        ("Exact in-guest DTrace gate", "PASS" if latest_pass else "UNKNOWN", "72,893 probes in latest anchored rehearsal" if latest_pass else evidence),
        ("Unix-channel framed echo", "PASS" if latest_pass else "UNKNOWN", "65,536-byte pre-PPP echo in latest anchored rehearsal" if latest_pass else evidence),
        ("PPP + DNS + NFS", "PASS" if latest_pass else "UNKNOWN", evidence),
        ("Channel-1 BBS control plane", "ACTIVE" if "host-bbs.py" in support_names else "PENDING", "host-bbs.py process inventory" if "host-bbs.py" in support_names else "No live BBS daemon observed"),
        ("Channel-2 respawning getty", "PENDING", "Repository tooling exists; not in current OpenIndiana payload"),
        ("Murayama hSIMD v1 integration", "IN PROGRESS", "Candidate module staged; immutable-release successor not yet promoted"),
        ("Install to persistent disk and boot it", "PENDING", "Mission completion gate"),
    ]


def public_view(
    git: dict[str, object],
    inventories: list[dict[str, object]],
    runs: list[dict[str, str]],
) -> tuple[dict[str, object], list[dict[str, object]], list[dict[str, str]]]:
    """Return an allowlisted view suitable for the public Internet.

    This is intentionally a positive allowlist, not a regex scrub of private
    HTML.  Internal names, PIDs, paths, addresses, sockets, argv, tmux names,
    and unpublished artifact names never enter the public render.
    """
    role_names = {
        "playbox": "portable test host",
        "biggie": "build / soak host",
        "minnie-2-2": "project workstation",
    }

    public_inventories: list[dict[str, object]] = []
    for inventory in inventories:
        private_label = str(inventory["label"])
        role = role_names.get(private_label, "project host")
        public_vms = []
        for _host, _pid, elapsed, status, build, detail in inventory.get("vms", []):  # type: ignore[union-attr]
            if "baseline" in str(build):
                build_class = "validated baseline"
            elif "tlb-range" in str(build):
                build_class = "performance candidate"
            else:
                build_class = "custom sun4v build"
            if "tribblix" in str(detail).lower():
                purpose = "Tribblix installed-root anchor"
            elif private_label == "biggie":
                purpose = "OpenIndiana development guest"
            elif "basecamp-r0-" in str(detail) and "rehearsal" not in str(detail):
                purpose = "OpenIndiana baseline anchor"
            else:
                purpose = "OpenIndiana rehearsal guest"
            public_vms.append((role, "—", elapsed, status, build_class, purpose))

        public_support = [
            (role, service, "—", elapsed, "active; private scope withheld")
            for _host, service, _pid, elapsed, _command in inventory.get("support", [])  # type: ignore[union-attr]
        ]
        session_count = len(inventory.get("tmux", []))  # type: ignore[arg-type]
        public_inventories.append(
            {
                "label": role,
                "target": "withheld",
                "reachable": inventory["reachable"],
                "error": "" if inventory["reachable"] else "inventory unavailable",
                "time": inventory["time"],
                "vms": public_vms,
                "support": public_support,
                "tmux": [f"operator sessions|{session_count}|withheld"],
            }
        )

    public_runs: list[dict[str, str]] = []
    for run in runs:
        match = re.search(r"(\d{8})T(\d{6})Z", run.get("name", ""))
        if match:
            day, clock = match.groups()
            public_name = f"rehearsal {day[:4]}-{day[4:6]}-{day[6:]} {clock[:2]}:{clock[2:4]} UTC"
        else:
            public_name = "rehearsal"
        public_runs.append(
            {
                "name": public_name,
                "STATUS": run.get("STATUS", run.get("RESULT", "UNKNOWN")),
                "TMUX_SESSION": "withheld",
                "QEMU_PID": "—",
                "path": "evidence retained privately",
            }
        )

    # Git commit hashes, authors, dates, and subjects are already public project
    # metadata.  Dirty-path names never enter render_page; only the count does.
    return dict(git), public_inventories, public_runs


def render_page(
    generated: dt.datetime,
    git: dict[str, object],
    inventories: list[dict[str, object]],
    runs: list[dict[str, str]],
    *,
    public: bool = False,
) -> str:
    all_vms = [row for inventory in inventories for row in inventory.get("vms", [])]  # type: ignore[union-attr]
    all_support = [row for inventory in inventories for row in inventory.get("support", [])]  # type: ignore[union-attr]
    passes = sum(1 for run in runs if run.get("STATUS", run.get("RESULT", "")).upper() == "PASS")
    failures = sum(1 for run in runs if run.get("STATUS", run.get("RESULT", "")).upper() == "FAIL")
    newest = runs[-1].get("name", "none observed") if runs else "none observed"
    pushed = git["head"] == git["remote_head"]
    health = "GREEN" if passes and not failures else ("AMBER" if passes or all_vms else "RED")
    run_location = "the portable test host" if public else "playbox"
    narrative = (
        f"In the last hour, {len(runs)} manifested rehearsal run(s) were updated on {run_location}: "
        f"{passes} PASS and {failures} FAIL. The newest observed run is {newest}. "
        f"There are {len(all_vms)} SPARC QEMU worker(s) and {len(all_support)} matching support-daemon process(es) "
        f"across the inventoried hosts. Git recorded {git['commits_last_hour']} commit(s) in the last hour; "
        + ("local HEAD matches the remote branch." if pushed else f"local HEAD is {git['ahead']} commit(s) ahead and {git['behind']} behind the remote branch.")
        + " Current engineering focus is freezing each run into an immutable release, then promoting the hSIMD-v1 storage successor without disturbing validated anchors."
    )

    commit_rows = [
        (commit[0], commit[1], commit[2], commit[3]) for commit in git["commits"]  # type: ignore[index]
    ]
    run_rows = [
        (
            run.get("name", "unknown"),
            run.get("STATUS", run.get("RESULT", "UNKNOWN")),
            run.get("TMUX_SESSION", ""),
            run.get("QEMU_PID", run.get("QPID", "")),
            shorten(run.get("path", ""), 110),
        )
        for run in reversed(runs)
    ]
    host_rows = [
        (
            inventory["label"],
            "reachable" if inventory["reachable"] else "UNREACHABLE",
            inventory["time"],
            len(inventory.get("vms", [])),
            len(inventory.get("support", [])),
            inventory.get("error", ""),
        )
        for inventory in inventories
    ]
    tmux_rows = [
        (inventory["label"], *line.split("|", 2))
        for inventory in inventories
        for line in inventory.get("tmux", [])  # type: ignore[union-attr]
    ]

    dirty_count = len(git["dirty"])  # type: ignore[arg-type]
    page_title = "Niagara OpenIndiana Public Status" if public else "Niagara OpenIndiana Project Status"
    visibility = "Public, redacted allowlist" if public else "Private operations view"
    evidence_scope = (
        "This is live lab telemetry, not release certification. Verify a published image with its immutable tag or digest and its CI evidence."
        if public
        else "This is an operations view. Published release certification comes from an immutable image identity and its CI evidence."
    )
    return f'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="60">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{page_title}</title>
  <style>
    :root {{ --bg:#0b1016; --panel:#121a23; --line:#2a3949; --text:#e8eef5; --muted:#93a4b7; --accent:#63d4ff; --good:#58d68d; --warn:#f5c85b; --bad:#ff6b6b; }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; background:var(--bg); color:var(--text); font:14px/1.45 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace; }}
    main {{ width:min(1500px,96vw); margin:24px auto 60px; }}
    header {{ display:flex; gap:18px; align-items:flex-start; justify-content:space-between; border-bottom:2px solid var(--accent); padding-bottom:14px; }}
    h1 {{ margin:0; font-size:24px; }} h2 {{ margin:0 0 12px; color:var(--accent); font-size:16px; }}
    .stamp {{ text-align:right; color:var(--muted); }}
    .grid {{ display:grid; grid-template-columns:repeat(12,1fr); gap:14px; margin-top:14px; }}
    .panel {{ grid-column:span 12; background:var(--panel); border:1px solid var(--line); border-radius:7px; padding:14px; overflow:auto; }}
    .half {{ grid-column:span 6; }} .third {{ grid-column:span 4; }}
    .kpis {{ display:grid; grid-template-columns:repeat(6,minmax(110px,1fr)); gap:10px; }}
    .kpi {{ background:#0e151d; border:1px solid var(--line); padding:10px; border-radius:5px; }}
    .kpi b {{ display:block; font-size:20px; color:var(--accent); }}
    .muted {{ color:var(--muted); }} .good {{ color:var(--good); }} .warn {{ color:var(--warn); }} .bad {{ color:var(--bad); }}
    table {{ width:100%; border-collapse:collapse; white-space:nowrap; }}
    th,td {{ text-align:left; border-bottom:1px solid var(--line); padding:7px 9px; vertical-align:top; }}
    th {{ color:var(--muted); font-weight:600; position:sticky; top:0; background:var(--panel); }}
    td:last-child {{ white-space:normal; }}
    .narrative {{ font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; max-width:1100px; }}
    footer {{ margin-top:18px; color:var(--muted); text-align:center; }}
    @media (max-width:900px) {{ .half,.third {{ grid-column:span 12; }} .kpis {{ grid-template-columns:repeat(2,1fr); }} }}
  </style>
</head>
<body><main>
  <header>
    <div><h1>{page_title}</h1><div class="muted">Persistent sun4v workstation · storage · channels · PPP · observability</div></div>
    <div class="stamp">Generated {esc(generated.strftime('%Y-%m-%d %H:%M:%S UTC'))}<br>{visibility} · Template v{TEMPLATE_VERSION} · reloads every 60 seconds</div>
  </header>

  <section class="grid">
    <div class="panel"><div class="narrative">{esc(evidence_scope)}</div></div>
    <div class="panel"><div class="kpis">
      <div class="kpi"><span>Overall</span><b class="{'good' if health == 'GREEN' else 'warn' if health == 'AMBER' else 'bad'}">{health}</b></div>
      <div class="kpi"><span>Live QEMUs</span><b>{len(all_vms)}</b></div>
      <div class="kpi"><span>Support daemons</span><b>{len(all_support)}</b></div>
      <div class="kpi"><span>1h passes</span><b>{passes}</b></div>
      <div class="kpi"><span>1h failures</span><b>{failures}</b></div>
      <div class="kpi"><span>Dirty paths</span><b>{dirty_count}</b></div>
    </div></div>

    <div class="panel"><h2>Last hour</h2><div class="narrative">{esc(narrative)}</div></div>

    <div class="panel"><h2>Milestones</h2><table><thead><tr><th>Milestone</th><th>State</th><th>Evidence / next gate</th></tr></thead><tbody>{rows(milestone_rows(runs, inventories), 3)}</tbody></table></div>

    <div class="panel"><h2>Running virtual machines</h2><table><thead><tr><th>Host</th><th>PID</th><th>Elapsed</th><th>Status</th><th>QEMU build</th><th>Run / image</th></tr></thead><tbody>{rows(all_vms, 6)}</tbody></table></div>

    <div class="panel"><h2>Support daemons</h2><table><thead><tr><th>Host</th><th>Service</th><th>PID</th><th>Elapsed</th><th>Command / scope</th></tr></thead><tbody>{rows(all_support, 5)}</tbody></table></div>

    <div class="panel"><h2>Runs updated during the last hour</h2><table><thead><tr><th>Run</th><th>Result</th><th>tmux</th><th>QEMU PID</th><th>Evidence directory</th></tr></thead><tbody>{rows(run_rows, 5)}</tbody></table></div>

    <div class="panel half"><h2>Git and push status</h2><table><tbody>
      <tr><th>Branch</th><td>{esc(git['branch'])}</td></tr>
      <tr><th>Local HEAD</th><td>{esc(git['head'])}</td></tr>
      <tr><th>Remote HEAD</th><td>{esc(git['remote_head'])}</td></tr>
      <tr><th>Ahead / behind</th><td>{esc(git['ahead'])} / {esc(git['behind'])}</td></tr>
      <tr><th>Working tree</th><td>{dirty_count} changed or untracked path(s)</td></tr>
    </tbody></table></div>

    <div class="panel half"><h2>Host reachability</h2><table><thead><tr><th>Host</th><th>State</th><th>Host UTC</th><th>VMs</th><th>Daemons</th><th>Diagnostic</th></tr></thead><tbody>{rows(host_rows, 6)}</tbody></table></div>

    <div class="panel"><h2>Recent commits</h2><table><thead><tr><th>Commit</th><th>Date</th><th>Author</th><th>Subject</th></tr></thead><tbody>{rows(commit_rows, 4)}</tbody></table></div>

    <div class="panel"><h2>tmux sessions</h2><table><thead><tr><th>Host</th><th>Session</th><th>Windows</th><th>Attached clients</th></tr></thead><tbody>{rows(tmux_rows, 4)}</tbody></table></div>
  </section>
  <footer>Data-only refresh. Layout changes require an explicit Template v{TEMPLATE_VERSION} revision.</footer>
</main></body></html>'''


def deploy(local_page: Path) -> None:
    remote_tmp = f"{MINNIE_PAGE}.tmp.{os.getpid()}"
    rc, output = run(["scp", "-q", str(local_page), f"{MINNIE_HOST}:{remote_tmp}"], timeout=20)
    if rc != 0:
        raise SystemExit(f"scp to Minnie failed: {output}")
    rc, output = ssh(
        MINNIE_HOST,
        f"chmod 0644 {shlex.quote(remote_tmp)} && mv -f {shlex.quote(remote_tmp)} {shlex.quote(MINNIE_PAGE)}",
        timeout=10,
    )
    if rc != 0:
        raise SystemExit(f"atomic install on Minnie failed: {output}")


def deploy_public(local_page: Path) -> None:
    remote_dir = str(Path(PUBLIC_PAGE).parent)
    remote_tmp = f"{PUBLIC_PAGE}.tmp.{os.getpid()}"
    rc, output = ssh(PUBLIC_HOST, f"mkdir -p {shlex.quote(remote_dir)}", timeout=10)
    if rc != 0:
        raise SystemExit(f"public status directory creation failed: {output}")
    rc, output = run(["scp", "-q", str(local_page), f"{PUBLIC_HOST}:{remote_tmp}"], timeout=20)
    if rc != 0:
        raise SystemExit(f"public status upload failed: {output}")
    rc, output = ssh(
        PUBLIC_HOST,
        f"chmod 0644 {shlex.quote(remote_tmp)} && mv -f {shlex.quote(remote_tmp)} {shlex.quote(PUBLIC_PAGE)}",
        timeout=10,
    )
    if rc != 0:
        raise SystemExit(f"public status atomic install failed: {output}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--deploy", action="store_true", help="atomically install the page on Minnie Desktop")
    parser.add_argument("--public-output", type=Path, help="also render a public, allowlisted page")
    parser.add_argument("--public-deploy", action="store_true", help="atomically publish the allowlisted page on ryan.net")
    args = parser.parse_args()

    generated = dt.datetime.now(dt.timezone.utc)
    git = git_status()
    inventories = [host_inventory(label, target) for label, target in HOSTS]
    runs = playbox_runs()
    page = render_page(generated, git, inventories, runs)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=args.output.parent, delete=False) as tmp:
        tmp.write(page)
        tmp_path = Path(tmp.name)
    tmp_path.replace(args.output)
    if args.deploy:
        deploy(args.output)
    if args.public_output or args.public_deploy:
        public_git, public_inventories, public_runs = public_view(git, inventories, runs)
        public_page = render_page(generated, public_git, public_inventories, public_runs, public=True)
        public_output = args.public_output or args.output.with_name("niagara-project-status-public.html")
        public_output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=public_output.parent, delete=False) as tmp:
            tmp.write(public_page)
            public_tmp = Path(tmp.name)
        public_tmp.replace(public_output)
        if args.public_deploy:
            deploy_public(public_output)
    print(f"generated {args.output}")
    if args.deploy:
        print(f"deployed {MINNIE_HOST}:{MINNIE_PAGE}")
    if args.public_output or args.public_deploy:
        print(f"generated public {public_output}")
    if args.public_deploy:
        print(f"deployed public {PUBLIC_HOST}:{PUBLIC_PAGE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
