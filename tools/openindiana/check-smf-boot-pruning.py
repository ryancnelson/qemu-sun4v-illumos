#!/usr/bin/env python3
"""Validate and canonically render the offline OpenIndiana SMF pruning plan.

This checker has no apply mode and invokes no system or guest command.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys


SCHEMA = "qemu-sun4v-illumos/openindiana-smf-pruning/v1"
DEFAULT_MANIFEST = Path(__file__).with_name("openindiana-smf-boot-pruning-v1.json")
AUTHORITY = "ryan-approval-after-successful-cold-reboot-login-required"
FMRI = re.compile(r"^svc:/[A-Za-z0-9_.+/-]+:[A-Za-z0-9_.+-]+$")
PROTECTED_CAPABILITIES = {
    "channel_ppp": {
        "patterns": [r"^svc:/site/niagara", r"(?:channel|ppp|sppp)"],
        "reason": "preserve channel endpoints, PPP supervision, and link startup",
    },
    "nfs": {
        "patterns": [r"^svc:/network/(?:nfs|rpc/)"],
        "reason": "preserve NFS client and RPC dependencies",
    },
    "console_login": {
        "patterns": [
            r"^svc:/milestone/(?:multi-user|multi-user-server)",
            r"^svc:/milestone/sysconfig",
            r"^svc:/system/(?:console-login|utmp|sac|tty|cryptosvc)",
            r"^svc:/network/ssh",
        ],
        "reason": "preserve serial console, login, multi-user, and remote login",
    },
    "devfs": {
        "patterns": [r"^svc:/milestone/devices", r"^svc:/system/device"],
        "reason": "preserve device enumeration and devfsadm ordering",
    },
    "filesystem": {
        "patterns": [
            r"^svc:/system/(?:filesystem|boot-archive|identity)",
            r"^svc:/milestone/single-user",
        ],
        "reason": "preserve root, local, and boot filesystem dependencies",
    },
    "zfs": {
        "patterns": [r"zfs"],
        "reason": "preserve rpool import, ZFS mounts, and installed root",
    },
    "networking": {
        "patterns": [
            r"^svc:/network/(?:physical|ip-interface-management|initial|routing|netmask|varpd)",
            r"^svc:/network/(?:dns/client|loopback|service)",
            r"^svc:/milestone/(?:network|name-services)",
        ],
        "reason": "preserve interfaces, routes, DNS policy, and network milestones",
    },
    "observability": {
        "patterns": [
            r"^svc:/system/(?:system-log|logging|svc/restarter|audit)",
            r"^svc:/(?:application/management|security/audit)",
        ],
        "reason": "preserve SMF restarter, logs, management, and audit evidence",
    },
}


class ManifestError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise ManifestError(message)


def load_manifest(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read manifest {path}: {exc}")
    if not isinstance(value, dict):
        fail("manifest root must be an object")
    return value


def protected_match(fmri: str) -> str | None:
    for capability, policy in PROTECTED_CAPABILITIES.items():
        for pattern in policy["patterns"]:
            if re.search(pattern, fmri, re.IGNORECASE):
                return capability
    return None


def validate_candidate(value: object) -> dict[str, object]:
    if not isinstance(value, dict):
        fail("each candidate must be an object")
    required = {"fmri", "action", "rationale", "evidence", "apply", "rollback"}
    if set(value) != required:
        fail(f"candidate keys mismatch: {sorted(set(value) ^ required)}")
    fmri = value["fmri"]
    if not isinstance(fmri, str) or not FMRI.fullmatch(fmri):
        fail(f"invalid canonical FMRI: {fmri!r}")
    protected = protected_match(fmri)
    if protected:
        fail(f"candidate {fmri} violates protected capability {protected}")
    if value["action"] != "disable":
        fail(f"candidate {fmri} has unsupported action {value['action']!r}")
    apply = f"svcadm disable -s {fmri}"
    rollback = f"svcadm enable -s {fmri}"
    if value["apply"] != apply or value["rollback"] != rollback:
        fail(f"candidate {fmri} apply/rollback command is not mechanical")
    if not isinstance(value["rationale"], str) or not value["rationale"].strip():
        fail(f"candidate {fmri} lacks rationale")
    evidence = value["evidence"]
    if (
        not isinstance(evidence, list)
        or not evidence
        or any(not isinstance(item, str) or not item.strip() for item in evidence)
    ):
        fail(f"candidate {fmri} lacks evidence citations")
    return {
        "fmri": fmri,
        "action": "disable",
        "apply": apply,
        "rollback": rollback,
        "rationale": value["rationale"],
        "evidence": sorted(evidence),
    }


def check_manifest(manifest: dict[str, object]) -> dict[str, object]:
    required = {
        "schema",
        "profile",
        "mode",
        "authority",
        "protected_capabilities",
        "candidates",
    }
    if set(manifest) != required:
        fail(f"manifest keys mismatch: {sorted(set(manifest) ^ required)}")
    if manifest["schema"] != SCHEMA:
        fail(f"unsupported manifest schema: {manifest['schema']!r}")
    if manifest["profile"] != "openindiana-sun4v-basecamp-conservative-v1":
        fail(f"unexpected profile: {manifest['profile']!r}")
    if manifest["mode"] != "dry-run-only" or manifest["authority"] != AUTHORITY:
        fail("manifest does not preserve dry-run and Ryan-approval boundaries")
    if manifest["protected_capabilities"] != PROTECTED_CAPABILITIES:
        fail("manifest protected-capability policy differs from checker policy")
    raw_candidates = manifest["candidates"]
    if not isinstance(raw_candidates, list) or not raw_candidates:
        fail("manifest must contain at least one candidate")
    candidates = [validate_candidate(item) for item in raw_candidates]
    names = [str(item["fmri"]) for item in candidates]
    if len(names) != len(set(names)):
        fail("manifest contains duplicate candidate FMRIs")
    candidates.sort(key=lambda item: str(item["fmri"]))
    return {
        "schema": SCHEMA,
        "profile": manifest["profile"],
        "status": "SMF_PRUNING_DRY_RUN_PASS",
        "mode": "dry-run-only",
        "apply_allowed": False,
        "authority": AUTHORITY,
        "protected_capabilities": sorted(PROTECTED_CAPABILITIES),
        "candidate_count": len(candidates),
        "candidates": candidates,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", type=Path, default=DEFAULT_MANIFEST)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = check_manifest(load_manifest(args.manifest))
    except ManifestError as exc:
        print(f"SMF_PRUNING_DRY_RUN_FAIL: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
