#!/usr/bin/env bash
# doctor.sh -- check for the failure modes this project has actually hit.
#
#   $ ~/sun4v/doctor.sh              # host checks, plus guest checks if reachable
#   $ ~/sun4v/doctor.sh --quiet      # only problems
#
# READ ONLY. It diagnoses and prints the fix; it never changes anything. Every check
# below corresponds to a real incident, not a hypothetical, and each one cost real time
# to find. The bracket form in process patterns -- [q]emu -- is deliberate: 'pgrep -f
# qemu-system-sparc64' matches the shell running the check itself and reports a phantom.
set -uo pipefail

IMG="${NIAGARA_IMG:-$HOME/sun4v/images/primary.img}"
FW="${NIAGARA_FW:-$HOME/sun4v/firmware/base-1gib}"
QEMU="${NIAGARA_QEMU:-$HOME/niag-proj/qemu/build/qemu-system-sparc64}"
GUEST_IP="${GUEST_IP:-10.0.5.15}"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

pass=0; warn=0; fail=0
ok()   { (( QUIET )) || printf '  \033[32mok\033[0m    %s\n' "$*"; pass=$((pass+1)); }
wrn()  { printf '  \033[33mwarn\033[0m  %s\n' "$*"; warn=$((warn+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }
fix()  { printf '        fix: %s\n' "$*"; }
head_() { (( QUIET )) || printf '\n== %s ==\n' "$*"; }

real_pids() {  # match workers only, never sudo/setsid wrappers or ourselves
    ps -eo pid,args --no-headers | grep -- "$1" \
        | grep -v -e 'sudo ' -e 'setsid ' -e grep -e doctor.sh | awk '{print $1}'
}

# ---------------------------------------------------------------- artifacts ----
head_ "artifacts"
if [[ -x "$QEMU" ]]; then
    v=$("$QEMU" --version 2>/dev/null | head -1)
    ok "qemu present: ${v:-unknown}"
    if "$QEMU" -M help 2>/dev/null | grep -q niagara; then
        ok "machine type 'niagara' available"
    else
        bad "this qemu has NO niagara machine type"; fix "rebuild: ./setup-host.sh"
    fi
else
    bad "qemu missing at $QEMU"; fix "./setup-host.sh"
fi

# The patch is what makes guest writes persist AND what the channels depend on.
NIAGARA_C="$(dirname "$QEMU")/../hw/sparc64/niagara.c"
if [[ -f "$NIAGARA_C" ]]; then
    if grep -q MAP_SHARED "$NIAGARA_C"; then
        ok "vdisk patch present in niagara.c"
    else
        bad "niagara.c has NO MAP_SHARED -- guest writes will be LOST"
        fix "git apply patches/0001-niagara-vdisk-writeback.patch && rebuild"
    fi
fi

[[ -d "$FW" ]] && ok "firmware dir $FW" || { bad "firmware missing: $FW"; fix "copy base-1gib from a working host"; }

if [[ -f "$IMG" ]]; then
    ok "image $(du -h "$IMG" | cut -f1) at $IMG"
elif [[ -b "$IMG" ]]; then
    bad "image is a BLOCK DEVICE. The vdisk must be a regular file:"
    fix "memory_region_init_ram_from_file() needs one, and block devices do not give reliable MAP_SHARED writeback"
else
    bad "image missing: $IMG"
fi

# ------------------------------------------------------------------- host ----
head_ "host capability"
ram=$(free -m | awk '/^Mem:/{print $2}')
(( ram >= 2500 )) && ok "ram ${ram} MB" || { bad "ram ${ram} MB is too little"; fix "the guest alone needs 1024 MB of anonymous memory; give the VM 4 GB"; }

avail=$(df -BG --output=avail "$(dirname "$IMG")" 2>/dev/null | tail -1 | tr -dc '0-9')
(( ${avail:-0} >= 5 )) && ok "disk ${avail}G free where the image lives" || wrn "only ${avail:-?}G free next to the image"

[[ -c /dev/ppp ]] && ok "/dev/ppp present" || { wrn "/dev/ppp missing -- STARTPPP and IP will not work"; fix "sudo modprobe ppp_generic"; }

# Reflink support decides whether a rollback copy is instant or a 6-minute stall.
fstype=$(df -T "$(dirname "$IMG")" 2>/dev/null | tail -1 | awk '{print $2}')
case "$fstype" in
    xfs|btrfs|bcachefs) ok "image filesystem is $fstype (reflink capable)" ;;
    *) wrn "image is on $fstype -- NO reflink support, so 'cp --reflink=auto' silently does a full copy (~6 min for 2.5 GB)"
       fix "lvcreate -L 12G -n images \$VG; mkfs.xfs -m reflink=1 /dev/\$VG/images; mount it at $(dirname "$IMG")" ;;
esac

# ---------------------------------------------------------------- runtime ----
head_ "runtime"
nq=$(real_pids '[q]emu-system-sparc64 -M niagara' | wc -l)
case "$nq" in
    0) ok "no guest running" ;;
    1) ok "exactly 1 guest running" ;;
    *) bad "$nq QEMU instances on one MAP_SHARED image -- THIS CORRUPTS IT"
       fix "sudo pkill -f '[q]emu-system-sparc64', then restore from a clean copy" ;;
esac

for c in 0 1 2; do
    n=$(real_pids "host-chan.py bridge $c" | wc -l)
    if (( n == 1 )); then
        ok "channel $c: 1 bridge writer"
    elif (( n == 0 )); then
        (( QUIET )) || printf '  \033[33mwarn\033[0m  channel %s: no bridge\n' "$c"
    else
        bad "channel $c has $n writers -- the design requires ONE; more corrupts the sequence handshake and looks like 'PPP will not come up'"
        fix "sudo bash tools/chan/host-up.sh   (it kills by PID and verifies)"
    fi
done

np=$(real_pids 'pppd notty' | wc -l)
(( np <= 2 )) && ok "pppd instances: $np" || { bad "$np pppd processes"; fix "sudo bash tools/chan/host-up.sh"; }

# ------------------------------------------------------------- networking ----
head_ "networking"
if ip -br addr show ppp0 2>/dev/null | grep -q .; then
    ok "ppp0 up: $(ip -br addr show ppp0 | awk '{print $3}')"
else
    wrn "no ppp0 on the host"
    fix "sudo -nE env NIAGARA_IMG=$IMG bash tools/chan/host-up.sh"
fi

fwd=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
[[ "$fwd" == "1" ]] && ok "ip_forward enabled" || { wrn "ip_forward=0 -- the guest will reach the host but NOT the internet, which looks like a PPP fault and is not"; fix "sudo sysctl -w net.ipv4.ip_forward=1"; }

if command -v iptables >/dev/null && sudo -n true 2>/dev/null; then
    nm=$(sudo -n iptables -t nat -S POSTROUTING 2>/dev/null | grep -c MASQUERADE)
    (( nm >= 1 )) && ok "NAT: $nm masquerade rule(s)" || { wrn "no MASQUERADE rule -- guest cannot reach the internet"; fix "sudo bash tools/chan/host-up.sh (now does this)"; }
fi

# ------------------------------------------------------------------ guest ----
if ping -c1 -W2 "$GUEST_IP" >/dev/null 2>&1; then
    head_ "guest (reachable at $GUEST_IP)"
    ok "guest responds to ping"
    G=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
       -o ConnectTimeout=10 -o BatchMode=yes -l root "$GUEST_IP")
    if out=$("${G[@]}" 'echo up' 2>/dev/null) && [[ "$out" == "up" ]]; then
        ok "ssh into guest works"

        # dropbear refuses keys unless "/" itself is sane -- a host-built tar
        # extracted at / once left it 1000:1000 drwxrwxr-x and broke all auth.
        rp=$("${G[@]}" 'ls -ld / | cut -c1-10' 2>/dev/null)
        [[ "$rp" == "drwxr-xr-x" ]] && ok "guest / permissions $rp" \
            || { bad "guest / is $rp -- dropbear will refuse every key"; fix "in guest: chown root:root / && chmod 755 /"; }

        # rc3.d only runs if this milestone exists; without it nothing autostarts.
        ms=$("${G[@]}" 'svcs -H -o state svc:/milestone/multi-user-server:default 2>/dev/null' 2>/dev/null)
        [[ "$ms" == "online" ]] && ok "multi-user-server online (rc3.d runs)" \
            || { wrn "multi-user-server is '${ms:-absent}' -- rc3.d will NOT run, so nothing autostarts at boot"; fix "in guest: svccfg import /var/svc/manifest/milestone/multi-user{,-server}.xml"; }

        dr=$("${G[@]}" 'netstat -nr | grep -c "^default"' 2>/dev/null)
        [[ "${dr:-0}" -ge 1 ]] && ok "guest has a default route" \
            || { wrn "guest has NO default route (sppp0 appears after boot, so /etc/defaultrouter does not cover it)"; fix "in guest: route add default 10.0.5.1   -- note .1, NOT .15 which is the guest itself"; }

        nk=$("${G[@]}" 'wc -l < /.ssh/authorized_keys 2>/dev/null || echo 0' 2>/dev/null)
        [[ "${nk:-0}" -gt 0 ]] && wrn "guest carries ${nk} authorized_keys -- personal data, must not ship" \
            || ok "guest authorized_keys empty"
        # The guest's dialer, and whether GET's advertised path actually exists there.
        if "${G[@]}" 'test -x /opt/niag/bin/guest-dial.pl' 2>/dev/null; then
            ok "guest has guest-dial.pl   -- dial with: perl /opt/niag/bin/guest-dial.pl 1"
        else
            wrn "guest lacks /opt/niag/bin/guest-dial.pl"
            fix "ssh -l root $GUEST_IP 'cat > /opt/niag/bin/guest-dial.pl' < tools/chan/guest-dial.pl"
        fi
        if "${G[@]}" 'test -d /share/chan' 2>/dev/null; then
            ok "guest can see /share/chan (GET deliveries land there)"
        else
            wrn "guest has NO /share/chan, but GET tells the caller to look there -- so GET"
            fix "fetches correctly and the guest cannot reach the file. Either mount the host"
            fix "export, or implement the channel-based PUT/GET in SPEC-portable.md section 4"
        fi

        fix_hint=$("${G[@]}" 'ls /etc/dropbear/ 2>/dev/null | wc -l' 2>/dev/null)
        [[ "${fix_hint:-0}" -gt 0 ]] && wrn "guest has ${fix_hint} dropbear host key(s) -- shipping them gives every downloader ONE host identity" \
            || ok "no baked-in dropbear host keys"
    else
        wrn "guest pings but ssh fails -- no trusted key from this host yet"
        fix "telnet $GUEST_IP (root, no password) and append your pubkey to /.ssh/authorized_keys"
    fi
fi

# -------------------------------------------------------------------- bbs ----
# The BBS is the guest's way to ask questions and fetch files over a channel. These
# checks double as the documentation: every failure prints the command that fixes it,
# because the prose version in CURRENT-STATE.md was written on a host with ZFS and NFS
# and did not survive the move to a portable one.
head_ "bbs oracle"
bbs_pids=$(real_pids '[h]ost-bbs.py' | wc -l)

if (( bbs_pids == 0 )); then
    # Not running is the NORMAL state, not a fault. The oracle is optional; the guest
    # boots, compiles and networks without it.
    (( QUIET )) || printf '  \033[36minfo\033[0m  BBS not running (optional). To start it on channel 1:\n'
    (( QUIET )) || cat <<EOF
        sudo systemd-run --unit=niag-bbs \\
            --setenv=NIAGARA_IMG=$IMG \\
            --setenv=BBS_LLM_URL=<an OpenAI-compatible /v1/chat/completions URL> \\
            --setenv=BBS_LLM_KEY=<if that endpoint needs one> \\
            --setenv=BBS_DELIVERY=\$HOME/sun4v/delivery \\
            python3 \$HOME/niag-proj/tools/chan/host-bbs.py /run/niag1
        then in the guest:  perl /opt/niag/bin/guest-dial.pl 1
        use systemd-run, NOT 'setsid nohup ... &' -- the backgrounded form silently
        does nothing through sudo over ssh: no process, no log, no error.
EOF
else
    ok "host-bbs.py running ($bbs_pids)"
    bch=$(ps -eo args --no-headers | grep '[h]ost-bbs.py' | grep -oE '/run/niag[0-9]+' | head -1)
    [[ -n "$bch" ]] && ok "attached to ${bch}   (guest dials /tmp/niag${bch##*niag})"
    [[ "$bch" == "/run/niag0" ]] && wrn "channel 0 usually carries PPP -- STARTPPP there would fight your IP link"

    # THE USUAL CASE: no endpoint configured. That is not a crash -- ASK answers
    # "ERROR: no oracle configured" -- but it is the single most likely reason the BBS
    # looks broken, so say it plainly and say what to do.
    # The redirection trap: 'sudo tr < /proc/PID/environ' opens the file as the CALLING
    # user, so cat must be the thing running under sudo. And an unreadable environment
    # means UNKNOWN, never "unset" -- asserting a negative from a failed measurement is
    # how this project wastes days.
    bp=$(real_pids '[h]ost-bbs.py' | head -1)
    env_txt=$(sudo -n cat "/proc/$bp/environ" 2>/dev/null | tr '\0' '\n')
    if [[ -z "$env_txt" ]]; then
        wrn "cannot read the daemon's environment (needs sudo) -- endpoint state UNKNOWN"
        fix "sudo journalctl -u niag-bbs | grep -i 'no oracle'"
    elif grep -q '^BBS_LLM_URL=.' <<< "$env_txt"; then
        ok "BBS_LLM_URL is set  ($(grep '^BBS_LLM_URL=' <<< "$env_txt" | cut -d= -f2- | cut -c1-46))"
        grep -q '^BBS_LLM_KEY=.' <<< "$env_txt" && ok "BBS_LLM_KEY is set" \
            || (( QUIET )) || printf '  \033[36minfo\033[0m  no BBS_LLM_KEY (fine for an endpoint that does not need one)\n'
    else
        wrn "NO BBS_LLM_URL -- this is the usual case, and ASK will answer"
        fix "'ERROR: no oracle configured'. It is unconfigured, not broken. Options:"
        fix "  * any OpenAI-compatible endpoint you already run, plus BBS_LLM_KEY if needed"
        fix "  * OpenRouter has 17 ':free' models, but there is NO anonymous access --"
        fix "    a keyless POST returns HTTP 401, so a free account and key are required"
        fix "  * do NOT run a local model in this VM. Measured: SmolLM2-135M (101 MB)"
        fix "    invents libraries and fabricates doc quotes even when told to admit"
        fix "    ignorance, and anything large enough to refuse well competes for the"
        fix "    RAM the guest needs."
    fi
fi

if [[ -d "${BBS_DELIVERY:-$HOME/sun4v/delivery}" ]]; then
    ok "delivery dir ${BBS_DELIVERY:-$HOME/sun4v/delivery}"
else
    wrn "no delivery dir -- GET has nowhere to put files"
    fix "mkdir -p ${BBS_DELIVERY:-$HOME/sun4v/delivery}"
fi

# ------------------------------------------------------------ rollback ----
head_ "rollback"
if [[ -f "$IMG.clean" ]]; then
    a=$(cksum "$IMG" 2>/dev/null | awk '{print $1}')
    b=$(cksum "$IMG.clean" 2>/dev/null | awk '{print $1}')
    if [[ "$a" == "$b" ]]; then
        ok "rollback copy present and identical"
    else
        ok "rollback copy present (image has diverged, which is normal after use)"
        printf '        restore: cp --reflink=auto %s %s\n' "$(basename "$IMG").clean" "$(basename "$IMG")"
    fi
else
    wrn "no rollback copy. An unclean stop leaves the UFS log dirty and the NEXT boot panics in ufs:readlog -- unrecoverable in practice"
    fix "after a clean 'init 5': cp --reflink=auto $IMG $IMG.clean"
fi

printf '\n%d ok, %d warn, %d FAIL\n' "$pass" "$warn" "$fail"
(( fail == 0 ))
