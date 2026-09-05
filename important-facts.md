# Important facts

Last verified: 2026-09-05.

Read this before rediscovering build environments, VM locations, or access
methods. Update it during work whenever an important fact is established or
changes. Replace stale statements, date live observations, and link detailed
evidence. Keep historical locations distinct from currently verified ones.

## Repository and driver ownership: check this first

This project spans separate repositories and branches. This checkout alone
does not contain all current driver work.

- `ryancnelson/qemu-sun4v-illumos`: project publication/base repository.
- `ryancnelson/qemu-sun4v-illumos--new-drivers`: native SNET work on
  `codex/snet-driver`, with its own [Woodpecker repo 6](http://biggie.lynx-eagle.ts.net:8110/repos/6).
  Local checkout: `~/devel/qemu-sun4v-illumos--new-drivers`; existing branch
  worktree: `snet-driver-worktree/` under this repo. Use that repo's pipeline
  for SNET work, as Ryan directed in the reviewed task.
- `ryancnelson/niagara-qemu-solaris-lab`: private appliance, boot and release
  work, [Woodpecker repo 2](http://biggie.lynx-eagle.ts.net:8110/repos/2).
  This checkout calls it `private-github`; its `origin` is the Biggie Gitea repo.

On 2026-09-05 this integration advanced private new-drivers main to `ae961b0`,
private lab main to `f7bc8e8`, and internal Gitea main to `0e0431e`.
The public project main remains `fb44736`: publication approval is pending.
Those integration commits require the subsequent SPARC no-FPU build fix below.
Other lab branches and uncommitted work have developed separately; do not
assume synchronization.

### SPARC kernel build regression: do not load the old SNET binary

SNET binary SHA-256
`3f0f5664485bafc41482c93aa708e3f415add3272ffb26bd936d290adeed2c72`
panicked TedDeck during `add_drv snet`. GCC's `-O2` constant copies used `%f8`;
the first offending instruction at `snet_attach+0x7c` exactly matched the trap.
Kernel builds require `-msoft-float`, as confirmed against illumos's
`-xregs=no%float` requirement. Both driver build scripts now enforce it and
scan disassembly. The regression test covers the observed load, FP branches,
FPU status registers, and valid integer `%fp`/flush instructions.
Always scan the final natively linked module too before installation.
TedDeck booted again using its original cached image and preserved volume;
the bad module was moved to `/var/tmp/snet-rejected-20260905/snet-hardfloat`.
No hsimd module was replaced. SNET runtime acceptance remains pending.

SNET is a real QEMU NIC plus illumos GLDv3 MAC driver using hypercalls
`0xf2`/`0xf3` and the SNET FIFO. It bypasses hsimd and disk channels.
[Pipeline 3](http://biggie.lynx-eagle.ts.net:8110/repos/6/pipeline/3)
at `ae87cdf070` passed; it built QEMU and guest objects. The reviewed task
and branch record final module linkage/load/TX-RX tests as still pending.
Today's guest-chand patch applies to the older PPP/disk-channel transport,
not SNET.

We have also edited, built, loaded and tested hsimd: the Solaris 11.4
`0.0.6_s114_mapin1` fix disables the illumos-specific page-list workaround
and uses `bp_mapin()` mappings. Preserve this fix when reviewing that variant.
See [driver/repository map](notes/DRIVER-REPOSITORY-MAP-2026-09-05.md) for
source locations, tested binaries, CI inventory and task evidence.

## Working SPARC compiler: TedDeck guest

The OpenIndiana guest in TedDeck's `openindiana-sparc64` Docker container has
a working native compiler at **`/jack/gcc13`**. It reports
`gcc (Illumos-SPARC-13.4.0-il-1) 13.4.0`.

The wrapper supplies:

- Compiler: `/jack/13/bin/gcc`.
- Assembler directory on PATH: `/jack/localbin`.
- Headers: `-isystem/jack/sysroot/usr/include`.
- Startup objects: `-B/jack/sysroot/usr/lib/sparcv9`.
- Runtime libraries from the running guest, rather than a redirected sysroot.

Use the wrapper. A missing `gcc` on a noninteractive shell's PATH, or missing
`/opt/csw/gcc4/bin/gcc` and `/usr/gcc/13/bin/gcc`, does **not** mean this guest
lacks a compiler.

Verified build command:

```sh
/jack/gcc13 -O2 -Wall -Wextra -o guest-chand guest-chand.c -lsocket -lnsl
```

Baseline and coalescing-candidate builds passed on 2026-09-05 and produced
64-bit SPARCV9 executables. Both are staged in guest directory
`/var/tmp/chand-coalesce-a9c7/`; the running network daemons were not replaced.
Installation background is recorded in commit
`b334a03e1887210d336f194109b9e5c926dc7f62`,
`notes/OPENINDIANA-NATIVE-GCC13-TOOLCHAIN.md` in the snet worktree/history.
The live wrapper also supplies headers, which the initial version of that
historical note did not yet describe.

## TedDeck lab access and channel mapping

Verified guest: `oi-basecamp`, OpenIndiana/illumos `31d3d510d0`, sun4v.
Its private PPP address is `10.0.5.15`. Run this from TedDeck:

```sh
ssh -o ProxyCommand='docker exec -i openindiana-sparc64 socat - TCP:10.0.5.15:22' \
  -i ~/.ssh/id_rsa root@10.0.5.15
```

The lab key is authorized for this work. Keep its contents out of the repo.
Channels 0 and 1 are occupied by the running network/BBS daemons.

| Setting | Verified value |
| --- | --- |
| Guest carrier device | `/dev/rdsk/c1d0s2` |
| Guest channel base block | `640` |
| Host carrier, inside container | `/run/unit100/carrier-unit100.raw` |
| Host channel-region byte offset | `327680` |

A source-built daemon requires `NIAG_CHAN_DEV=/dev/rdsk/c1d0s2` and
`NIAG_CHAN_GUEST_BLK=640`. The source header's Solaris 10 default differs;
the installed guest binary has a patched default. Recheck channel use before
using a spare channel. Do not initialize the entire region under live daemons.

## ec2trib has a running SPARC VM

ec2trib itself is x86 Tribblix m41. Its host `/usr/bin/gcc` targets
`i386-pc-solaris2.11`; that is separate from its emulated guest.

On 2026-09-05, QEMU PID 35294 was running `oi-login-raw` with two CPUs and
3072 MiB RAM. The guest console log showed `oi-basecamp` at a root prompt.

- Run directory: `/tink/runs/niagara-smp-mondo-fix-20260904-04/`.
- Console: `console.sock` and `console.log` in that directory.
- QMP and debugger: `qmp.sock` and `gdb.sock` in that directory.
- Existing tmux session: `niagara-smp-recovery-20260904-01`.

The console's last `gcc` check reported command not found, and `ifconfig -a`
showed only loopback. A compiler inside this particular guest has not been
verified. Do not confuse guests merely because both are named `oi-basecamp`.

## Previous hsimd build environment

AgentsView records the earlier driver build work on **biggie's donor VM**,
using sources at host path **`/export/solaris/hsimd-build`**. The compiler was
confirmed in that session before the module build work. This is a historical
location; its current availability has not been rechecked.

Retrieval evidence: AgentsView session
`codex:01a01c25-31fa-7e31-a982-4425847532df`,
`solaris-sparc and webradiocontrol`, ordinals 3144-3157, 2026-08-21.
Search AgentsView for `hsimd compiled` or `guest-chand gcc` before declaring
the toolchain unavailable. Cross-check recovered paths against the live host.

## I/O findings that affect the next change

### New appliance build (verified September 5, 2026)

Task `01a050c8-366e-7693-afcc-338952e410ca` (`blu debugging arm-qemu-appliance`)
owns the cross-architecture golden-volume build. Its source branch is
`codex/cross-arch-golden-volume`; inspected head was `89baac8`.
The live amd64 build is on `root@ec2cicd`, under
`/tank/niagara-ci/golden-volume/golden-volume-amd64-112`.
Container `golden-amd64-112` passed its build/boot gates and was subsequently
cleaned up by its owning pipeline. Conversation retrieval lagged behind the live build: check live
markers and artifact digests before using an older task summary as status.

Later in this session, run 112 published amd64 with recorded digest
`sha256:4922d58501ffbd369d8e5837efb87e68d241931c5d9aa8f42555963d542004e2`.
The SNET integration build on ec2cicd is isolated under
`/tank/niagara-ci/snet-main-integration-20260905`. Its QEMU build includes
the run-112 source archive, existing SMP patches, and the SNET overlay;
device discovery and the existing range-flush binary check passed.
The derived test image is
`sparc64-qemu-openindiana-20g:snet-main-integration-20260905` (local image
ID `2de7e03af5ad`). It contains the rejected hard-float SNET module above;
do not install that module. Its first two-CPU guest boot timed out before
module installation. Evidence and the failed volume are archived under
`evidence/two-cpu-failed-volume.tar.zst` in the integration directory.
An unchanged run-112 control, `snet-main-control-20260905`, successfully
booted and reached a root shell. Its firmware requires exactly two CPUs.
Runtime network acceptance is still pending; SNET is not a release default.

The new appliance's QEMU still reports `Device 'sun4v-snet' not found`, as
does the current TedDeck VM. SNET needs the matching QEMU device plus the
guest module and a fresh VM launch. Reuse the new frozen guest disk as the
integration base; a fresh OS installation is not inherently required.
Do not alter the active appliance test container or its frozen disk in place.

The September 5 profile found high fixed cost for small hsimd requests;
large raw requests performed well. ZFS already submitted mostly 128 KiB writes.
The measured inner hypercall duration is not async backend-completion latency.

The profiled TedDeck OI driver is `v0.0.6_aio2`, SHA-256
`40201a31bb6b721975ae8ced12f22b1e6f620c8863d352ba411472e464a9a1a0`.
Prior task notes identify it as our VERSION_1/multiunit build staged on Biggie.
It differs from the accepted Solaris 11.4 `s114_mapin1` binary. The old
`third_party/hsimd` source is not the source of truth for either deployed
variant. Establish the matching source, patch and build flags before editing.
The current candidate instead batches guest-chand socket input while waiting
for acknowledgement. Local integrity tests and native compilation pass.
The live channel-2 A/B test improved 3 MiB transfer throughput from 0.208 to
1.27 MiB/s (6.1x), with 509 versus 77 payload writes confirmed by DTrace and
identical payload hashes. This used 6 KiB socket chunks and a controlled
20 ms acknowledgement delay. End-to-end PPP/SSH performance and interactive
latency remain unmeasured for the patch; it is not installed on live channel 0.

See [the coalescing experiment](notes/GUEST-CHAND-COALESCING-2026-09-05.md).
Original DTrace evidence is on TedDeck at
`$HOME/vms/openindiana-io-profile-20260905/`.
