#!/usr/bin/env bash
# BASECAMP_R0 cold-boot anchor: fail-closed, one-command replay from
# immutable hash-pinned inputs through deterministic root login, dynamic
# HSFS media discovery, /usr, DTrace(=72893), a proven exact framed-echo
# channel gate, isolated PPP, and external/DNS/NFS assertions -- all
# REQUIRED gates, none advisory.
#
# Every numeric constant here is either (a) an immutable input hash checked
# against notes/BASECAMP-R0-RELEASE-MANIFEST.md, or (b) re-derived/asserted
# at runtime rather than assumed. Nothing here silently reuses a prior
# session's device enumeration (chief-engineer invariant #13).
#
# THIS SCRIPT NEVER TOUCHES PRIMARY R0. It never shares primary R0's image
# path, sockets, run directory, PPP subnet (10.0.5.x), NFS export ACL, or
# QEMU PID. Collision checks match by exact image/socket path, never a broad
# `pgrep -f niagara`. All host-side helper processes this script starts are
# put in their OWN process group (setsid) and their PIDs recorded to files
# in $RUNDIR, so teardown kills the exact owned worker -- never a wrapper
# PID (sudo/nohup/setsid layers are not the real worker and killing them
# alone leaks the child, exactly the host-up.sh bug this project already
# fixed once).
#
# LAYOUT: this file lives at tools/basecamp-r0-cold-anchor.sh in a checkout
# that preserves the repo's tree shape (tools/openindiana/, tools/chan/,
# captures/...). Deploy with tools/deploy-r0-anchor-to-playbox.sh, which
# mirrors that same relative layout under $PLAYBOX_DIR -- it must NOT flatten
# everything into one directory, or SELFDIR-relative lookups below break.
#
# Usage:
#   tools/basecamp-r0-cold-anchor.sh --preflight-only
#       Purely local/static checks: syntax, dependency-file presence, tar
#       member hash asserts. No playbox runtime tools required, no image
#       hashes checked, never boots QEMU, never touches the network or
#       sudo state. Safe on any workstation, anytime.
#
#   tools/basecamp-r0-cold-anchor.sh --runtime-preflight-only
#       Run ON niagara-playbox after deploy. Verifies every LIVE prerequisite
#       a full replay depends on (tools, sudo rights, large-input hashes,
#       ip_forward, the proven NFS export, no image/QEMU collision) WITHOUT
#       booting QEMU, mutating iptables, or creating a transient NFS export.
#       Read-only with respect to running state.
#
#   tools/basecamp-r0-cold-anchor.sh
#       Full replay, run ON niagara-playbox after deploy: build disposable
#       R0, boot it in its own scoped run dir, prove /usr + DTrace + a
#       framed-echo channel gate + PPP + external ping + DNS + NFS (all
#       required), then leave the rehearsal VM running for inspection and
#       emit a scoped teardown script.
set -euo pipefail

H="$HOME"
PROJ="$H/niag-proj"
IMAGES="$H/sun4v/images"
SRC="$IMAGES/OpenIndiana_Text_SPARC_12_2025.iso.clean"
ARC="${ARC:-$IMAGES/OpenIndiana_Text_SPARC_12_2025.boot_archive.hsimd}"
QEMU="${QEMU:-$PROJ/qemu/build/qemu-system-sparc64.tlb-range}"
FW="$H/sun4v/firmware/base-1gib"
SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OI="$SELFDIR/openindiana"
CHAN="$SELFDIR/chan"
# Repo-relative, NOT $PROJ-relative: the proven payload ships inside the
# repo's own captures/ tree and must be deployed alongside the scripts (see
# tools/deploy-r0-anchor-to-playbox.sh), never assumed already present under
# $PROJ on playbox.
PAYLOAD_TAR="${PAYLOAD_TAR:-$SELFDIR/../captures/openindiana-live-20260824/staged-payload/basecamp-r0-bootstrap.proven.tar}"

SRC_SHA=173ade54c7f390ab0ba86500b0340f03aa92160a1805cb2d0ed7dd4e0bd85f04
ARC_SHA="${ARC_SHA:-f334e542c0ba0ac35fea8bf8f6270f813e984727a6d5c77a3c6fda0906cee376}"
QEMU_SHA="${QEMU_SHA:-bed76dbbc0c33246ab5964af939137b1272d8636c814b17630f7e37aee73f81b}"
ARC_OFFSET_SECTOR=878408      # byte 449744896
ARC_LEN_SECTORS=376164        # 192595968 bytes
CHAN_HOST_BYTE=520093696      # = compiled CHAN_GUEST_BLK 1015808 * 512
CHAN_BOOTSTRAP_BLOCK=1046530  # channel-15 h2g data area for this base; inside
                               # the boot-archive extent -- POST-BOOT ONLY.
DTRACE_EXPECT=72893

# The EXACT proven artifact recovered read-only from niagara-playbox
# (/tmp/basecamp-r0-bootstrap.tar, captured live 2026-08-25), not a freshly
# regenerated tar: three bounded reconstruction attempts with GNU tar
# (differing member order, --owner/--group/--mode/--mtime pinned) each
# produced a DIFFERENT hash from the proven artifact -- tar header/padding
# details depend on the exact tar build, not just the flags given here. Per
# chief-engineer direction, anchoring the recovered bytes closes the gap now;
# a reproducible from-scratch recipe is a later improvement, tracked but not
# blocking.
PAYLOAD_SHA="${PAYLOAD_SHA:-d3820b9eb2e8adff62dff30cdc13ca67c8b83f994dd3d2c2a6e33e857a0e807b}"
PAYLOAD_SECTORS="${PAYLOAD_SECTORS:-60}"
declare -A PAYLOAD_MEMBER_SHA=(
    [guest-chand]="${PAYLOAD_SHA_GUEST_CHAND:-baa7bd2798a414cf7f774f83588fdb132b857f86f5a189ade65f7e1440baffc9}"
    [guest-echocli]="${PAYLOAD_SHA_GUEST_ECHOCLI:-e41e6c419783885bc2f3af9143340bb7cb3b236069831bdeb8e50ff2109ccfa1}"
    [guest-ppp-chan.pl]="${PAYLOAD_SHA_GUEST_PPP_CHAN:-59e6fbe123c6824238e93b0f3f5aae289b7e06cf1cd906be915a5fc021f21eca}"
)
# The proven tar stores all three members mode 0644 (verified via `tar tvf`
# on playbox). guest-chand (ELF), guest-echocli (ELF), and guest-ppp-chan.pl
# (perl script) all need +x before they can be launched -- fixed explicitly
# post-extraction, before any of them run, below.
PAYLOAD_EXEC_MEMBERS="guest-chand guest-echocli guest-ppp-chan.pl"

# host-chan.py's own consts() parser is the single source of truth for CHAN_*
# (see chan.h); chan-test.py's default payload size (262144 bytes) is used
# unmodified for the pre-PPP echo gate below.
CHAN_TEST_SIZE=65536

# Isolated from primary R0's proven 10.0.5.1<->10.0.5.15 link. Never share a
# subnet with a live primary session.
GUEST_IP="${NIAG_REHEARSAL_GUEST_IP:-10.0.6.15}"
HOST_IP="${NIAG_REHEARSAL_HOST_IP:-10.0.6.1}"
# The proven, already-exported NFS directory (see /etc/exports on playbox:
# "/home/niagara/nfs-oi 10.0.5.15/32"). This replay ADDS a transient,
# additional client ACL for $GUEST_IP to the SAME directory via
# `exportfs -i` (in-memory only, never touches /etc/exports), and removes
# exactly that added ACL on exit -- primary R0's 10.0.5.15/32 entry is never
# read, modified, or re-exported.
NFS_EXPORT_DIR="${NIAG_REHEARSAL_NFS_DIR:-$H/nfs-oi}"

CMD_TIMEOUT="${NIAG_GUEST_CMD_TIMEOUT:-60}"
# 240s was measured against a warm cache; a genuinely cold boot (fresh ISO,
# fresh boot_archive splice, no page cache) has been observed to exceed that.
# r0-obp-boot-and-login.exp's own `timeout`/`eof` branches already die
# cleanly and report state on a real hang or an unexpectedly closed serial
# socket -- raising the ceiling here only gives a genuinely slow-but-alive
# cold boot room to finish; it does not mask a hung/dead QEMU, which the
# expect script still catches via its `eof` branch regardless of this value.
BOOT_TIMEOUT="${NIAG_BOOT_TIMEOUT:-1800}"

MODE=full
for a in "$@"; do
    case "$a" in
        --preflight-only) MODE=preflight ;;
        --runtime-preflight-only) MODE=runtime-preflight ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

die() { echo "COLD-ANCHOR FAIL: $*" >&2; exit 1; }

# LIFECYCLE INVARIANT (added after run basecamp-r0-rehearsal-20260825T162639Z
# was corrupted mid-run: an `scp` overwrite of THIS SAME staged script path
# while a still-running full-mode replay was mid-execution shifted bash's
# line offsets and caused a comment fragment to be misread as a command --
# "line 798: e: command not found". bash reads a script SOURCED FROM A FILE
# PATH incrementally as execution proceeds, not slurped whole up front, so a
# concurrent edit to that same path corrupts an in-flight run. Fix: for a
# real (full-mode) replay, immediately copy this script plus its
# openindiana/ and chan/ helper subtrees into a uniquely named, otherwise-
# untouched per-run release directory, then re-exec THAT COPY with the same
# argv/env. Every further byte this process reads comes from a path nothing
# else will ever write to again. --preflight-only/--runtime-preflight-only
# skip this (fast, read-only, no multi-minute window for a race) to avoid
# needless per-invocation copies during iteration.
if [[ "$MODE" == full && -z "${NIAG_R0_FROZEN_RELEASE:-}" ]]; then
    FREEZE_TS=$(date -u +%Y%m%dT%H%M%SZ)
    RELEASE_DIR="$H/sun4v/releases/basecamp-r0-cold-anchor-${FREEZE_TS}"
    mkdir -p "$RELEASE_DIR"
    cp -- "$SELFDIR/basecamp-r0-cold-anchor.sh" "$RELEASE_DIR/" 2>/dev/null \
        || cp -- "${BASH_SOURCE[0]}" "$RELEASE_DIR/basecamp-r0-cold-anchor.sh"
    cp -r -- "$OI" "$RELEASE_DIR/openindiana"
    cp -r -- "$CHAN" "$RELEASE_DIR/chan"
    # Prove the frozen copy is genuinely byte-identical before trusting it --
    # never re-exec into a copy that silently truncated or partially wrote.
    live_sha=$(sha256sum "${BASH_SOURCE[0]}" 2>/dev/null | awk '{print $1}')
    frozen_sha=$(sha256sum "$RELEASE_DIR/basecamp-r0-cold-anchor.sh" 2>/dev/null | awk '{print $1}')
    [[ -n "$live_sha" && "$live_sha" == "$frozen_sha" ]] \
        || die "frozen release copy hash mismatch ($frozen_sha) vs live source ($live_sha) -- refusing to re-exec into a corrupted copy"
    echo "  froze harness+helpers into immutable release dir: $RELEASE_DIR (SHA $frozen_sha)"
    # The re-exec'd copy will recompute SELFDIR as $RELEASE_DIR, which has no
    # ../captures/ sibling -- export every already-resolved default (ARC,
    # QEMU, PAYLOAD_TAR, and all *_SHA values already read at this point)
    # so the child inherits THIS process's resolution, not a broken one
    # derived from its own new (and wrong) SELFDIR-relative default.
    export ARC QEMU PAYLOAD_TAR ARC_SHA QEMU_SHA PAYLOAD_SHA PAYLOAD_SECTORS \
        PAYLOAD_SHA_GUEST_CHAND PAYLOAD_SHA_GUEST_ECHOCLI PAYLOAD_SHA_GUEST_PPP_CHAN
    export NIAG_R0_FROZEN_RELEASE="$RELEASE_DIR"
    exec bash "$RELEASE_DIR/basecamp-r0-cold-anchor.sh" "$@"
fi

# STEP_LOG/STEP_CURRENT track which named gates were reached, in order, for
# manifest.env's GATES_* fields. A step being logged here means it was
# ENTERED, not necessarily completed -- if the run dies partway through a
# step, that step's name is still the last GATE_N/LAST_STEP recorded, which
# is exactly the "how far did we get" evidence recovery needs.
declare -a STEP_LOG=()
STEP_CURRENT=""
step() {
    STEP_CURRENT="$*"
    STEP_LOG+=("$*")
    printf '\n=== %s ===\n' "$*"
}

# Match REAL worker processes only, never sudo/setsid wrapper layers (the
# exact false-positive class fixed in host-up.sh/preflight.sh already).
# Explicit `|| true`: zero matches is the NORMAL, expected outcome for every
# caller of this function (an unrelated qemu, or none at all) and must never
# be treated as this function's own failure -- `grep` returning 1 on no
# match would otherwise propagate through `pipefail` into any `$(real_pids
# ...)` assignment under the caller's `set -e` and abort the whole script
# silently, before that caller's own semantic check/die() ever runs. Every
# caller still receives an empty string on no match and performs its OWN
# rejection check on that string; this function's exit status no longer
# conflates "found nothing" with "this function failed."
real_pids() {
    ps -eo pid,args --no-headers 2>/dev/null | grep -- "$1" \
        | grep -v -e 'sudo ' -e 'setsid ' -e grep | awk '{print $1}' || true
}

guest_cmd() {
    # Bounded single command via the exact-status expect wrapper. Never
    # exceeds 200 chars (r0-guest-command.exp itself enforces this).
    local sock=$1 cmd=$2 timeout=${3:-$CMD_TIMEOUT}
    [[ ${#cmd} -le 200 ]] || die "internal error: guest command exceeds 200 chars: $cmd"
    expect -f "$OI/r0-guest-command.exp" "$sock" "$cmd" "$timeout"
}

# Launch "$@" as a background job of THIS shell -- deliberately NO setsid
# and NO sudo inside this function itself. `setsid`(1) forks a child and
# (without -f) the ORIGINAL setsid process exits almost immediately, so $!
# from a backgrounded `setsid cmd &` is a PID that is already dead, not the
# real worker -- the exact wrapper-PID confusion host-up.sh had to fix once
# already. Removing setsid means: when "$@" itself has no privileged wrapper
# (the unprivileged bridge case), $! IS the exact worker PID, no self-report
# needed.
#
# When "$@" DOES need a privileged wrapper (sudo), sudo forks its own child
# and $! from `sudo cmd &` is sudo's own PID, not the worker's -- the same
# class of bug. For that case the caller passes a non-empty PIDFILE and
# wraps its command as `sudo bash -c 'echo $$ > "$1"; exec real-worker ...'`
# so the self-reported PID IS the real worker's PID (the bash `exec`
# replaces the image but keeps the same PID that was just written to
# PIDFILE). This function then waits for that self-report and returns it
# instead of $!, verifying liveness before trusting it.
launch_owned() {
    local logfile=$1 pidfile=$2; shift 2
    "$@" > "$logfile" 2>&1 < /dev/null &
    local job_pid=$!
    if [[ -z "$pidfile" ]]; then
        echo "$job_pid"
        return 0
    fi
    local waited=0
    while [[ ! -s "$pidfile" ]]; do
        kill -0 "$job_pid" 2>/dev/null \
            || { echo "launch_owned: job $job_pid exited before self-reporting to $pidfile" >&2; return 1; }
        if (( waited >= 20 )); then
            echo "launch_owned: timed out waiting for self-report at $pidfile" >&2
            return 1
        fi
        sleep 0.5
        waited=$((waited + 1))
    done
    local real_pid
    real_pid=$(<"$pidfile")
    [[ "$real_pid" =~ ^[0-9]+$ ]] \
        || { echo "launch_owned: $pidfile did not contain a bare PID: $real_pid" >&2; return 1; }
    kill -0 "$real_pid" 2>/dev/null \
        || { echo "launch_owned: self-reported PID $real_pid is not alive" >&2; return 1; }
    echo "$real_pid"
}

# Ownership-aware liveness check. Plain `kill -0 PID` from this
# unprivileged script fails with EPERM (rc=1) on a ROOT-OWNED process even
# when it is genuinely alive -- indistinguishable from "not alive" by exit
# status alone. Reproduced read-only against primary R0's own live pppd
# (PID 717692, root-owned): `kill -0 717692` as niagara -> rc=1
# "Operation not permitted", while `ps` confirms it running; `sudo -n kill
# -0 717692` -> rc=0. The socat/pppd chain launched via `sudo -n setsid
# nohup socat ...` is root-owned throughout (pppd itself, and any
# intermediate fork), so every liveness check on PPPD_PEER_PID/PPPD_PID
# downstream of resolve_unix_peer() must use this, never a bare `kill -0`.
# PPPD_LAUNCH_PID is the one exception worth naming explicitly: it is
# `$!` from a `sudo -n setsid nohup socat ... &` background job run
# directly by THIS shell, so it may retain this script's own real UID
# (niagara) as the *sudo* frontend's PID even though the inner pppd/socat
# process it wraps does not -- so PPPD_LAUNCH_PID's own liveness ALSO goes
# through this same ownership-aware check rather than assuming either
# ownership case.
pid_alive() {
    local pid=$1
    kill -0 "$pid" 2>/dev/null && return 0
    sudo -n kill -0 "$pid" 2>/dev/null
}

# Discover the ANONYMOUS peer of a named AF_UNIX socket via inode
# cross-linking, and that peer's live parent PID -- all from EXACTLY ONE
# captured `sudo ss -H -x -p` snapshot (never two separate ss invocations,
# and never unprivileged `ss` alone: unprivileged ss can omit process/pid
# info for sockets it does not own, which is exactly the class of silent
# false-negative this resolver must not have). Necessary because
# host-up.sh-parity launch (setsid nohup socat ... EXEC:pppd,nofork &, no
# self-report wrapper) means $! is socat's own PID, but socat's `nofork`
# on the EXEC address calls execvp() directly (man socat: "Does not fork
# a subprocess for executing the program, instead calls execvp() or
# system() directly from the actual socat instance") -- so the launched
# PID (PPPD_LAUNCH_PID, the wrapper tracked at launch) and the process
# actually holding the connected peer fd can differ if pppd itself forks
# internally (observed live on primary R0: sudo/socat PID 717683 -> pppd
# child 717688 -> pppd grandchild 717692, the innermost of which is the
# true socket peer). Never assume the launched PID is the peer; always
# re-derive it from one ss snapshot after launch.
#
# Validated read-only against primary R0's live, proven-working PPP link
# before this function was ever wired into the full-mode replay path,
# using one `sudo ss -H -x -p` snapshot:
#   row for /run/niag0:         local_inode=5377968 peer_inode=5382286 pid=717627 (bridge, NOT the PPP peer)
#   row with local_inode=5382286: pid=717692 (pppd) -- this IS the real peer
#   ps -o pid,ppid -p 717692 -> PPID=717688 (pppd's own parent, NOT the sudo/socat wrapper 717683)
# Negative controls confirmed to reject: a nonexistent socket path, and a
# socket row whose peer inode has no matching row anywhere in the same
# snapshot.
resolve_unix_peer() {
    local sock=$1
    local snapshot row_a local_inode peer_inode row_b row_b_peer_inode peer_pid peer_ppid
    snapshot=$(sudo -n ss -H -x -p 2>/dev/null) \
        || { echo "resolve_unix_peer: sudo ss -H -x -p failed" >&2; return 1; }
    row_a=$(printf '%s\n' "$snapshot" | grep -F " $sock " | head -1)
    [[ -n "$row_a" ]] || { echo "resolve_unix_peer: no ss row for $sock" >&2; return 1; }
    local_inode=$(awk '{print $6}' <<< "$row_a")
    peer_inode=$(awk '{print $8}' <<< "$row_a")
    [[ "$local_inode" =~ ^[0-9]+$ && "$peer_inode" =~ ^[0-9]+$ ]] \
        || { echo "resolve_unix_peer: unparseable inode fields for $sock: $row_a" >&2; return 1; }
    # Cross-link on the SAME snapshot, BIDIRECTIONALLY: row_b is not just
    # "any row whose local inode equals row_a's peer_inode" (a one-way
    # match that a coincidental/stale inode reuse could satisfy) -- it
    # must ALSO report row_a's own local_inode as ITS peer_inode. Only a
    # genuine mutual AF_UNIX pairing satisfies both directions at once.
    row_b=$(printf '%s\n' "$snapshot" | awk -v want="$peer_inode" '$6==want' | head -1)
    [[ -n "$row_b" ]] || { echo "resolve_unix_peer: no anonymous peer row for inode $peer_inode in this snapshot" >&2; return 1; }
    row_b_peer_inode=$(awk '{print $8}' <<< "$row_b")
    [[ "$row_b_peer_inode" == "$local_inode" ]] \
        || { echo "resolve_unix_peer: peer row $row_b does not report $local_inode back as its own peer inode -- not a genuine mutual pairing" >&2; return 1; }
    peer_pid=$(grep -oE 'pid=[0-9]+' <<< "$row_b" | head -1 | cut -d= -f2)
    [[ -n "$peer_pid" ]] || { echo "resolve_unix_peer: no pid= in peer row: $row_b" >&2; return 1; }
    peer_ppid=$(ps -o ppid= -p "$peer_pid" 2>/dev/null | tr -d ' ')
    [[ "$peer_ppid" =~ ^[0-9]+$ ]] \
        || { echo "resolve_unix_peer: could not resolve live parent of peer PID $peer_pid" >&2; return 1; }
    echo "$peer_pid $peer_ppid"
}

# ---------------------------------------------------------------------------
# --preflight-only is a purely LOCAL/STATIC check: syntax, dependency
# presence, pinned-artifact hash verification. It must run on any workstation
# without requiring playbox's runtime toolchain, the multi-GB source ISO, or
# a live QEMU. It never touches sudo, iptables, exportfs, or the network.
if [[ "$MODE" == preflight ]]; then
    step "static: bash -n on this script"
    bash -n "${BASH_SOURCE[0]}" || die "self syntax check failed"
    echo "  ok"

    step "static: dependency files present (syntax/content only, no execution)"
    for f in \
        "$OI/r0-obp-boot-and-login.exp" "$OI/r0-guest-command.exp" "$OI/r0-maintenance-login.exp" \
        "$OI/qemu-owner.sh" "$CHAN/host-chan.py" "$CHAN/chan.h" "$CHAN/chan-test.py" "$PAYLOAD_TAR"
    do
        [[ -f "$f" ]] || die "missing dependency: $f"
        echo "  present  $f"
    done

    step "static: expect helpers parse cleanly (tclsh, no socat/spawn)"
    for f in "$OI/r0-obp-boot-and-login.exp" "$OI/r0-guest-command.exp" "$OI/r0-maintenance-login.exp"; do
        out=$(tclsh <<EOF 2>&1 || true
set argv0 "$f"
set argv {}
set argc 0
if {[catch {source {$f}} err]} {
    if {![string match "*no such variable*" \$err] && ![string match "*wrong # args*" \$err] \
        && ![string match "*invalid command name \"spawn\"*" \$err]} {
        puts "SYNTAX-ERROR: \$err"
    }
}
EOF
)
        if echo "$out" | grep -q SYNTAX-ERROR; then
            die "$f failed syntax check: $out"
        fi
        echo "  ok  $(basename "$f")"
    done

    step "static: python3 syntax check (skipped if python3 absent locally)"
    if command -v python3 >/dev/null; then
        python3 -m py_compile "$CHAN/host-chan.py" || die "host-chan.py syntax error"
        python3 -m py_compile "$CHAN/chan-test.py" || die "chan-test.py syntax error"
        echo "  ok  host-chan.py, chan-test.py"
    else
        echo "  SKIPPED: python3 not present on this workstation"
    fi

    step "static: pinned payload artifact hash and member hashes"
    [[ "$(sha256sum "$PAYLOAD_TAR" | awk '{print $1}')" == "$PAYLOAD_SHA" ]] \
        || die "PAYLOAD_TAR does not match pinned hash $PAYLOAD_SHA -- artifact drifted, do not trust"
    actual_sectors=$(( ( $(stat -c %s "$PAYLOAD_TAR" 2>/dev/null || stat -f %z "$PAYLOAD_TAR") + 511 ) / 512 ))
    [[ "$actual_sectors" == "$PAYLOAD_SECTORS" ]] \
        || die "PAYLOAD_TAR sector count $actual_sectors != pinned $PAYLOAD_SECTORS"
    if command -v tar >/dev/null; then
        d=$(mktemp -d)
        tar xf "$PAYLOAD_TAR" -C "$d"
        for m in "${!PAYLOAD_MEMBER_SHA[@]}"; do
            [[ -f "$d/$m" ]] || die "pinned tar missing expected member: $m"
            got=$(sha256sum "$d/$m" | awk '{print $1}')
            [[ "$got" == "${PAYLOAD_MEMBER_SHA[$m]}" ]] \
                || die "member $m hash $got != pinned ${PAYLOAD_MEMBER_SHA[$m]}"
        done
        rm -rf "$d"
        echo "  ok  whole-tar hash + all ${#PAYLOAD_MEMBER_SHA[@]} member hashes verified"
    else
        echo "  SKIPPED member extraction (no tar locally); whole-tar hash still verified"
    fi

    echo
    echo "PREFLIGHT-ONLY (static/local mode) PASSED. Syntax, dependency"
    echo "presence, and pinned payload hashes only -- no image hashes, no"
    echo "playbox runtime tools, no network/sudo/iptables/exportfs touched,"
    echo "no QEMU. Next: --runtime-preflight-only ON niagara-playbox."
    exit 0
fi

# ===========================================================================
# RECOVERY-EVIDENCE LAYER init. Gated on MODE==full and placed BEFORE every
# runtime prerequisite/hash/collision check below, so replay.log genuinely
# captures the ENTIRE full-mode run from its first byte -- including a
# failure in tool presence, sudo rights, input hashes, or the NAT/NFS
# collision checks, none of which produced any evidence before this fix.
# --runtime-preflight-only shares the checks below but returns via its own
# `exit 0` further down without ever entering this block, so it stays
# non-mutating: no RUNDIR, no replay.log, no trap.
#
# The EXIT trap is installed HERE too (not after QEMU starts), so a failure
# in ANY step below -- even before an image exists or QEMU is launched --
# still produces a FAIL manifest.env. cleanup() is written defensively: every
# variable it touches uses a `${VAR:-}` default, because at this early point
# essentially nothing (R0, QPID, OWNER_PID, NAT_WAN, BRIDGE_PID, PPPD_PID)
# has been assigned yet, and `set -u` turns an unguarded reference to any of
# them into a crash inside the trap itself -- the exact failure mode this
# whole layer exists to avoid.
# ===========================================================================
if [[ "$MODE" == full ]]; then
    TS=$(date -u +%Y%m%dT%H%M%SZ)
    RUNDIR="$H/sun4v/runs/basecamp-r0-rehearsal-${TS}"
    mkdir -p "$RUNDIR"
    REPLAY_LOG="$RUNDIR/replay.log"
    exec > >(tee -a "$REPLAY_LOG") 2>&1
    START_EPOCH=$(date +%s)
    START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    MANIFEST="$RUNDIR/manifest.env"
    declare -A MILESTONE_UTC=()
    declare -A MILESTONE_ELAPSED=()

    record_milestone() {
        local name=$1 now_epoch now_utc
        now_epoch=$(date +%s)
        now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        MILESTONE_UTC[$name]=$now_utc
        MILESTONE_ELAPSED[$name]=$(( now_epoch - START_EPOCH ))
        echo "  MILESTONE $name  utc=$now_utc  elapsed_s=${MILESTONE_ELAPSED[$name]}"
    }

    # Single emit point for every manifest line. %q shell-quotes the value
    # losslessly (spaces, quotes, $, backslashes all round-trip), so
    # manifest.env stays a genuinely `source`-able shell env file even for
    # fields with embedded spaces (QEMU_ARGV, GATE_N step names) -- a raw
    # `echo "KEY=$VALUE"` silently breaks the moment any such value appears.
    manifest_kv() { printf '%s=%q\n' "$1" "$2"; }

    # Written atomically (tmp file + rename on the same filesystem) so a
    # reader never observes a half-written manifest, whether this run
    # passed or died. Called from cleanup() below (every exit path: success,
    # die(), or an uncaught error under `set -euo pipefail`) and once more,
    # explicitly, on the success path before the EXIT trap is disarmed.
    write_manifest() {
        local rc=$1 status
        [[ "$rc" -eq 0 ]] && status=PASS || status=FAIL
        local end_utc; end_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        local elapsed_s=$(( $(date +%s) - START_EPOCH ))
        {
            manifest_kv STATUS "$status"
            manifest_kv RC "$rc"
            manifest_kv START_UTC "$START_UTC"
            manifest_kv END_UTC "$end_utc"
            manifest_kv ELAPSED_S "$elapsed_s"
            manifest_kv LAST_STEP "${STEP_CURRENT:-}"
            manifest_kv QEMU_PATH "$QEMU"
            manifest_kv QEMU_SHA "$QEMU_SHA"
            manifest_kv QEMU_ARGV "${QEMU_ARGV_SERIALIZED:-}"
            manifest_kv SRC_ISO_PATH "$SRC"
            manifest_kv SRC_ISO_SHA "$SRC_SHA"
            manifest_kv ARC_PATH "$ARC"
            manifest_kv ARC_SHA "$ARC_SHA"
            manifest_kv PAYLOAD_TAR_PATH "$PAYLOAD_TAR"
            manifest_kv PAYLOAD_SHA "$PAYLOAD_SHA"
            manifest_kv IMAGE_PATH "${R0:-}"
            manifest_kv RUNDIR "$RUNDIR"
            manifest_kv REPLAY_LOG "$REPLAY_LOG"
            manifest_kv MONITOR_SOCK "${MONITOR:-}"
            manifest_kv SERIAL_SOCK "${SERIAL:-}"
            manifest_kv CHANSOCK "${CHANSOCK:-}"
            manifest_kv OWNER_PID "${OWNER_PID:-}"
            manifest_kv TMUX_SESSION "${TMUX_SESSION_NAME:-}"
            manifest_kv TMUX_WINDOW "${TMUX_WINDOW_NAME:-}"
            manifest_kv TMUX_REPLAY_WINDOW "${TMUX_REPLAY_WINDOW_NAME:-}"
            manifest_kv QPID "${QPID:-}"
            manifest_kv BRIDGE_PID "${BRIDGE_PID:-}"
            manifest_kv PPPD_LAUNCH_PID "${PPPD_LAUNCH_PID:-}"
            manifest_kv PPPD_PID "${PPPD_PID:-}"
            manifest_kv PPPD_DEBUG_LOG "${PPPD_DEBUG_LOG:-}"
            manifest_kv PPPD_PEER_PID "${PPPD_PEER_PID:-}"
            manifest_kv GUEST_DEV "${GUEST_DEV:-}"
            manifest_kv GUEST_DEV_BLOCK "${GUEST_DEV_BLOCK:-}"
            manifest_kv LOFI_DEV "${LOFI_DEV:-}"
            manifest_kv NAT_WAN "${NAT_WAN:-}"
            manifest_kv NAT_RULE_ADDED "${NAT_RULE_ADDED:-0}"
            manifest_kv NFS_ACL_ADDED "${NFS_ACL_ADDED:-0}"
            local m
            for m in IMAGE_BUILT QEMU_STARTED MAINTENANCE_SHELL DTRACE CHANNEL_ECHO PPP_LINK NFS FINAL_PASS; do
                manifest_kv "MILESTONE_${m}_UTC" "${MILESTONE_UTC[$m]:-}"
                manifest_kv "MILESTONE_${m}_ELAPSED_S" "${MILESTONE_ELAPSED[$m]:-}"
            done
            manifest_kv GATES_REACHED "${#STEP_LOG[@]}"
            local i
            for i in "${!STEP_LOG[@]}"; do
                manifest_kv "GATE_${i}" "${STEP_LOG[$i]}"
            done
        } > "$MANIFEST.tmp"
        mv -f "$MANIFEST.tmp" "$MANIFEST"
        echo "  manifest written: $MANIFEST (status=$status)"
    }

    # Defensive against every var it touches being unset this early: `set -u`
    # would otherwise crash the trap itself on the very first full-mode
    # failure (e.g. a missing tool), which is exactly the silent-evidence
    # failure mode this layer exists to close.
    #
    # INTERNAL_ABORT_RC=97: documented sentinel exit code for "cleanup()
    # ran with the EXIT trap still armed and rc=0" -- the ONLY way the
    # success path reaches record_milestone FINAL_PASS -> step "REPLAY
    # PASSED" -> write_manifest 0 -> trap - EXIT, so any OTHER arrival at
    # cleanup() with rc=0 (external SIGTERM/SIGINT/SIGHUP landing between
    # gates, or any future code path that exits 0 without disarming the
    # trap first) is unconditionally a failure, never a real pass. Bug
    # found live (Retry #10, 2026-08-25): a SIGTERM sent to fail-close a
    # stalled run left $? as an unrelated prior value that happened to be
    # 0, and write_manifest was called with that raw $rc, producing
    # STATUS=PASS RC=0 at GATES_REACHED=11 despite the run never reaching
    # completion -- a false-positive manifest.  97 is chosen because it is
    # outside the reserved 0-2/124-126/128+n signal ranges bash and this
    # script's own die()/exit callers already use (0=pass, 2=usage,
    # 124/125/126=this script's own expect-adjacent exit codes documented
    # elsewhere, 128+n=killed-by-signal-n).
    cleanup() {
        local rc=$?
        echo
        if [[ $rc -ne 0 ]]; then
            echo "FAIL-CLOSED CLEANUP: replay failed (rc=$rc). Tearing down ONLY this"
            echo "run's owned processes and scoped host state."
        else
            echo "Replay reported success but reached EXIT without an explicit"
            echo "'trap - EXIT' -- treating as a failure path defensively."
            rc=97
        fi
        echo "Primary R0 is never referenced by this run's PIDs, sockets, image"
        echo "path, subnet, or NFS export ACL."
        # Exact `== "1"` (never `-n`): NFS_ACL_ADDED/NAT_RULE_ADDED are read
        # elsewhere with a `${VAR:-0}` default (see write_manifest), and the
        # string "0" is non-empty -- `[[ -n "0" ]]` is TRUE. A bare `-n`
        # check here would therefore treat "not yet added" the same as
        # "added", entering the mutation branch on every single failure and
        # referencing $GUEST_IP/$NFS_EXPORT_DIR/$NAT_WAN before any of them
        # are guaranteed to be set this early -- the exact "unset variable
        # expands empty and the command still runs" fail-OPEN behavior this
        # trap exists to prevent. Every variable actually referenced inside
        # each block is now also explicitly guarded, not just the flag.
        if [[ "${NFS_ACL_ADDED:-0}" == "1" && -n "${GUEST_IP:-}" && -n "${NFS_EXPORT_DIR:-}" ]]; then
            sudo -n exportfs -u "${GUEST_IP}:${NFS_EXPORT_DIR}" 2>/dev/null || true
            echo "  removed transient NFS ACL for $GUEST_IP"
        fi
        if [[ "${NAT_RULE_ADDED:-0}" == "1" && -n "${GUEST_IP:-}" && -n "${NAT_WAN:-}" ]]; then
            sudo -n iptables -t nat -D POSTROUTING -s "$GUEST_IP/32" -o "$NAT_WAN" -j MASQUERADE 2>/dev/null || true
            echo "  removed transient NAT rule"
        fi
        [[ -n "${PPPD_PEER_PID:-}" ]] && { sudo -n kill -TERM "$PPPD_PEER_PID" 2>/dev/null || true; sleep 1; sudo -n kill -9 "$PPPD_PEER_PID" 2>/dev/null || true; }
        [[ -n "${PPPD_PID:-}" ]] && { sudo -n kill -TERM "$PPPD_PID" 2>/dev/null || true; sleep 1; sudo -n kill -9 "$PPPD_PID" 2>/dev/null || true; }
        [[ -n "${PPPD_LAUNCH_PID:-}" ]] && { sudo -n kill -TERM "$PPPD_LAUNCH_PID" 2>/dev/null || true; sleep 1; sudo -n kill -9 "$PPPD_LAUNCH_PID" 2>/dev/null || true; }
        [[ -n "${BRIDGE_PID:-}" ]] && { kill -TERM "$BRIDGE_PID" 2>/dev/null || true; sleep 1; kill -9 "$BRIDGE_PID" 2>/dev/null || true; }
        [[ -n "${OWNER_PID:-}" ]] && kill "$OWNER_PID" 2>/dev/null || true
        [[ -n "${QPID:-}" ]] && kill "$QPID" 2>/dev/null || true
        [[ -n "${TMUX_SESSION_NAME:-}" ]] && tmux kill-session -t "$TMUX_SESSION_NAME" 2>/dev/null || true
        echo "  evidence preserved in $RUNDIR${R0:+ and $R0}"
        write_manifest "$rc"
        # Disarm ALL traps before the final exit -- calling `exit` from
        # inside a still-armed EXIT trap would otherwise recurse into
        # cleanup() a second time. This also guarantees the actual OS
        # process exit status is $rc (nonzero on every failure/defensive
        # path), not whatever ambient $? happened to be when the shell's
        # implicit post-trap exit occurred -- the exact gap that let
        # Retry #10's SIGTERM-during-stall produce a process exit status
        # of 0 alongside a STATUS=PASS manifest.
        trap - EXIT INT TERM HUP
        exit "$rc"
    }
    trap cleanup EXIT
    # Route external termination signals through the SAME fail-closed
    # cleanup path with CONVENTIONAL nonzero exit codes (128+signum, the
    # standard shell convention), rather than trusting whatever ambient
    # $? cleanup()'s `local rc=$?` would otherwise capture from an
    # unrelated prior command. Without this, a bare `kill -TERM` on the
    # main script's PID (the exact action used to fail-close Retry #10)
    # can leave $? at 0 if the most recently completed foreground command
    # before the signal landed happened to succeed -- indistinguishable
    # from the genuine success path once inside cleanup(), which is
    # precisely the false-PASS bug being fixed here.
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Inert unless NIAG_EVIDENCE_SELFTEST_FAIL=1 is explicitly set. Exists so
    # the recovery-evidence layer itself (replay.log/manifest.env/cleanup)
    # can be exercised end-to-end by running the ACTUAL script -- not a
    # line-range extraction into a separate harness, which already proved
    # brittle twice (wrong boundary, then a missing closing `fi`) against
    # ordinary edits to this file. A real HOME can be pointed at a throwaway
    # mktemp dir and this run entirely locally: no playbox, no QEMU, no
    # tool-presence/sudo/hash prerequisites needed, because this fires
    # before any of those checks run.
    if [[ "${NIAG_EVIDENCE_SELFTEST_FAIL:-0}" == "1" ]]; then
        step "synthetic-evidence-failure"
        die "NIAG_EVIDENCE_SELFTEST_FAIL=1: synthetic failure for evidence-layer self-test (never touches playbox or QEMU)"
    fi
fi

# ===========================================================================
# Everything past this point assumes it is running on niagara-playbox with
# the full toolchain, large inputs, and sudo rights present.
# ===========================================================================
step "tool presence (runtime replay)"
for t in sha256sum socat expect python3 dd cmp perl pppd tar sudo iptables exportfs ip setsid ss tmux; do
    command -v "$t" >/dev/null || die "required tool missing: $t"
done
echo "  all required tools present"

step "sudo rights: iptables/exportfs/host-chan.py must be runnable non-interactively"
sudo -n true 2>/dev/null || die "passwordless sudo is required for this replay (iptables/exportfs/host-chan.py) -- niagara's sudoers must permit -n"
echo "  sudo -n OK"

step "verify immutable/pinned inputs"
[[ -f "$SRC" ]] || die "source ISO missing: $SRC"
[[ -f "$ARC" ]] || die "boot archive missing: $ARC"
[[ -x "$QEMU" ]] || die "qemu binary missing/not executable: $QEMU"
[[ -f "$PAYLOAD_TAR" ]] || die "pinned payload tar missing: $PAYLOAD_TAR (deploy did not carry captures/)"
[[ "$(sha256sum "$SRC" | awk '{print $1}')" == "$SRC_SHA" ]] || die "source ISO hash mismatch"
[[ "$(sha256sum "$ARC" | awk '{print $1}')" == "$ARC_SHA" ]] || die "boot archive hash mismatch"
[[ "$(wc -c < "$ARC")" -eq $((ARC_LEN_SECTORS * 512)) ]] || die "boot archive size mismatch: expected $((ARC_LEN_SECTORS * 512)) bytes"
[[ "$(sha256sum "$QEMU" | awk '{print $1}')" == "$QEMU_SHA" ]] || die "QEMU binary hash mismatch"
[[ "$(sha256sum "$PAYLOAD_TAR" | awk '{print $1}')" == "$PAYLOAD_SHA" ]] || die "payload tar hash mismatch"
echo "  inputs OK"

step "preflight: no collision with any live Niagara QEMU (image-scoped, not broad pgrep)"
existing=$(real_pids 'qemu-system-sparc64.*-M niagara' | wc -l | tr -d ' ')
if [[ "$existing" != "0" ]]; then
    echo "  NOTE: $existing other niagara QEMU process(es) already running (e.g."
    echo "  primary R0). Expected for side-by-side rehearsal; this replay never"
    echo "  shares an image path, socket, PID, or subnet with them."
fi

step "preflight: ip_forward=1 (required for NAT/external-ping/DNS gates)"
fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)
[[ "$fwd" == "1" ]] || die "net.ipv4.ip_forward=$fwd -- required before boot; this script does not silently flip host-wide forwarding, fix it deliberately first (sysctl -w net.ipv4.ip_forward=1)"
echo "  ip_forward=1"

step "preflight: proven NFS export exists as a base for a transient client ACL"
# Unprivileged `exportfs` cannot read /var/lib/nfs state on this host (fails
# with EACCES on the etab lock, but exits 0 -- a silent false negative that
# once made this gate fail for the wrong reason). Always query via sudo -n
# (non-interactive; every exportfs read/write in this script uses -n so a
# missing sudoers NOPASSWD entry fails loud here, not with a silent auth
# prompt hang deep in a later step).
sudo -n exportfs 2>/dev/null | grep -qF "$NFS_EXPORT_DIR" \
    || die "$NFS_EXPORT_DIR is not exported at all -- this replay only ADDS a transient client ACL to an existing export, it does not create one from scratch. Confirm the proven /home/niagara/nfs-oi export is intact."
if sudo -n exportfs -s 2>/dev/null | grep -F "$NFS_EXPORT_DIR" | grep -q "$GUEST_IP"; then
    die "an export ACL for $GUEST_IP already exists on $NFS_EXPORT_DIR -- a prior run's teardown likely failed; clean it up manually (sudo exportfs -u $GUEST_IP:$NFS_EXPORT_DIR) before retrying"
fi
echo "  base export present, no stale $GUEST_IP ACL"

step "preflight: no stale scoped NAT rule (mirrors the NFS ACL gate above)"
# A pre-existing exact-match MASQUERADE rule for this rehearsal subnet is
# evidence of a failed prior teardown, exactly like a stale NFS ACL above --
# not a benign "someone else's rule" to silently reuse or delete out from
# under. Full mode must never adopt or clean up unexplained prior state; it
# only ever owns a rule IT added itself in THIS run. Die here, loud, with
# the same manual-cleanup guidance as the NFS ACL gate.
NAT_WAN="$(ip route show default | awk '{print $5}' | head -1)"
[[ -n "$NAT_WAN" ]] || die "no default route on this host -- cannot prove external ping/DNS gates"
sudo -n iptables -t nat -C POSTROUTING -s "$GUEST_IP/32" -o "$NAT_WAN" -j MASQUERADE 2>/dev/null \
    && die "a scoped MASQUERADE rule for $GUEST_IP -> $NAT_WAN already exists -- a prior run's teardown likely failed; clean it up manually (sudo iptables -t nat -D POSTROUTING -s $GUEST_IP/32 -o $NAT_WAN -j MASQUERADE) before retrying"
echo "  no stale $GUEST_IP -> $NAT_WAN MASQUERADE rule"

if [[ "$MODE" == runtime-preflight ]]; then
    echo
    echo "RUNTIME-PREFLIGHT-ONLY PASSED. All live prerequisites for a full replay"
    echo "are present and verified read-only: tools, sudo -n, pinned input"
    echo "hashes, no QEMU/image collision, ip_forward=1, base NFS export intact,"
    echo "no leftover rehearsal ACL. NOTHING was booted, and no iptables rule or"
    echo "NFS ACL was added -- this mode never mutates host state. Run without"
    echo "any flag for the full replay."
    exit 0
fi

step "build fresh disposable R0 (never reuses a mutated prior deploy)"
R0="$IMAGES/basecamp-r0-rehearsal-${TS}.iso"
cp --reflink=always -- "$SRC" "$R0"
cmp -s "$SRC" "$R0" || die "reflink differs from source immediately after copy"
dd if="$ARC" of="$R0" bs=512 seek="$ARC_OFFSET_SECTOR" conv=notrunc status=none
[[ "$(dd if="$R0" bs=512 skip="$ARC_OFFSET_SECTOR" count="$ARC_LEN_SECTORS" status=none | sha256sum | awk '{print $1}')" \
   == "$ARC_SHA" ]] || die "spliced archive region does not match"
echo "  R0 = $R0"
sha256sum "$R0"
record_milestone IMAGE_BUILT

step "preflight: this exact image path is not already open by any QEMU"
# `real_pids ... | while read; do ...; done` exhausts its input with no
# matches in the normal case: `read` returns 1 on EOF, which is the last
# command executed in the while's own condition, so the loop's exit status
# is 1 even though "zero matches" is success, not failure. Under
# `set -euo pipefail`, `holders=$(...)` then aborted the WHOLE SCRIPT before
# the `[[ -z "$holders" ]] || die` line below ever ran -- no die() message,
# no diagnostic, just a silent kill. `|| true` on the assignment itself
# fixes exactly this: it does not affect what gets captured into $holders
# (a real match's PID is still echoed into the substitution and still
# collected) -- it only prevents the empty/no-match case's nonzero loop
# status from being treated as a script-ending error. The actual rejection
# of a genuine collision still happens on the next line, unchanged.
holders=$(real_pids 'qemu-system-sparc64' | while read -r p; do
    [[ -r "/proc/$p/cmdline" ]] || continue
    cmdline=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    if [[ "$cmdline" == *"$R0"* ]]; then
        echo "$p"
    fi
done) || true
[[ -z "$holders" ]] || die "impossible: fresh image already open by PID(s) $holders"
echo "  clear"

step "deploy: unique run dir, scoped sockets, detached stdio (qemu-owner.sh)"
MONITOR="$RUNDIR/monitor.sock"
SERIAL="$RUNDIR/serial.sock"
CHANSOCK="$RUNDIR/niag0.sock"      # scoped, never global /run/niag0
PPPLOG="$RUNDIR/pppd.log"
BRIDGELOG="$RUNDIR/bridge0.log"
TEARDOWN="$RUNDIR/teardown.sh"

# Single source of truth for the QEMU invocation: build it once as an array,
# then use THAT SAME ARRAY both to launch qemu-owner.sh and to derive the
# manifest's recorded argv. Two independently-typed argv strings (one for
# the real launch, one for the manifest) can silently drift the moment
# either one is edited without the other; an array launched via "${arr[@]}"
# and serialized via printf %q per-element cannot drift, by construction.
QEMU_ARGV=("$QEMU" -M niagara -L "$FW" -m 1024 -nographic \
    -monitor "unix:$MONITOR,server=on,wait=off" \
    -serial "unix:$SERIAL,server=on,wait=off" \
    -drive "if=pflash,file=$R0,format=raw")
# Lossless, shell-re-parseable serialization (each element %q-quoted, space-
# joined) -- distinct from a plain "${QEMU_ARGV[*]}" join, which reproduces
# exactly the unquoted-spaces defect this fix exists to close.
QEMU_ARGV_SERIALIZED=$(printf '%q ' "${QEMU_ARGV[@]}")
QEMU_ARGV_SERIALIZED=${QEMU_ARGV_SERIALIZED% }

# HARD POLICY (Ryan): every QEMU worker must run inside a uniquely named,
# attachable tmux session -- so a human can `tmux attach -t <name>` on the
# same host at any time, independent of this script's own process tree.
# Session name is derived from the same $TS as RUNDIR/R0 -- guaranteed
# unique per run, no separate counter to keep in sync.
#
# TWO windows, not one: ancestry of QPID alone does not satisfy the
# watch-along intent -- the qemu-owner window has no visible output (QEMU's
# serial console is a Unix socket, not a tty QEMU writes to directly), so a
# human attaching to it sees nothing happening. The second window tails
# THIS RUN'S OWN replay.log (a plain file `tail -F` never touches the serial
# socket) so there is always a live, readable transcript. This must NEVER
# open a second serial client while `expect` (via r0-obp-boot-and-login.exp
# / r0-guest-command.exp) owns $SERIAL -- tailing a file is safe precisely
# because it does not compete for that single-consumer socket.
command -v tmux >/dev/null || die "tmux is required (hard launch policy: every QEMU worker must run inside a named tmux session)"
TMUX_SESSION_NAME="r0-rehearsal-${TS}"
TMUX_WINDOW_NAME="qemu-owner"
TMUX_REPLAY_WINDOW_NAME="replay"
tmux new-session -d -s "$TMUX_SESSION_NAME" -n "$TMUX_WINDOW_NAME" \
    "bash '$OI/qemu-owner.sh' '$RUNDIR' -- ${QEMU_ARGV_SERIALIZED}" \
    || die "tmux new-session failed for $TMUX_SESSION_NAME"
tmux new-window -t "$TMUX_SESSION_NAME" -n "$TMUX_REPLAY_WINDOW_NAME" \
    "tail -F '$REPLAY_LOG'" \
    || die "tmux new-window (replay transcript) failed for $TMUX_SESSION_NAME"
echo "  tmux session=$TMUX_SESSION_NAME  windows: $TMUX_WINDOW_NAME (qemu-owner, no visible output -- serial is a socket), $TMUX_REPLAY_WINDOW_NAME (live replay.log transcript)"
echo "  attach:            tmux attach -t $TMUX_SESSION_NAME"
echo "  select owner win:  tmux select-window -t $TMUX_SESSION_NAME:$TMUX_WINDOW_NAME"
echo "  select replay win: tmux select-window -t $TMUX_SESSION_NAME:$TMUX_REPLAY_WINDOW_NAME"
echo "  DO NOT open a second serial client (socat/expect) against \$SERIAL while this run owns it;"
echo "  an interactive serial window may be attached only AFTER FINAL_PASS releases the socket."
sleep 2
tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null \
    || die "tmux session $TMUX_SESSION_NAME did not survive startup"
tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -qx "$TMUX_WINDOW_NAME" \
    || die "tmux window $TMUX_WINDOW_NAME missing from session $TMUX_SESSION_NAME"
tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' 2>/dev/null | grep -qx "$TMUX_REPLAY_WINDOW_NAME" \
    || die "tmux replay window $TMUX_REPLAY_WINDOW_NAME missing from session $TMUX_SESSION_NAME"
echo "  both tmux windows confirmed present: $TMUX_WINDOW_NAME, $TMUX_REPLAY_WINDOW_NAME"
OWNER_PID=$(cat "$RUNDIR/qemu-owner.pid" 2>/dev/null) \
    || die "qemu-owner did not start (no $RUNDIR/qemu-owner.pid)"
kill -0 "$OWNER_PID" 2>/dev/null || die "qemu-owner did not start"
QPID=$(cat "$RUNDIR/qemu.pid" 2>/dev/null || true)
[[ -n "$QPID" ]] || die "qemu.pid was not written by qemu-owner.sh"
kill -0 "$QPID" 2>/dev/null || die "QEMU worker (PID $QPID) is not alive"

# POST-LAUNCH ASSERTION (hard policy): prove QPID actually descends from the
# tmux pane we just created, not merely that a same-named session exists
# alongside an unrelated QEMU. Walk /proc/<QPID>/status's PPid chain until it
# either reaches the tmux pane's own shell PID (owner_chain hit) or exhausts
# (PPid=0 / pid 1), which fails closed rather than assuming success.
TMUX_PANE_PID=$(tmux list-panes -t "$TMUX_SESSION_NAME:$TMUX_WINDOW_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
[[ -n "$TMUX_PANE_PID" ]] || die "could not read tmux pane PID for $TMUX_SESSION_NAME"
descends_from_pane=0
walk_pid=$QPID
for _ in $(seq 1 20); do
    [[ "$walk_pid" == "$TMUX_PANE_PID" ]] && { descends_from_pane=1; break; }
    ppid=$(awk '/^PPid:/{print $2}' "/proc/$walk_pid/status" 2>/dev/null) || break
    [[ -n "$ppid" && "$ppid" != "0" && "$ppid" != "1" ]] || break
    walk_pid=$ppid
done
[[ "$descends_from_pane" == 1 ]] \
    || die "QEMU PID $QPID does not descend from tmux pane $TMUX_PANE_PID (session $TMUX_SESSION_NAME) -- hard launch policy violated"
echo "  tmux descent proof OK: QPID=$QPID descends from pane PID=$TMUX_PANE_PID (session $TMUX_SESSION_NAME)"

echo "  owner PID=$OWNER_PID  qemu PID=$QPID  RUNDIR=$RUNDIR"
record_milestone QEMU_STARTED

step "deterministic boot: OBP -> boot disk -v -> root/root maintenance login"
expect -f "$OI/r0-obp-boot-and-login.exp" "$SERIAL" "$BOOT_TIMEOUT" \
    || die "OBP boot / maintenance login did not reach a shell"
echo "  MAINTENANCE_SHELL_READY"
record_milestone MAINTENANCE_SHELL

step "dynamic HSFS media discovery (never assume a fixed guest disk ID)"
# Re-enumerate per invariant #13. Use the PROVEN fstyp path
# (/usr/lib/fs/hsfs/fstyp), not a bare `fstyp`: at the maintenance prompt,
# before /usr is mounted, PATH may not include /usr/sbin or /usr/lib/fs/*,
# so a bare `fstyp` can report "not found" rather than an fstyp verdict --
# a silent false negative that would fail discovery for the wrong reason.
DISCOVER_CMD='n=0;g=;for d in /dev/rdsk/*s2;do /usr/lib/fs/hsfs/fstyp $d 2>/dev/null|grep -q ^hsfs&&{ g=$d;n=$((n+1));};done;echo FOUND:$g:COUNT:$n'
disc_out=$(guest_cmd "$SERIAL" "$DISCOVER_CMD" 60) || die "HSFS discovery command failed"
GUEST_DEV=$(printf '%s\n' "$disc_out" | grep -oE 'FOUND:[^:]*:COUNT:[0-9]+' | tail -1 | sed 's/FOUND:\(.*\):COUNT:.*/\1/') || true
DISC_COUNT=$(printf '%s\n' "$disc_out" | grep -oE 'COUNT:[0-9]+' | tail -1 | cut -d: -f2) || true
[[ -n "$GUEST_DEV" ]] || die "no HSFS media device discovered on this boot (raw output: $disc_out)"
[[ "$DISC_COUNT" == "1" ]] || die "expected exactly one HSFS-typed s2 device, found $DISC_COUNT (raw output: $disc_out)"
# Raw (character) device for dd/channel I/O; block device for mount(1M) --
# Solaris/illumos mount(2) requires the block node, not the raw node.
GUEST_DEV_BLOCK=${GUEST_DEV/\/dev\/rdsk\//\/dev\/dsk\/}
[[ "$GUEST_DEV_BLOCK" != "$GUEST_DEV" ]] || die "internal error: could not derive block device from $GUEST_DEV"
echo "  discovered HSFS device (unique): raw=$GUEST_DEV block=$GUEST_DEV_BLOCK"

step "/.cdrom mount + verify solaris.zlib presence"
guest_cmd "$SERIAL" "mkdir -p /.cdrom && mount -F hsfs -o ro $GUEST_DEV_BLOCK /.cdrom" 60 \
    || die "mount /.cdrom failed"
guest_cmd "$SERIAL" 'test -f /.cdrom/solaris.zlib && echo ZLIB_PRESENT' 15 \
    || die "/.cdrom/solaris.zlib not present after mount -- wrong media or discovery picked the wrong device"
echo "  /.cdrom mounted, solaris.zlib present"

step "attach solaris.zlib and mount /usr from the DYNAMICALLY assigned lofi node"
lofi_out=$(guest_cmd "$SERIAL" 'lofiadm -a /.cdrom/solaris.zlib' 30) \
    || die "lofiadm attach failed"
LOFI_DEV=$(printf '%s\n' "$lofi_out" | grep -oE '/dev/lofi/[0-9]+' | head -1) || true
[[ -n "$LOFI_DEV" ]] || die "lofiadm did not report an assigned device (raw output: $lofi_out)"
echo "  lofiadm assigned: $LOFI_DEV"
guest_cmd "$SERIAL" "mount -F hsfs -o ro $LOFI_DEV /usr" 60 \
    || die "mount /usr failed"
echo "  /usr mounted"

step "DTrace exact-probe-count gate: asserted INSIDE the guest command"
# `wc -l`'s output can be left-padded with spaces (observed live on this
# guest's `wc -l`), so the raw n="  72893" failed the numeric `-eq` test AND
# printed "DTRACE_OK: 72893" (space before the digits) -- which then also
# failed the host-side grep's exact `DTRACE_OK:72893` pattern, masking a
# correct probe count as a false failure. `tr -d ' '` strips the padding
# in-guest, before either the numeric compare or the echoed marker, so the
# marker text and the exact-match grep on the host side agree byte-for-byte
# whenever the count is genuinely right.
DTRACE_CMD="n=\$(dtrace -l|wc -l|tr -d ' ');[ \"\$n\" -eq $DTRACE_EXPECT ]&&echo DTRACE_OK:\$n||echo DTRACE_BAD:\$n"
[[ ${#DTRACE_CMD} -le 200 ]] || die "internal error: DTRACE_CMD exceeds 200 chars (${#DTRACE_CMD})"
dt_out=$(guest_cmd "$SERIAL" "$DTRACE_CMD" 60) || die "dtrace assertion command failed"
# The captured serial stream carries CRLF (observed live: "DTRACE_OK:72893\r\r\n"),
# and relying on a `\r` escape inside an ERE (`grep -E ... DTRACE_OK:$DTRACE_EXPECT\r`)
# to match that literal CR is not portable across grep/glibc regex builds --
# it silently failed to match a genuinely correct DTRACE_OK:72893 on this
# exact host, masking a real pass as a false failure. Strip ALL \r first
# (tr -d '\r'), then anchor an EXACT match against the clean, CR-free text;
# the numeric assertion itself (DTRACE_EXPECT) is unchanged and still exact.
dt_out_clean=$(printf '%s\n' "$dt_out" | tr -d '\r')
printf '%s\n' "$dt_out_clean" | grep -qE "^DTRACE_OK:$DTRACE_EXPECT\$" \
    || { dt_bad=$(printf '%s\n' "$dt_out_clean" | grep -oE 'DTRACE_(OK|BAD):[0-9]+' | tail -1) || true; \
         die "DTrace probe count assertion failed (guest reported: ${dt_bad:-none}, raw: $dt_out)"; }
echo "  DTrace probes = $DTRACE_EXPECT (exact, asserted in-guest)"
record_milestone DTRACE

# ---------------------------------------------------------------------------
# POST-BOOT payload staging. CHAN_BOOTSTRAP_BLOCK sits inside the boot-archive
# extent, so its bytes are only safe to overwrite once boot has ALREADY
# consumed the archive into guest RAM. Never move this earlier. The tar
# itself is the pinned proven artifact (see PAYLOAD_SHA above).
step "stage the pinned proven payload POST-BOOT at sector $CHAN_BOOTSTRAP_BLOCK"
dd if="$PAYLOAD_TAR" of="$R0" bs=512 seek="$CHAN_BOOTSTRAP_BLOCK" conv=notrunc status=none
readback_sha=$(dd if="$R0" bs=512 skip="$CHAN_BOOTSTRAP_BLOCK" count="$PAYLOAD_SECTORS" status=none | sha256sum | awk '{print $1}')
[[ "$readback_sha" == "$PAYLOAD_SHA" ]] || die "host-side readback of staged payload does not match pinned hash"
echo "  host-side staging verified; $R0 is now single-use (boot archive region mutated by design)"

step "guest extraction via iseek (never skip= on a raw character device)"
EXTRACT_CMD="dd if=$GUEST_DEV of=/tmp/bootstrap.tar bs=512 iseek=$CHAN_BOOTSTRAP_BLOCK count=$PAYLOAD_SECTORS"
guest_cmd "$SERIAL" "$EXTRACT_CMD" 60 || die "guest-side dd iseek extraction failed"
guest_digest_out=$(guest_cmd "$SERIAL" 'digest -a sha256 /tmp/bootstrap.tar' 30) \
    || die "guest digest command failed"
guest_sha=$(printf '%s\n' "$guest_digest_out" | grep -oE '[0-9a-f]{64}' | head -1) || true
[[ "$guest_sha" == "$PAYLOAD_SHA" ]] || die "guest-extracted tar hash $guest_sha != pinned $PAYLOAD_SHA"
echo "  guest extraction verified byte-identical to pinned payload"

guest_cmd "$SERIAL" 'mkdir -p /tmp/bs && tar xf /tmp/bootstrap.tar -C /tmp/bs' 30 \
    || die "guest tar extraction failed"

step "per-member hash assertion, then chmod +x (proven tar ships members at 0644)"
for m in "${!PAYLOAD_MEMBER_SHA[@]}"; do
    mout=$(guest_cmd "$SERIAL" "digest -a sha256 /tmp/bs/$m" 20) || die "guest digest failed for $m"
    got=$(printf '%s\n' "$mout" | grep -oE '[0-9a-f]{64}' | head -1) || true
    [[ "$got" == "${PAYLOAD_MEMBER_SHA[$m]}" ]] || die "member $m guest-side hash $got != pinned ${PAYLOAD_MEMBER_SHA[$m]}"
done
echo "  all ${#PAYLOAD_MEMBER_SHA[@]} member hashes verified in-guest"
for m in $PAYLOAD_EXEC_MEMBERS; do
    guest_cmd "$SERIAL" "chmod 755 /tmp/bs/$m" 15 || die "chmod 755 failed for $m"
    # Capture the FULL producer output into a variable first (own transport
    # `|| die`), THEN string-match against it -- never pipe expect's writer
    # straight into `grep -q`. `grep -q` exits the instant it sees a match,
    # closing its end of the pipe; under `set -o pipefail` that is often
    # harmless, but the expect wrapper's own `puts $expect_out(buffer)` can
    # still be mid-write when the reader vanishes, producing a real SIGPIPE
    # ("broken pipe") in the *expect* process itself -- exactly what was
    # observed live -- which can corrupt/truncate the very output this
    # gate is trying to read, causing a false "not executable" verdict
    # even though chmod succeeded. Capturing to a variable lets expect's
    # writer run to completion every time, and keeps "transport/command
    # failed" (guest_cmd's own exit status) distinct from "ran fine but the
    # marker is missing" (the string test below).
    exec_out=$(guest_cmd "$SERIAL" "test -x /tmp/bs/$m && echo EXEC_OK" 15) \
        || die "guest_cmd transport/command failed while checking $m is executable"
    [[ "$exec_out" == *EXEC_OK* ]] || die "$m is still not executable after chmod"
done
echo "  guest-chand, guest-echocli, guest-ppp-chan.pl confirmed executable"

step "scoped channel bootstrap (never a global socket)"
# init only needs read-write on the image file, which this run's own user
# already owns (R0 was just created by this script) -- no sudo required.
NIAGARA_IMG="$R0" NIAG_CHAN_HOST_BYTE="$CHAN_HOST_BYTE" \
    python3 "$CHAN/host-chan.py" init 0 || die "host-chan.py init failed"
# Unprivileged: same reasoning as init above, and the bridge only needs to
# read/write $R0 (owned by this user) and create $CHANSOCK under $RUNDIR
# (also owned by this user) -- no root required, so no self-report needed;
# $! from launch_owned with no wrapper IS the exact worker PID.
BRIDGE_PID=$(launch_owned "$BRIDGELOG" "" \
    env NIAGARA_IMG="$R0" NIAG_CHAN_HOST_BYTE="$CHAN_HOST_BYTE" \
    python3 "$CHAN/host-chan.py" bridge 0 "$CHANSOCK") \
    || die "scoped host-chan.py bridge did not start, see $BRIDGELOG"
sleep 2
kill -0 "$BRIDGE_PID" 2>/dev/null || die "scoped host-chan.py bridge PID $BRIDGE_PID is not alive, see $BRIDGELOG"
[[ -S "$CHANSOCK" ]] || die "scoped channel socket $CHANSOCK was not created"
echo "  bridge PID=$BRIDGE_PID (exact, unprivileged worker)  socket=$CHANSOCK"

# Composed as ONE valid background command followed by an explicit marker
# command after the `&` (never a bare trailing `&` at end-of-string, which
# broke as "-bash: syntax error near unexpected token `;'" once the expect
# wrapper appended its own `; niag_rc=$?; echo NIAG_COMMAND_END:$niag_rc`
# suffix -- `cmd &; more` is invalid bash, but `cmd & echo MARKER` is not,
# and composes safely with anything appended after it). `</dev/null` makes
# the backgrounded worker's detached stdin explicit rather than inherited.
# Capturing the output and requiring the EXACT launch marker means a
# transport/syntax failure (guest_cmd itself failing, or no marker at all)
# is a distinct, differently-worded die() from the later liveness check
# below (guest-chand did not create /tmp/niag0).
CHAND_LAUNCH_CMD="NIAG_CHAN_DEV=$GUEST_DEV nohup /tmp/bs/guest-chand 0 /tmp/niag0 </dev/null >/tmp/chand0.log 2>&1 & echo CHAND_LAUNCHED"
[[ ${#CHAND_LAUNCH_CMD} -le 200 ]] || die "internal error: CHAND_LAUNCH_CMD exceeds 200 chars (${#CHAND_LAUNCH_CMD})"
chand_launch_out=$(guest_cmd "$SERIAL" "$CHAND_LAUNCH_CMD" 20) \
    || die "guest-chand launch command failed (transport/syntax)"
[[ "$chand_launch_out" == *CHAND_LAUNCHED* ]] \
    || die "guest-chand launch did not report CHAND_LAUNCHED (raw: $chand_launch_out)"
sleep 2
chand_out=$(guest_cmd "$SERIAL" 'test -S /tmp/niag0 && echo CHAND_SOCK_OK' 10) \
    || die "guest_cmd transport/command failed while checking for /tmp/niag0"
[[ "$chand_out" == *CHAND_SOCK_OK* ]] \
    || die "guest-chand did not create /tmp/niag0 -- check chmod/exec above and /tmp/chand0.log"

step "PRE-PROTOCOL GATE: exact framed channel echo, before any PPP (acceptance ladder step 5)"
# A ping over PPP is not a substitute for this: it proves LCP/IPCP/routing,
# not that the raw channel framing itself round-trips byte-exact. Prove the
# channel in isolation first, exactly as the proven Basecamp session did.
guest_cmd "$SERIAL" 'nohup /tmp/bs/guest-echocli /tmp/niag0 >/tmp/echocli0.log 2>&1 & echo ECHOCLI_PID:$!' 15 \
    || die "guest-echocli launch failed"
sleep 2
echocli_out=$(guest_cmd "$SERIAL" 'pgrep -x guest-echocli >/dev/null && echo ECHOCLI_UP' 10) \
    || die "guest_cmd transport/command failed while checking guest-echocli is running"
[[ "$echocli_out" == *ECHOCLI_UP* ]] \
    || die "guest-echocli did not stay running -- see /tmp/echocli0.log"

NIAG_CHAN_SOCK="$CHANSOCK" python3 "$CHAN/chan-test.py" 0 "$CHAN_TEST_SIZE" \
    || die "framed channel echo test FAILED -- do not proceed to PPP on an unproven channel"
echo "  framed echo round-trip verified ($CHAN_TEST_SIZE bytes, byte-exact)"
record_milestone CHANNEL_ECHO

# Terminate the echo client cleanly and verify guest-chand's accept slot is
# free again before handing the channel to pppd -- guest-chand serves one
# client at a time (see guest-chand.c's outer accept() loop); a lingering
# echocli would make the next accept() by pppd's peer hang or ENOENT.
gone_out=$(guest_cmd "$SERIAL" 'pkill -x guest-echocli; sleep 1; pgrep -x guest-echocli >/dev/null || echo ECHOCLI_GONE' 15) \
    || die "guest_cmd transport/command failed while terminating guest-echocli"
[[ "$gone_out" == *ECHOCLI_GONE* ]] \
    || die "guest-echocli did not terminate cleanly -- refusing to start PPP on a channel that may still be held"
echo "  echo client terminated; channel accept slot confirmed free"

step "isolated PPP on scoped channel 0 (subnet $HOST_IP<->$GUEST_IP, distinct from primary R0's 10.0.5.x)"
guest_cmd "$SERIAL" '/usr/sbin/devfsadm -i sppp -i sppptun' 30 \
    || die "devfsadm sppp/sppptun failed"
# Same fix as guest-chand above: one valid background command followed by
# an explicit marker after `&` (never a bare trailing `&`), `</dev/null`
# for explicit detached stdin, and the launch marker captured+required so
# a transport/syntax failure is distinct from a later liveness failure.
GPPP_LAUNCH_CMD="nohup /tmp/bs/guest-ppp-chan.pl 0 $GUEST_IP:$HOST_IP </dev/null >/tmp/gppp0.log 2>&1 & echo GPPP_LAUNCHED"
[[ ${#GPPP_LAUNCH_CMD} -le 200 ]] || die "internal error: GPPP_LAUNCH_CMD exceeds 200 chars (${#GPPP_LAUNCH_CMD})"
gppp_launch_out=$(guest_cmd "$SERIAL" "$GPPP_LAUNCH_CMD" 20) \
    || die "guest-ppp-chan.pl launch command failed (transport/syntax)"
[[ "$gppp_launch_out" == *GPPP_LAUNCHED* ]] \
    || die "guest-ppp-chan.pl launch did not report GPPP_LAUNCHED (raw: $gppp_launch_out)"

# GUEST READINESS GATE, before any host-side dial-in. guest-ppp-chan.pl's
# own connect-retry loop (see its comment: "RETRY, do not die: at boot the
# guest reaches this long before the host bridge exists") only proves it
# reached the bridge; it says nothing about whether its own exec("pppd",
# ...) actually happened afterward. Evidence found in Run #6: the bridge
# recorded a second "client connected" (the guest-side channel handshake
# genuinely completed), yet the HOST pppd still hung up 498ms after
# connect -- consistent with the guest's own pppd not yet running when the
# host began LCP negotiation. Poll for the guest's own pppd process
# (`pgrep -x pppd`), not merely the perl wrapper, with the same
# capture-then-marker pattern as every other guest_cmd site (never a bare
# `guest_cmd | grep` pipe). On failure, capture BOTH of guest-ppp-chan.pl's
# own documented evidence files before die(): /tmp/gppp0.log (this script's
# own redirected stdout/stderr for the perl launch) and /tmp/gppp-chan0.log
# (the perl script's OWN stderr, opened explicitly via `open(STDERR, '>',
# $log)` in guest-ppp-chan.pl) -- these are two DIFFERENT files, not a typo.
guest_pppd_ready=0
for _ in $(seq 1 10); do
    # `pgrep -x pppd >/dev/null && echo GUEST_PPPD_UP` returns pgrep's own
    # exit status (1) on no-match via `&&` short-circuit, and the expect
    # wrapper faithfully propagates that as guest_cmd's own nonzero
    # return -- indistinguishable from a genuine transport failure, and
    # exactly what tripped the outer `|| die` on Retry #7 even though the
    # guest was simply not ready YET, not broken. Explicit if/else always
    # emits a marker and always exits 0: WAIT is a normal, expected
    # polling state, never a guest_cmd failure.
    gpppd_out=$(guest_cmd "$SERIAL" 'if pgrep -x pppd >/dev/null; then echo GUEST_PPPD_UP; else echo GUEST_PPPD_WAIT; fi' 10) \
        || die "guest_cmd transport/command failed while polling for guest pppd readiness"
    if [[ "$gpppd_out" == *GUEST_PPPD_UP* ]]; then
        guest_pppd_ready=1
        break
    fi
    sleep 1
done
if [[ "$guest_pppd_ready" -ne 1 ]]; then
    gppp_log_out=$(guest_cmd "$SERIAL" 'cat /tmp/gppp0.log 2>/dev/null; echo GPPP_LOG_END' 15) || true
    gppp_wait_out=$(guest_cmd "$SERIAL" 'cat /tmp/gppp-chan0.wait 2>/dev/null; echo GPPP_WAIT_END' 15) || true
    gppp_chan_log_out=$(guest_cmd "$SERIAL" 'cat /tmp/gppp-chan0.log 2>/dev/null; echo GPPP_CHAN_LOG_END' 15) || true
    gpppd_chan_log_out=$(guest_cmd "$SERIAL" 'cat /tmp/gpppd-chan0.log 2>/dev/null; echo GPPPD_CHAN_LOG_END' 15) || true
    die "guest-side pppd never became visible via pgrep -x pppd after guest-ppp-chan.pl launch (guest not ready for host dial-in) -- /tmp/gppp0.log: ${gppp_log_out:-none} -- /tmp/gppp-chan0.wait: ${gppp_wait_out:-none} -- /tmp/gppp-chan0.log: ${gppp_chan_log_out:-none} -- /tmp/gpppd-chan0.log: ${gpppd_chan_log_out:-none}"
fi
echo "  guest-side pppd confirmed running (pgrep -x pppd) before host dial-in"

# HOST PPP LAUNCH: host-up.sh PARITY, not the prior self-report pattern.
# host-up.sh (the proven-working reference; see its own executable order,
# not its comments) launches PPP as a bare `setsid nohup socat ...
# EXEC:'pppd ...',nofork &` directly in ITS OWN already-root shell -- no
# per-command sudo, no self-report wrapper, because host-up.sh itself runs
# as root throughout. This script is unprivileged and needs sudo per
# command, so `sudo -n` prefixes the same bare invocation; PPPD_LAUNCH_PID
# is `$!` from that background job, and it is explicitly the WRAPPER pid
# (sudo's own child), never called "the worker" -- socat's `nofork` on the
# EXEC address calls execvp() directly (confirmed via `man socat` locally:
# "Does not fork a subprocess for executing the program, instead calls
# execvp() or system() directly from the actual socat instance"), so
# PPPD_LAUNCH_PID becomes socat's PID via exec, and MAY further become
# pppd's own PID via socat's own exec -- but pppd itself can still fork
# internally (observed live on primary R0: sudo/socat 717683 -> pppd child
# 717688 -> pppd grandchild 717692, the innermost of which holds the real
# channel-socket fd). PPPD_LAUNCH_PID is therefore tracked ONLY as "the
# process we launched" for liveness/cleanup bookkeeping -- the actual
# socket peer and its live parent are re-derived below via
# resolve_unix_peer(), never assumed from the launch PID.
#
# debug + logfile added (Linux pppd 2.4.9 confirmed to support both via
# `man pppd` on niagara-playbox itself; guest-ppp-chan.pl already uses
# `logfile` for the guest-side pppd, so this is proven-supported usage,
# not new surface): a genuine future hangup now has its own pppd-level
# diagnostic trail in $PPPD_DEBUG_LOG, distinct from $PPPLOG (the launch
# wrapper's own redirected stdout/stderr) -- shell redirection and pppd's
# `logfile` option must NEVER target the same path: pppd's `logfile` opens
# its own fd independently from a fresh cold state, and having the shell
# ALSO redirect that same path from the wrapper side is two independent
# writers racing on one file (truncation-on-open vs append, buffering
# differences) -- exactly the kind of unverified-but-plausible assumption
# this project's own standing rule forbids. Two distinct files, always.
PPPD_DEBUG_LOG="$RUNDIR/pppd-debug.log"
sudo -n setsid nohup socat UNIX-CONNECT:"$CHANSOCK" \
    "EXEC:'/usr/sbin/pppd notty noauth local noccp nodeflate nobsdcomp novj asyncmap 0xffffffff lcp-echo-interval 0 lcp-echo-failure 0 debug logfile ${PPPD_DEBUG_LOG} ${HOST_IP}:${GUEST_IP} nodetach',nofork" \
    > "$PPPLOG" 2>&1 < /dev/null &
PPPD_LAUNCH_PID=$!
echo "  PPP launch wrapper PID=$PPPD_LAUNCH_PID (sudo/setsid/socat chain, NOT the worker)  wrapper log=$PPPLOG  pppd debug log=$PPPD_DEBUG_LOG"

step "verify QEMU worker still alive, then use SIGUSR2 exactly like host-up.sh's proven sync gate"
# Moved to immediately after the PPP launch wrapper starts (and BEFORE the
# host->guest link-up wait): host-up.sh's own proven executable order
# (read directly, not its comments) signals QEMU 3s after PPP start, before
# any peer-resolution or link-up wait. Preserved exactly here.
#
# No host-PPP liveness gate runs before this sync point (recording
# PPPD_LAUNCH_PID above is bookkeeping only, not a gate) -- host-up.sh's
# own proven order has NOTHING between starting PPP and the sleep-3/SIGUSR2
# pair, and inserting a liveness check there is not something the working
# reference does.
#
# QPID is ALREADY the exact real worker this run itself launched via
# qemu-owner.sh -- no rediscovery, no pgrep-by-image-substring here (that
# broad-match approach is what host-up.sh's own history flagged as the bug:
# matching "qemu-system-sparc64" also matched sudo/setsid WRAPPER argv).
# Since this run owns QPID directly from qemu.pid, signal it directly and
# treat a failed signal as a hard gate.
sleep 3
kill -0 "$QPID" 2>/dev/null || die "QEMU worker PID $QPID died before the post-PPP sync point"
kill -USR2 "$QPID" || die "SIGUSR2 to the owned QEMU worker (PID $QPID) failed -- treating as a gate, not a soft warning"
sleep 1
kill -0 "$QPID" 2>/dev/null || die "QEMU worker PID $QPID did not survive SIGUSR2"
echo "  SIGUSR2 delivered to owned worker PID $QPID; still alive"

# PEER RESOLUTION: discover the ANONYMOUS peer of $CHANSOCK and that peer's
# live parent, via inode cross-linking in one captured `ss -H -x -p` table
# (resolve_unix_peer() above; already validated read-only against primary
# R0's live link before being wired in here: /run/niag0 -> peer 717692,
# parent 717688). PPPD_PEER_PID is the process actually holding the
# connected socket fd (the innermost pppd); PPPD_PID is its live parent,
# tracked separately so cleanup/manifest can terminate the real ownership
# chain (wrapper, parent, peer) without ever assuming PPPD_LAUNCH_PID
# itself is either of them.
resolved=$(resolve_unix_peer "$CHANSOCK") \
    || die "could not resolve the anonymous peer of $CHANSOCK via ss inode cross-linking -- see stderr above"
PPPD_PEER_PID=$(awk '{print $1}' <<< "$resolved")
PPPD_PID=$(awk '{print $2}' <<< "$resolved")
[[ "$PPPD_PEER_PID" =~ ^[0-9]+$ && "$PPPD_PID" =~ ^[0-9]+$ ]] \
    || die "resolve_unix_peer returned unparseable output: $resolved"
pid_alive "$PPPD_PEER_PID" \
    || die "resolved peer PID $PPPD_PEER_PID is not alive -- refusing to trust a stale/exited process"
pid_alive "$PPPD_PID" \
    || die "resolved parent PID $PPPD_PID is not alive -- refusing to trust a stale/exited process"

# Ancestry check: PPPD_LAUNCH_PID's own process image may have BECOME
# PPPD_PID or PPPD_PEER_PID via socat's `nofork` execvp() chain (bash ->
# socat -> pppd, same PID throughout, confirmed via `man socat` locally),
# so exact PID equality with either is the expected collapsed case, not a
# failure. If PPPD_LAUNCH_PID is still a DIFFERENT, still-alive PID (the
# multi-process case observed on primary R0: sudo/socat wrapper survives
# as its own PID while pppd forks separately), walk PPPD_PEER_PID's own
# ancestry chain (via `ps -o ppid=`) and require PPPD_LAUNCH_PID to appear
# in it -- proving the resolved peer genuinely descends from what this run
# itself launched, not an unrelated pppd elsewhere on the host.
if pid_alive "$PPPD_LAUNCH_PID"; then
    if [[ "$PPPD_LAUNCH_PID" != "$PPPD_PID" && "$PPPD_LAUNCH_PID" != "$PPPD_PEER_PID" ]]; then
        ancestor_found=0
        walk_pid="$PPPD_PEER_PID"
        for _ in $(seq 1 10); do
            [[ "$walk_pid" == "$PPPD_LAUNCH_PID" ]] && { ancestor_found=1; break; }
            walk_ppid=$(ps -o ppid= -p "$walk_pid" 2>/dev/null | tr -d ' ')
            [[ "$walk_ppid" =~ ^[0-9]+$ && "$walk_ppid" != "1" ]] || break
            walk_pid="$walk_ppid"
        done
        [[ "$ancestor_found" == "1" ]] \
            || die "resolved peer PID $PPPD_PEER_PID's ancestry does not trace back to launch wrapper PID $PPPD_LAUNCH_PID -- refusing to trust an unrelated pppd"
    fi
fi

# cmdline check: both the resolved parent and peer must actually BE pppd
# processes speaking THIS run's isolated rehearsal endpoints
# ($HOST_IP:$GUEST_IP, 10.0.6.x), and must NEVER match primary R0's proven
# 10.0.5.x link -- this is the hard guarantee that peer resolution cannot
# accidentally latch onto primary R0's own pppd chain.
for pid_to_check in "$PPPD_PID" "$PPPD_PEER_PID"; do
    cmdline=$(ps -o args= -p "$pid_to_check" 2>/dev/null)
    [[ "$cmdline" == *pppd* ]] \
        || die "resolved PID $pid_to_check's cmdline does not look like pppd: ${cmdline:-<empty, process gone>}"
    [[ "$cmdline" == *"${HOST_IP}:${GUEST_IP}"* ]] \
        || die "resolved PID $pid_to_check's cmdline does not carry this run's rehearsal endpoints ${HOST_IP}:${GUEST_IP}: $cmdline"
    [[ "$cmdline" != *"10.0.5."* ]] \
        || die "resolved PID $pid_to_check's cmdline references primary R0's 10.0.5.x subnet -- refusing to touch it: $cmdline"
done
echo "  pppd peer PID=$PPPD_PEER_PID  parent PID=$PPPD_PID  (resolved via ss inode cross-link, ancestry+cmdline validated, log=$PPPLOG)"

step "scoped NAT for the rehearsal subnet only (never touches primary R0's 10.0.5.15 rule)"
# NAT_WAN was already resolved and validated by the preflight gate above
# (which also proved no stale exact-match rule exists) -- no need to
# re-derive it or defensively delete-before-add here. Full mode adds
# exactly one rule and owns exactly what it added.
sudo -n iptables -t nat -A POSTROUTING -s "$GUEST_IP/32" -o "$NAT_WAN" -j MASQUERADE \
    || die "failed to add scoped NAT rule"
NAT_RULE_ADDED=1
echo "  nat: $GUEST_IP -> $NAT_WAN (masquerade, added and owned by this run)"

step "REQUIRED assertions: host->guest ping, guest->host ping, external ping, DNS"
link_up=0
for _ in $(seq 1 20); do
    if ping -c1 -W2 "$GUEST_IP" > /dev/null 2>&1; then link_up=1; break; fi
    sleep 5
done
[[ "$link_up" == "1" ]] || die "host->guest ping to $GUEST_IP never came up"
echo "  host->guest ping OK"
record_milestone PPP_LINK

guest_ping_out=$(guest_cmd "$SERIAL" "/usr/sbin/ping $HOST_IP" 30) \
    || die "guest->host ping failed (transport/command)"
[[ "$guest_ping_out" == *"$HOST_IP is alive"* ]] \
    || die "guest->host ping did not report '$HOST_IP is alive' (raw: $guest_ping_out)"
echo "  guest->host ping OK"

guest_ping_ext_out=$(guest_cmd "$SERIAL" '/usr/sbin/ping 8.8.8.8' 30) \
    || die "external ping (8.8.8.8) failed (transport/command) -- required gate, not advisory"
[[ "$guest_ping_ext_out" == *"8.8.8.8 is alive"* ]] \
    || die "external ping did not report '8.8.8.8 is alive' (raw: $guest_ping_ext_out) -- required gate, not advisory"
echo "  external ping OK"

dns_out=$(guest_cmd "$SERIAL" '/usr/bin/dig @8.8.8.8 example.com' 30) \
    || die "DNS resolution command failed (transport/command) -- required gate, not advisory"
# `dig`'s own output can carry a stray CR from the serial line discipline
# (same CRLF hazard already fixed for the DTrace gate); strip it before
# the exact status/answer checks below, and never pipe the live guest_cmd
# straight into grep -q (same SIGPIPE-on-Expect-writer hazard fixed at
# the other 5 sites earlier this session) -- capture to a variable first.
dns_out_clean=$(tr -d '\r' <<< "$dns_out")
[[ "$dns_out_clean" == *"status: NOERROR"* ]] \
    || die "DNS resolution did not report status: NOERROR (raw: $dns_out_clean)"
[[ "$dns_out_clean" =~ ANSWER:\ [1-9][0-9]* ]] || [[ "$dns_out_clean" == *$'\tIN\tA\t'* ]] \
    || die "DNS resolution reported NOERROR but no nonzero ANSWER count or A record was found (raw: $dns_out_clean)"
echo "  DNS resolution OK"

step "REQUIRED assertion: NFS, via a TRANSIENT client ACL on the proven export"
# Never touches primary R0's 10.0.5.15/32 ACL: `exportfs -i` layers an
# additional in-memory client entry for THIS subnet's guest onto the SAME
# already-exported directory, and it is removed (never the base export)
# in the cleanup trap, success or failure.
sudo -n exportfs -i -o rw,no_root_squash,insecure "${GUEST_IP}:${NFS_EXPORT_DIR}" \
    || die "failed to add transient NFS client ACL for $GUEST_IP"
NFS_ACL_ADDED=1
sudo -n exportfs -s 2>/dev/null | grep -F "$NFS_EXPORT_DIR" | grep -q "$GUEST_IP" \
    || die "transient NFS ACL for $GUEST_IP did not take effect"
echo "  transient NFS ACL added for $GUEST_IP -> $NFS_EXPORT_DIR"

guest_cmd "$SERIAL" "mkdir -p /mnt/host && mount -F nfs -o vers=3,proto=tcp ${HOST_IP}:${NFS_EXPORT_DIR} /mnt/host" 45 \
    || die "NFS mount failed"
nfs_out=$(guest_cmd "$SERIAL" 'ls /mnt/host >/dev/null && echo NFS_LIST_OK' 15) \
    || die "guest_cmd transport/command failed while checking /mnt/host listing"
[[ "$nfs_out" == *NFS_LIST_OK* ]] \
    || die "NFS mount did not produce a readable listing"
echo "  NFS mount OK ($NFS_EXPORT_DIR)"
record_milestone NFS

step "emit scoped teardown script"
cat > "$TEARDOWN" <<EOF
#!/usr/bin/env bash
# Scoped teardown for rehearsal run $TS. Removes ONLY this run's owned
# processes and transient host state. Never touches primary R0 (PID
# $QPID here is THIS run's worker, distinct from primary R0's PID).
set -uo pipefail
echo "tearing down rehearsal run $TS ..."
sudo -n exportfs -u "${GUEST_IP}:${NFS_EXPORT_DIR}" 2>/dev/null && echo "  removed NFS ACL for $GUEST_IP"
sudo -n iptables -t nat -D POSTROUTING -s "$GUEST_IP/32" -o "$NAT_WAN" -j MASQUERADE 2>/dev/null && echo "  removed NAT rule"
sudo -n kill -TERM $PPPD_PEER_PID 2>/dev/null; sleep 1; sudo -n kill -9 $PPPD_PEER_PID 2>/dev/null
sudo -n kill -TERM $PPPD_PID 2>/dev/null; sleep 1; sudo -n kill -9 $PPPD_PID 2>/dev/null
sudo -n kill -TERM $PPPD_LAUNCH_PID 2>/dev/null; sleep 1; sudo -n kill -9 $PPPD_LAUNCH_PID 2>/dev/null
kill -TERM $BRIDGE_PID 2>/dev/null; sleep 1; kill -9 $BRIDGE_PID 2>/dev/null
kill $OWNER_PID 2>/dev/null
kill $QPID 2>/dev/null
tmux kill-session -t $TMUX_SESSION_NAME 2>/dev/null
echo "  done. Evidence remains in $RUNDIR and $R0 (not deleted)."
EOF
chmod +x "$TEARDOWN"
echo "  wrote $TEARDOWN"

record_milestone FINAL_PASS
step "REPLAY PASSED"
write_manifest 0
trap - EXIT INT TERM HUP
cat <<EOF
  image        $R0
  rundir       $RUNDIR
  qemu pid     $QPID
  tmux session $TMUX_SESSION_NAME  windows: $TMUX_WINDOW_NAME (qemu-owner), $TMUX_REPLAY_WINDOW_NAME (replay.log transcript)
  attach            tmux attach -t $TMUX_SESSION_NAME
  select owner win  tmux select-window -t $TMUX_SESSION_NAME:$TMUX_WINDOW_NAME
  select replay win tmux select-window -t $TMUX_SESSION_NAME:$TMUX_REPLAY_WINDOW_NAME
  bridge pid   $BRIDGE_PID  socket $CHANSOCK
  pppd peer pid $PPPD_PEER_PID  parent pid $PPPD_PID  launch wrapper pid $PPPD_LAUNCH_PID  wrapper log $PPPLOG  pppd debug log $PPPD_DEBUG_LOG
  guest dev    $GUEST_DEV   lofi $LOFI_DEV
  dtrace       $DTRACE_EXPECT probes (exact, in-guest assertion)
  channel gate framed echo verified pre-PPP ($CHAN_TEST_SIZE bytes)
  ppp          $HOST_IP <-> $GUEST_IP (isolated from primary R0's 10.0.5.x)
  nat          $GUEST_IP -> $NAT_WAN (transient rule)
  nfs export   $NFS_EXPORT_DIR (transient ACL for $GUEST_IP)

This rehearsal VM is left running for inspection. It never touched primary
R0's PID, image, sockets, subnet, or NFS export ACL. Tear it down with:
  bash $TEARDOWN
EOF
