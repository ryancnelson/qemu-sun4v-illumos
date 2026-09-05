# Driver integration across project mains

The user authorized merging the SNET work and accepted hsimd changes into
the project main branches and making subsequent appliance builds consume
them. Repositories are `qemu-sun4v-illumos`,
`qemu-sun4v-illumos--new-drivers`, `niagara-qemu-solaris-lab`, and the
existing Gitea `niagra-qemu-solaris-project` mirror. Preserve each repository's
unrelated work and never force-push divergent main branches.

SNET requires both the guest GLDv3 module and the QEMU FIFO device. It does
not use hsimd disk channels. The accepted Solaris 11.4 hsimd mapin change is
a separate build variant; its binary must not silently replace the
OpenIndiana module with a different ABI.

The appliance integration base is the cross-architecture golden-volume
work, currently branch `codex/cross-arch-golden-volume` at `89baac8`.
On September 5, amd64 run 112 on ec2cicd had produced a healthy container
and passed its first cold boot. It still lacks `sun4v-snet`. Preserve that
run and reuse its frozen guest payload in an isolated driver test appliance.
Preserve its accepted QEMU range-flush and SMP patches when adding SNET.

Before enabling SNET as the network default, native module linkage and a
guest test must prove attach, ARP, ICMP, bidirectional TCP integrity and
stop/detach behavior. Existing build success proves compilation only.
Record artifact hashes and build revisions so later builds cannot quietly
fall back to the 2006 vendored hsimd or an unpatched QEMU tarball.

Merges will follow code review and relevant tests. The live TedDeck VM and
the appliance task's active CI container remain available during testing.
