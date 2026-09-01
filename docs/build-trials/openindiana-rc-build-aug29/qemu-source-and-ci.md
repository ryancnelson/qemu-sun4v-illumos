# QEMU source and CI boundary

## QEMU repository

The `qemu-system-sparc64` binary used for this bundle comes from Ryan Nelson's
QEMU fork:

```text
https://github.com/ryancnelson/qemu
branch: niagara-persistent-nvram
tip observed 2026-08-29: b0c85dc7f814a40e6f521b3dcbf90d0b16021de3
```

The branch is based on QEMU 10.2 and contains:

- Masayuki Murayama's imported sun4v, multi-disk, asynchronous-I/O, and SMP
  work through commit `879fee341ad8`;
- Ryan's persistent Niagara NVRAM change at `89491443f3fe`; and
- Ryan's SPARC large-TTE range-flush change at `b0c85dc7f814`.

The current native `ec2trib` checkout has the same NVRAM and TTE patches under
different commit IDs, plus one additional host-portability commit:

```text
9573242 hw/sparc64: port sun4v disk handling to illumos hosts
```

That additional commit must be published on an authoritative branch before a
GitHub-driven build can reproduce the current native `ec2trib` binary exactly.

## Woodpecker

The active Woodpecker service is on Biggie:

```text
http://biggie.lynx-eagle.ts.net:8110
```

The Woodpecker repository currently named `ryancnelson/tribblix-woodpecker`
orchestrates QEMU build and boot tests. Its eventual name is recorded as
`qemu-sun4m-solaris9-ci`; that workflow is a separate Solaris 9 sun4m project
and must not become the product repository for this OpenIndiana bundle.

For Niagara QEMU work, Biggie Woodpecker is the controller. A pipeline may SSH
to `ec2trib`, where the native Tribblix build runs. Woodpecker should not be
redesigned or reinstalled unless a demonstrated CI-platform defect blocks the
QEMU or bundle workflow.

## Ownership boundary

The QEMU fork owns:

- Niagara machine implementation;
- Masa's hSIMD multi-disk support;
- persistent NVRAM support;
- host portability needed to build on Tribblix; and
- QEMU-specific regression tests.

The `openindiana-rc-build-aug29` product owns:

- disk-role assignments;
- UFS and ZFS image assembly;
- boot-archive modification;
- the exact QEMU commit and binary hash required by a release;
- launch configuration; and
- guest boot acceptance tests.

Destination hosts may build or obtain their own QEMU binary. Admission requires
the declared QEMU version, patch capabilities, and executable hash or an
explicitly accepted compatibility record.
