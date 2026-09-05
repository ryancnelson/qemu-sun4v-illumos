# Niagara SMP QEMU patchset

These patches are copied from the repository-level `patches/` directory so
they are available inside the appliance Docker build context. Their combined
result matches the QEMU binary that booted `oi-basecamp` with CPUs 0 and 1
online in run `niagara-smp-mondo-fix-20260904-04`.

The pinned source archive already contains the large-SPARC-TTE range-flush
change. It is not applied again here: `qemu-contract.env` pins that archive's
SHA-256, and `verify-qemu-contract.py` proves the source and compiled binary
use the range helper from `replace_tlb_entry()`.

Apply them in numeric order to QEMU commit
`049affb20df67162cf58deeaf74d5ad4b83cbdc3`. Patch 0005 adds diagnostics;
patches 0004 and 0006 change runtime behavior.
