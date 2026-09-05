# Driver repositories and CI

Verified 2026-09-05 from GitHub branch refs, local checkouts, Biggie
Woodpecker, and task `red sol11 niagara - assembly`
(`01a06e32-477b-7630-b0d6-17c650e631fd`). No merge, pipeline restart or driver
deployment was performed during this review.

## Repositories and branches

| Repository | Role and verified location |
| --- | --- |
| `ryancnelson/qemu-sun4v-illumos` | Base/publication repo; remote `github` in the current checkout |
| `ryancnelson/qemu-sun4v-illumos--new-drivers` | SNET driver and QEMU NIC; `~/devel/qemu-sun4v-illumos--new-drivers` on Minnie; remote `origin` there |
| `ryancnelson/niagara-qemu-solaris-lab` | Private lab builds and releases; remote `private-github` in the current checkout |
| Biggie Gitea `ryan/niagra-qemu-solaris-project` | Remote `origin` in the current checkout; not the same remote as the new-drivers checkout's `origin` |

GitHub `main` on both qemu-sun4v-illumos repos currently resolves to
`fb447367dde6d8e778d2ac0f75080372766d460a`. New-drivers branch
`codex/snet-driver` resolves to `29c3db6c80eb476ddcec819e091d6f9f88092126`.
Its five commits are `d94ae6d`, `db62f54`, `72df903`, `ae87cdf`, `29c3db6`.
The diff adds 18 files/1,119 lines relative to their shared main.

Existing SNET worktree on Minnie:
`~/devel/niagra-qemu-solaris-project/snet-driver-worktree`, on
`codex/snet-driver`. The separate primary new-drivers checkout remains on
`main`. Both were clean at inspection. The current task checkout is on
`codex/openbios-sun4u-ci`, not the SNET branch.

The reviewed Solaris task uses the separate 9401 Codex worktree. Its
`tools/solaris-rescue/` and trial-33 notes are untracked there. Therefore
neither a GitHub main comparison nor inspection of this working tree alone
recovers all of the accepted hsimd changes. No synchronization is implied.

## Network implementations

SNET source is `drivers/snet/snet.c` and `snet_hcall.s`; the QEMU frontend is
`qemu-overlay/hw/net/sun4v_snet.c` in the SNET worktree. It is a GLDv3 MAC
driver using OpenSPARC calls 0xf2/0xf3 and FIFO address 0xfff0c2c050, with
ordinary QEMU networking. It does not carry packets through hsimd.

Woodpecker [repo 6, pipeline 3](http://biggie.lynx-eagle.ts.net:8110/repos/6/pipeline/3)
is successful at `ae87cdf07025e62d3708ebee97653afba976242d`.
`build-snet-on-biggie` exited 0; the pipeline lasted 1m53s. This is QEMU-build
and guest-object compilation evidence. Final illumos module linking,
load/attach, ARP/ICMP and sustained TCP remain unproved in the reviewed task
and branch documentation. The later `29c3db6` commit records that status.

Ethernet-over-disk/DLPI and PPP/guest-chand are separate, older network
transports. The 6.1x coalescing result in this task concerns guest-chand on
TedDeck's channel carrier. It says nothing about SNET performance.

## hsimd variants and accepted changes

| Variant | Evidence |
| --- | --- |
| Old `third_party/hsimd` | Vendored synchronous implementation; insufficient as the baseline for newer builds |
| Upstream `0.0.6_aio2` | Biggie `~/devel/masa-sun4v/guest-util/hsimd`, clean commit `128e7528a9da448eb0c0f78c41032f239b5bb613`; source SHA-256 `b7af2cba8ba12c8ecd5cd6355d8cffb3b18bb1cc9ae06feb7f076f596fbe1167` |
| Our OI VERSION_1/multiunit build | 28,808 bytes; SHA-256 `40201a31bb6b721975ae8ced12f22b1e6f620c8863d352ba411472e464a9a1a0`; matches the profiled TedDeck module |
| Our Solaris 11.4 `0.0.6_s114_mapin1` | 28,344 bytes; SHA-256 `13ff1a9c2a6cb1893b777d95ca01b97b763c383e31076bef165ea1187ffa7eb3`; live-loaded and filesystem hashes passed in trial 33 |

The OI build was staged at Biggie
`~/devel/masa-sun4v/ci/runs/term4code-02/staging/payload-root/platform/sun4v/kernel/drv/sparcv9/hsimd`.

The Solaris fix disables `CONFIG_HAT_BUG`. Its page-list path read illumos
`struct page` fields on Oracle Solaris; using the existing `bp_mapin()`
mapping and `va_to_pa()` instead repaired file-content reads. The reviewed
task verified `.volsetid` and all three installer archive hashes after the
live module swap. Raw multiunit access alone had passed before this fix,
but filesystem content had not.

Build artifacts and accepted module on Biggie:
`~/vms/solaris11-installer-20260904/cpu-id-trials/033-s114-combined-range-flush/hsimd-mapin-candidate/`.
This contains source, `build.sh`, objects and `hsimd.accepted`. Build used
GCC 13 SPARC cross-compilation against pinned headers, then Solaris-native
`ld -r -dy -N misc/cmlb`. Candidate source SHA-256:
`100d3b3377c0ca833cd8d844e2b2366c9f373ceac46d8dce919c6814d0f46ed7`.

Patch and full test record in the 9401 worktree:
`tools/solaris-rescue/hsimd-s114-mapin.patch` and
`notes/SOLARIS11-TRIAL33-COMBINED-FIXES-2026-09-04.md`.
The upstream snapshot under `captures/hsimd-source-review-20260905/` in this
checkout is reference material, not a replacement for that patched source.

## Woodpecker inventory

[Biggie dashboard](http://biggie.lynx-eagle.ts.net:8110/repos), observed
2026-09-05. Status describes the latest listed build at inspection time.

| CI ID | GitHub repo, under ryancnelson | Observed status |
| --- | --- | --- |
| 1 | `tribblix-woodpecker` | failure; installer-contract test |
| 2 | `niagara-qemu-solaris-lab` | running; pipeline 112, `codex/cross-arch-golden-volume`, `89baac8fa1` |
| 3 | `gcc` | success; compiler build |
| 4 | `HTCommander` | failure; unrelated radio project |
| 5 | `new-delegate` | success; separate project |
| 6 | `qemu-sun4v-illumos--new-drivers` | success; SNET pipeline 3 |
| 7 | `im-an-old-sun-box--mcp` | killed; console/pipeline guest discovery |

The base `qemu-sun4v-illumos` repo was not a separate entry in this dashboard.
Lab repo 2 also shows active development on native boot performance/profiling,
lookup counters, the QEMU contract and dual-architecture golden volumes.
Its pipeline history is independent of the SNET repo.

CI evidence was read through the authenticated browser. A read-only API
fallback used the generic HTTP wrapper with the documented guardrail bypass
because no Woodpecker service wrapper exists; it returned 401. No credentials
were extracted and no CI mutation was attempted.
