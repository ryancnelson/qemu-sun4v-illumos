#!/usr/bin/env python3
"""Validate generated cone meshes and their physical dimensions."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import trimesh


EXPECTED_BOUNDS_MM = np.array([60.0, 60.0, 100.0])


def validate_mesh(path: Path) -> dict:
    mesh = trimesh.load_mesh(path, process=True)
    components = mesh.split(only_watertight=False)
    checks = {
        "exists": path.is_file(),
        "nonempty": not mesh.is_empty,
        "watertight": bool(mesh.is_watertight),
        "is_volume": bool(mesh.is_volume),
        "positive_volume": bool(mesh.volume > 0),
        "single_component": len(components) == 1,
        "bounds_match_mm": bool(
            np.allclose(mesh.bounding_box.extents, EXPECTED_BOUNDS_MM, atol=0.05)
        ),
    }
    report = {
        "path": str(path),
        "checks": checks,
        "vertices": int(len(mesh.vertices)),
        "faces": int(len(mesh.faces)),
        "components": len(components),
        "volume_mm3": float(mesh.volume),
        "bounds_mm": mesh.bounding_box.extents.tolist(),
        "euler_number": int(mesh.euler_number),
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        raise RuntimeError(f"{path.name} failed checks: {', '.join(failed)}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-dir", type=Path, default=Path("artifacts"))
    args = parser.parse_args()

    reports = [
        validate_mesh(args.artifact_dir / "cone_round_bore.stl"),
        validate_mesh(args.artifact_dir / "cone_teardrop_bore.stl"),
    ]
    report_path = args.artifact_dir / "validation.json"
    report_path.write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()

