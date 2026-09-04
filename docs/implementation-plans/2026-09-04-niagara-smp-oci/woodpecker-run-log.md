# Woodpecker run log

Branch: `codex/niagara-smp-oci`

Controller: Biggie Woodpecker, repository `ryancnelson/niagara-qemu-solaris-lab`

Build host: `ec2cicd` (`100.71.153.107`)

| Pipeline | Commit | Result | Finding |
| ---: | --- | --- | --- |
| 56 | `b859f8d` | failed | Woodpecker expanded `${SMP_CPUS:-2}` inside a static `grep`; commit `d8d9f54` replaced the brittle assertion. |
| 57 | `d8d9f54` | failed | The 20 GiB guest-root rewrite filled ec2cicd. The partial `.tmp` was removed, dangling Docker images were pruned, and the persistent `openindiana-sparc64` volume was preserved. |
| 59 | `ee89f80` | failed | A repository-level policy test ran after only the appliance subtree had been staged. Commit `c16ec24` moved the assertion to the pre-staging Woodpecker step. |
| 60 | `c16ec24` | failed | The mutable root and its read-only backup had both drifted from `assets.release.SHA256SUMS`. |
| 61 | `b5c9056` | failed | The build host's release archive had also drifted from `RELEASE-ARCHIVE.SHA256SUMS`. |
| 62 | `1e72660` | killed | The archive was restored from immutable GHCR digest `sha256:29cadb0e...`. The controller killed the workflow while the remote root hash was still running; no image was produced. |
| 63 | `1e72660` | failed | Bundle and root recovery passed; the final image built as `:self-contained`. `SELF_IMAGE` was not exported to the child appliance process, so the required `:smp-63` tag did not exist. |
| 64 | `942bf2e` | failed | The `:smp-64` image built successfully. The interactive gate could not start because superseded untagged images had exhausted the build host; only those images were removed and the persistent guest-root volume was preserved. |
| 65 | `e0df5af` | failed | Image assembly and the interactive gate passed. The cold boot proved `OCI_GUEST_SMP=PASS cpus=0,1 kmdb=absent`, then reached networking and failed because the packaged guest configured the container DNS forwarder at `10.0.5.1` while the gate still expected `8.8.8.8`. |

Commit `942bf2e` exports `SELF_IMAGE`. Local verification at that checkpoint:

```text
SMP_POLICY=PASS cpus=2 kmdb=disabled
OPENBOOT_POLICY=PASS root_unit=105 openboot_disk=5 boot_file=-v auto_boot=true
94 passed, 2 skipped
```

Pipeline 65 proved the two-CPU, no-KMDB objective. Its remaining failure is an
independent resolver-policy mismatch. The appliance documentation already names
`10.0.5.1` as the guest resolver because that address is the container-local DNS
forwarder; the guest helper, installer, policy test, and cold-boot assertion are
being aligned to that address for the next run.
