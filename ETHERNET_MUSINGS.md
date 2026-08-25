# Ethernet Musings

This document collects the architectural discussion around giving the QEMU
Niagara/T2000 guest networking. It deliberately separates the immediate
Ethernet-over-channel experiment from possible longer-term virtual hardware.

The short conclusion is that Solaris does not need to believe it has a real
PCI Ethernet card. The useful compatibility boundary is the illumos MAC/GLDv3
framework. A small driver can present a normal data link to Solaris while its
other side exchanges frames with a deliberately simple virtual transport.

## What exists now

The Niagara QEMU machine is unusually sparse. `qemu-new/hw/sparc64/niagara.c`
creates the CPU, partition and hypervisor memory, firmware regions, UART, RTC,
and a memory-backed virtual disk. It creates neither a PCI bus nor a VirtIO
bus.

The firmware stack is:

```text
reset.bin
  -> q.bin             OpenSPARC/Sun sun4v hypervisor
       -> openboot.bin Sun OpenBoot
            -> Solaris or illumos sun4v kernel
```

This is distinct from QEMU's generic `sun4u` machine, which runs OpenBIOS
directly. Niagara boots Solaris because it has the Sun hypervisor and OpenBoot
environment Solaris expects.

The working disk path is:

```text
UFS/raw disk request
  -> hsimd
  -> hypercall 0xf0 or 0xf1
  -> q.bin
  -> QEMU's shared mapping of the disk image
```

The existing host channels reuse a reserved region of that same disk image:

```text
guest /tmp/niag/N
  -> guest-chand
  -> reserved raw disk blocks
  -> hsimd and q.bin
  -> shared disk-image pages
  -> host-chan.py
  -> host /run/niagN
```

q.bin does not know about Unix sockets. The guest and host daemons create a
socket facade around a shared, polled disk region.

This is functionally a primitive virtqueue wearing a disk costume: shared
buffers, producer and consumer state, and polling in place of doorbells and
interrupts. It proved that bidirectional data exchange works, but it also
inherits sector alignment, block-device contention, polling overhead, and a
risk of damaging storage when boundaries are wrong.

## Ethernet does not imply a physical NIC

Solaris 11 and illumos already separate network links from physical adapters.
Etherstubs, VNICs, VLANs, zones, and the IP stack operate above the MAC/GLDv3
interface. A host-facing driver only needs to register a data link and move
complete Ethernet frames:

```text
host packet -> RX ring -> niagnet -> mac_rx() -> Solaris network stack
Solaris packet -> niagnet mc_tx() -> TX ring -> host
```

The driver would provide the small set of MAC operations needed for:

- start and stop;
- transmit;
- unicast and multicast address configuration;
- promiscuous mode;
- link-state reporting;
- receive delivery through `mac_rx()`.

After registration, Solaris should see an ordinary link such as `niag0` or
`ryan0`. IP, VNICs, VLANs, etherstubs, zones, routing, and other facilities can
sit above it without understanding the transport.

Consequently, this device does not need to imitate HME, Tulip, e1000, or any
other piece of silicon. Those models are valuable primarily when reusing
existing drivers across many operating systems is more important than the
cost of emulating their historical register, descriptor, PHY, EEPROM, DMA,
and interrupt behavior.

## The Ryanomatic 4000 thought experiment

A made-up virtual peripheral is legitimate. Device names and register layouts
are contracts, not laws. For example, OpenBoot might eventually present:

```text
/virtual-devices@100/ryanomatic@0
    compatible = "ryan,ryanomatic4000"
    channels = 16
    ...transport-specific properties...
```

OpenBoot only describes the device. A driver binding to
`ryan,ryanomatic4000` supplies its meaning.

A generic transport could eventually support several clients:

```text
ryanomatic transport
  |- niagnet   -> GLDv3/MAC Ethernet link
  |- niagchan  -> character streams and additional consoles
  `- niagblk   -> optional block device
```

That decomposition is an end-state, not a requirement for the first
experiment. The initial implementation should contain only the transport and
the networking client needed to prove packet movement.

## Smallest useful transport

The first dedicated transport need not implement DMA or interrupts. It can
use fixed shared memory and copied packets:

```text
struct ring {
    producer_index;
    consumer_index;
    descriptor descriptors[N];
};
```

Required rules include:

- fixed, documented byte order and structure layout;
- strict bounds and maximum-frame checks;
- ownership rules for each descriptor;
- monotonic or explicitly wrapping producer/consumer counters;
- reset and reconnection behavior;
- no descriptor may name memory outside the assigned shared region.

Polling is acceptable for the first proof. Doorbells and guest interrupts can
be added after the queue is demonstrably correct. Avoiding device-driven DMA
initially also reduces the ways a driver or emulator mistake can corrupt the
guest after a long boot.

There are two principal ways to place the transport below the driver:

```text
Solaris driver -> MMIO/shared memory -> QEMU device
```

or:

```text
Solaris driver -> custom hypercalls -> q.bin -> shared host service
```

The direct-QEMU route may avoid changing q.bin, but it must first prove that a
sun4v guest can map and access the chosen physical I/O region. Interrupts must
still be translated into the sun4v guest's interrupt model.

The hypercall route fits the existing `/virtual-devices` architecture, but it
requires either rebuilding or safely patching the working q.bin. Suggested
hypercall numbers in discussions are illustrative only; they have not been
allocated or implemented.

## A pseudo-driver can prove the upper half first

A firmware-described device might not be needed for the earliest GLDv3 test.
A Solaris pseudo driver could register beneath `/pseudo`, expose a MAC link,
and use the already-working disk channel as its backend. That would test:

- MAC registration and link creation;
- outbound `mc_tx()` handling;
- inbound `mac_rx()` delivery;
- ARP, IP, TCP, and normal Solaris administration;
- sustained Ethernet framing over the current channel.

Once that works, the MAC-facing portion can remain unchanged while its backend
moves from the disk mailbox to dedicated shared rings.

The lower-risk userland version of this experiment is already described in
[`notes/ETHERNET-OVER-CHANNEL.md`](notes/ETHERNET-OVER-CHANNEL.md): attach a
DLPI relay to a VNIC/etherstub and carry raw Ethernet frames through a channel
to a Linux TAP device. It should remain the quickest no-new-kernel-driver
experiment.

## Why this need not be PCI

Calling a custom transport PCI creates obligations that provide no benefit if
we never intend to attach existing PCI devices:

- configuration-space enumeration;
- BAR discovery and mapping;
- PCI address and DMA conventions;
- interrupt pins and possibly MSI/MSI-X;
- bridge/nexus behavior;
- standard PCI firmware properties.

A custom platform or virtual device should therefore not be called PCI merely
because it moves data between a driver and an emulator.

PCI becomes useful under a different objective: reuse QEMU's existing PCI
devices and their stock guest drivers. If the objective changes to attaching
`sunhme`, IDE, USB, or arbitrary QEMU PCI devices, then paying for a PCI nexus
can be worthwhile.

## What can be reused from QEMU sun4u PCI

QEMU's `sun4u` implementation already constructs:

```text
sun4u IOMMU
  -> Sabre PCI host bridge
       -> Simba PCI bridges
            |- EBus and serial
            |- PCI NIC
            `- CMD646 IDE
```

The implementation supplies a QEMU `PCIBus`, configuration-space access,
MMIO and I/O address spaces, an IOMMU address space, interrupt collection,
secondary buses, and arbitrary QEMU PCI leaf devices. Those internal pieces
are reusable in a Niagara-derived machine.

Merely copying a Sabre node into the Machine Description would not be enough.
A working graft has three contracts:

1. OpenBoot must describe the PCI nexus to Solaris.
2. Configuration, MMIO, and DMA must reach the QEMU PCI implementation, with
   DMA translated into Niagara partition RAM rather than sun4u's memory map.
3. PCI interrupts must be delivered through q.bin's sun4v guest interrupt
   mechanism rather than wired directly to the CPU as `sun4u.c` does.

Possible strategies are:

- expose Sabre and attempt to reuse a suitable 64-bit Solaris sun4u nexus;
- expose a minimally compatible Fire/`px` frontend backed by QEMU's existing
  PCI core;
- expose a deliberately simple PCI root and write a custom `niagapci` nexus.

This path may be valuable as a general virtual platform, but it is not
automatically the shortest route to networking.

## The Solaris 9 SPARCstation-5 reference

A running Solaris 9 VM on `teddeck` was inspected through its console. It
reported:

```text
SunOS solaris 5.9 Generic sun4m sparc SUNW,SPARCstation-5
32-bit sparc kernel modules
```

Its working network hierarchy is:

```text
iommu
  -> sbus
       -> ledma
            -> le
```

That machine demonstrates that QEMU firmware descriptions, a Solaris nexus,
DMA support, and a stock leaf driver can compose successfully. It does not
provide a self-contained `le` device that can simply be named in the Niagara
tree. The `le` driver depends on `ledma`, SBus mapping and interrupts, and the
sun4m IOMMU; its observed modules are 32-bit and cannot be loaded directly in
a 64-bit sun4v kernel.

Solaris would not object to an historically implausible peripheral merely
because of its age. It would object when the parent-bus, register, DMA, or
interrupt contracts were absent.

## HME, Tulip, and portable historical drivers

QEMU's `sunhme` model is a `PCIDevice` and uses PCI DMA and PCI interrupt
services. Presenting it to Niagara therefore requires a PCI path or a material
rewrite of the device model and guest driver.

Masayuki Murayama's historical Solaris Ethernet-driver collection is relevant
as design archaeology. Many drivers shared the GEM framework (`gem.c` and
`gem.h`), showing how a common Solaris-facing layer can support many different
hardware backends. It is not a reason to emulate one of those chips when we
control both sides of the virtual interface. A direct modern GLDv3 provider is
likely smaller, while GEM remains useful reference material for Solaris driver
structure and portability.

## USB is the same abstraction question

USB does not inherently require PCI. A virtual host-controller driver can
present a root hub regardless of what imaginary platform bus contains it.
Solaris's existing USB controller drivers, however, expect the real controller
and nexus contracts they were written for. Implementing a virtual HCD would be
possible but offers little toward the immediate networking goal compared with
a direct MAC provider.

## Recommended sequence

1. Finish the userland Ethernet-over-channel experiment using DLPI,
   etherstub/VNIC, and Linux TAP.
2. If userland overhead or boot integration is unacceptable, implement a
   minimal pseudo MAC driver using the same channel backend.
3. Specify and test a transport-independent ring ABI in host-side/userland
   harnesses.
4. Implement dedicated shared rings through either QEMU MMIO or new q.bin
   hypercalls.
5. Replace the MAC driver's disk-channel backend without changing its GLDv3
   interface.
6. Add notification/interrupt delivery only after polling is reliable.
7. Consider a PCI root-complex graft only if reusing multiple existing QEMU
   PCI devices becomes an explicit project objective.

The architectural rule is: preserve standard Solaris abstractions above the
driver, but do not emulate unnecessary historical abstractions below it.
