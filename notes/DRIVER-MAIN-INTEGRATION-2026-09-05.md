# Driver main integration, September 5

## Verified changes

SNET's existing branch was integrated at `29c3db6`. Commit `dcf9459` fixes
receive callback lifetime, failed-detach behavior and transmit error handling.
TX now sends its header and payload in one hypercall. Independent review found
no blocking issue in these fixes. The module linked natively in the TedDeck
OpenIndiana guest: SHA-256
`3f0f5664485bafc41482c93aa708e3f415add3272ffb26bd936d290adeed2c72`.

Commit `dce58b0` recovers the VERSION_1/multiunit hsimd sources and the accepted
Solaris 11.4 mapin patch, with explicit build variants. Both variants compile;
the patched Solaris source exactly matches the historical accepted hash.
Commit `753aa6a` includes the reviewed channel coalescing change and its native
I/O evidence. The local actual-daemon regression and six protocol tests pass.

Woodpecker driver repository 6, pipeline 4, reports success for `753aa6a`:
<http://biggie.lynx-eagle.ts.net:8110/repos/6/pipeline/4/1>.

## New amd64 appliance

The appliance task `01a050c8-366e-7693-afcc-338952e410ca` produced amd64
golden-volume run 112 on ec2cicd. Its published digest is
`sha256:4922d58501ffbd369d8e5837efb87e68d241931c5d9aa8f42555963d542004e2`.
That image does not contain SNET. Its frozen guest payload can be reused;
adding SNET requires the matching QEMU device and a fresh VM launch.

An isolated build under `/tank/niagara-ci/snet-main-integration-20260905`
adds SNET to run 112's exact QEMU archive after the existing SMP patches.
QEMU compiles, recognizes `sun4v-snet`, and passes the range-flush binary
check. Derived local image `2de7e03af5ad` contains this QEMU and the native
guest module at `/opt/snet/snet`.

## Runtime test remains incomplete

The fresh two-CPU test entered OpenIndiana, then stopped advancing during
startup after the known SMF profile/dependency warnings. The bounded login
test expired, and a separate console probe got no response. Both CPUs were
observed in `cpu_halt+0xcc`. The SNET guest module had not been loaded, so
this is not evidence of a driver attach failure or a successful network test.

The failed container was preserved as
`snet-main-integration-20260905-two-cpu-failed`; its disk is not a cleanly
shut-down golden image. Console/register evidence is in the build's
`evidence/` directory. A fresh one-CPU test uses container
`snet-main-integration-20260905-one-cpu` and its own volume.
Attach, ARP, ICMP and bidirectional TCP integrity remain release gates.

## Repository scope

GitHub verified `qemu-sun4v-illumos--new-drivers` and
`niagara-qemu-solaris-lab` as private, and `qemu-sun4v-illumos` as public.
The first private CI-branch push was rejected by automatic approval review;
after verifying its destination and visibility, the same push was approved
and succeeded. No public push had occurred at the time of this note.

Local private-main and Gitea-main merge candidates preserve their original
unrelated files and contain only the 33 driver-related changed paths. Main
publication and appliance-default activation are separate remaining steps.
