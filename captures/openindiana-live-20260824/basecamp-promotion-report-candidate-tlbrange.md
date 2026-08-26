# Basecamp Candidate Promotion Report — tlb-range Cold-Boot Replay (Second Full Green Run)
Generated: 2026-08-25T12:3X:XXZ (evidence-only; no guest/host state mutated to produce this report)
Author: assistant, evidence-only compilation for Aggie adversarial completeness review
Companion to: `basecamp-promotion-report-retry13.md` (baseline binary, same document format)

## 1. Identity / provenance

| Field | Value |
|---|---|
| Script SHA (deployed, Aggie-approved) | `47fdad4dd03a908fc4e2b7bbadfb6537bca10b55cc918714dc07a3fd158eb865` |
| QEMU binary under test (candidate) | `/home/niagara/niag-proj/qemu/build/qemu-system-sparc64.tlb-range` |
| QEMU_SHA (candidate) | `bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b` |
| QEMU binary (Retry #13 baseline, for comparison) | `qemu-system-sparc64.baseline-11aa0b1`, SHA `7073119a7c2c15527cd93a315ccce30bafacb537228e049eafb4118b46b0a053` |
| Base commit both binaries share | `11aa0b1ff115b86160c4d37e7c37e6a6b13b77ea` (QEMU v8.2.2); candidate differs ONLY by `patches/0003-sparc-tlb-range-flush.patch` to `target/sparc/ldst_helper.c` — independently proven via object-build-timestamp audit in the prior turn (both binaries share the identical, never-recompiled `hw_sparc64_niagara.c.o`) |
| RUNDIR | `/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T122604Z` |
| Rehearsal subnet | 10.0.7.1 (host) <-> 10.0.7.15 (guest) — distinct from primary (10.0.5.x) and Retry #13 (10.0.6.x, paused/parked) |
| SRC_ISO_SHA / ARC_SHA / PAYLOAD_SHA | identical to Retry #13 (same pinned inputs, only the QEMU binary and subnet changed) |

## 2. Manifest outcome (verbatim)

```
STATUS=PASS
RC=0
START_UTC=2026-08-25T12:26:04Z
END_UTC=2026-08-25T12:28:57Z
ELAPSED_S=173
LAST_STEP=REPLAY PASSED
GATES_REACHED=27  (GATE_0 through GATE_26, identical gate list to Retry #13 except GATE_20's subnet text)
NAT_RULE_ADDED=1
NFS_ACL_ADDED=1
```

## 3. Process / PID inventory (MEASURED — confirmed alive via `ps` at report time)

| Role | PID | PPID | Elapsed (at report time) | STAT | Exact argv/cmd |
|---|---|---|---|---|---|
| OWNER_PID | 771678 | 1 | 05:03 | S | `bash .../qemu-owner.sh <RUNDIR> -- <qemu argv>` |
| QPID (candidate QEMU worker) | 771681 | 771678 | 05:03 | Ssl | `qemu-system-sparc64.tlb-range -M niagara -L .../base-1gib -m 1024 -nographic -monitor unix:.../monitor.sock,server=on,wait=off -serial unix:.../serial.sock,server=on,wait=off -drive if=pflash,file=.../basecamp-r0-rehearsal-20260825T122604Z.iso,format=raw` |
| BRIDGE_PID | 771925 | 1 | 02:36 | S | `python3 .../host-chan.py bridge 0 <RUNDIR>/niag0.sock` |
| PPPD_LAUNCH_PID | 771974 | 1 | 02:24 | S | `sudo -n setsid nohup socat UNIX-CONNECT:<RUNDIR>/niag0.sock EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff debug logfile <RUNDIR>/pppd-debug.log 10.0.7.1:10.0.7.15 nodetach',nofork` |
| PPPD_PID | 771976 | 771974 | 02:24 | Ss | same pppd argv |
| PPPD_PEER_PID | 771977 | 771976 | 02:24 | S | same pppd argv (innermost fork) |

## 4. Socket / network / export inventory (MEASURED, current live state, all three subnets coexisting)

**Sockets** (RUNDIR, `ls -la`):
- `monitor.sock` — `srwxr-xr-x`, created 12:26
- `serial.sock` — `srwxr-xr-x`, created 12:26
- `niag0.sock` — `srw-rw-rw-`, created 12:28

**NAT (iptables -t nat -S POSTROUTING), current live table, all three concurrent entries:**
```
-A POSTROUTING -s 10.0.5.15/32 -o enp0s1 -j MASQUERADE   <- primary R0, untouched
-A POSTROUTING -s 10.0.6.15/32 -o enp0s1 -j MASQUERADE   <- Retry #13 baseline, paused/parked, untouched
-A POSTROUTING -s 10.0.7.15/32 -o enp0s1 -j MASQUERADE   <- candidate, this run
```

**NFS export (exportfs -s), current live table, all three coexisting client ACLs on the same base directory:**
```
/home/niagara/nfs-oi  10.0.7.15(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
/home/niagara/nfs-oi  10.0.6.15(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
/home/niagara/nfs-oi  10.0.5.15/32(sync,wdelay,hide,no_subtree_check,sec=sys,rw,insecure,no_root_squash,no_all_squash)
```

**Invariant checks (MEASURED at report time):**
- Primary R0 (PID 709698): continuously alive throughout, NAT/export entries unchanged in content/position.
- Retry #13 (PID 761173): confirmed alive, `STAT=Ssl` (paused, sleeping) — paused via its own monitor socket (`stop` -> `info status` -> `VM status: paused`) prior to the candidate launch, per the load-parity design (primary + one active test at a time). Its own NAT/export/sockets/PIDs unchanged.

## 5. Milestone timestamps and elapsed seconds — candidate (MEASURED, verbatim manifest.env)

| Milestone | UTC timestamp | Elapsed (s) from START_UTC |
|---|---|---|
| START | 2026-08-25T12:26:04Z | 0 |
| IMAGE_BUILT | 2026-08-25T12:26:06Z | 2 |
| QEMU_STARTED | 2026-08-25T12:26:08Z | 4 |
| MAINTENANCE_SHELL | 2026-08-25T12:28:17Z | 133 |
| DTRACE | 2026-08-25T12:28:28Z | 144 |
| CHANNEL_ECHO | 2026-08-25T12:28:41Z | 157 |
| PPP_LINK | 2026-08-25T12:28:49Z | 165 |
| NFS | 2026-08-25T12:28:57Z | 173 |
| FINAL_PASS | 2026-08-25T12:28:57Z | 173 |
| END | 2026-08-25T12:28:57Z | 173 (= ELAPSED_S) |

## 6. Milestone comparison: candidate vs. Retry #13 baseline (both MEASURED, single sample each)

| Milestone | Retry #13 baseline (s) | Candidate tlb-range (s) | Delta (s) | Delta (%) |
|---|---|---|---|---|
| IMAGE_BUILT | 1 | 2 | +1 | n/a (sub-component, noise-level) |
| QEMU_STARTED | 3 | 4 | +1 | n/a (sub-component, noise-level) |
| MAINTENANCE_SHELL | 160 | 133 | **-27** | **-16.9%** |
| DTRACE | 174 | 144 | -30 | -17.2% |
| CHANNEL_ECHO | 188 | 157 | -31 | -16.5% |
| PPP_LINK | 198 | 165 | -33 | -16.7% |
| NFS / FINAL_PASS (total) | 206 | 173 | **-33** | **-16.0%** |

The largest absolute reduction (-27s) occurs in the MAINTENANCE_SHELL phase (boot to login), the phase this session's provenance audit already flagged as the dominant boot-time component and most plausibly sensitive to per-page TLB-flush overhead during large-TTE-heavy early boot/ZFS activity. All downstream phases (DTRACE onward) show consistent, non-widening deltas (-30 to -33s), consistent with the improvement being concentrated in the boot phase and simply carried forward additively through the rest of the run, not compounding further.

## 7. SINGLE-SAMPLE CAVEAT (explicit, per evidence discipline)

**This is one run of each binary.** No repeated baseline runs, no repeated candidate runs. The consistent ~16-17% reduction across every downstream milestone is suggestive and directionally consistent with the patch's stated intent, but:
- No variance/standard-deviation estimate exists for either binary — a single outlier run (host scheduling jitter, concurrent I/O, thermal/CPU throttling, etc.) cannot be distinguished from a genuine, reproducible effect with n=1 per arm.
- Host load context differs slightly between the two runs: at baseline (Retry #13) time, only primary R0 was concurrently running; at candidate time, Retry #13 was PAUSED (not running) alongside primary — meaning the candidate run actually had a MARGINALLY LOWER concurrent host load than the baseline run did (primary + 0 active others, vs. baseline's primary + 0 active others also, since Retry #13 didn't exist yet during its own run — both runs in fact had equivalent host load: primary + 1 active rehearsal each). Stated for completeness; no confound identified from this angle.
- **A defensible before/after claim requires multiple repeated runs of both binaries** (e.g. N=3 or more each) with the same subnet/pinned-input methodology, computing mean and spread, before promoting this as a validated performance characteristic rather than a single encouraging data point.

## 8. PPP negotiation evidence (MEASURED — verbatim pppd-debug.log, candidate run, no truncation)

```
using channel 19613
Using interface ppp1
Connect: ppp1 <--> /dev/pts/8
sent [LCP ConfReq id=0x1 <magic 0xf3ea5de0> <pcomp> <accomp>]
rcvd [LCP ConfReq id=0xb1 <magic 0x8e605e57> <pcomp> <accomp>]
sent [LCP ConfAck id=0xb1 <magic 0x8e605e57> <pcomp> <accomp>]
sent [LCP ConfReq id=0x1 <magic 0xf3ea5de0> <pcomp> <accomp>]
rcvd [LCP ConfAck id=0x1 <magic 0xf3ea5de0> <pcomp> <accomp>]
sent [LCP EchoReq id=0x0 magic=0xf3ea5de0]
sent [IPCP ConfReq id=0x1 <addr 10.0.7.1>]
sent [IPV6CP ConfReq id=0x1 <addr fe80::85a4:847a:d31b:0351>]
rcvd [LCP Ident id=0xb2 magic=0x8e605e57 "ppp-2.4.0b1 (Sun Microsystems, Inc.)"]
rcvd [IPCP ConfReq id=0xe6 <addr 10.0.7.15>]
sent [IPCP ConfAck id=0xe6 <addr 10.0.7.15>]
rcvd [LCP EchoRep id=0x0 magic=0x8e605e57]
rcvd [LCP ProtRej id=0xb3 80 57 01 01 00 0e 01 0a 85 a4 84 7a d3 1b 03 51]
Protocol-Reject for 'IPv6 Control Protocol' (0x8057) received
rcvd [IPCP ConfAck id=0x1 <addr 10.0.7.1>]
Script /etc/ppp/ip-pre-up started (pid 771984)
Script /etc/ppp/ip-pre-up finished (pid 771984), status = 0x0
local  IP address 10.0.7.1
remote IP address 10.0.7.15
Script /etc/ppp/ip-up started (pid 771991)
Script /etc/ppp/ip-up finished (pid 771991), status = 0x0
```
Clean negotiation, no hangup, same shape as Retry #13's baseline negotiation (magic numbers and PIDs differ, as expected for an independent run).

## 9. Teardown path (not executed — reference only)

```
/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T122604Z/teardown.sh
```
MEASURED: `-rwxr-xr-x`, 1096 bytes, written 12:28. NOT invoked as part of this report.

## 10. Explicit non-actions this turn
No teardown, resume, reboot, or deploy performed. Retry #13 remains paused (not resumed). No skill/memory/profile/global file writes.
