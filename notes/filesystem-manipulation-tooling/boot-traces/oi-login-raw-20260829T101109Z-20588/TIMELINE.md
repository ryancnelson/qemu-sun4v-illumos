# ec2trib raw-unit104 login baseline

Outcome: **PASS — reached `oi-basecamp console login:`**.

This trace is the comparison baseline for later sun4v boots. The run attached
the writable raw file in the outer Tribblix ZFS clone directly as unit104;
it did not use the failed multi-layer unit104 qcow2 lineage.

## Identity

```text
run_id: oi-login-raw-20260829T101109Z-20588
created_utc according to ec2trib: 2026-08-29T10:11:10Z
QEMU PID: 20615
QEMU commit: 049affb20df67162cf58deeaf74d5ad4b83cbdc3
QEMU SHA-256: 05dd8b8e90dd098377e9649a04453362b7401055c0feccb0c5745ffb8df52d98
OpenBoot command: boot /virtual-devices@100/disk@4:a -k -v
inner rpool GUID: 18135893029031842473
pre-boot outer snapshot GUID: 370532935438843004
```

The full artifact paths, unit roles, firmware identity, NVRAM identity, and
exact QEMU arguments are preserved in `manifest.txt` and `qemu-command.sh`.

## Clock basis

Times labeled `ec2trib observed UTC` came from `date -u` in the Tribblix host
monitoring pane. They are first-observed times, not instrumentation at the
exact instant the guest emitted a line. Messages emitted by `svc.startd` use
the guest's local clock and are kept separately. The Codex controller clock
was one calendar day ahead during this run, so its timestamps must not be
mixed with the ec2trib timeline.

## Gate timeline

| ec2trib observed UTC | Elapsed from run creation | Gate | Evidence |
|---|---:|---|---|
| 10:11:10 | 00:00 | Run created | `manifest.txt` |
| before 10:18:09 | — | OpenBoot loaded kernel | `unix`, `genunix`, kmdb, OpenIndiana banner |
| before 10:18:09 | — | unit104 attached | `hsimd4`; slice `a` start 16065, length 125788950 |
| before 10:18:09 | — | ZFS root selected | `root on rpool/ROOT/openindiana fstype zfs` |
| 10:18:09 | 06:59 | Hostname established | `Hostname: oi-basecamp`; outer write delta 19.3 MiB |
| 10:18:49 | 07:39 | Device enumeration active | DTrace, FBT, fasttrap, lofi and other pseudo devices online; 21.9 MiB written |
| 10:18:58 | 07:48 | unit103 attached | `hsimd3 is /virtual-devices@100/disk@3`; 22.8 MiB written |
| 10:19:42 | 08:32 | ZFS dataset mounts complete | `Mounting ZFS filesystems: (8/8)`; 32.1 MiB written |
| 10:19:57 | 08:47 | Login gate | `oi-basecamp console login:` |

The browser operator typed `root` after the login prompt, leaving the frozen
console copy at `Password:`. Codex did not enter a password.

## Known warnings that did not prevent login

```text
hsimd4: add_intr failed err:1
WARNING: svccfg apply /etc/svc/profile/generic.xml failed
```

`svc.startd` reported the known dependency cycle twice, at guest-local times
03:15:31 and 03:16:27. The cycle includes `filesystem/root-minimal`,
`boot-archive`, `filesystem/usr`, `device/local`, `network/varpd`,
`network/physical`, and `identity:node`. Despite it, the boot reached login.

## Frozen trace checksums

These identify the copies captured immediately after the login gate:

```text
a06f7db40d786081848cf977d5a981d77238e879f7fe422132337d0a6f0cf126  console.log
ece36dc7fb577afea65cfef0fc5e50635431239213952ca9c3fd7c9a18e7159f  manifest.txt
3d880f5814987c86105c717c040fbb763820fbfbe3fcddf82a7483282a3ce442  qemu-command.sh
```

The live QEMU continues after this frozen checkpoint. A later copy of its
console log will legitimately have a different size and checksum.

## Post-login checkpoint

`console-through-root-session.log` preserves the later interactive checkpoint
after a successful root login. It records:

- uptime advancing from six to seven minutes;
- `rpool/ROOT/openindiana` mounted read/write at `/`;
- all eight ZFS filesystems mounted, including `/var`, `/export`, and `/rpool`;
- `/opt/niag/bin` containing `guest-chand`, `guest-echocli`,
  `guest-ppp-chan.pl`, `guest-rootpty.sh`, and `socat`;
- `iostat 1` showing 100% system CPU during the sample and long rpool service
  times;
- `svc:/network/inetd-upgrade:default` timing out and being killed, without
  removing the usable root shell.

The post-login checkpoint is 11,221 bytes with SHA-256:

```text
51da2f33283263995a897946e0027e7f81a951876dfc900a00911eda89fa4e88  console-through-root-session.log
```
