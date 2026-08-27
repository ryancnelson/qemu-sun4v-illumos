# Cone with east-west through-hole

This directory contains a reproducible, parametric CAD model for a cone with
a horizontal through-hole running along the X axis (east-west).

## Default dimensions

- Height: 100 mm
- Base diameter: 60 mm
- Top diameter: 0 mm
- Bore width/diameter: 10 mm
- Bore center: 50 mm above the base

Two variants are generated:

- `round`: the literal circular bore requested.
- `teardrop`: the same 10 mm envelope with a 45-degree roof for support-free
  FDM printing when the cone is printed upright.

## Generate and validate

```sh
python3.11 -m venv .venv311
.venv311/bin/pip install -r requirements.txt
.venv311/bin/python generate.py
.venv311/bin/python validate.py
```

Artifacts are written to `artifacts/`:

- STEP: exact solid interchange format
- STL: binary, 0.02 mm linear tessellation tolerance
- 3MF: unit-aware mesh alternative for slicers
- JSON manifests containing parameters and validation results

The validation checks that each STL is watertight, represents a positive
volume, contains one connected component, and has 60 x 60 x 100 mm bounds.

STL does not encode units. Treat all coordinates as millimeters and verify the
imported height is 100 mm in Tinkercad or the slicer.
