# Virtual Niagara: illumos on QEMU sun4v

**It boots, and you can run it in one command.**  A modern OpenIndiana
Hipster 2025.12 `sun4v` guest cold-boots to a login prompt inside a
multi-architecture Docker image, with no OpenBoot interaction required.

## Quick start

```sh
docker run --rm -it \
  --name openindiana-sparc64 \
  --hostname oi-basecamp \
  --memory 6g \
  --cpus 2 \
  --cap-add NET_ADMIN \
  --device /dev/ppp \
  --sysctl net.ipv4.ip_forward=1 \
  --tmpfs /run/unit100:rw,size=1200m,mode=0700 \
  --mount type=volume,src=openindiana-sparc64,dst=/var/lib/illumos-appliance \
  ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:latest
```

The image is published for `linux/amd64` and `linux/arm64`.  Log in as `root`
with password `root`; the normal user `jack` also exists.  Emulated SPARC is
slow, and how slow depends heavily on the host: about 7 minutes to the login
prompt on a bare-metal Linux builder, but roughly 40 minutes under nested
virtualization such as Docker Desktop on macOS.  The guest is working the whole
time; verbose device messages continue to print after the login prompt appears.

- Add `-e OPENBOOT_AUTO_BOOT=false` to stop at the OpenBoot `ok` prompt.
- Add `-e NIAGARA_NETWORK=off` and drop the three networking options to run
  without the container's PPP/NAT helpers.
- Inside the guest, `/jack/BRING_UP_NETWORKING.sh` brings up the channel
  daemons and PPP link; `/jack/CALL_BBS.sh` dials the container-local BBS.
- Video of the boot: <https://www.youtube.com/watch?v=TzgbLWeTZPM>

Full appliance documentation, including detached/socket console mode and the
guest network contract, is in
[`appliances/sparc64-qemu-illumos-docker-guest/README.md`](appliances/sparc64-qemu-illumos-docker-guest/README.md).

## What this repository is

This repository is the laboratory record and tooling behind a useful SPARC64
Solaris/illumos virtual machine on QEMU's `niagara` (`sun4v`) machine.

Work began in mid-August 2026 with a Solaris 10 reference guest on QEMU 8.2.2
and reached modern Tribblix and OpenIndiana kernels within five days:
persistent `hsimd` storage, framed host/guest channels over a shared disk, PPP
networking, NFS, iSCSI, ZFS, and a Ctrl-C-safe maintenance console.  Work
continued through the end of August and into September 2026, and the emphasis
shifted from "can it boot at all" to reproducibility: an installed ZFS root, a
QEMU 10.2 runtime incorporating Masayuki Murayama's sun4v work, automatic boot
driven from the Machine Description, and a CI-gated, self-contained,
multi-architecture container release.

The illustrated account of the first five days is at
[ryan.net/sparc64-lives](https://ryan.net/sparc64-lives/).  That page covers
the August 19-24 story only; this README is the current status.

## Relationship to Masayuki Murayama's sun4v work

Masayuki Murayama independently published a substantially extended QEMU sun4v
stack in July and August 2026: a coherent QEMU 10.2 machine, modified OpenBoot
and hypervisor, multiple block-backed disks, asynchronous I/O, and SMP.  Its
documented limitation was the one this project had spent its first several days
crossing: networking.

That comparison is no longer pending.  This project's runtime is now built on
his work.  The `qemu-system-sparc64` used by the released appliance comes from
[`ryancnelson/qemu`](https://github.com/ryancnelson/qemu), branch
`niagara-persistent-nvram`, which is QEMU 10.2 containing:

- Murayama's imported sun4v, multi-disk, asynchronous-I/O and SMP work through
  commit `879fee341ad8`;
- a persistent Niagara NVRAM property (`-M niagara,nvram-file=PATH`) at
  `89491443f3fe`;
- a SPARC large-TTE TLB range-flush change at `b0c85dc7f814`; and
- an illumos-host portability commit so the same tree builds on Tribblix.

The container image pins an archive of that tree at
`049affb20df67162cf58deeaf74d5ad4b83cbdc3`.  That commit exists only in the
`ec2trib` working checkout and the pinned source tarball, not yet on a public
branch; publishing it is the outstanding reproducibility gap.  See
[`docs/build-trials/openindiana-rc-build-aug29/qemu-source-and-ci.md`](docs/build-trials/openindiana-rc-build-aug29/qemu-source-and-ci.md).

On 2026-08-27 a native Tribblix build of Murayama's fork booted this project's
installed OpenIndiana root through kmdb to the OpenIndiana banner.  That test
also found a machine-initialization defect: `niagara_init()` probes only unit
100 (or unit 102) before calling `niagara_load_vdisk()`, so a valid disk
attached at unit 104 alone never reaches the full unit scan and appears broken
to the firmware.  A small carrier image at unit 100 activates the backend.
Details in
[`notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md`](notes/TRIBBLIX-NATIVE-MURAYAMA-QEMU-AND-VDISK-ACTIVATION-20260827.md)
and the prior-art survey in
[`notes/MURAYAMA-QEMU-SUN4V-PRIOR-ART.md`](notes/MURAYAMA-QEMU-SUN4V-PRIOR-ART.md).

Primary repositories:

- <https://github.com/masa-murayama/qemu-sun4v>
- <https://github.com/masa-murayama/qemu-sun4v-dist-pkg>
- <https://github.com/masa-murayama/qemu-sun4v-openboot>
- <https://github.com/masa-murayama/qemu-sun4v-hypervisor>
- <https://github.com/masa-murayama/qemu-sunv4-guest-util>
- <https://github.com/masa-murayama/qemu-sun4v-host-util>

Dmitry Pimenov has independently rebuilt the OpenSPARC sun4v hypervisor with
its Fire/PCIe path enabled and made QEMU's `e1000` appear in the OpenBoot
device tree; see
[`notes/DMITRY-PIMENOV-SUN4V-PCIE-COLLABORATION.md`](notes/DMITRY-PIMENOV-SUN4V-PCIE-COLLABORATION.md)
and <https://unix0.cc/2026/08/10/hv-build-pcie-space/>.  His PCIe firmware path
and this project's guest/installer work are complementary.

### The remaining networking proposal

The container appliance gives the guest a working IP network today, but it does
so with PPP over a shared-disk channel plus container-side NAT, not an emulated
Ethernet device.  The shortest path to ordinary Ethernet still does not require
emulating a PCI NIC or writing a kernel driver: illumos can create an etherstub
with two VNICs, one belonging to the IP stack and one owned by a small
`libdlpi` relay that carries complete Ethernet frames over channel 2 to a Linux
TAP interface.

The data-link proof remains partial.  Temporary etherstub and VNIC creation
succeeded, but `ipadm` could not open its library handle in the stripped-down
Tribblix environment.  The relay, TAP bridge, ARP, and IP path are still not
implemented or demonstrated.  The bounded experiment is in
[`notes/ETHERNET-OVER-CHANNEL.md`](notes/ETHERNET-OVER-CHANNEL.md); the longer
design discussion, including a GLDv3 pseudo-driver and a native sun4v virtual
device, is in [`ETHERNET_MUSINGS.md`](ETHERNET_MUSINGS.md).

## What is verified

The following claims have console transcripts, checksums, CI gates, or captured
host evidence in this repository:

**Released appliance (2026-09-01 / 09-02, CI-gated)**

- A self-contained OCI image cold-boots OpenIndiana Hipster 2025.12
  (`illumos-31d3d510d0`, sun4v) to `oi-basecamp console login:` with no
  OpenBoot input, no bind mounts, and no preexisting Docker volume.
- Automatic boot is driven from the Niagara Machine Description's `variables`
  node, not NVRAM.  OpenBoot's `loadconfig.fth` runs `pdnvupdate` at stand-init
  and copies `boot-device`, `boot-file`, and `auto-boot?` from the platform
  description, which supersedes both `setenv` and QEMU's generic `-prom-env`.
- The release Machine Description is regenerated by Sun's `mdgen`, gated on a
  byte-identical round trip of the accepted baseline, and is deterministic at
  SHA-256 `561859faa18066b8e9b5c408eb7cd7a5f2576d3208c4cfb3c07d77dcf468167c`.
- The 20 GiB ZFS root is 21474836480 bytes logical, ~2.91 GiB allocated, passed
  a full scrub with zero errors, and has SHA-256
  `24306fcf52c9d05c6dd49115f5e2833a3b8563e59d88b923f7022a214308e722`.
- The same image passes, in CI, a channel-readiness gate, a `CONNECT 2400`
  exchange with the container-local BBS, bidirectional PPP, guest NAT to
  `8.8.8.8`, DNS via `10.0.5.1:53`, and an HTTP CONNECT proxy handshake via
  `10.0.5.1:8888` — all from inside OpenIndiana.
- The image is published for both architectures from native builders:
  `linux/amd64` on `ec2cicd` and `linux/arm64` on `niagara-playbox`, combined
  into one multiarch manifest and verified anonymously from GHCR.
- An independently pulled `:latest` on an Apple-silicon Mac (Docker Desktop
  5.7.1, arm64) reproduced the whole path on 2026-09-03: OpenBoot auto-boot with
  no input, `hsimd5` attach, `root on distpool/ROOT/openindiana fstype zfs`,
  `oi-basecamp console login:`, a root login, `SunOS oi-basecamp 5.11
  illumos-31d3d510d0 sun4v sparc SUNW,Sun-Fire-T200`, `all pools are healthy`,
  user `jack` present as uid 65432, both `/jack/*.sh` helpers installed, and
  77,745 available DTrace probes.  Wall-clock to the login prompt was roughly
  40 minutes on that nested-virtualization host, against about 7 minutes on the
  bare-metal CI builders.

**Guest and machine work (August 2026)**

- Solaris 10 boots under the QEMU 8.2.2 Niagara machine used for the original
  baseline.
- A `MAP_SHARED` virtual-disk patch makes guest writes persist in the backing
  regular file.
- Tribblix m34 boots from a remastered RAM archive.
- The Solaris 10 SPARC V9 `hsimd` module loads and attaches under Tribblix;
  discriminating canaries verify reads and writes at nonzero disk offsets.
- An OpenIndiana Hipster 2025.12 SPARC kernel boots with a derivative archive,
  attaches `hsimd0`, mounts the HSFS installation media presented through that
  disk, and mounts its compressed live userland.
- OpenIndiana cold-boots an installed ZFS root from hSIMD, reaches a multiuser
  root prompt, reports a healthy pool, and passes PPP plus routed Internet
  packets.
- Framed host/guest channels operate over a reserved region of the shared
  disk.  Channel 0 carries PPP; channel 1 provides a separate root PTY on which
  Ctrl-C interrupts the guest command rather than terminating QEMU.
- OpenIndiana resolves DNS, mounts NFS, discovers a Linux LIO iSCSI target over
  the PPP link, creates an online ZFS pool, writes and reads a canary, exports
  the pool, and closes the target session cleanly.
- The same running guest reports 82,806 available DTrace probes.  Probe counts
  are per-image and not interchangeable: the Basecamp R0 live-media release
  asserts an exact 72,893, and the 2026-09-01 released appliance root reports
  77,745.
- Host profiling identifies repeated per-page TCG TLB invalidation as the
  largest measured boot-time cost in the sampled interval.
- Solaris 9 sun4m networking works under QEMU 7.2.0 and fails under QEMU 9.1.0
  and 11.1.0, bounding the first bad release to that interval.

The narrative and exact evidence are in:

1. [`THE-TRIBBLIX-HSIMD-STORY.md`](THE-TRIBBLIX-HSIMD-STORY.md)
2. [`THE-OPENINDIANA-BASECAMP-STORY.md`](THE-OPENINDIANA-BASECAMP-STORY.md)
3. [`appliances/sparc64-qemu-illumos-docker-guest/EXPERIMENT-NOTEBOOK.md`](appliances/sparc64-qemu-illumos-docker-guest/EXPERIMENT-NOTEBOOK.md)
4. [`notes/filesystem-manipulation-tooling/EXPERIMENT-NOTEBOOK-2026-08-30.md`](notes/filesystem-manipulation-tooling/EXPERIMENT-NOTEBOOK-2026-08-30.md)
5. [`docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md`](docs/implementation-plans/2026-08-24-openindiana-boot-to-checkpoint.md)
6. [`notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md`](notes/OPENINDIANA-PERFORMANCE-NOTEBOOK.md)

## What is not yet verified

These boundaries are deliberate:

- The exact QEMU commit the release pins (`049affb2…`) is not published on any
  public branch.  Until it is, a third party cannot rebuild the released binary
  bit-for-bit from GitHub; they can only rebuild from the pinned source tarball.
- The released root disk must be attached as Niagara unit105.  Its ZFS labels
  record `/virtual-devices@100/disk@5:a`; moving it to unit104 makes pre-root
  ZFS discovery fall back to a full device scan, which trips the known hsimd
  large-I/O assertion (`sz <= 128*1024`) and panics.  This is a driver
  limitation, not an appliance preference.  See
  [`notes/OPENINDIANA-HSIMD-LARGE-IO-PANIC.md`](notes/OPENINDIANA-HSIMD-LARGE-IO-PANIC.md).
- The hsimd large-I/O fix itself is diagnosed but not implemented.  ZFS
  aggregates vdev I/O up to 1 MiB and calls `ldi_strategy()` without honoring
  hsimd's advertised 128 KiB `dki_maxtransfer`.
- Murayama's distributed `hsimd` binary fails `cmlb_attach()` against the
  current OpenIndiana ABI because it was built selecting `TG_DK_OPS_VERSION_0`,
  which `cmlb.c` rejects unconditionally.  A VERSION_1 rebuild was cross-
  compiled and symbol-audited but has never been loaded in a live guest.
- The released guest has no SSH listener, no channel-1 getty, and no verified
  in-guest compiler.  Its network is brought up by an explicit script, not by
  SMF at boot.
- PPP plus container NAT is a bootstrap network, not an emulated Ethernet
  device.  Framed Ethernet over channel 2 is designed but not implemented.
- The OpenIndiana text installer still does not accept an hSIMD disk as its
  target.  The released root was assembled by hand and by CI, not installed by
  the installer.
- Persistent NVRAM writes do not work.  QEMU file backing was implemented and
  the file is mapped `MAP_SHARED`, but OpenBoot routes variable writes through a
  missing LDOM Domain Service provider and never modifies physical NVRAM
  (`Unable to update LDOM Variable`).  Filed as
  [`ryancnelson/qemu#1`](https://github.com/ryancnelson/qemu/issues/1); the
  Machine Description workaround above is what actually ships.
- The TCG TLB range-flush patch (`patches/0003`) ships in the release binary but
  its controlled A/B measurement and correctness regression are still pending.
  Do not cite it as a proven speedup.
- WAN boot of a remastered `boot_archive` over OpenBoot's network path has not
  been demonstrated on this machine.
- The Solaris 9 sun4m network regression is bounded to a QEMU release interval
  but the responsible commit has not been identified.
- The `tests/` harness (7 integration tests) dates from the Solaris 10 / QEMU
  8.2.2 baseline and has not been re-run against the QEMU 10.2 stack or the
  appliance.  Treat its recorded results as historical.

## The current stack

The released appliance:

```text
any amd64 or arm64 Linux Docker host
  container: pinned qemu-system-sparc64 (QEMU 10.2, Murayama sun4v + local patches)
    OpenSPARC hypervisor + OpenBoot + release Machine Description
      OpenIndiana Hipster 2025.12 sun4v guest, ZFS root on unit105
```

The container runs the guest with 3072 MiB and one vCPU, and attaches three
hSIMD units:

```text
unit 100  RAM-backed carrier; also the channel transport
unit 103  read-only installer/boot media
unit 105  writable 20 GiB OpenIndiana ZFS root (distpool)
```

The original development stack, still used for host-side experiments:

```text
Apple-silicon laptop
  UTM AArch64 Linux VM (hardware-accelerated)
    QEMU 8.2.2 qemu-system-sparc64 -M niagara (TCG)
      OpenSPARC hypervisor + OpenBoot
        OpenIndiana/Tribblix sun4v guest
```

The Niagara machine exposes memory-mapped hypercall disks and no NIC.  This
project uses reserved sectors in a disk as bidirectional channels:

```text
channel 0  PPP bootstrap and fallback
channel 1  Ctrl-C-safe maintenance console; also the container-local BBS
channel 2  reserved for framed Ethernet (not implemented)
```

Channel 0 starts at whole-disk block 640 (host byte 327680) and channel 1 at
block 2688 on the OpenIndiana carrier.  The framing constants are canonical in
`tools/chan/chan.h`; only the placement is per-image.

## Build, release, and CI

The appliance is built and gated by Woodpecker on `biggie`, which drives two
native builders — `ec2cicd` for amd64 and `niagara-playbox` for arm64 — and
publishes to GHCR only after a full cold-boot acceptance run.  Workflows live
under `.woodpecker/`.  The release path is deliberately push-event only: the
GHCR credential is not available to manual runs.

Artifact discipline:

- immutable, hash-pinned releases; `current` and `green` are separate labels;
- every QEMU run gets a fresh writable clone, never the release image, because
  the Niagara `MAP_SHARED` model and channel mailboxes write to their backing
  files;
- promotion only after a fresh-QEMU cold boot passes semantic gates.

See [`tools/ci/README.md`](tools/ci/README.md),
[`notes/PORTABLE-QCOW2-CI-CD-CONVEYOR.md`](notes/PORTABLE-QCOW2-CI-CD-CONVEYOR.md),
[`notes/AWS-CICD-ENGINE.md`](notes/AWS-CICD-ENGINE.md), and
[`docs/design-plans/2026-09-01-self-contained-oci.md`](docs/design-plans/2026-09-01-self-contained-oci.md).

## Repository map

```text
README.md                  current public orientation and evidence boundaries
appliances/                the released Docker/OCI appliance and its notebook
.woodpecker/               CI workflows for the amd64 and arm64 release builds
BACKLOG.md                 prioritized work items with pre-registered acceptance
CURRENT-STATE.md           detailed Solaris 10/Tribblix lab ledger (historical)
THE-*-STORY.md             narrative chapters with corrections and evidence
patches/                   reviewable QEMU/illumos patches (no QEMU source tree)
third_party/               preserved upstream sources, e.g. the hsimd driver
tools/chan/                host/guest shared-disk channels and PPP helpers
tools/openindiana/         OpenIndiana archive construction and boot helpers
tools/ci/                  the build-and-boot conveyor and artifact rules
scripts/                   ec2trib lab drivers: assemble, launch, preflight
infra/                     build-host configuration (e.g. niagara-playbox)
tests/                     Solaris 10-era integration harness (historical)
captures/                  bounded transcripts, manifests, and checkpoint data
docs/                      design and implementation plans
docs/build-trials/         build-specific product design and acceptance records
notes/                     investigations, performance data, and handoffs
md/                        editable OpenSPARC machine-description sources
```

The appliance is the current product surface; start at
[`appliances/sparc64-qemu-illumos-docker-guest/README.md`](appliances/sparc64-qemu-illumos-docker-guest/README.md)
and its
[experiment notebook](appliances/sparc64-qemu-illumos-docker-guest/EXPERIMENT-NOTEBOOK.md),
which records every release pipeline including the failures.

`CURRENT-STATE.md` is the detailed Solaris 10 and Tribblix ledger and was last
fully reconciled in late August 2026.  Where a dated later observation conflicts
with it, the later evidence controls.

The earlier portable OpenIndiana bundle trial is documented in
[`docs/build-trials/openindiana-rc-build-aug29/`](docs/build-trials/openindiana-rc-build-aug29/README.md).

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

Each patch documents its base or intended context.  Patches 0001 and 0003 are
now folded into the QEMU 10.2 branch the appliance builds from; the files here
remain the reviewable record of what each change does.

## Reproduction scope

The easiest reproduction is the published container image; nothing else is
required.

Rebuilding from source is harder.  The repository does **not** redistribute
Oracle installation media or the OpenSPARC Solaris disk image.  The historical
Solaris 10 baseline begins with Oracle's OpenSPARC T1 Architecture 1.5 package
and QEMU 8.2.2; see [`setup-host.sh`](setup-host.sh),
[`run-solaris.sh`](run-solaris.sh), and the historical integration tests.

The OpenIndiana root was assembled with a Solaris-family donor for safe UFS
boot-archive editing, from inputs whose hashes are recorded in the appliance
notebook and the implementation plans.  It is reproducible from those preserved
inputs, but it is not a one-command build from a bare host: the writable-UFS
step still needs a Solaris/illumos guest, and the pinned QEMU commit is not yet
public.  Remaining packaging work is tracked in
[`notes/OPENINDIANA-NEXT-ISO-TODO.md`](notes/OPENINDIANA-NEXT-ISO-TODO.md) and
`BACKLOG.md`.

The historical integration tests manipulate disposable ZFS datasets, launch
QEMU, and in some cases require root.  Read the scripts before running them.  Do
not point them at an irreplaceable VM image.

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

## What's next

The compatibility baseline the project originally set out to establish is done:
Murayama's stack builds, boots this project's OpenIndiana root, and is now the
release runtime.  The open work is narrower:

1. Publish the exact pinned QEMU commit on a public branch so the released
   binary is reproducible from GitHub alone.
2. Fix hsimd's large-I/O path so a ZFS root is not pinned to the unit it was
   created on, then restore the conventional unit104 role.
3. Load and prove the `TG_DK_OPS_VERSION_1` hsimd rebuild in a live guest.
4. Implement the channel-2 `libdlpi` relay and give the guest real Ethernet
   instead of PPP plus NAT.
5. Run the controlled A/B for the TLB range-flush patch and either justify or
   drop it.
6. Make the OpenIndiana text installer accept an hSIMD target so the root can be
   installed rather than assembled.
7. Ship an SSH listener and an in-guest compiler in the release image.

Murayama's OpenSolaris NIC and GEM/GLDv3 work makes his review of item 4
especially valuable, and Pimenov's PCIe firmware path is the other plausible
route to a real NIC.

If those pieces compose, the result is much closer to the useful illumos SPARC64
VM these projects are all trying to build.
