# Integration sequence

1. Establish immutable repository heads, deployed module identities, and
   the new appliance build location. Done: SNET commits fast-forwarded into
   isolated integration branch; six protocol tests pass. No main pushed.
2. Review the existing SNET guest and QEMU implementation. Correct runtime
   blockers and make the guest build/link procedure reproducible.
3. Preserve the accepted hsimd sources and Solaris-specific mapin patch
   with explicit variant selection and source provenance.
4. Apply SNET to the current appliance QEMU source after its existing SMP
   and range-flush fixes; stage the guest module. Use a copy of the frozen
   amd64 guest payload for runtime tests without altering run 112.
5. Verify native module loading, network traffic integrity, lifecycle and
   cold boot. Update build gates and main-branch CI triggers.
6. Review the final changes; merge the scoped driver/build work into all
   project mains without dropping divergent changes. Verify remote heads
   and CI. Update important-facts.md with exact artifacts and results.
