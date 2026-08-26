# Basecamp Promotion Report — Retry #13 (First Full Green Cold-Boot Replay)
Generated: 2026-08-25T12:0X:XXZ (evidence-only; no guest/host state mutated to produce this report)
Author: assistant, evidence-only compilation for Aggie adversarial completeness review

## 1. Identity / provenance

| Field | Value |
|---|---|
| Script SHA (deployed, Aggie-approved) | `d4aacd708a859a61ad2854e2c829bfdd12d092516eb3d6019778de976d422e69` |
| r0-obp-boot-and-login.exp SHA | `8b63e1bf7a486ff45e1109a30ef2c51aff56f49dc4057b3295a35aade94e36d2` |
| r0-guest-command.exp SHA (unchanged all session) | `f3dd444aab91dd40a4b7ac7ddc8f07ae6ab90ef8f179b463a0b09c234a8fff2b` |
| RUNDIR | `/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T115447Z` |
| IMAGE_PATH | `/home/niagara/sun4v/images/basecamp-r0-rehearsal-20260825T115447Z.iso` |
| IMAGE size (MEASURED) | 644,198,400 bytes (`ls -la`, timestamp Aug 25 12:00) |
| SRC_ISO_PATH | `/home/niagara/sun4v/images/OpenIndiana_Text_SPARC_12_2025.iso.clean` |
| SRC_ISO_SHA | `173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04` |
| ARC_PATH | `/home/niagara/sun4v/images/OpenIndiana_Text_SPARC_12_2025.boot_archive.hsimd` |
| ARC_SHA | `f334e542c0ba0ac35fea8bf8f6270f813e984727a6d5c77a3c6fda0906cee376` |
| PAYLOAD_TAR_PATH | `/home/niagara/niag-proj-anchor/tools/../captures/openindiana-live-20260824/staged-payload/basecamp-r0-bootstrap.proven.tar` |
| PAYLOAD_SHA | `d3820b9eb2e8adff62dff30cdc13ca67c8b83f994dd3d2c2a6e33e857a0e807b` |
| PAYLOAD_TAR size (MEASURED) | 30,720 bytes |
| QEMU_PATH | `/home/niagara/niag-proj/qemu/build/qemu-system-sparc64.baseline-11aa0b1` |
| QEMU_SHA | `7073119a7c2c15527cd93a315ccce30bafacb537228e049eafb4118b46b0a053` |

## 2. Manifest outcome (verbatim from manifest.env)

```
STATUS=PASS
RC=0
START_UTC=2026-08-25T11:54:47Z
END_UTC=2026-08-25T11:58:13Z
ELAPSED_S=206
LAST_STEP=REPLAY PASSED
GATES_REACHED=27  (GATE_0 through GATE_26, all logged; full list in section 6)
NAT_RULE_ADDED=1
NFS_ACL_ADDED=1
```

## 3. Process / PID inventory (all MEASURED — confirmed alive via `ps` at report time, matching manifest exactly)

| Role | PID | PPID | Elapsed (at report time) | Exact argv/cmd |
|---|---|---|---|---|
| OWNER_PID (qemu-owner.sh wrapper) | 761170 | 1 | 05:20 | `bash .../qemu-owner.sh <RUNDIR> -- <qemu argv>` |
| QPID (QEMU worker) | 761173 | 761170 | 05:20 | `qemu-system-sparc64.baseline-11aa0b1 -M niagara -L .../firmware/base-1gib -m 1024 -nographic -monitor unix:.../monitor.sock,server=on,wait=off -serial unix:.../serial.sock,server=on,wait=off -drive if=pflash,file=.../basecamp-r0-rehearsal-20260825T115447Z.iso,format=raw` |
| BRIDGE_PID (host-chan.py) | 761401 | 1 | 02:21 | `python3 .../tools/chan/host-chan.py bridge 0 <RUNDIR>/niag0.sock` |
| PPPD_LAUNCH_PID (sudo/setsid/socat wrapper — NEVER the worker) | 761450 | 1 | 02:07 | `sudo -n setsid nohup socat UNIX-CONNECT:<RUNDIR>/niag0.sock EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff debug logfile <RUNDIR>/pppd-debug.log 10.0.6.1:10.0.6.15 nodetach',nofork` |
| PPPD_PID (parent, resolved via ss inode cross-link) | 761452 | 761450 | 02:07 | `/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff debug logfile <RUNDIR>/pppd-debug.log 10.0.6.1:10.0.6.15 nodetach` |
| PPPD_PEER_PID (innermost, holds the connected channel-socket fd) | 761453 | 761452 | 02:07 | same argv as PPPD_PID (pppd's own internal fork) |

Note: per this session's ownership-aware `pid_alive()` fix, PPPD_PID/PPPD_PEER_PID are root-owned (launched via `sudo -n`); PPPD_LAUNCH_PID retains the unprivileged real UID as the `sudo` frontend. All three PIDs independently confirmed alive via direct `ps -o pid,ppid,etime,cmd -p <pid>` at report time — MEASURED, not inferred from the manifest alone.

## 4. Socket / network / export inventory (MEASURED, current live state)

**Sockets** (all under RUNDIR, confirmed present via `ls -la`):
- `monitor.sock` — `srwxr-xr-x`, created 11:54
- `serial.sock` — `srwxr-xr-x`, created 11:54
- `niag0.sock` (CHANSOCK, scoped channel bridge) — `srw-rw-rw-`, created 11:57

**NAT (iptables -t nat -S POSTROUTING), current live table:**
```
-A POSTROUTING -s 10.0.5.15/32 -o enp0s1 -j MASQUERADE   <- primary R0, untouched all session
-A POSTROUTING -s 10.0.6.15/32 -o enp0s1 -j MASQUERADE   <- Retry #13's transient rule, still present (VM left up for inspection)
```

**NFS export (exportfs -s, single-line-per-client format, current live table):**
```
/home/niagara/nfs-oi  10.0.6.15(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
/home/niagara/nfs-oi  10.0.5.15/32(sync,wdelay,hide,no_subtree_check,sec=sys,rw,insecure,no_root_squash,no_all_squash)
```
Both entries on the SAME base directory (`/home/niagara/nfs-oi`), isolated by distinct client specs — confirms the "layer an additional in-memory client entry onto the same already-exported directory" design intent, not a duplicate/conflicting export.

**Primary R0 invariant check (MEASURED at report time):** PID 709698, `ps -o etime` = 06:05:54+ (continuously alive since before this session began), its NAT/export entries (`10.0.5.15/32`) unchanged in content and position throughout.

## 5. Milestone timestamps and elapsed seconds (MEASURED — verbatim from manifest.env)

| Milestone | UTC timestamp | Elapsed (s) from START_UTC |
|---|---|---|
| START | 2026-08-25T11:54:47Z | 0 |
| IMAGE_BUILT | 2026-08-25T11:54:48Z | 1 |
| QEMU_STARTED | 2026-08-25T11:54:50Z | 3 |
| MAINTENANCE_SHELL | 2026-08-25T11:57:27Z | 160 |
| DTRACE | 2026-08-25T11:57:41Z | 174 |
| CHANNEL_ECHO | 2026-08-25T11:57:55Z | 188 |
| PPP_LINK | 2026-08-25T11:58:05Z | 198 |
| NFS | 2026-08-25T11:58:13Z | 206 |
| FINAL_PASS | 2026-08-25T11:58:13Z | 206 |
| END | 2026-08-25T11:58:13Z | 206 (= ELAPSED_S) |

## 6. Full gate list (MEASURED, verbatim GATE_0..GATE_26 from manifest.env)

```
GATE_0  = tool presence (runtime replay)
GATE_1  = sudo rights: iptables/exportfs/host-chan.py must be runnable non-interactively
GATE_2  = verify immutable/pinned inputs
GATE_3  = preflight: no collision with any live Niagara QEMU (image-scoped, not broad pgrep)
GATE_4  = preflight: ip_forward=1 (required for NAT/external-ping/DNS gates)
GATE_5  = preflight: proven NFS export exists as a base for a transient client ACL
GATE_6  = preflight: no stale scoped NAT rule (mirrors the NFS ACL gate above)
GATE_7  = build fresh disposable R0 (never reuses a mutated prior deploy)
GATE_8  = preflight: this exact image path is not already open by any QEMU
GATE_9  = deploy: unique run dir, scoped sockets, detached stdio (qemu-owner.sh)
GATE_10 = deterministic boot: OBP -> boot disk -v -> root/root maintenance login
GATE_11 = dynamic HSFS media discovery (never assume a fixed guest disk ID)
GATE_12 = /.cdrom mount + verify solaris.zlib presence
GATE_13 = attach solaris.zlib and mount /usr from the DYNAMICALLY assigned lofi node
GATE_14 = DTrace exact-probe-count gate: asserted INSIDE the guest command
GATE_15 = stage the pinned proven payload POST-BOOT at sector 1046530
GATE_16 = guest extraction via iseek (never skip= on a raw character device)
GATE_17 = per-member hash assertion, then chmod +x (proven tar ships members at 0644)
GATE_18 = scoped channel bootstrap (never a global socket)
GATE_19 = PRE-PROTOCOL GATE: exact framed channel echo, before any PPP (acceptance ladder step 5)
GATE_20 = isolated PPP on scoped channel 0 (subnet 10.0.6.1<->10.0.6.15, distinct from primary R0's 10.0.5.x)
GATE_21 = verify QEMU worker still alive, then use SIGUSR2 exactly like host-up.sh's proven sync gate
GATE_22 = scoped NAT for the rehearsal subnet only (never touches primary R0's 10.0.5.15 rule)
GATE_23 = REQUIRED assertions: host->guest ping, guest->host ping, external ping, DNS
GATE_24 = REQUIRED assertion: NFS, via a TRANSIENT client ACL on the proven export
GATE_25 = emit scoped teardown script
GATE_26 = REPLAY PASSED
```

## 7. Teardown path (not executed — provided for reference only per "do not teardown" instruction)

```
/home/niagara/sun4v/runs/basecamp-r0-rehearsal-20260825T115447Z/teardown.sh
```
MEASURED: `-rwxr-xr-x`, 1096 bytes, written 11:58. NOT invoked as part of this report.

## 8. PPP negotiation evidence (MEASURED — verbatim pppd-debug.log, full content, no truncation)

```
using channel 19612
Using interface ppp1
Connect: ppp1 <--> /dev/pts/8
sent [LCP ConfReq id=0x1 <magic 0x95a60fd1> <pcomp> <accomp>]
rcvd [LCP ConfReq id=0xae <magic 0xd5692820> <pcomp> <accomp>]
sent [LCP ConfAck id=0xae <magic 0xd5692820> <pcomp> <accomp>]
sent [LCP ConfReq id=0x1 <magic 0x95a60fd1> <pcomp> <accomp>]
rcvd [LCP ConfAck id=0x1 <magic 0x95a60fd1> <pcomp> <accomp>]
sent [LCP EchoReq id=0x0 magic=0x95a60fd1]
sent [IPCP ConfReq id=0x1 <addr 10.0.6.1>]
sent [IPV6CP ConfReq id=0x1 <addr fe80::24ee:7901:ac81:522a>]
rcvd [LCP Ident id=0xaf magic=0xd5692820 "ppp-2.4.0b1 (Sun Microsystems, Inc.)"]
rcvd [IPCP ConfReq id=0x7e <addr 10.0.6.15>]
sent [IPCP ConfAck id=0x7e <addr 10.0.6.15>]
rcvd [LCP EchoRep id=0x0 magic=0xd5692820]
rcvd [LCP ProtRej id=0xb0 80 57 01 01 00 0e 01 0a 24 ee 79 01 ac 81 52 2a]
Protocol-Reject for 'IPv6 Control Protocol' (0x8057) received
rcvd [IPCP ConfAck id=0x1 <addr 10.0.6.1>]
Script /etc/ppp/ip-pre-up started (pid 761463)
Script /etc/ppp/ip-pre-up finished (pid 761463), status = 0x0
local  IP address 10.0.6.1
remote IP address 10.0.6.15
Script /etc/ppp/ip-up started (pid 761471)
Script /etc/ppp/ip-up finished (pid 761471), status = 0x0
```
No "Modem hangup" / "Connection terminated" lines present — clean, complete negotiation (contrast with Retry #10's identical-format log showing hangup 498ms post-connect). IPV6CP is Protocol-Rejected by the guest and never negotiated — expected/benign (project only exercises IPv4 PPP).

## 9. Pre-miss-storm performance baseline

**Framing note (per instruction):** "miss-storm" is not a term this session has independently defined or previously used; no prior session evidence establishes what specific event that label refers to. This section derives a MEASURED baseline strictly from Retry #13's own evidence, and separately what would need to be INFERRED (with explicit caveats) to characterize deviation from it. No claim is made here about identifying or bounding a "miss-storm" itself — that requires a second, comparison data point this report does not have.

### 9a. MEASURED (directly from manifest.env / replay.log / pppd-debug.log, this run only)

| Phase | Measured duration |
|---|---|
| Image build (disposable R0 assembly) | 1s (START -> IMAGE_BUILT) |
| QEMU cold start to owned-worker-alive | 3s (START -> QEMU_STARTED) |
| Boot to maintenance shell (OBP -> boot disk -v -> login) | 157s (QEMU_STARTED -> MAINTENANCE_SHELL, i.e. 160-3) |
| Maintenance shell to DTrace probe-count assertion | 14s (160 -> 174) |
| DTrace to framed-channel-echo verified | 14s (174 -> 188) |
| Channel echo to PPP_LINK (includes guest-side pppd launch/readiness poll, host dial-in, SIGUSR2 sync, NAT add, all 4 ping/DNS assertions) | 10s (188 -> 198) |
| PPP_LINK to NFS mount verified | 8s (198 -> 206) |
| **Total cold-boot-to-full-pass** | **206s (3m26s)** |

Replay.log for this run: 373 lines, 21,833 bytes (MEASURED, `wc`).

### 9b. What would need to be INFERRED to compare against a prior/future run (explicitly flagged, not computed here)

- Whether 206s total is "typical" or an outlier requires at least one OTHER successful full-pass run's ELAPSED_S for comparison. This session has exactly one successful full-pass run (Retry #13) — no second data point exists yet, so no variance/typical-range claim can be made. **This is a single-sample baseline, not a statistical one.**
- The 157s boot-to-maintenance-shell phase is by far the largest single component (76% of total elapsed time). Whether this is dominated by QEMU sparc64 emulation speed, guest boot-archive size, or host CPU contention (e.g. the primary R0 QEMU process running concurrently on the same host) is NOT measured here — would require either a solo-run comparison (no primary R0 concurrently active) or host-level CPU/load sampling during the run, neither of which was captured.
- Network-layer timing (PPP negotiation itself, sub-components of the 198->206s NFS phase) is visible qualitatively in pppd-debug.log (no retransmits, no delays, clean single-round-trip ConfReq/ConfAck exchanges) but has no per-message timestamps in the captured log — exact negotiation latency in milliseconds is NOT measured, only "fast enough to complete within the 10s CHANNEL_ECHO->PPP_LINK window."

## 10. Explicit non-actions this turn
No teardown executed (primary or rehearsal VM). No code/doc edits made. No skill/memory/profile/global file writes. No guest-state mutation beyond what Retry #13 itself already produced before this report was compiled.
