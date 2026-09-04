# Niagara SMP preview — 2026-09-04

Ryan explicitly requested publication of the already built SMP appliance,
knowing the full networking gate was not green. This is a preview promotion,
not a rebuild or a claim that all release tests passed.

## Artifact

- Repository: `ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g`
- Preview tag: `smp-preview`
- Version tag: `20260904-smp-preview-343d2a755d03`
- Host architecture: **linux/amd64 only**.
- Guest: OpenIndiana, two Niagara CPUs, automatic verbose boot without KMDB.
- Exact OCI manifest digest / local Docker 29 image ID:
  `sha256:343d2a755d03352645d0c3ea63b3f687468a8390d2710e941b34feafac6663bc`.
- Embedded root hash:
  `c17b2c53ca831b550ee0e5795d17f1fbdc51aaca97f5a172830d44b7c70ef279`.

The local `smp-65` and `smp-66` tags both resolve to this artifact.
Biggie Woodpecker runs 65 and 66 recorded this exact build ID and:

```text
APPLIANCE_LOGIN_SMOKE=PASS
OCI_GUEST_SMP=PASS cpus=0,1 kmdb=absent
```

The same runs failed later at the compound guest resolver assertion. PPP,
outbound IP ping, and direct DNS lookup passed, but full networking acceptance
remains incomplete. This publication does not change the guest's resolver.

## Publication procedure

`.woodpecker/niagara-smp-preview.yml` runs only on the dedicated
`codex/niagara-smp-preview-publish` branch. It stages
`scripts/publish-niagara-smp-preview.sh` on ec2cicd and uses the existing
Woodpecker `ghcr_token` secret via stdin and a temporary Docker configuration.
It pins the existing image ID, verifies amd64/two-CPU/no-KMDB metadata, pushes
only the two preview tags, and checks both manifests anonymously against the
same OCI digest. `latest`, `amd64`, and `arm64` are not changed.

No QEMU boot, image build, root-volume materialization, or persistent Docker
credential change is needed. The independent development workflows do not
match this publish branch.

Download after the publication workflow succeeds:

```sh
docker pull ghcr.io/ryancnelson/sparc64-qemu-openindiana-20g:smp-preview
```

Use the normal appliance run options with this image tag. A new named volume
is required to test the embedded guest from scratch; an existing volume keeps
its prior guest disk contents.
