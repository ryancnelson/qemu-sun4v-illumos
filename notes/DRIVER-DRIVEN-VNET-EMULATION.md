# Driver-driven Ethernet emulation for QEMU Niagara

**Status:** design hypothesis and staged experiment, not an implemented device
**Recorded:** 2026-08-25
**Immediate target:** determine whether the running Tribblix/OpenIndiana sun4v
guest contains the native `vnet`/`vnex`/`ldc` stack, then make the smallest
possible existing guest driver attach without building a PCI bus.

## The useful lesson from the eShard experiment

eShard's Raspberry Pi 3B+ experiment is unusually close to this project's
networking problem. Their goal was time-travel analysis of an unmodified
U-Boot image, but execution could not reach the NFS code because QEMU did not
model the board's LAN9514/SMSC95xx USB Ethernet function. They added a minimal
`usb-smsc95xx` model, connected it to a QEMU network backend, and implemented
only the behavior that the existing U-Boot driver demanded. Exact USB
descriptors and endpoints made the device enumerate; logging every control
transfer exposed polling loops; reading the corresponding U-Boot driver showed
which reset, MII, transmit, and receive side effects were missing. The result
reached DHCP and ICMP without recompiling the target firmware.[^eshard]

The transferable result is not their time-travel product, and it is not
specific to ARM or USB. It is a method:

1. Preserve the existing guest binary and driver.
2. Treat that driver's source as an executable peripheral specification.
3. Expose the minimum identity and topology required for driver attachment.
4. Trace every operation at the guest/emulator boundary.
5. When the guest repeats an operation or polls forever, correlate the trace
   with the driver loop and implement the missing device-side transition.
6. Advance through deliberately small milestones: discovery, attachment,
   negotiation, link-up, one transmitted frame, one received frame, then
   normal networking.

Time-travel debugging would improve this loop, but it is not a prerequisite.
QEMU tracing, targeted logging, GDB, guest `mdb`, and the illumos source can
provide the observations needed for this method.

## Does this require PCI?

Not necessarily. “Add an Ethernet port” describes the guest-visible result;
it does not dictate the bus underneath it.

| Guest-visible contract | PCI required? | What must be implemented |
| --- | --- | --- |
| Existing PCI NIC (`ge`, `bge`, `e1000g`, etc.) | **Yes** | Fire/PCIe host bridge, config and MMIO windows, DMA/IOMMU, interrupts, firmware description, and the NIC model |
| Existing USB Ethernet NIC | Not inherently, but it needs a USB bus | A sun4v-visible USB host controller, its nexus/interrupt/DMA contracts, and the USB NIC |
| Native sun4v `vnet` | **No** | MD topology, LDC queue/interrupt transport, a minimal VIO/vnet service peer, and a QEMU packet backend |
| Custom MMIO/shared-memory MAC | **No** | A new illumos driver plus an MD node, shared rings, and notification/polling |
| Existing Ethernet-over-channel design | **No** | The already-designed DLPI/etherstub relay and host TAP relay; no new emulated device |

The complete Fire/PCIe path remains valuable if the goal is to attach several
stock QEMU PCI devices. It is not a prerequisite for a native sun4v virtual
network interface.

## What `vnet` actually implies

Oracle documents a `vnet` as an Ethernet-like device in a guest domain that
connects through the hypervisor to a virtual switch by Logical Domain Channels
(LDCs). The virtual switch normally runs in a service domain.[^oracle-vnet]
That means `vnet` is not a magic QEMU NIC and q.bin is not, by itself, the
whole switch. In this project's single-domain machine, something must act as
the service peer and exchange Ethernet frames with a host backend.

The illumos implementation identifies the contracts more precisely:

- `vnet.c` is the guest MAC provider: it registers the network interface and
  implements start, stop, transmit, receive, link state, multicast, and MAC
  address operations.[^illumos-vnet]
- `vnet_gen.c` discovers `network` and `channel-endpoint` nodes in the Machine
  Description, attaches LDC channels, negotiates VIO versions and attributes,
  registers descriptor rings, and moves network data.[^illumos-vnet-gen]
- `vnex.c` is an **illumos guest nexus driver** under `/virtual-devices`; it is
  not a device that should be implemented in QEMU.[^illumos-vnex]
- `ldc.c` registers the guest's LDC hypervisor-service API and manages transmit
  and receive queues, channel state, messages, memory cookies, and
  notifications.[^illumos-ldc]
- `vio_mailbox.h` and `vnet_mailbox.h` define the version, attribute,
  descriptor-ring, ready-to-exchange, data, multicast, and link-state message
  formats. These headers are the wire-level starting specification.[^vio-mailbox]
  [^vnet-mailbox]

The corrected target architecture is therefore:

```text
illumos MAC/IP stack
        |
      vnet
        |
  VIO messages and descriptor rings
        |
       LDC
        |
  q.bin hypervisor queue/interrupt transport
        |
  minimal service peer in QEMU (placement to be proven)
        |
  QEMU NICState/NetClient backend
        |
    user/slirp, TAP, socket, or passt
```

QEMU already separates emulated NIC frontends from host network backends;
official options include user-mode networking, TAP, bridge, socket, and
passt.[^qemu-netdev] The new Niagara work should terminate in that existing
backend API rather than reimplement host IP networking.

There is now an additional, potentially shorter placement to test before
writing a VIO peer in QEMU: the running Tribblix image contains the stock
`vsw` service driver as well as `vnet`. A real service domain runs `vsw`, so an
MD containing both a `vnet` endpoint and a `vsw` endpoint in this single guest
might let the existing drivers perform the entire VIO network negotiation,
leaving q.bin responsible only for LDC transport. The live hypervisor MD
already proves that q.bin permits a same-domain LDC endpoint pair. Whether the
stock `vnet`/`vsw` drivers will use such a pair, and whether `vsw` can attach to
an etherstub or another usable MAC backend in this image, remain untested. Test
those before duplicating `vsw` in QEMU.[^oracle-vsw]

## Facts already established in this repository

- The current Niagara machine creates no PCI or VirtIO bus.
- The checked-in MD has `/virtual-devices`, simdisk, console, NVRAM, and TOD,
  but no `network` or `channel-endpoint` node. The `net` devalias alone does not
  instantiate a device. Masa's active MD is a different configuration and does
  contain LDC endpoint topology, as recorded below.
- The proven hsimd disk path uses private hypercalls `0xf0`/`0xf1`, not LDC.
- The old Solaris 10 3/05 donor was inventoried and does **not** contain
  `vnet`, `vnex`, `ldc`, `cnex`, `mdeg`, or the other LDoms virtual-I/O
  modules. Native vnet is closed for that specific guest.
- Current OpenIndiana and Tribblix media are different guests. Their module
  availability must be measured rather than inferred from the donor.
- No virtual-switch service has yet been demonstrated in this emulator. The
  live experiment below does establish guest enumeration of MD-described LDC
  endpoints and successful LDC service-group negotiation.

### Runtime result: Tribblix passes the module-availability gate

On 2026-08-25, the running Tribblix sun4v guest produced this installed-module
inventory:

```text
/platform/sun4v/kernel/misc/sparcv9/ldc
/platform/sun4v/kernel/kmdb/sparcv9/ldc
/platform/sun4v/kernel/drv/sparcv9/vnex
/platform/sun4v/kernel/drv/sparcv9/cnex
/platform/sun4v/kernel/drv/sparcv9/vnet
/platform/sun4v/kernel/drv/sparcv9/vsw
```

The same live guest reported:

```text
41  7be00000   9060   -   1  ldc  (sun4v LDC module)
42  7be08f60    f80 174   1  vnex (sun4v virtual-devices nexus dri)
43   13f9c30   18c0 238   1  cnex (sun4v channel-devices nexus)
129 7bfe0000   2340 246   1  vldc (sun4v Virtual LDC Driver)
```

`/etc/name_to_major` assigns `vnet` major 248, and
`/etc/driver_aliases` binds it to `SUNW,sun4v-network`. Thus the absence of a
loaded `vnet` is consistent with the current MD having no network node; it is
not a missing-driver result. `mdesc`, the Machine Description driver, is also
loaded. `mdeg` did not appear as a standalone module name; in illumos it is an
API implementation used by MD consumers, so the practical remaining test is
whether `vnet` resolves and registers its MDEG callbacks when a network node is
present.[^illumos-mdeg]

This also proves more than file availability. The inspected illumos `ldc.c`
returns failure from `_init()` when `hsvc_register()` cannot negotiate the
hypervisor LDC service group.[^illumos-ldc] Because `ldc` is loaded, this q.bin
successfully advertised a compatible LDC service version. Individual queue,
interrupt, mapping, and endpoint operations remain untested.

The live device tree goes further. `prtconf -Dv` shows `vnex` attached at
`/virtual-devices@100`, `cnex` at `channel-devices@200`, and `vldc` endpoints
named `hvctl` and `ldom-primary`, plus a virtual console concentrator. The exact
hypervisor MD used by this VM declares a same-domain LDC pair: guest channel 1
targets guest 0/channel 2, and channel 2 targets guest 0/channel 1. q.bin thus
already has the routing primitive needed to connect two service endpoints
inside this single Tribblix domain. This is the template for the first
`vnet`/`vsw` experiment.

### Exact live-candidate provenance

The shell was reached through biggie tmux target `tribcons:0`. The active QEMU
worker was PID 265686 under candidate directory
`tribblix-hsimd-v1-20260825T2255Z`. The measured inputs were:

| Object | SHA-256 |
| --- | --- |
| QEMU `qemu-tlb-integration/build/qemu-system-sparc64` | `ea9348f2565befef00b7f8628489be01bde5799df842c88cdfe70a25664bba3c` |
| q.bin | `47ddae19e1d4ee0143326991ffc71eca71b5d7b0383cd3947187171bbb2eaee3` |
| guest `md.bin` | `b5d160f6f55a30d2ed56b5e24f9b1158180bb6a84d71fe222b4476945bd5b823` |
| hypervisor `hv.bin` | `1c3d9dc2a5dace6e33b7443c1cae07b4ee235109ca29b9d6c54c3171b968ee27` |
| `staging/boot_archive.v5.ufs` | `45e8c559d0c7198ee6da2ca183623972ef799c1f06c1a339a0457db85d22df45` |
| `images/big-disk-unit103-v5.img` | `96caa933432abcc909a6760a654d0dde89e70ccd954a4a1159d8d856f124433c` |

The boot archive and unit-103 image mtimes were unchanged across hashing. The
guest identified itself as `SunOS 5.11 tribblix-m34 sun4v sparc` and
`/etc/release` reported Tribblix m34.

### Existing `snet` prior art: real, close, and unfinished

Masa's active guest MD also contains an `snet` virtual device with
`fcode-driver-name = "net-virtual-device"`; live `prtconf` sees `snet`, but no
driver attaches and no device node is created. The paired hypervisor MD gives
it physical address `0xfff0c2c050` and interrupt `0x3f`.

This is not a placeholder name. OpenSPARC's `vdev_snet.s` implements q.bin
hypercalls `SNET_READ` (`0xf2`) and `SNET_WRITE` (`0xf3`) by copying an aligned
packet buffer between guest real memory and the fixed SNET physical address;
it also propagates an SNET interrupt to the guest.[^opensparc-snet] That is
almost exactly the “add an Ethernet port behind an existing driver contract”
shape suggested by eShard.

It is not already a usable port. The supplied OpenBoot `snet` FCode defines
only `open` and `close` and comments that `read` and `write` are still needed
for network boot. Tribblix has no attached OS driver for the live `snet` node.
The SNET path is useful implementation archaeology and a possible small
custom-driver target, not a substitute for the stock-vnet experiment.

## Pre-registered experiment

### Gate 0: inventory the running guest — passed for Tribblix

Run as root in the currently booted Tribblix/OpenIndiana guest:

```sh
echo '=== installed modules ==='
find /kernel /platform/sun4v/kernel -type f \
  \( -name vnet -o -name vnex -o -name ldc -o -name cnex \
     -o -name mdesc -o -name vsw \) -print 2>/dev/null

echo '=== loaded modules ==='
modinfo | egrep 'vnet|vnex|ldc|cnex|mdesc|vldc|vsw'

echo '=== driver registrations ==='
egrep 'vnet|vnex|cnex' /etc/name_to_major /etc/driver_aliases 2>/dev/null

echo '=== enumerated device tree ==='
prtconf -Dv | egrep -i \
  'virtual-devices|virtual-device|network|vnet|vnex|channel-endpoint|ldc'
```

Interpretation:

- Installed `vnet`, `vnex`, `ldc`, `cnex`, and `mdesc` modules make this path a
  candidate. An empty `modinfo` result only means they are not loaded.
- Missing guest modules close the stock-vnet path for that image; use a newer
  boot archive, add the modules, or pursue the existing channel/custom-MAC
  path.
- Missing network nodes in `prtconf` are expected with the current MD and do
  not disprove module support.

The live Tribblix result above passes the functional availability check and
records exact QEMU, firmware, MD, boot-archive, and media hashes. Repeat
independently for OpenIndiana.

### Gate 1: prove the hypervisor transport boundary

Before writing packet code:

1. Enumerate the LDC-related hypercall/service groups used by this exact guest
   from `ldc.c` and the sun4v headers.
2. Start from the already-enumerated same-domain LDC channels 1 and 2. Extend
   that known-good topology rather than designing endpoint routing anew.
3. Determine whether a same-domain `vnet`/`vsw` pair is supported. Use the
   installed guest `vsw` as the first service peer; only if that fails should
   a minimal peer move to the q.bin/QEMU boundary.
4. Add minimal MD `network` and `network-switch` nodes plus their endpoint
   pair, based on properties consumed by `vnet_gen.c` and `vsw.c`.
5. Instrument every relevant hypercall, queue-state transition, and interrupt.
6. Boot once and capture the first failed call or repeated poll.

**Gate-1 acceptance:** `vnex` enumerates a network child and `vnet` reaches a
specific, logged LDC operation. A device-tree node with no driver progress is
not acceptance.

### Gate 2: attach without packet movement

Implement only enough LDC and VIO behavior for:

1. channel reset/up;
2. VIO version negotiation;
3. network attribute negotiation, including a fixed locally administered MAC;
4. descriptor-ring registration;
5. ready-to-exchange completion; and
6. link-up notification.

**Gate-2 acceptance:** `dladm show-link` reports one stable vnet-backed link
with the expected MAC and link state. No DHCP or IP requirement yet.

### Gate 3: one frame in each direction

Connect the service peer to a QEMU network backend and prove, in order:

1. one transmitted Ethernet frame reaches a host capture;
2. one injected frame reaches the guest MAC layer;
3. ARP completes;
4. static-address ICMP succeeds; and
5. DHCP succeeds only after deterministic layer-2 traffic works.

Every run must retain the QEMU command, q.bin/MD/QEMU/boot-archive hashes,
console transcript, hypercall/VIO trace, packet capture, and elapsed time.

## Decision rule

Attempt Gate 0 and Gate 1 before committing to a full Fire/PCIe implementation.
If the guest has the required modules and the LDC boundary is observable, use
the eShard loop: satisfy the next operation demanded by the existing driver,
one state transition at a time. If the LDC path is absent or inseparable from
an unavailable service-domain implementation, that is evidence for the
custom shared-memory MAC described in `ETHERNET_MUSINGS.md`, not evidence that
Ethernet inherently requires PCI.

## References

[^eshard]: Guillaume Vinet, eShard, [“Time Travel Analysis with QEMU on IoT Targets: Not Always That Hard — Part II”](https://www.eshard.com/blog/u-boot-cve-tta-qemu-part-2), 13 May 2026.
[^oracle-vnet]: Oracle, [“Virtual Network Device”](https://docs.oracle.com/en/virtualization/oracle-vm-server-sparc/ldoms-admin/virtual-network-device.html), Oracle VM Server for SPARC Administration Guide.
[^oracle-vsw]: Oracle, [“Virtual Switch”](https://docs.oracle.com/en/virtualization/oracle-vm-server-sparc/ldoms-admin/virtual-switch.html), Oracle VM Server for SPARC Administration Guide.
[^illumos-vnet]: illumos gate, [`usr/src/uts/sun4v/io/vnet.c`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/io/vnet.c), source revision inspected 2026-08-25.
[^illumos-vnet-gen]: illumos gate, [`usr/src/uts/sun4v/io/vnet_gen.c`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/io/vnet_gen.c), source revision inspected 2026-08-25.
[^illumos-vnex]: illumos gate, [`usr/src/uts/sun4v/io/vnex.c`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/io/vnex.c), source revision inspected 2026-08-25.
[^illumos-ldc]: illumos gate, [`usr/src/uts/sun4v/io/ldc.c`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/io/ldc.c), source revision inspected 2026-08-25.
[^illumos-mdeg]: illumos gate, [`usr/src/uts/sun4v/io/mdeg.c`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/io/mdeg.c), source revision inspected 2026-08-25.
[^vio-mailbox]: illumos gate, [`usr/src/uts/sun4v/sys/vio_mailbox.h`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/sys/vio_mailbox.h), source revision inspected 2026-08-25.
[^vnet-mailbox]: illumos gate, [`usr/src/uts/sun4v/sys/vnet_mailbox.h`](https://github.com/illumos/illumos-gate/blob/f9db9ff779c49e6c6c53004fb478ca21c4cbdb57/usr/src/uts/sun4v/sys/vnet_mailbox.h), source revision inspected 2026-08-25.
[^qemu-netdev]: QEMU project, [QEMU invocation documentation: network options](https://www.qemu.org/docs/master/system/invocation.html#hxtool-5), accessed 2026-08-25.
[^opensparc-snet]: OpenSPARC hypervisor source, [`src/greatlakes/common/src/vdev_snet.s`](https://github.com/sun4v/hypervisor/blob/69cd71bb382d4560668f56acbc117ed8dd1760aa/src/greatlakes/common/src/vdev_snet.s), source revision inspected 2026-08-25.
