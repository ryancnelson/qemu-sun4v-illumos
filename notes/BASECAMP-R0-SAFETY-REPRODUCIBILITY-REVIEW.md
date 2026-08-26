# Basecamp R0 Cold-Boot Replay & Safety Review

> **STATUS**: Audited Code Review of `tools/basecamp-r0-cold-anchor.sh` and `tools/openindiana/maintenance-login.sh`.

---

## 1. Audit Scope & Evaluation Criteria

Both scripts were evaluated against the strict operational standard:
> **"One command from immutable inputs to verified `/usr` + DTrace (exact 72,893 probes) + channels + PPP + DNS + NFS, zero manual memory, zero impact on running live R0, and side-by-side rehearsal capability."**

---

## 2. Concrete Safety & Reproducibility Gaps

| Script / Component | Identified Gap / Defect | Impact Against Criterion |
|---|---|---|
| `basecamp-r0-cold-anchor.sh` | **1. Truncates into Manual Steps**<br>Lines 75–116 print text cat-block instead of driving console. | **FAILS "ONE COMMAND" GOAL**: Halts at line 75; operator must manually type 7 guest & 4 host commands. |
| `basecamp-r0-cold-anchor.sh` | **2. Global Process Blocker**<br>Line 44 `pgrep -f 'qemu...niagara'` exits. | **BLOCKS SIDE-BY-SIDE REHEARSAL**: Fails immediately if live R0 is currently running. |
| `basecamp-r0-cold-anchor.sh` | **3. Global Socket Collisions in Instructions**<br>Lines 111–112 prescribe global `/run/niag0`. | **COLLISION RISK**: Would corrupt active channel bridges on the same host if run alongside live R0. |
| `basecamp-r0-cold-anchor.sh` | **4. Destructive Archive Overlap**<br>`CHAN_HOST_BYTE=520093696` overwrites boot archive. | **NON-REBOOTABLE**: Slices channel mailbox into byte 520,093,696, invalidating the boot archive on disk. |
| `maintenance-login.sh` | **5. Transport Mismatch**<br>Expects `tmux-target`; anchor uses detached serial socket. | **INTEGRATION FAILURE**: Cannot drive the `-serial unix:$SERIAL` headless socket emitted by line 66. |
| `maintenance-login.sh` | **6. Hardcoded Prompt Fragility**<br>Line 48 expects `root@openindiana:~#`. | **TIMEOUT RISK**: In raw ramdisk maintenance mode before `/usr` is mounted, prompt is `#` or `root@openindiana:/#`. |
| `maintenance-login.sh` | **7. Missing OBP Boot Trigger**<br>Starts at maintenance prompt. | **INCOMPLETE STATE MACHINE**: Does not send `boot disk -v` to the initial OpenBoot `ok` prompt. |

---

## 3. Existing Capabilities vs. Proposed Code Changes

### Existing Capability (Verified in Code)
* **`host-chan.py` Scoped Sockets**:
  In `tools/chan/host-chan.py:157` and `336-337`, `cmd_bridge(ch, sockpath)` **already natively accepts a custom socket path**:
  ```bash
  python3 tools/chan/host-chan.py bridge 0 /tmp/run-unique/niag0.sock
  ```
  *(Zero code changes required in `host-chan.py`)*.

### Proposed Code Changes (Required for Automation)
1. **`host-up.sh` Scoped Wrapper**: Modify `tools/chan/host-up.sh` to accept `SOCKDIR=${SOCKDIR:-/run}` so non-colliding bridges can be spawned for rehearsal VMs.
2. **Serial Socket Automator**: Replace lines 75–116 in `basecamp-r0-cold-anchor.sh` with a headless socket driver (e.g. Python `pexpect` / `socket`) that connects to `$SERIAL` and deterministically executes:
   - `ok` $\rightarrow$ `boot disk -v`
   - `Enter user name...` $\rightarrow$ `root`
   - `Enter root password...` $\rightarrow$ `root`
   - `root@...#` $\rightarrow$ mount `/.cdrom`, attach `solaris.zlib`, mount `/usr`.
3. **Exact DTrace Assertion**:
   Assert exact **`72,893`** probe count (`dtrace -l | wc -l == 72893`) for this immutable Basecamp R0 release.

---

## 4. Single-Command Rehearsal Architecture

```
[basecamp-replay.sh]
  |--> 1. Generate unique $RUNDIR=/tmp/run-<UUID>
  |--> 2. Create reflink $R0=$RUNDIR/work.iso
  |--> 3. Launch QEMU with scoped sockets:
  |         -monitor unix:$RUNDIR/monitor.sock
  |         -serial  unix:$RUNDIR/serial.sock
  |--> 4. Launch Headless Serial Automator
  |--> 5. Launch Scoped Host Bridge (host-chan.py bridge 0 $RUNDIR/niag0.sock)
  |--> 6. Start Scoped pppd (10.0.6.1 <-> 10.0.6.15 on non-colliding subnet)
  |--> 7. Assert exact DTrace probe count (72,893 probes)
```
