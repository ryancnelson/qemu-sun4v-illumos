# Potential sun4v PCIe collaboration with Dmitry Pimenov

Date: 2026-08-27

This note collects Dmitry Pimenov's published work on adding PCIe to the QEMU
Niagara machine, this project's work on the guest and installer side, and a
possible experiment using both.

## Short version

Dmitry has done substantial work below OpenBoot: rebuilding the OpenSPARC
sun4v hypervisor, enabling its Fire/PCIe path, describing the PCIe devices in
the Machine Description, and making QEMU's `e1000` appear in the OpenBoot
device tree. This project has concentrated on the other end of the problem:
bootable and installed illumos-family guests, persistent disk images,
installer adaptations, guest tooling, host/guest channels, PPP bootstrap
networking, DTrace, and reproducible tests.

The published Machine Description sources can be compiled into MD blobs, but
they cannot be compiled into `q.bin`. Reproducing the result will also require
the modified executable hypervisor described in Dmitry's article. A useful
next step would be to exchange exact artifacts and build recipes, then boot
this project's guest media on his PCIe-capable firmware/QEMU stack.

## Dmitry's published work

Dmitry's article, [QEMU/SPARC64 - rebuilding sun4v hypervisor with
PCIe](https://unix0.cc/2026/08/10/hv-build-pcie-space/), describes:

- rebuilding `q.bin`, the executable sun4v hypervisor, from the OpenSPARC T1/T2
  sources;
- replacing assembler macros as needed for a GNU toolchain and checking the
  resulting objects against Sun-built objects;
- enabling the hypervisor's I/O and PCIe support, including the Fire path and
  a second hypervisor serial console;
- implementing enough of the QEMU and hypervisor path for OpenBoot to enumerate
  `/pci@0/ethernet@0`, compatible with `pci8086,100e`, backed by QEMU's `e1000`;
  and
- making PCI configuration hypercalls and the Machine Description's PCIe arc
  agree well enough to reach that OpenBoot result.

His earlier reports also cover full-size installation media, Solaris 10 and
Solaris 11 boot progress, and a signed-size bug in QEMU's sun4v virtual-disk
path. That QEMU fix was accepted upstream as
[commit 76dbe26](https://github.com/qemu/qemu/commit/76dbe26fd6500a94b85bf0f3a39d73b72f5fab7b).

Relevant public repositories include:

- [unix0cc/md](https://github.com/unix0cc/md), containing MD sources, generated
  blobs, and stock firmware inputs;
- [unix0cc/md-artefacts](https://github.com/unix0cc/md-artefacts), containing
  generated test artifacts;
- [unix0cc/mdbuild](https://github.com/unix0cc/mdbuild), containing his MD
  build tooling; and
- [unix0cc/qemu-experimental-patches](https://github.com/unix0cc/qemu-experimental-patches),
  containing selected QEMU patches.

His [boot-results table](https://unix0cc.github.io/md/) records an important
installer limitation: several installers reach maintenance mode because the
installer mounts a second HSFS slice that its ISO kernel cannot access without
`hsimd`. Prepared media from this project may provide a way past that point.

## Machine Descriptions are not `q.bin`

The firmware inputs have separate jobs and separate build paths:

```text
*.pdesc       -> 1up-md.bin   # guest-visible machine description
*.hdesc       -> 1up-hv.bin   # hypervisor resource configuration
SPARC assembly -> q.bin       # executable sun4v hypervisor
```

QEMU loads `1up-md.bin`, `1up-hv.bin`, `nvram1`, `openboot.bin`, `q.bin`, and
`reset.bin` as separate files. The PCIe MD material under
`src/_test/hvmd_v1_pciex/4096` in Dmitry's `md` repository can describe the
PCIe hierarchy and allocate resources. It cannot supply the executable PCI
configuration, MMIO, IOMMU, MSI, or interrupt hypercalls that must live in the
hypervisor.

The public `fw_blobs/q.bin` in that repository is 163,216 bytes and is
documented as byte-identical to Sun's stock OpenSPARC T1 S10image hypervisor.
Dmitry's PCIe article reports a modified `q.bin` of 216,912 bytes. I did not
find that modified binary, its changed assembly source, or its build recipe in
the four repositories above. Those are the remaining inputs I need to ask him
about before attempting to reproduce the PCIe result.

## This project's relevant work

This project has a complementary set of artifacts and experience:

- An OpenIndiana SPARC image has cold-booted from an installed ZFS root into
  multiuser mode. The current artifact and its limitations are recorded in
  [OPENINDIANA-WORKSTATION-CANDIDATE-20260826.md](OPENINDIANA-WORKSTATION-CANDIDATE-20260826.md).
- A prepared installer disk and a sparse 60 GiB installed-root image avoid
  depending on the unmodified installer ISO's missing `hsimd` path.
- Host/guest block channels provide file exchange and a bootstrap PPP path
  while Ethernet is absent. Manual PPP and routed traffic passed in the
  documented candidate run. Network restoration is not automatic, and later
  cold-boot acceptance remains unfinished.
- The guest has exposed tens of thousands of DTrace probes, which gives us a
  strong observation point once a PCI device reaches the kernel.
- The repository contains boot, persistence, MD round-trip, toolchain, and
  channel tests. It also records exact image lineage and hashes so experiments
  do not silently change their inputs.
- The current firmware still exposes only one CPU and 3072 MiB to the guest
  even when QEMU is asked for more. Guest-visible SMP and larger-memory MD
  topology are active investigation areas.

These research artifacts are still being prepared for release. The current
workstation image is being preserved and promoted carefully, and the latest
harness work has unresolved process-reaping and cold-boot network acceptance
issues. See [CURRENT-STATE.md](../CURRENT-STATE.md) for the latest live VM
status.

## Proposed first joint experiment

1. Ask Dmitry for the source or patch series, build commands,
   compiler/binutils versions, and hashes for his 216,912-byte PCIe `q.bin` and
   matching QEMU executable.
2. Pair those with his PCIe `1up-md.bin` and `1up-hv.bin`, preserving the
   provenance and hash of every firmware input.
3. Attach this project's prepared OpenIndiana installer or installed-root
   image without changing it.
4. Confirm the existing OpenBoot result: `/pci@0/ethernet@0` is present and
   its configuration space is readable.
5. Boot OpenIndiana and determine whether `e1000g` attaches. If it does not,
   capture the guest console, `prtconf`, `modinfo`, DTrace observations, QEMU
   trace output, and hypervisor diagnostics at the first failure boundary.
6. If the driver attaches, test interrupts, DMA, transmit, receive, and reset
   separately before calling Ethernet operational.

This experiment combines Dmitry's PCIe and hypervisor work with a guest image
that gets past the installer-media limitation and has tools for investigating
the next failure.

## Points for an introductory email

- I have been working on making QEMU's Niagara machine useful as a repeatable
  illumos/Solaris development environment, carrying successful boots forward
  into installed systems, persistent storage, guest tooling, and automated
  tests.
- I was excited to find your PCIe work because it covers much of the host,
  firmware, and hypervisor work I hoped to tackle next.
- I now have prepared installer media and an installed OpenIndiana ZFS-root
  image that reaches multiuser mode. I also have persistent virtual disks,
  host/guest channels, bootstrap PPP, guest tools, DTrace, and test automation.
- My prepared media may help with the installer-side `hsimd` limitation
  recorded in your boot matrix.
- If you are interested, I would like to try these guest artifacts with your
  PCIe stack and report exactly how far the illumos `e1000g` driver gets.
- I am happy to share hashes, disk layouts, boot commands, and prepared images,
  and to preserve attribution and licensing boundaries for every borrowed
  artifact.
- Would you be willing to share the modified 216,912-byte `q.bin`, its source
  or patch series, and the matching QEMU work? I would also appreciate the
  toolchain details and exact firmware inputs needed to reproduce your result.

Public contact points found with the work are `dpim@unix0.cc` on the site and
`sun4qemu@gmail.com` in the QEMU patch history. Confirm the preferred address
before sending large files or private artifact links.
