# EC2 OpenIndiana workstation channel run — 2026-08-26

This note records the acceptance contract, durable evidence, and follow-up
decisions from run `workstation-ec2-ch8-20260826T210446Z`.  Run-local logs and
images remain under `/var/lib/niagara-ci/experiments/` on the EC2 worker; paths
and PIDs are historical evidence, not stable interfaces.

## Launch contract and result

The run used the known-good QEMU SHA-256
`ea9348f2565befef00b7f8628489be01bde5799df842c88cdfe70a25664bba3c`,
one vCPU, 3072 MiB, immutable raw workstation base SHA-256
`964d10a2f0bba82bffb940db4e30c7fb111f27b6acd3400d0da6fe826ecc3fbd`,
and a per-run qcow2 overlay.  Units 100, 101, 103, and 104 retained their
documented roles.  The first 8192 MiB launch failed before guest execution
because the EC2 host could not allocate guest RAM; the 3072 MiB retry matched
the memory exposed by the current firmware.

QEMU was launched in Ryan's provided tmux pane with kmdb enabled and the exact
installed-root command:

```text
boot /virtual-devices@100/disk@4:a -k -v
```

The run reached the OpenIndiana login prompt without guest input after that
boot command.  Durable evidence is `logs/unattended-login-pass.txt` in the run
directory.  The boot felt materially faster on this EC2 CPU than prior Biggie
runs, but this session did not execute a controlled three-run benchmark; do
not turn that observation into a performance number.

The initial QEMU topology requested eight host/guest channel endpoints over
run-local unit 101.  `start-channels.sh` initialized the mailbox before
starting polling bridges for channels 0 through 7, all at host byte 327680,
and exposed `sockets/niag0.sock` through `niag7.sock`.  Logs show actual client
connections on channels 1 through 5 and 7.  Mere socket existence is not a
byte-transport acceptance result for the idle channels.

## Guest experiments and accepted conclusions

- The console can receive input during early polling paths, then stops
  receiving it when illumos switches to interrupt-driven `qcn`.  This is a
  known missing QEMU Niagara UART/IRQ path, not an SMF timing mystery.  Booting
  single-user or otherwise retaining the polling fallback is a useful recovery
  method, but the real fix requires coherent QEMU interrupt wiring plus a
  matching firmware Machine Description rebuild and guest-visible validation.
- Channels 2 and 3 were exercised as additional interactive paths.  A normal
  root getty was obstructed by login/utmpx policy, so the demonstrated fallback
  was a respawnable `bash -l` endpoint rather than proof of a conventional
  authenticated getty.  Future acceptance must name which behavior it expects.
- A host HTTP proxy path was prototyped by adapting a TCP listener to a Unix
  socket and then to a channel socket.  The resulting multi-hop
  `guest channel -> host-chan -> socat -> TCP proxy` works as a transport
  pattern but needs a single socket-native supervisor before promotion.
- The host BBS was attached to a spare channel after its original role was
  displaced.  Its local menu path worked; the Vibeproxy/LiteLLM oracle path did
  not pass and remains optional.  An absent LLM endpoint must degrade the BBS,
  never block guest boot.
- PPP was started over its channel and the guest link came up, but host NAT was
  not initially present.  Static Solaris name-service ordering was repaired
  with `files dns`.  The PPP-up process needs bounded wait/retry behavior for a
  late host endpoint rather than one-shot startup.
- Tribblix GCC payloads were unpacked without `pkgadd`; the guest demonstrated
  a working compiler.  The exact durable compiler/NFS acceptance is recorded
  separately in `notes/BIGGIE-TERM4CODE-OPENINDIANA-RUN.md`.
- ZFS checkpoints were taken during the guest work.  A snapshot taken while a
  VM is live is a rollback point only when its guest-sync and dataset lineage
  are recorded; it is not automatically a promoted standalone artifact.

The final shutdown could not be made graceful through `system_powerdown`,
Stop-A, serial break, or NMI.  QEMU was paused and quit through HMP.  The root
overlay passed `qemu-img`'s corruption check and no QEMU or root-disk opener
remained, but the filesystem state is only crash-consistent.  No 60 GiB
whole-image checksum was performed.

## Decisions for the next boot

1. Continue with one vCPU.  Treat sun4v SMP as an independent future lane;
   neither `-smp 4` nor the existing 2c8t MD proves guest-visible SMP.
2. Keep an immutable, hash-addressed standalone qcow2 base and create a
   per-run overlay.  Promotion flattens to a new standalone qcow2, runs
   `qemu-img check`, hashes it, makes it read-only, writes complete lineage,
   and publishes `READY` last.
3. Replace the disposable unit-101 mailbox backing with a file on host tmpfs
   (for example `/dev/shm`), seeded by the deterministic mailbox initializer
   before QEMU starts.  It remains an ordinary QEMU file-backed drive; only
   its host filesystem is RAM-backed.  Verify capacity before launch, never
   fall back silently to persistent disk, and record init/transport wall time.
4. Provision eight channels before boot.  Preserve the intended roles—PPP,
   two interactive endpoints, BBS, proxy, and spare capacity—without making
   optional host services guest boot dependencies.
5. Boot in the exact tmux pane Ryan provides.  Observe the baseline before
   mutation, retain kmdb access, and ask Ryan before declaring a slow boot a
   failure.
6. Re-test SMF persistence, PPP late-host retry, channel 2/3 endpoint
   semantics, BBS degraded mode, and direct byte transport on every provisioned
   channel.
7. Do not use IPS/package tools during this recovery lane until the separately
   recorded networking/package crash boundary is cleared.

