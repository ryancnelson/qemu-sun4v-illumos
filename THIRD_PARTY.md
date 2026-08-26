# Third-party material and provenance

This project records experiments across QEMU, OpenSPARC firmware, Solaris, and
illumos.  A public repository does not make every file share the same license.
This inventory is practical provenance, not legal advice.

## Original project work

Unless a file states otherwise, Ryan Nelson's original scripts, notes, tests,
and source in this repository are released under CDDL 1.0.  See `LICENSE`.
That project-level choice does not change the license of material received
from another source.

## QEMU patches

Files under `patches/` that modify QEMU are patches against the upstream QEMU
source tree.  QEMU's repository contains code under multiple licenses; the
Niagara/SPARC files touched here carry QEMU's applicable notices.  Patch bases
are identified in the patch headers or accompanying notes.

- Upstream: <https://gitlab.com/qemu-project/qemu>
- Historical baseline: QEMU v8.2.2, commit
  `11aa0b1ff115b86160c4d37e7c37e6a6b13b77ea`
- Murayama comparison fork: <https://github.com/masa-murayama/qemu-sun4v>

## OpenSPARC machine descriptions

The editable `.hdesc` and `.pdesc` files under `md/` originated in Sun's
OpenSPARC T1 Architecture package and carry GPLv2 notices.  Preserve those
headers and the corresponding GPL terms when redistributing or modifying them.

## `hsimd`

The captured `hsimd` guest binary came from Artyom Tarasenko's GPLv2 Niagara
work rather than from this project's original code:

<https://github.com/artyom-tarasenko/qemu-sun4v-md>

A clean public source release should either omit that binary or distribute it
with the exact corresponding source and GPL materials.  A link to a changing
external branch is useful provenance but is not a substitute for preserving
the corresponding source for a binary release.

## OpenIndiana and illumos files

Some diagnostic captures contain guest configuration files and the
OpenIndiana `media-fs-root` script.  The latter carries the CDDL notice used by
illumos/OpenIndiana.  The project's preferred publishable modification is the
transform in `tools/openindiana/patch-media-fs-root.py`, not a freestanding
claim of authorship over the guest script.

- illumos source: <https://github.com/illumos/illumos-gate>
- OpenIndiana: <https://www.openindiana.org/>

## Solaris and OpenSPARC inputs not included

This repository does not intentionally redistribute Oracle Solaris
installation media, the OpenSPARC Solaris disk image, or Oracle firmware.
Reproduction instructions require users to obtain any proprietary inputs from
an authorized source.

## Capture bundle caution

The `captures/` tree is evidence, not a binary distribution.  Before a public
GitHub release, remove redundant archives and third-party executables from the
publication snapshot or bundle their exact corresponding source and license
materials.  Keep hashes and textual observations so experimental claims remain
auditable.
