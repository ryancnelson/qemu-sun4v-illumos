# illumos SNET driver

This is the guest half of the OpenSPARC SNET FIFO experiment. It is a GLDv3
MAC driver, not a block driver. The hsimd code supplied the known-good sun4v
hypercall and attach conventions only.

Install integration for an illumos gate:

- `snet.c` -> `usr/src/uts/sun4v/io/snet.c`
- `snet_hcall.s` -> `usr/src/uts/sun4v/ml/snet_hcall.s`
- add `SNET_OBJS = snet.o snet_hcall.o` to `usr/src/uts/common/Makefile.files`
- add a `usr/src/uts/sun4v/snet/Makefile` following the local hsimd module
- alias `snet "net-virtual-device"` in `driver_aliases`

The first version polls once per millisecond because QEMU's Niagara IOB does
not yet provide a proven route for the q.bin SNET mondo. That is intentionally
visible in the design rather than hidden behind a fake interrupt claim.

`scripts/build-snet-driver.sh` cross-compiles both SPARC V9 objects against the
pinned illumos headers on Biggie. Copy its output directory to the SPARC
illumos guest and run `bash scripts/link-snet-driver.sh OBJECT_DIRECTORY
OUTPUT_MODULE` there. `SNET_LD` can select an existing native linker when
`/usr/ccs/bin/ld` is unavailable. Native linkage alone does not prove attach
or network traffic; those remain runtime acceptance gates.

Kernel compilation must use `-msoft-float`. Run
`bash scripts/check-sparc-kernel-object.sh OUTPUT_MODULE` on a host with
SPARC GNU objdump after native linkage as well as checking the input objects.
The old hard-float module panicked during attach; see `important-facts.md`.

The run-112 amd64 appliance boots and the corrected module attaches, but its
firmware returns `H_EBADTRAP` for both SNET calls. A matching firmware build
that enables `T1_FPGA_SNET` remains required. Do not enable SNET as a release
default until traffic acceptance passes. The existing OpenIndiana disk can
be reused with the matching emulator and firmware.

`dtrace -s tools/snet/hypercall-status.d -c '/usr/sbin/ping -s PEER 56 5'`
traces the C hypercall boundary for ten seconds. The leaf assembly stubs
themselves have no SPARC FBT probes. Negative return values preserve the raw
hypervisor error code; `-7` means invalid function number.
