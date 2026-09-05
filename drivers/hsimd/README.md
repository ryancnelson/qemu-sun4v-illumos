# Current hsimd sources

These are the VERSION_1/multiunit sources preserved from Biggie's
`~/devel/masa-sun4v/hsimd-version1-candidate/build-output-isolated` on
September 5, 2026. They supersede the old synchronous source in
`third_party/hsimd` for current driver work. Upstream lineage is
`masa-murayama/qemu-sunv4-guest-util`, commit
`128e7528a9da448eb0c0f78c41032f239b5bb613`, with our compatibility edits.

| Source | SHA-256 |
| --- | --- |
| hsimd.c | `1aadce86da1dfa6f23875254c8863ee196b0e62bd6eadf0c5e8fa55f0e18da2b` |
| hsimd_asm.s | `e3b6455203a6bea8ac882499bbb23be30549b86f5d7ee00ae80a36d5fe9f2d9b` |
| hsimd.c after s114-mapin.patch | `100d3b3377c0ca833cd8d844e2b2366c9f373ceac46d8dce919c6814d0f46ed7` |

The Solaris 11.4 variant disables `CONFIG_HAT_BUG`, using `bp_mapin()` and
`va_to_pa()` instead of relying on illumos `struct page` offsets. It is an
explicit variant, not an automatic replacement for the OpenIndiana module.
The accepted native Solaris module was version `0.0.6_s114_mapin1`, SHA-256
`13ff1a9c2a6cb1893b777d95ca01b97b763c383e31076bef165ea1187ffa7eb3`.
Trial 033 verified live module replacement and matching reads of installer
files up to 191 MiB. Build evidence resides on Biggie under
`~/vms/solaris11-installer-20260904/cpu-id-trials/033-s114-combined-range-flush/hsimd-mapin-candidate`.

The OpenIndiana module currently loaded on TedDeck is `0.0.6_aio2`, SHA-256
`40201a31bb6b721975ae8ced12f22b1e6f620c8863d352ba411472e464a9a1a0`.
Rebuilt artifacts require their own hash and runtime verification. SNET is
a separate MAC driver; hsimd remains responsible for disk I/O.

Build objects with `bash scripts/build-hsimd-driver.sh oi-aio2` or
`bash scripts/build-hsimd-driver.sh s114-mapin1`. `ILLUMOS_UTS`, `SPARC_CC`
and `HSIMD_DRIVER_BUILD` select the pinned headers, cross compiler and
output directory. Native linkage on the intended SunOS SPARC build guest is
`ld -r -dy -N misc/cmlb -o hsimd hsimd.o hsimd_asm.o`. Object compilation
does not establish kernel ABI compatibility. Verify the target variant
before replacing a live root-disk driver.
