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

The published driver source is:

<https://github.com/artyom-tarasenko/hsimd>

`third_party/hsimd/` preserves upstream commit
`a04793b34219e5c31a6c7635c512231655174a1e`, including its GPLv2 license and
build instructions. See `third_party/hsimd/UPSTREAM.md` for provenance and the
kernel-gate build constraint.

We have not yet proved that the captured binary was built from that exact
source commit. A clean public binary release must establish and preserve the
actual corresponding source, or omit the binary. A link to a changing external
branch is useful provenance but is not a substitute for corresponding source.

## Other published Niagara boot reports

GitHub user `whensungoesdown` published a 2022 report of booting the OpenSPARC
`disk.s10hw2` Solaris image with `qemu-system-sparc64 -M niagara`:

<https://github.com/whensungoesdown/whensungoesdown.github.io/blob/585d0ac95f65c91ae955c6169cc694434f35a741/_posts/2022-04-30-Qemu-Solaris.md>

The post documents an operator result using the QEMU and OpenSPARC recipe.  It
does not claim independent QEMU, firmware, or illumos implementation work.

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
