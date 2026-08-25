# Murayama qemu-sun4v prior art (2026-08-24)

## Correction to the project premise

Masayuki Murayama has published a current, reproducible Solaris 10 installation
procedure for a substantially extended QEMU `niagara` machine.  This is more
than the older result that merely reaches a Solaris prompt with an `hsimd`
RAM-disk image.  It does not yet provide networking, but it provides a serial
console, as many as eight virtual disks, 1--8 guest CPUs, a launcher default of
3 GiB RAM, and a procedure for installing Solaris 10u11 onto a persistent
virtual disk.

The distribution repository first appeared on 2026-07-15.  Version 0.2 with
MP support and an updated `hsimd` package appeared on 2026-08-23/24 (JST), so
this is genuinely new prior art.

Primary sources:

- <https://github.com/masa-murayama/qemu-sun4v-dist-pkg>
- <https://github.com/masa-murayama/qemu-sun4v-dist-pkg/blob/main/run_vm_test.sh>
- <https://github.com/masa-murayama/qemu-sun4v>
- <https://github.com/masa-murayama/qemu-sun4v-openboot>
- <https://github.com/masa-murayama/qemu-sun4v-hypervisor>
- <https://github.com/masa-murayama/qemu-sunv4-guest-util>
- <https://github.com/masa-murayama/qemu-sun4v-host-util>

## What the published procedure does

The documented workflow boots the Solaris 10u11 SPARC DVD from
`/virtual-devices/disk@3`, lets the stock installer fall to a shell because
the paravirtual disk driver is absent, transfers `hsimd.pkg.shar` over the
console with `cu`, installs the driver, and restarts `install-solaris`.  After
installation it installs `hsimd` into the target root and runs:

```text
bootadm update-archive -R /a
```

The launcher presents the writable root image as bus 0/unit 100 and the DVD
as bus 0/unit 103.  This is a real block-backed, persistent install target,
not just an ISO or a single memory-mapped donor image.

The README explicitly says that devices such as networking are not supported
yet.  Therefore our working OpenIndiana boot archive, channel services, and
networking work remain novel and useful even if we adopt this implementation
as a stronger emulator base.

## Source-level comparison

The current source branch is `sun4v` at commit
`879fee341ad8307f8f0a0110b4a7dc6d6853d639` (`mp snapshot 0.2`) and is tagged
`v10.2.0-sun4v-0.2`.  Against its QEMU 10.2 base (`698104725...`) it changes
18 files by approximately +2625/-55 lines.  The largest changes are:

- `hw/sparc64/niagara.c`: machine construction, multiple block-backed virtual
  disks, UART arrangement, and a sun4v I/O bridge/interrupt model;
- `target/sparc/int64_helper.c`: extensive interrupt/trap and sun4v behavior;
- `target/sparc/ldst_helper.c`: MMU/ASI fixes, including sun4v `PGSIZE2`;
- CPU initialization and SMP support throughout the SPARC target.

Its binary is an x86-64 Linux ELF with debug information and is not stripped.
The distribution binary's SHA-256 is:

```text
804f9b0dc6b64973e24d525a8d6ecab4145e1f0299e08dd0cc5b595a59a59e4e
```

Do not execute the downloaded binary merely on the strength of this note;
prefer a source build and preserve exact commit/build provenance.

Repository heads inspected for this note:

```text
qemu-sun4v           879fee341ad8307f8f0a0110b4a7dc6d6853d639
qemu-sun4v-openboot  7c3ab581b1b0c482df6bb87a8eb28b357a721bec
qemu-sun4v-hypervisor a30011e462a4af69bb42be541c99063aae46ca32
qemu-sun4v-host-util f9ae43e7c80f8ba63651acff853ae2f4f107eb76
qemu-sunv4-guest-util 128e7528a9da448eb0c0f78c41032f239b5bb613
qemu-sun4v-dist-pkg  3eb7ce6cbda552ff2c03afc5fbb8a2bfede2cdd0
```

## Relevance to current bugs and performance work

### Console and interrupts

Murayama's machine defines two UART roles: a hypervisor/FPGA UART on serial 0
and a standard UART (`ttya`) on serial 1.  Its launcher discards serial 0 and
connects `cu` to the PTY for serial 1.  The 16550 construction still passes a
null direct QEMU IRQ, so this is not a one-line answer to our blocking-getty
problem.  The likely material differences are the separate UART roles plus
the modified hypervisor, OpenBoot, IOB, interrupt dispatch, and CPU-kick path.
Those pieces must be tested as a coherent stack.

### Storage

The source supports multiple `BlockBackend`-backed disks and asynchronous
block I/O.  That is a much better base for the OpenIndiana installer than our
current layout and could eliminate the installer's inability to discover an
ordinary target disk.  It should also be compared directly with our original
memory-mapped `hsimd` path for boot-time performance.

### TLB performance

Murayama's current `replace_tlb_entry()` still invalidates a large mapping one
8 KiB page at a time with repeated `tlb_flush_page()` calls.  Our independently
derived `tlb_flush_range_by_mmuidx()` experiment therefore remains relevant
and should be benchmarked on this fork after establishing a clean baseline.
Do not mix it into the first compatibility test.

### Networking and channels

The imported hypervisor source contains LDC machinery, and the guest utility
tree includes illumos/Solaris LDC and vnet headers, but the distribution
README explicitly reports no network device.  Presence of those inherited
sources is not evidence of a working host channel server or vnet backend.
Our channel server and Ethernet-over-channel work still fill the published
implementation's most important missing feature.

#### Specific proposal for Murayama: etherstub to channel 2

The smallest useful collaboration experiment is a userland Ethernet path:

```text
illumos IP -> vnic0 -> etherstub -> wire0 -> libdlpi relay
            -> channel 2 -> Linux relay -> TAP -> host network
```

It needs no emulated PCI bus, stock NIC model, or new guest kernel driver.  It
would let us validate ordinary Ethernet semantics on his QEMU machine while
keeping channel 0 available for PPP and channel 1 for the maintenance console.

This is a proposal, not a completed result.  We have demonstrated temporary
etherstub and VNIC creation, but the stripped-down Tribblix environment failed
at `ipadm` because its IP administration/socket-provider substrate is
incomplete.  The DLPI relay, Linux TAP bridge, ARP, and IP traffic remain to be
built and tested.  The exact validation sequence is in
[`ETHERNET-OVER-CHANNEL.md`](ETHERNET-OVER-CHANNEL.md); alternatives at the
GLDv3 and native virtual-device layers are in
[`../ETHERNET_MUSINGS.md`](../ETHERNET_MUSINGS.md).

Murayama's prior OpenSolaris NIC and GEM/GLDv3 work makes this a particularly
useful design boundary to review together: the userland relay can prove the
upper path immediately, then the unchanged Ethernet-facing design can move
behind a pseudo-driver or a proper sun4v virtual device.

## Next evaluation sequence

- [ ] Preserve the currently running instrumented baseline; do not interrupt
  or replace it for this discovery.
- [ ] Clone and pin all five source repositories and record full commit IDs.
- [ ] Build the `sun4v` QEMU branch from source on playbox; do not initially
  run the distributed executable.
- [ ] Build and use Murayama's matching OpenBoot, hypervisor, and machine
  description rather than mixing firmware generations on the first run.
- [ ] Reproduce the documented Solaris 10u11 install on a disposable image.
- [ ] Boot our current OpenIndiana ISO unchanged on that coherent stack and
  record console milestones, CPU time, wall time, and disk discovery.
- [ ] Compare its two-UART console behavior with our channel-1 getty failure.
- [ ] Determine the smallest source delta needed to connect our host channel
  server and Ethernet-over-channel implementation.
- [ ] Only after the baseline comparison, port and A/B test our TLB range-flush
  optimization.
- [ ] Contact Masayuki Murayama before duplicating work; offer our OpenIndiana boot
  archive, networking/channel work, measurements, and fixes upstream.

## Revised project claim

The defensible claim is no longer “there is no published useful sun4v VM.”
It is:

> A newly published QEMU sun4v stack can install and persistently boot Solaris
> 10 with serial console, multiple disks, and SMP, but it does not yet provide
> networking.  This project is extending the state of the art toward a useful
> OpenIndiana/illumos VM with working channels and networking.
