#!/usr/bin/env python3
"""Generate parametric cone-with-through-hole CAD artifacts.

The canonical geometry is an exact OpenCascade B-rep. STL and 3MF files are
derived meshes; STEP preserves the editable solid geometry.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import types
from dataclasses import asdict, dataclass
from pathlib import Path

# CadQuery's OCP wrapper probes the legacy top-level ``vtk`` module even when
# no visualization is requested.  Importing that compatibility module eagerly
# loads the entire VTK stack and is unnecessary for headless CAD generation.
sys.modules.setdefault("vtk", types.ModuleType("vtk"))

import cadquery as cq
import trimesh


@dataclass(frozen=True)
class ConeParameters:
    height_mm: float = 100.0
    base_diameter_mm: float = 60.0
    top_diameter_mm: float = 0.0
    bore_diameter_mm: float = 10.0
    bore_center_height_mm: float = 50.0
    cutter_overrun_mm: float = 4.0

    def validate(self) -> None:
        if self.height_mm <= 0:
            raise ValueError("height_mm must be positive")
        if self.base_diameter_mm <= 0:
            raise ValueError("base_diameter_mm must be positive")
        if not 0 <= self.top_diameter_mm < self.base_diameter_mm:
            raise ValueError("top_diameter_mm must be non-negative and smaller than the base")
        if self.bore_diameter_mm <= 0:
            raise ValueError("bore_diameter_mm must be positive")
        if not 0 < self.bore_center_height_mm < self.height_mm:
            raise ValueError("bore center must lie between the base and tip")
        local_cone_diameter = self.base_diameter_mm + (
            self.top_diameter_mm - self.base_diameter_mm
        ) * (self.bore_center_height_mm / self.height_mm)
        if self.bore_diameter_mm >= local_cone_diameter:
            raise ValueError(
                "bore diameter must be smaller than the cone diameter at bore height"
            )
        if self.cutter_overrun_mm <= 0:
            raise ValueError("cutter_overrun_mm must be positive")


def make_cone(params: ConeParameters) -> cq.Shape:
    return cq.Solid.makeCone(
        params.base_diameter_mm / 2.0,
        params.top_diameter_mm / 2.0,
        params.height_mm,
        cq.Vector(0, 0, 0),
        cq.Vector(0, 0, 1),
    )


def cutter_length(params: ConeParameters) -> float:
    # Longer than the widest part, avoiding coincident end faces in the boolean.
    return params.base_diameter_mm + 2.0 * params.cutter_overrun_mm


def make_round_cutter(params: ConeParameters) -> cq.Shape:
    length = cutter_length(params)
    return cq.Solid.makeCylinder(
        params.bore_diameter_mm / 2.0,
        length,
        cq.Vector(-length / 2.0, 0, params.bore_center_height_mm),
        cq.Vector(1, 0, 0),
    )


def make_teardrop_cutter(params: ConeParameters) -> cq.Shape:
    """Make a support-friendly horizontal bore with 45-degree roof slopes.

    In the YZ cross-section, the lower half is a semicircle and the upper half
    is a 90-degree triangular roof. Maximum width and height equal the nominal
    bore diameter.
    """

    radius = params.bore_diameter_mm / 2.0
    length = cutter_length(params)
    return (
        cq.Workplane(
            "YZ",
            origin=(-length / 2.0, 0, params.bore_center_height_mm),
        )
        .moveTo(-radius, 0)
        .threePointArc((0, -radius), (radius, 0))
        .lineTo(0, radius)
        .close()
        .extrude(length)
        .val()
    )


def build_part(params: ConeParameters, variant: str) -> cq.Shape:
    params.validate()
    cone = make_cone(params)
    if variant == "round":
        cutter = make_round_cutter(params)
    elif variant == "teardrop":
        cutter = make_teardrop_cutter(params)
    else:
        raise ValueError(f"unknown variant: {variant}")

    result = cone.cut(cutter)
    if not result.isValid():
        raise RuntimeError(f"CadQuery produced an invalid {variant} solid")
    return result


def clean_stl(path: Path) -> None:
    """Remove zero-area facets occasionally emitted at an exact cone tip."""

    mesh = trimesh.load_mesh(path, process=True)
    mesh.update_faces(mesh.nondegenerate_faces(height=1e-8))
    mesh.remove_unreferenced_vertices()
    mesh.export(path, file_type="stl")


def export_part(part: cq.Shape, stem: Path) -> dict[str, str]:
    stem.parent.mkdir(parents=True, exist_ok=True)
    paths = {
        "step": stem.with_suffix(".step"),
        "stl": stem.with_suffix(".stl"),
        "3mf": stem.with_suffix(".3mf"),
    }
    cq.exporters.export(part, str(paths["step"]))
    part.exportStl(
        str(paths["stl"]),
        tolerance=0.02,
        angularTolerance=0.1,
        ascii=False,
        relative=False,
        parallel=True,
    )
    clean_stl(paths["stl"])
    cq.exporters.export(part, str(paths["3mf"]), tolerance=0.02, angularTolerance=0.1)
    return {key: str(value) for key, value in paths.items()}


def part_metadata(part: cq.Shape, params: ConeParameters, variant: str) -> dict:
    bounds = part.BoundingBox()
    return {
        "variant": variant,
        "parameters": asdict(params),
        "brep_valid": part.isValid(),
        "volume_mm3": part.Volume(),
        "bounds_mm": [bounds.xlen, bounds.ylen, bounds.zlen],
        "cone_unbored_volume_mm3": math.pi
        * params.height_mm
        * (
            (params.base_diameter_mm / 2.0) ** 2
            + (params.base_diameter_mm / 2.0) * (params.top_diameter_mm / 2.0)
            + (params.top_diameter_mm / 2.0) ** 2
        )
        / 3.0,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts"))
    parser.add_argument("--height", type=float, default=100.0)
    parser.add_argument("--base-diameter", type=float, default=60.0)
    parser.add_argument("--top-diameter", type=float, default=0.0)
    parser.add_argument("--bore-diameter", type=float, default=10.0)
    parser.add_argument("--bore-height", type=float, default=50.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    params = ConeParameters(
        height_mm=args.height,
        base_diameter_mm=args.base_diameter,
        top_diameter_mm=args.top_diameter,
        bore_diameter_mm=args.bore_diameter,
        bore_center_height_mm=args.bore_height,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)

    manifest = {"parameters": asdict(params), "variants": {}}
    for variant in ("round", "teardrop"):
        part = build_part(params, variant)
        stem = args.output_dir / f"cone_{variant}_bore"
        manifest["variants"][variant] = {
            **part_metadata(part, params, variant),
            "files": export_part(part, stem),
        }

    manifest_path = args.output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
