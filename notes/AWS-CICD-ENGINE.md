# AWS CI/CD engine

This is the canonical host-level runbook and design contract for the AWS
Niagara development workhorse. It distinguishes durable data from live process
state and records what an ordinary EC2 reboot does today, before the proposed
boot orchestrator exists.

Audit time: 2026-08-27 06:06 UTC. Revalidate mutable identities and service
state before operating the host.

## Host identity

| Property | Audited value |
| --- | --- |
| EC2 instance | `i-0f3608bc9d120b043` |
| Type | `m8azn.large` |
| Region / AZ | `us-east-2` / `us-east-2b` |
| Private IPv4 | `10.215.10.217` |
| Public IPv4 at audit | `3.16.55.40` |
| Tailscale IPv4 | `100.71.153.107` |
| Tailscale DNS | `ip-10-215-10-217.lynx-eagle.ts.net` |
| OS | Ubuntu 24.04.4 LTS, x86-64 |
| Root storage | 80 GB EBS, ext4, about 24 GB free at audit |

The public address is an observation, not the management contract. Use
Tailscale or the private VPC address and re-resolve mutable addressing after an
instance stop/start. The EBS volume is persistent across an ordinary guest or
EC2 reboot; tmux sessions, `/run`, `/tmp`, Unix sockets, forwarded agents, and
processes are not.

## Current reboot answer

The host is **data-persistent but not yet able to restart the complete working
environment automatically**. A reboot preserves repositories, run evidence,
firmware, base images, overlays, and logs on the root EBS volume. It stops QEMU,
tmux, channel bridges, PPP, tunnels, sockets, and their live connections. Those
programs must then be started again in the correct order; today there is no
single boot service that does that.

### Returns automatically

| Component | Evidence | Qualification |
| --- | --- | --- |
| Root, `/srv`, `/var/lib/niagara-ci`, `/home`, `/root` | All are on `/dev/root`, EBS volume `vol05cda186b8fcee30c` | Files survive; open processes do not |
| Tailscale | `tailscaled.service` enabled and active | Stable management path after network convergence |
| Inbound SSH | `ssh.socket` enabled; `ssh.service` active | Do not rely on `ssh.service`'s disabled unit-file state alone |
| Tinyproxy | `tinyproxy.service` enabled and active | TCP proxy only; channel path has a separate defect |
| Tinyproxy Unix listener | `tinyproxy-unix.socket` enabled and active | Socket under `/run` is recreated by systemd |
| QEMU host preparation | `qemu-kvm.service` and `run-qemu.mount` enabled | Does not launch a SPARC VM |

### Does not return automatically

- QEMU VMs;
- tmux sessions and their console/monitor panes;
- run-scoped console, monitor, and `niag0.sock` through `niag7.sock` sockets;
- unit-101 polling bridges;
- PPP daemons, addresses, routes, forwarding, and NAT;
- the host BBS and Biggie LiteLLM SSH tunnel;
- Ryan's forwarded SSH agent and its `SSH_AUTH_SOCK`;
- pane layout and scrollback not copied to a file; and
- services created with `systemd-run` without persistent unit files.

At 2026-08-27 06:10 UTC Ryan reported QEMU shut down. Host readback found no
`qemu-system-sparc` or `qemu-system-sparc64` process and Ubuntu's `sparc9` tmux
server was gone. Revalidate immediately before reboot; this is evidence, not a
permanent invariant.

### Known boot-time defects

1. `niagara-channel5-tinyproxy.service` is enabled but hard-codes historical
   run `workstation-ec2-ch8-20260826T210446Z`. Its `niag5.sock` is not created
   at boot, so the unit restart-loops. Disable it or replace it with a run-aware
   dependency chain before calling the host clean.
2. `niagara-channel1-ppp.service`, `niagara-channel4-bbs.service`, and
   `niagara-litellm-biggie-tunnel.service` are transient units under
   `/run/systemd/transient` and disappear at reboot. The tunnel also names a
   session-specific forwarded-agent socket.
3. `niagara-channel1-ppp.service` is already failed. Its one-shot launcher is
   not forgiving when the channel or peer appears late.
4. `cloud-final.service` failed during first boot. The user-data script printed
   completion, but `scripts_user` returned failure after package/service work.
   Cloud-init is not a proven recovery orchestrator.
5. No enabled unit selects a current bundle, creates a run, initializes unit
   101, starts eight bridges, launches QEMU with durable console capture, or
   evaluates acceptance gates.

## Durable artifact inventory

```text
/root/qemu-sun4v-illumos/             project source and runbooks
/srv/niagara/artifacts/               immutable/published inputs
/var/lib/niagara-ci/experiments/      per-run overlays, logs, sockets, tools
/home/ubuntu/niagara-ci/              Solaris 9/QEMU development work
```

`/srv/niagara/artifacts/workstation-candidate-20260826/` is a ready-last
published raw workstation candidate. It contains `MANIFEST`, `SHA256SUMS`,
source-before/source-after evidence, wire-byte/timing evidence, `qemu-img`
inspection results, a zero-length `READY`, and the 64,424,509,440-byte sparse
unit-104 image. Do not perform another whole-logical-image checksum merely for
an operational inventory; use recorded evidence unless a gate requires it.

`openindiana-workstation-rc-20260826T235031Z/` contains an 8.3 GB standalone
qcow2 and an incomplete `.zst.partial`. A partial transfer is not `READY` and
must never be selected. The hidden `.rsync-abandoned` directory preserves the
stopped logical-stream rsync attempt; it is failure evidence, not a release.

## Safe host reboot procedure today

A host reboot affects every VM. Obtain explicit operator authority and
inventory again immediately before it.

1. Run `git pull --ff-only` in the canonical checkout and confirm it is clean.
   Commit and push new evidence first.
2. Inventory every QEMU PID with complete argv, block devices, sockets, run
   directory, owner, and protection status. Never trust stale PID files.
3. Gracefully stop every writable guest that matters and wait for QEMU exit.
   If impossible, record attempts and classify disks as crash-consistent.
4. Never signal Murayama Niagara QEMU as a synchronization mechanism. The
   recorded SIGUSR2 incident terminated a VM.
5. Confirm no QEMU and no opener of writable VM disks remains. Preserve run
   directories, disks, logs, and failure evidence.
6. Record failed/enabled/transient units, mounts, free space, and Tailscale
   identity.
7. Expect tmux, forwarded agents, tunnels, sockets, bridges, PPP, and transient
   services to disappear.
8. Reboot normally. Do not substitute stop/start, which has different address
   and placement consequences.

## Manual recovery after reboot today

1. Verify EBS mounts, free space, clock, DNS, Tailscale, and SSH.
2. Inspect `systemctl --failed`; do not blindly restart Niagara units.
3. Disable or mask the stale historical channel-5 unit before it can hide a
   broken dependency chain behind retries.
4. Establish a fresh authorized agent with `agent-bootstrap`; never bake a
   forwarded socket path into a persistent unit.
5. Pull the project and select an exact `READY` artifact by manifest, not mtime.
6. Create a new timestamped run and fresh overlay. Never reuse an old writable
   overlay as if it were a fresh CI run.
7. Verify QEMU, firmware, base hash, virtual size, cluster size, and backing
   chain. Use one vCPU until the separate SMP card passes.
8. Seed a fresh unit-101 mailbox and eight sockets. The next trial should use
   explicitly sized tmpfs, fail closed without capacity, and record wall time.
9. Start console capture before QEMU and display it in Ryan's named tmux pane.
10. Start optional BBS/proxy/LLM edges in degraded mode; never block boot.
11. Start PPP with bounded wait/retry after channels exist, then scoped NAT.
12. Run the chosen acceptance profile and publish evidence. Ask Ryan before
    declaring a semantically progressing boot failed.

## Target boot-replay architecture

The target is deterministic reconstruction, not restarting yesterday's PIDs:

```text
host admission
  -> select manifest whose READY marker was published last
  -> verify metadata and required hashes
  -> create timestamped run and qcow2 overlay
  -> create/seed tmpfs unit-101 mailbox
  -> start eight bridges and durable console capture
  -> launch one-vCPU QEMU
  -> observe boot acceptance
  -> start/retry optional PPP, BBS, proxy and LLM edges
  -> emit versioned milestone evidence
```

Recommended persistent units:

- `niagara-host-preflight.service`: disk, memory, tools, network, stale-QEMU,
  artifact-manifest, and secret-reference admission;
- `niagara-run@.target`: owns a named run without global historical paths;
- `niagara-channels@.service`: initializes tmpfs unit 101 and eight bridges;
- `niagara-qemu@.service`: launches only after inputs and capture are ready;
- `niagara-ppp@.service`: exact peers, scoped NAT, bounded wait/retry;
- `niagara-bbs@.service`: optional and healthy without an LLM;
- `niagara-litellm-tunnel@.service`: optional and credential-helper based; and
- `niagara-acceptance@.service`: records gates without owning VM lifecycle.

Units consume a validated run manifest. They must not hard-code a dated run.

## Portable artifact and transfer contract

Qcow2 is the cross-provider delta contract:

1. A standalone base is hash-addressed, read-only, and has no backing file.
2. A run uses an overlay only when the exact base hash matches.
3. Manifests record base hash, virtual size, cluster size, backing format, and
   complete chain.
4. Promotion flattens to a new standalone qcow2, runs `qemu-img check`, hashes
   the closed file, makes it read-only, writes evidence, and publishes `READY`
   last.
5. Transfer only the overlay when the receiver proves the exact base hash;
   otherwise transfer the promoted standalone qcow2.

ZFS send is an optional same-provider cache transport, not the portability
contract. With project-specific ZFS datasets, use immutable hashed snapshots,
incremental `zfs send -i`, resumable receives, and cheap per-run clones.

For ext4/EBS use documented sparse-extent or standalone-qcow2 transport. If
rsync is necessary, seed the destination and use in-place, partial/resumable,
sparse transfer without whole-file mode. Never spend hours transmitting a
60 GiB logical stream of holes. Measure wire bytes and wall time, stage under a
temporary name, and promote atomically with `READY` last.

## Blue/green operation

- `current-blue` and `current-green` identify immutable accepted bases, never
  live writable disks.
- Smoke the inactive color in three identical-artifact QEMU runs. Record wall
  time, host CPU time, semantic milestones, and all artifact hashes.
- Benchmark the identical artifact on Exabyte and AWS with one-vCPU topology.
  A subjective “snappy” boot remains a hypothesis until measured.
- Promote only after all required runs pass; update selectors atomically and
  retain the previous color for rollback.
- Never derive a release from a live Biggie disk or unexplained EC2 overlay.
  Today's lineage gap came from an installed-root image lacking immutable
  source-snapshot provenance.

## Security and evidence

- Secret values belong in Doppler or another approved store. Repositories,
  manifests, wiki pages, units, process listings, and logs name references only.
- Do not put GitHub, Atlassian, LLM, or AWS tokens in units or shell history.
- Prefer Tailscale SSH and narrowly scoped service identities.
- Persistent tunnels use a dedicated credential helper, not Ryan's interactive
  forwarded agent.
- Every run records input hashes, QEMU argv, units, read-only flags, socket
  paths, timestamps, wall/CPU time, wire bytes, outcome, and root cause.
- Preserve failed runs and disks until explicitly retired.

## Definition of reboot-safe

Do not call the engine reboot-safe until a controlled host reboot proves:

1. EBS, Tailscale, SSH, and checkout health;
2. no stale dated unit restart loop;
3. selection of only a complete `READY` manifest;
4. a fresh overlay and initialized tmpfs unit 101;
5. eight bridges before guest channel services;
6. pinned one-vCPU QEMU and durable console capture;
7. unattended required guest login/multiuser milestone;
8. PPP late-endpoint tolerance, scoped NAT, and connectivity;
9. BBS/proxy success or clean degradation;
10. storage, channel, compiler, milestone, and lineage evidence; and
11. the same result on a second reboot without warm-state dependence.

## Related evidence

- Nelson Wiki: `https://nelson-dot-dev.atlassian.net/wiki/spaces/OPERATIONS/pages/139984897/AWS+CI+CD+Engine`
- `notes/EC2-WORKSTATION-CHANNEL-RUN-20260826.md`
- `notes/OPENINDIANA-WORKSTATION-CANDIDATE-20260826.md`
- `notes/WORKSTATION-COLD-REBOOT-ACCEPTANCE.md`
- `notes/BIGGIE-EXABYTE-ZFS-REPLICATION.md`
- `notes/RC-TRIAGE-INTERVIEW-MODEL.md`
- `what-is-this-disk-lunacy-sir.md`
- `tools/ci/README.md`
- GitHub Projects #2, **Niagara sun4v — Engineering Kanban**
