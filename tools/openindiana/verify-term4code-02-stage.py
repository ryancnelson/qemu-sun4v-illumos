#!/usr/bin/env python3
"""Verify one completed term4code-02 preparation stage from durable evidence."""

import hashlib
import json
import os
from pathlib import Path
import shlex
import sys


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def lines(path):
    return set(Path(path).read_text().splitlines())


def require(condition, message):
    if not condition:
        raise SystemExit(f"VERIFY_FAIL: {message}")


def main():
    require(len(sys.argv) == 2, "usage: verifier STAGE")
    stage = sys.argv[1]
    config = json.loads(Path(os.environ["TERM4CODE02_CONFIG"]).read_text())
    evidence = config["evidence"]
    artifact = config["artifacts"]
    manifest = lines(artifact["installer_manifest"])
    if stage == "verify_pinned_hsimd":
        pinned = config["pinned"]
        p = lines(evidence["pinned_manifest"])
        require(f"hsimd_size_bytes={pinned['hsimd_size']}" in p, "pinned hSIMD size")
        require(f"hsimd_sha256={pinned['hsimd_sha256']}" in p, "pinned hSIMD hash")
    elif stage == "apply_media_v2":
        require("media_fallback_v2:PASS" in manifest, "media V2")
        require("# NIAGARA_HSIMD_MEDIA_FALLBACK_V2" in manifest, "media marker")
    elif stage == "apply_aggregation_literal":
        require("etc_system_literal:set zfs:zfs_vdev_aggregation_limit=0x20000:PASS"
                in manifest, "aggregation literal")
    elif stage in ("stage_donor", "run_mutation"):
        require(Path(evidence["builder_console"]).is_file(), "builder console")
        text = Path(evidence["builder_console"]).read_text(errors="replace")
        require("FILES_PASS" in text and "40201a31bb6b721975ae8ced12f22b1e6f620c8863d352ba411472e464a9a1a0"
                in text, "builder mutation readback")
    elif stage == "reopen_read_only":
        require("archive_reopened_read_only:PASS" in manifest, "read-only reopen")
    elif stage == "publish_immutable":
        release = json.loads(Path(evidence["release_manifest"]).read_text())
        require(release["state"] == "READY", "release state")
        require(release["outputs"]["big_disk"]["sha256"] ==
                evidence["installer_sha256"], "release installer hash")
        require(Path(artifact["installer"]).stat().st_mode & 0o222 == 0,
                "run-local installer must be read-only")
        require(digest(Path(artifact["installer"])) == evidence["installer_sha256"],
                "run-local installer identity")
    elif stage == "verify_unit101":
        p = lines(artifact["channel_manifest"])
        require("mailbox_offsets:verified:PASS" in p, "unit101 offsets")
        require(Path(artifact["channel101"]).stat().st_size == 33554432, "unit101 size")
    elif stage == "verify_unit104":
        p = lines(artifact["unit104_manifest"])
        for item in ("all_features_disabled:PASS", "clean_export:PASS",
                     "loop_detached:PASS"):
            require(item in p, f"unit104 {item}")
        require(Path(artifact["unit104"]).stat().st_size == 64424509440,
                "unit104 size")
    elif stage == "prepare_qemu_argv":
        value = " ".join(shlex.split(Path(artifact["qemu_argv"]).read_text()))
        for item in ("-smp 1", "unit=101,", "unit=103,readonly=on,",
                     "unit=104,readonly=off,", "-serial unix:", "-monitor unix:"):
            require(item in value, f"argv {item}")
        require("-serial stdio" not in value, "unsafe serial")
    else:
        raise SystemExit(f"VERIFY_FAIL: unknown stage {stage}")
    print(f"{stage}:PASS")


if __name__ == "__main__":
    main()
