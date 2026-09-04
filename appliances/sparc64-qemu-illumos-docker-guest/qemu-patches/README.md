# Niagara SMP QEMU patchset

These patches are copied from the repository-level `patches/` directory so
they are available inside the appliance Docker build context. Their combined
result matches the QEMU binary that booted `oi-basecamp` with CPUs 0 and 1
online in run `niagara-smp-mondo-fix-20260904-04`.

Apply them in numeric order to QEMU commit
`049affb20df67162cf58deeaf74d5ad4b83cbdc3`. Patch 0005 adds diagnostics;
patches 0004 and 0006 change runtime behavior.
