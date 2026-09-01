#!/usr/bin/bash

set -euo pipefail
umask 077

EXPECTED_POOL_GUID=18135893029031842473
EXPECTED_BOOTFS=rpool/ROOT/openindiana
EXPECTED_INACTIVE_BE=workstation-candidate-20260826
RYAN_HOME=/export/home/ryan
JACK_HOME=/jack

SNAPSHOTS=(
    pre-fortify
    fortified-files
    fortified-bootarchive-pass
    pre-hsimd-registration
    hsimd-registration-bootarchive-pass
    2026-08-26-19:25:13
)

die()
{
    echo "NIAGARA_RELEASE_CLEANUP=FAIL reason=$*" >&2
    exit 1
}

MODE=${1:---audit}
case "$MODE" in
--audit|--apply)
    ;;
*)
    die "usage: $0 --audit|--apply"
    ;;
esac

[[ "$(uname -s)" = SunOS ]] || die "this script must run inside the SunOS guest"
[[ "$(id -u)" = 0 ]] || die "this script must run as root"

ACTUAL_POOL_GUID=$(zpool get -H -o value guid rpool) || die "rpool is unavailable"
[[ "$ACTUAL_POOL_GUID" = "$EXPECTED_POOL_GUID" ]] || \
    die "unexpected rpool GUID: $ACTUAL_POOL_GUID"

ACTUAL_BOOTFS=$(zpool get -H -o value bootfs rpool)
[[ "$ACTUAL_BOOTFS" = "$EXPECTED_BOOTFS" ]] || \
    die "unexpected rpool bootfs: $ACTUAL_BOOTFS"

echo "NIAGARA_RELEASE_CLEANUP_MODE=${MODE#--}"
echo "rpool_guid=$ACTUAL_POOL_GUID"
echo "rpool_bootfs=$ACTUAL_BOOTFS"
zfs list -o name,used,usedbysnapshots,usedbydataset,usedbychildren,usedbyrefreservation
zfs list -t snapshot -o name,used,refer,creation -s creation || true
getent passwd ryan jack || true
id jack || die "jack account is missing"
passwd -s jack || die "jack password status is unavailable"

if [[ "$MODE" = --audit ]]; then
    echo "NIAGARA_RELEASE_CLEANUP=AUDIT_PASS"
    exit 0
fi

if getent passwd ryan >/dev/null 2>&1
then
    [[ -d "$RYAN_HOME" ]] || die "Ryan home is missing: $RYAN_HOME"
    RYAN_CONTENTS=$(ls -A "$RYAN_HOME")
    [[ "$RYAN_CONTENTS" = .bashrc ]] || \
        die "Ryan home contains unreviewed material: $RYAN_CONTENTS"
    [[ -f "$RYAN_HOME/.bashrc" ]] || die "Ryan .bashrc is missing"
    [[ ! -e "$JACK_HOME" ]] || die "jack home already exists: $JACK_HOME"

    mkdir -m 0755 "$JACK_HOME"
    cp -p "$RYAN_HOME/.bashrc" "$JACK_HOME/.bashrc"
    chown -R jack:staff "$JACK_HOME"

    su - jack -c 'test "$HOME" = /jack && test "$PWD" = /jack && id' || \
        die "jack cannot start a login shell in /jack"

    /usr/sbin/userdel ryan
    getent passwd ryan >/dev/null 2>&1 && die "ryan account still exists"
    rm "$RYAN_HOME/.bashrc"
    rmdir "$RYAN_HOME"
else
    [[ -d "$JACK_HOME" && -f "$JACK_HOME/.bashrc" ]] || \
        die "ryan is absent but jack home migration is incomplete"
fi

# The final inventoried snapshot is the origin of this development-only BE.
# Remove it through beadm, never with a recursive ZFS dependency destroy.
if beadm list -H "$EXPECTED_INACTIVE_BE" >/dev/null 2>&1
then
    beadm destroy -F "$EXPECTED_INACTIVE_BE"
fi

for snapshot in "${SNAPSHOTS[@]}"
do
    target="${EXPECTED_BOOTFS}@${snapshot}"
    if zfs list -H -t snapshot -o name "$target" >/dev/null 2>&1
    then
        zfs destroy -r "$target"
    fi
done

[[ -z "$(zfs list -H -t snapshot -o name -r "$EXPECTED_BOOTFS")" ]] || \
    die "snapshots remain below $EXPECTED_BOOTFS"
[[ -d "$JACK_HOME" && -f "$JACK_HOME/.bashrc" ]] || \
    die "jack home migration is incomplete"
[[ "$(zpool get -H -o value bootfs rpool)" = "$EXPECTED_BOOTFS" ]] || \
    die "rpool bootfs changed during cleanup"

echo "post_cleanup_account=jack"
id jack
echo "post_cleanup_home=$JACK_HOME"
ls -la "$JACK_HOME"
zfs list -o name,used,usedbysnapshots,usedbydataset,usedbychildren,usedbyrefreservation
echo "NIAGARA_RELEASE_CLEANUP=PASS"
