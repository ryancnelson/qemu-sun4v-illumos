# Virtual Niagara: illumos on QEMU sun4v

This repository is an experimental path toward a useful SPARC64
Solaris/illumos virtual machine on QEMU's `niagara` (`sun4v`) machine.

In five days of independent work in August 2026, the project moved from a
Solaris 10 reference guest to modern Tribblix and OpenIndiana kernels with
persistent `hsimd` storage, host/guest channels, PPP networking, NFS, iSCSI,
ZFS, and a Ctrl-C-safe maintenance console.

The illustrated account is at
[ryan.net/sparc64-lives](https://ryan.net/sparc64-lives/).

## Why this repository is being shared now

Masayuki Murayama independently published a substantially extended QEMU sun4v
stack in July and August 2026.  His work supplies a coherent QEMU 10.2 machine,
modified OpenBoot and hypervisor, multiple block-backed disks, asynchronous
I/O, and SMP.  Its documented limitation is the one this project has spent the
last several days crossing: networking.

The immediate goal is to compare the two implementations, reproduce
Murayama's Solaris 10 result from source, boot this project's OpenIndiana image
on his complete stack, and contribute the smallest clean combination of:

- Murayama's machine, interrupt, MMU, disk, and SMP work;
- this project's OpenIndiana boot-archive integration;
- reliable host/guest channels and a network path; and
- measured performance fixes.

Start with [`notes/MURAYAMA-QEMU-SUN4V-PRIOR-ART.md`](notes/MURAYAMA-QEMU-SUN4V-PRIOR-ART.md).

### A concrete networking proposal for Murayama

The shortest path to ordinary Ethernet does not require emulating a PCI NIC or
writing a kernel driver.  illumos can create an etherstub with two VNICs: one
belongs to the IP stack and a small `libdlpi` relay owns the other.  The relay
carries complete Ethernet frames over channel 2 to a Linux TAP interface.

This is directly relevant to Murayama's stack because it can provide a useful
network while its native virtual-device work evolves.  The data-link proof is
partial: temporary etherstub and VNIC creation succeeded, but `ipadm` could not
open its library handle in the stripped-down Tribblix environment.  The relay,
TAP bridge, ARP, and IP path have not yet been implemented or demonstrated.

The bounded experiment is in
[`notes/ETHERNET-OVER-CHANNEL.md`](notes/ETHERNET-OVER-CHANNEL.md).  The longer
design discussion—including a GLDv3 pseudo-driver and a native sun4v virtual
device—is in [`ETHERNET_MUSINGS.md`](ETHERNET_MUSINGS.md).  Murayama's extensive
OpenSolaris NIC-driver work makes his review of this boundary especially
valuable.

## What is verified

The following claims have console transcripts, checksums, tests, or captured
host evidence in this repository:

- Solaris 10 boots under the QEMU 8.2.2 Niagara machine used here.
- A `MAP_SHARED` virtual-disk patch makes guest writes persist in the backing
  regular file.
- Tribblix m34 boots from a remastered RAM archive.
- The Solaris 10 SPARC V9 `hsimd` module loads and attaches under Tribblix;
  discriminating canaries verify reads and writes at nonzero disk offsets.
- An OpenIndiana Hipster 2025.12 SPARC kernel boots with a derivative archive,
  attaches `hsimd0`, mounts the HSFS installation media presented through that
  disk, and mounts its compressed live userland.
- Framed host/guest channels operate over a reserved region of the shared
  disk.
- OpenIndiana negotiates PPP over channel 0, reaches the Linux host and the
  Internet, resolves DNS, and mounts NFS.
- Channel 1 provides a separate root PTY on which Ctrl-C interrupts the guest
  command rather than terminating QEMU.
- OpenIndiana discovers a Linux LIO target over that PPP link, creates an
  online ZFS pool, writes and reads a canary, exports the pool, and closes the
  target session cleanly.
- The same running guest reports 82,806 available DTrace probes.
- Host profiling identifies repeated per-page TCG TLB invalidation as the
  largest measured boot-time cost in the sampled interval.

The narrative and exact evidence are in:

1. [`THE-TRIBBLIX-HSIMD-STORY.md`](THE-TRIBBLIX-HSIMD-STORY.md)
2. [`THE-OPENINDIANA-BASECAMP-STORY.md`](THE-OPENINDIANA-BASECAMP-STORY.md)
3. [`docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md`](docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md)
4. [`notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md`](notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md)

## What is not yet verified

These boundaries are deliberate:

- OpenIndiana does **not** yet cold-boot into an installed persistent root on
  this branch.  The present result is a networked live/maintenance environment.
- The OpenIndiana text installer does not yet accept `hsimd0` as its target
  disk.
- A direct raw-device ZFS pool on an appended `hsimd` slice has not completed
  create/export/import validation.  The successful OpenIndiana pool used
  iSCSI over PPP.
- PPP is a bootstrap network, not an emulated Ethernet device.  Framed
  Ethernet over channel 2 is designed but not implemented.
- The blocking single-user/getty console path remains unreliable on the older
  QEMU stack because the emulated UART has no useful interrupt delivery path.
- The experimental TCG TLB range-flush patch compiles, but its OpenIndiana A/B
  boot and correctness tests are still pending.
- Murayama's QEMU/OpenBoot/hypervisor stack has been inspected, not yet built
  or executed by this project.

## The current two stacks

### This repository's measured baseline

```text
Apple-silicon laptop
  UTM AArch64 Linux VM (hardware-accelerated)
    QEMU 8.2.2 qemu-system-sparc64 -M niagara (TCG)
      OpenSPARC hypervisor + OpenBoot
        OpenIndiana/Tribblix sun4v guest
```

The older QEMU machine exposes one memory-mapped hypercall disk and no NIC.
This project uses reserved sectors in that disk as bidirectional channels:

```text
channel 0  PPP bootstrap and fallback
channel 1  Ctrl-C-safe maintenance console
channel 2  reserved for framed Ethernet
```

### Murayama's newly published stack

Murayama's current `sun4v` branch is based on QEMU 10.2 and adds extensive
machine, MMU, trap, interrupt, IOB, disk, and SMP work.  The published launcher
supports eight disks and 1--8 CPUs; its published launcher defaults to a 3 GiB
guest.  It documents installing Solaris 10u11 onto a persistent virtual disk.
Its README explicitly says that network devices are not yet supported.

Primary repositories:

- <https://github.com/masa-murayama/qemu-sun4v>
- <https://github.com/masa-murayama/qemu-sun4v-dist-pkg>
- <https://github.com/masa-murayama/qemu-sun4v-openboot>
- <https://github.com/masa-murayama/qemu-sun4v-hypervisor>
- <https://github.com/masa-murayama/qemu-sunv4-guest-util>

## Repository map

```text
README.md                  current public orientation and evidence boundaries
CURRENT-STATE.md           detailed Solaris 10/Tribblix lab ledger
THE-*-STORY.md             narrative chapters with corrections and evidence
patches/                   reviewable QEMU/illumos patches (no QEMU source tree)
tools/chan/                host/guest shared-disk channels and PPP helpers
tools/openindiana/         OpenIndiana archive construction and boot helpers
tests/                     destructive-test-aware integration harness
captures/                  bounded transcripts, manifests, and checkpoint data
docs/                      design and implementation plans
notes/                     investigations, performance data, and handoffs
md/                        editable OpenSPARC machine-description sources
```

The QEMU checkout itself is intentionally ignored.  Patches must be committed
as files under `patches/`; do not rely on an unpublished edit inside `qemu/`.
Generated images, ISO staging trees, and raw profiler data belong under
ignored `work/` or outside the repository.

## Relevant patches

- [`patches/0001-niagara-vdisk-writeback.patch`](patches/0001-niagara-vdisk-writeback.patch)
  changes Niagara's virtual disk from a one-time anonymous-RAM copy to a
  shared mapping of a regular backing file and adds explicit `msync`.  The
  shared mapping is what makes the reserved-disk channel transport observable
  by both host and guest.
- [`patches/0002-mdgen-x86-crossbuild.patch`](patches/0002-mdgen-x86-crossbuild.patch)
  makes the OpenSPARC machine-description generator build on x86 hosts.
- [`patches/0003-sparc-tlb-range-flush.patch`](patches/0003-sparc-tlb-range-flush.patch)
  is an unvalidated performance experiment replacing repeated 8 KiB TLB page
  flushes with QEMU's range API.
- [`patches/illumos-pppd-sparcv9.patch`](patches/illumos-pppd-sparcv9.patch)
  carries the illumos PPP build adjustment used for the SPARC V9 guest.

Each patch documents its base or intended context.  Patch 0003 must not be
combined with the first Murayama compatibility test; establish his unmodified
baseline first.

## Reproduction scope

The repository does **not** redistribute Oracle installation media or the
OpenSPARC Solaris disk image.  The historical Solaris 10 baseline begins with
Oracle's OpenSPARC T1 Architecture 1.5 package and QEMU 8.2.2.  See
[`setup-host.sh`](setup-host.sh), [`run-solaris.sh`](run-solaris.sh), and the
integration tests for that environment.

The OpenIndiana result currently also depends on a Solaris-family donor for
safe UFS boot-archive editing and on inputs whose hashes are recorded in the
implementation plan.  It is reproducible from the preserved inputs and tools,
but it is not yet a one-command build for an unrelated host.  That packaging
work is tracked in [`notes/OPENINDIANA-NEXT-ISO-TODO.md`](notes/OPENINDIANA-NEXT-ISO-TODO.md).

The integration tests manipulate disposable ZFS datasets, launch QEMU, and in
some cases require root.  Read the scripts before running them.  Do not point
them at an irreplaceable VM image.

## Performance result

During a fresh OpenIndiana boot, the guest vCPU saturated one host core while
QEMU performed no measurable block I/O.  A 70-second, 99 Hz `perf` sample put
31.8% inclusive time in `tlb_flush_page_by_mmuidx_async_0`, called from SPARC
TLB replacement.  This rules out storage and host-wide CPU/RAM pressure as the
cause of the sampled multi-minute silent phase and motivates patch 0003.

See [`notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md`](notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md)
for the full measurement conditions and the required A/B validation.

## Publication model

The public GitHub repository is a reviewed, squashed source snapshot.  The
older Gitea repository remains the private laboratory history because earlier
commits contain redundant captured binaries and third-party guest files.  New
public work should use the correctly spelled repository:

<https://github.com/ryancnelson/qemu-sun4v-illumos>

See [`PUBLICATION-CHECKLIST.md`](PUBLICATION-CHECKLIST.md) for the publication
boundary and remaining follow-up work.

## Provenance and licensing

This repository combines original project code, patches against upstream
projects, generated observations, and bounded copies of third-party material.
They do not all share one license.  See [`THIRD_PARTY.md`](THIRD_PARTY.md)
before redistributing binaries or extracted guest files.

Unless a file states otherwise, Ryan Nelson's original project code and
documentation are released under CDDL 1.0; see [`LICENSE`](LICENSE).  Upstream
patches, OpenSPARC material, and captured third-party files retain their
existing licenses and notices.

## Collaboration target

The first useful joint experiment is intentionally small:

1. Build Murayama's pinned QEMU/OpenBoot/hypervisor stack from source.
2. Reproduce its documented Solaris 10u11 installation on a disposable disk.
3. Boot this project's current OpenIndiana ISO unchanged on that stack.
4. Record disk discovery, both UARTs, interrupt-driven input, CPU time, and
   wall-clock milestones.
5. Add no optimization until that compatibility baseline is preserved.
6. Then connect the existing channel/network work and A/B test the TLB patch.

If those pieces compose, the result is much closer to the useful illumos
SPARC64 VM both projects are trying to build.
