#!/usr/bin/env python3
"""Fail-closed preparation driver for the bounded term4code-02 trial.

The builder is allowed to boot; the trial is never launched here.  Every
external operation is an explicit argv vector with a timeout and an expected
marker.  A missing donor topology is a typed blocker, not a discovery prompt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time


BLOCKED_TOPOLOGY = "BLOCKED_MISSING_BUILDER_TOPOLOGY"
PRELAUNCH_READY = "PRELAUNCH_READY"
LITERAL = "set zfs:zfs_vdev_aggregation_limit=0x20000"
MEDIA_MARKER = "# NIAGARA_HSIMD_MEDIA_FALLBACK_V2"


class PipelineError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_keys(value: dict, keys: tuple[str, ...], where: str) -> None:
    missing = [key for key in keys if key not in value]
    if missing:
        raise PipelineError(f"{where}: missing {','.join(missing)}")


def validate_config(config: dict) -> None:
    require_keys(config, ("schema_version", "run_id", "run_dir", "pinned",
                          "builder_topology", "artifacts", "commands"), "config")
    if config["schema_version"] != 1 or config["run_id"] != "term4code-02":
        raise PipelineError("config: unsupported schema or run identity")
    topology = config["builder_topology"]
    if not topology:
        raise PipelineError(BLOCKED_TOPOLOGY)
    require_keys(topology, ("run_id", "run_dir", "tmux_session", "console_socket",
                            "monitor_socket", "transport", "work_guest_device", "drives"),
                 "builder_topology")
    if not topology["run_id"].startswith("oi-archive-builder-biggie-"):
        raise PipelineError("builder_topology: wrong disposable run identity")
    if topology["tmux_session"] != topology["run_id"]:
        raise PipelineError("builder_topology: tmux must equal builder run id")
    if Path(topology["run_dir"]).name != topology["run_id"]:
        raise PipelineError("builder_topology: run directory must match builder run id")
    transports = {"pcfs": "/dev/dsk/c0t0d0s3:c",
                  "raw_slice": "/dev/dsk/c4d4s3"}
    if topology["transport"] not in transports:
        raise PipelineError("builder_topology: unsupported transport")
    if topology["work_guest_device"] != transports[topology["transport"]]:
        raise PipelineError("builder_topology: unproven work device")
    units = [drive.get("unit") for drive in topology["drives"]]
    if len(units) != len(set(units)) or not units:
        raise PipelineError("builder_topology: duplicate or absent drive units")
    for drive in topology["drives"]:
        require_keys(drive, ("unit", "role", "path", "readonly"), "builder drive")
        if not drive["path"].startswith(topology["run_dir"] + "/"):
            raise PipelineError("builder_topology: every disk must be run-local")
    pinned = config["pinned"]
    require_keys(pinned, ("boot_archive", "boot_archive_size", "boot_archive_sha256",
                          "hsimd_size", "hsimd_sha256"), "pinned")
    if pinned["boot_archive_size"] <= 0 or pinned["hsimd_size"] <= 0:
        raise PipelineError("pinned: sizes must be positive")
    for key in ("boot_archive_sha256", "hsimd_sha256"):
        value = pinned[key]
        if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
            raise PipelineError(f"pinned: {key} must be lowercase SHA-256")
    artifacts = config["artifacts"]
    require_keys(artifacts, ("installer", "installer_manifest", "channel101",
                             "channel_manifest", "unit104", "unit104_manifest",
                             "qemu_argv"), "artifacts")
    for name, command in config["commands"].items():
        require_keys(command, ("argv", "timeout_seconds", "expect"), f"command {name}")
        if not isinstance(command["argv"], list) or not command["argv"]:
            raise PipelineError(f"command {name}: argv must be nonempty list")
        if not 1 <= command["timeout_seconds"] <= 1200:
            raise PipelineError(f"command {name}: invalid timeout")


def append_evidence(path: Path, event: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(event, sort_keys=True) + "\n")


def run_stage(name: str, spec: dict, evidence: Path, env: dict[str, str]) -> None:
    started = time.time()
    process = subprocess.Popen(spec["argv"], text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, env=env)
    output = ""
    while True:
        remaining = spec["timeout_seconds"] - (time.time() - started)
        if remaining <= 0:
            process.kill()
            tail, _ = process.communicate()
            output = tail or output
            append_evidence(evidence, {"stage": name, "result": "TIMEOUT",
                                       "argv": spec["argv"], "output": output})
            raise PipelineError(f"{name}: timeout")
        try:
            output, _ = process.communicate(timeout=min(60, remaining))
            break
        except subprocess.TimeoutExpired as exc:
            partial = exc.stdout or ""
            if isinstance(partial, bytes):
                partial = partial.decode(errors="replace")
            append_evidence(evidence, {"stage": name, "result": "PROGRESS",
                                       "argv": spec["argv"],
                                       "elapsed": time.time() - started,
                                       "output_tail": partial[-2000:]})
    append_evidence(evidence, {"stage": name, "result": process.returncode,
                               "argv": spec["argv"], "elapsed": time.time() - started,
                               "output": output})
    if process.returncode or spec["expect"] not in output:
        raise PipelineError(f"{name}: expected marker absent or command failed")


def require_identity(path: Path, size: int, digest: str, label: str) -> None:
    if not path.is_file() or path.stat().st_size != size or sha256(path) != digest:
        raise PipelineError(f"{label}: identity mismatch")


def require_manifest(config: dict) -> None:
    manifest = Path(config["artifacts"]["installer_manifest"]).read_text()
    required = (
        "etc_system:zfs_vdev_aggregation_limit=0x20000:PASS",
        f"etc_system_literal:{LITERAL}:PASS",
        "media_fallback_v2:PASS",
        "hsimd_pinned_unchanged:PASS",
        "ramroot_required_mounts_rw:PASS",
        "guest_channel_payload:unit101-block640:PASS",
        "archive_reopened_read_only:PASS",
    )
    for line in required:
        if line not in manifest.splitlines():
            raise PipelineError(f"installer manifest lacks: {line}")
    if MEDIA_MARKER not in manifest:
        raise PipelineError("installer manifest lacks exact media V2 marker")


def require_qemu_argv(config: dict) -> None:
    argv = " ".join(shlex.split(Path(config["artifacts"]["qemu_argv"]).read_text()))
    required = ("-smp 1", "unit=101,", "unit=103,readonly=on,",
                "unit=104,readonly=off,", "-serial unix:", "-monitor unix:")
    for token in required:
        if token not in argv:
            raise PipelineError(f"qemu argv lacks: {token}")
    if "-serial stdio" in argv or "-smp 2" in argv:
        raise PipelineError("qemu argv violates console or one-vCPU policy")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--check-config", action="store_true")
    args = parser.parse_args()
    try:
        config = json.loads(Path(args.config).read_text())
        validate_config(config)
        if args.check_config:
            print("CONFIG_PASS")
            return 0
        run_dir = Path(config["run_dir"])
        evidence = run_dir / "evidence" / "prepare-events.jsonl"
        env = os.environ.copy()
        env["TERM4CODE02_CONFIG"] = str(Path(args.config).resolve())
        pinned = config["pinned"]
        require_identity(Path(pinned["boot_archive"]), pinned["boot_archive_size"],
                         pinned["boot_archive_sha256"], "pinned boot archive")
        for stage in ("verify_pinned_hsimd", "apply_media_v2",
                      "apply_aggregation_literal", "stage_donor", "run_mutation",
                      "reopen_read_only", "publish_immutable", "verify_unit101",
                      "verify_unit104", "prepare_qemu_argv"):
            if stage not in config["commands"]:
                raise PipelineError(f"commands: missing {stage}")
            run_stage(stage, config["commands"][stage], evidence, env)
        require_manifest(config)
        require_qemu_argv(config)
        print(PRELAUNCH_READY)
        return 0
    except (OSError, json.JSONDecodeError, PipelineError) as exc:
        message = str(exc)
        if BLOCKED_TOPOLOGY in message:
            print(BLOCKED_TOPOLOGY)
            return 20
        print(f"PREPARATION_FAILED: {message}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
