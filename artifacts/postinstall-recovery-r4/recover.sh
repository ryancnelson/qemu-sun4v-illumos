#!/usr/bin/bash
# Narrow installed snv134 recovery. Owner execution only; no guest work by helpers.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin
export PATH
LC_ALL=C
export LC_ALL
umask 077
ROOT=svc:/system/filesystem/root:default
MEDIA=svc:/system/filesystem/root:media
SETUP=svc:/system/install-setup:default
MAP=/etc/auto_home
PENDING="$MAP.postinstall-recovery.pending"
MANIFEST=/var/svc/manifest/system/filesystem/root-fs.xml
PIN=cfac5c32f4dcdb4da0ea1c774d4f0cf6f4910bb5246dc820b95de4970dbbe004
MODE=dry-run
SNAP=
EVIDENCE=
TMP=
EVIDENCE_OWNED=no
die() { echo "REFUSE: $*" >&2; exit 1; }
manifest_hash() {
    local raw parsed prefix
    if raw=$(digest -a sha256 "$MANIFEST"); then
        # Solaris digest success must be exactly one bare hexadecimal digest.
        :
    else
        echo "digest provider failed; trying openssl SHA256 with unchanged manifest pin" >&2
        raw=$(openssl dgst -sha256 "$MANIFEST") ||
            die "openssl hash command failed"
        # Accept only the named-file form for this exact input, never a loose grep.
        prefix="SHA256($MANIFEST)="
        case "$raw" in
            "$prefix"*) raw=${raw#"$prefix"} ;;
            *) die "missing or malformed openssl digest record" ;;
        esac
    fi
    parsed=$(printf '%s\n' "$raw" | /usr/bin/nawk '
        NR == 1 {
            sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "")
            if (length($0) == 64 && $0 ~ /^[0-9a-fA-F]+$/) value=tolower($0)
        }
        END {if (NR == 1 && length(value) == 64) print value; else exit 1}
    ') || die "missing, malformed or ambiguous manifest digest"
    printf '%s\n' "$parsed"
}
cleanup() {
    local rc=$?
    trap - EXIT
    if [ -n "$TMP" ]; then rm -f "$TMP" || :; fi
    if [ "$EVIDENCE_OWNED" = yes ]; then
        printf '%s\n' "$rc" > "$EVIDENCE/script-exit-status" || :
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) MODE=dry-run; shift ;;
        --apply) MODE=apply; shift ;;
        --snapshot) [ "$#" -ge 2 ] || die "missing snapshot"; SNAP=$2; shift 2 ;;
        --evidence) [ "$#" -ge 2 ] || die "missing evidence path"; EVIDENCE=$2; shift 2 ;;
        *) die "usage: recover.sh [--dry-run|--apply] [--snapshot rpool/ROOT/opensolaris@NAME --evidence /var/tmp/postinstall-recovery-NAME]" ;;
    esac
done
# A prior map commit may not have completed automount reconciliation.
# Never infer reconciliation from an already-correct map on retry.
[ ! -e "$PENDING" ] && [ ! -L "$PENDING" ] ||
    die "pending map reconciliation at $PENDING; owner must resolve recorded evidence before retry"
[ "$(id -u)" = 0 ] || die "requires root for reliable repository reads"
[ "$(uname -s)" = SunOS ] && [ "$(uname -r)" = 5.11 ] &&
[ "$(uname -v)" = snv_134 ] && [ "$(uname -m)" = sun4u ] || die "not exact snv_134 sun4u"
[ "$(/usr/bin/nawk '$2 == "/" {print $1 ":" $3}' /etc/mnttab)" = rpool/ROOT/opensolaris:zfs ] ||
    die "not installed rpool/ROOT/opensolaris mounted at /"
[ "$(zfs get -H -o value mounted rpool/ROOT/opensolaris)" = yes ] || die "root dataset not mounted"
[ -f "$MANIFEST" ] && [ ! -L "$MANIFEST" ] || die "stock manifest missing/symlink"
actual_hash=$(manifest_hash) || die "cannot verify stock manifest hash"
[ "$actual_hash" = "$PIN" ] || die "stock manifest hash mismatch"
svccfg validate "$MANIFEST" || die "stock manifest validation failed"
[ -x /lib/svc/method/fs-root ] || die "stock method missing"
# Require the dangerous installer entrypoints already stopped by owner.
# This script will never disable an active menu contract containing its shell.
for svc in "$MEDIA" "$SETUP"; do
    [ "$(svcprop -c -p general/enabled "$svc")" = false ] || die "$svc must already be persistently disabled"
    [ "$(svcprop -p restarter/state "$svc")" = disabled ] || die "$svc must already be stopped"
done
[ "$(svcprop -c -p general/enabled svc:/system/console-login:default)" = true ] ||
    die "normal console login must already be enabled"
stock() {
    local view=$1 prop want got
    while read -r prop want; do
        if [ "$view" = current ]; then
            got=$(svcprop -c -p "$prop" "$ROOT" 2>/dev/null) || return 1
        else
            got=$(svcprop -s "$view" -p "$prop" "$ROOT" 2>/dev/null) || return 1
        fi
        [ "$got" = "$want" ] || return 1
    done <<'PROPERTIES'
start/exec /lib/svc/method/fs-root
start/timeout_seconds 300
stop/exec :true
stop/timeout_seconds 0
startd/duration transient
PROPERTIES
}
REVERT=no
if ! stock current; then
    stock last-import || die "needed last-import snapshot is not the verified stock method tuple"
    REVERT=yes
fi
[ -f "$MAP" ] && [ ! -L "$MAP" ] || die "auto_home missing/symlink"
[ "$(ls -ldn "$MAP" | /usr/bin/nawk '{print $3}')" = 0 ] || die "map not root owned"
[ "$(getent passwd niagara | /usr/bin/nawk -F: '{print $1 ":" $3 ":" $4 ":" $6}')" = niagara:101:10:/home/niagara ] ||
    die "account identity/home differs; no account repair allowed"
for p in /export /export/home /export/home/niagara; do
    [ -d "$p" ] && [ ! -L "$p" ] || die "backing path absent/symlink: $p"
done
[ "$(/usr/bin/nawk '$2 == "/export/home" {n++; type=$3} END {if (n == 1) print type}' /etc/mnttab)" = zfs ] ||
    die "expected backing /export/home ZFS mount missing or ambiguous"
[ "$(ls -ldn /export/home/niagara | /usr/bin/nawk '{print $1 ":" $3 ":" $4}')" = drwxr-xr-x:101:10 ] ||
    die "backing ownership/mode differs; no chmod/chown allowed"
MAPSTATE=$(/usr/bin/nawk '
$1 == "niagara" {
 n++
 if (NF == 2 && $2 == "localhost:/export/home/&") old++
 else if (NF == 3 && $2 == "-fstype=lofs" && $3 == ":/export/home/niagara") new++
 else bad++
}
END {if (n == 1 && old == 1 && !bad) print "old";
 else if (n == 1 && new == 1 && !bad) print "new"; else print "refuse"}' "$MAP")
[ "$MAPSTATE" != refuse ] || die "map must contain exactly one exact old or recovered niagara entry"
echo "PLAN: revert-last-import=$REVERT; explicit enable root:default; svccfg refresh; verify current/running; map=$MAPSTATE"
echo "PLAN: preserve stopped media/install-setup; no package/account/ICT/device-policy edits or reboot"
if [ "$MODE" = dry-run ]; then
    echo "DRY-RUN ONLY: no changes; apply additionally requires verified existing rollback snapshot and new private evidence directory"
    exit 0
fi
case "$SNAP" in rpool/ROOT/opensolaris@?*) ;; *) die "exact-root rollback snapshot required" ;; esac
case "$SNAP" in *[!a-zA-Z0-9_/@.-]*) die "invalid snapshot characters" ;; esac
[ "$(zfs list -H -t snapshot -o name "$SNAP")" = "$SNAP" ] || die "rollback snapshot not present"
case "$EVIDENCE" in /var/tmp/postinstall-recovery-?*) ;; *) die "new /var/tmp/postinstall-recovery-NAME required" ;; esac
case "${EVIDENCE#/var/tmp/}" in */*|*[!a-zA-Z0-9_.-]*) die "invalid evidence basename" ;; esac
[ ! -e "$EVIDENCE" ] && [ ! -L "$EVIDENCE" ] || die "evidence path already exists"
mkdir -m 700 "$EVIDENCE" || die "cannot create evidence directory"
EVIDENCE_OWNED=yes
printf '%s\n' "$SNAP" > "$EVIDENCE/rollback-snapshot.txt"
# Exports can include sensitive properties: private directory, never echo contents.
svccfg export system/filesystem/root > "$EVIDENCE/root-before.xml"
svccfg export system/install-setup > "$EVIDENCE/install-setup-before.xml"
svccfg export system/console-login > "$EVIDENCE/console-login-before.xml"
cp -p "$MAP" "$EVIDENCE/auto_home.before"
echo "Evidence retained: $EVIDENCE (private; do not publish exports)"
if [ "$REVERT" = yes ]; then
    # Revert affects ancestor service properties too; exported above.
    svccfg -s "$ROOT" revert last-import
    # Preserve owner-selected disabled media after shared service restoration.
    svcadm disable "$MEDIA"
fi
svcadm enable "$ROOT"
svccfg -s "$ROOT" refresh
stock current || die "current method tuple not stock after recovery"
# Refresh may be asynchronous: bounded read-only wait, never assume exit0 means updated.
ok=no
for attempt in 1 2 3 4 5; do
    if stock running; then ok=yes; break; fi
    sleep 1
done
[ "$ok" = yes ] || die "running snapshot not stock; retained evidence, no further changes"
[ "$(svcprop -c -p general/enabled "$ROOT")" = true ] || die "root enable did not persist"
for svc in "$MEDIA" "$SETUP"; do
    [ "$(svcprop -c -p general/enabled "$svc")" = false ] || die "disabled setting changed: $svc"
done
[ "$(svcprop -c -p general/enabled svc:/system/console-login:default)" = true ] ||
    die "console setting changed"
if [ "$MAPSTATE" = old ]; then
    cmp -s "$MAP" "$EVIDENCE/auto_home.before" || die "map changed concurrently"
    next_tmp="$MAP.postinstall-recovery.$$"
    ( set -C; : > "$next_tmp" ) || die "temporary map exists"
    TMP=$next_tmp
    cp -p "$MAP" "$TMP"
    /usr/bin/nawk '$1 == "niagara" {print "niagara -fstype=lofs :/export/home/niagara"; next} {print}' "$MAP" > "$TMP"
    cmp -s "$MAP" "$EVIDENCE/auto_home.before" || die "map changed concurrently"
    cp -p "$TMP" "$EVIDENCE/auto_home.intended"
    # Publish pending BEFORE committing the map. Leave it on failure/signal.
    ( set -C; printf '%s\n' "$EVIDENCE" > "$PENDING" ) ||
        die "cannot create pending reconciliation marker"
    mv "$TMP" "$MAP"
    TMP=
    if /usr/sbin/automount; then
        rm "$PENDING"
    else
        rc=$?
        echo "PENDING: automount failed ($rc); map may be changed; see $PENDING; no automatic retry" >&2
        exit "$rc"
    fi
fi
svccfg export system/filesystem/root > "$EVIDENCE/root-after.xml"
cp -p "$MAP" "$EVIDENCE/auto_home.after"
echo "CONFIGURATION VERIFIED: current/running stock tuple, root enabled, media/install-setup disabled, exact lofs map"
echo "OWNER ACCEPTANCE STILL REQUIRED: bounded niagara HOME access, fresh login, natural clean boot and service/policy health"
