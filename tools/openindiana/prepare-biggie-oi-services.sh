#!/usr/bin/env bash
# Idempotently prepare Biggie's host half of PPP, NFS and a disposable iSCSI LUN.
set -euo pipefail

SESSION=${1:?usage: prepare-biggie-oi-services.sh SESSION}
MASA=${MASA:-/home/ryan/devel/masa-sun4v}
RUN=${RUN:-$MASA/ci/runs/$SESSION}
GUEST_IP=${GUEST_IP:-10.0.5.15}
EGRESS=${EGRESS:-$(ip route show default | awk 'NR==1 {print $5}')}
EXPORT=${EXPORT:-/export/solaris}
IQN=${IQN:-iqn.2026-08.net.ryan:$SESSION}
BACKSTORE=${BACKSTORE:-${SESSION//[^A-Za-z0-9]/_}}
LUN_FILE=$RUN/iscsi-unit0-512m.img
CANARY=$EXPORT/${SESSION}-nfs-canary.txt

[[ -f $RUN/run.manifest ]] || { echo "FAIL: unknown run $RUN" >&2; exit 1; }
sudo -n true || { echo "FAIL: passwordless sudo required" >&2; exit 1; }
command -v targetcli >/dev/null || { echo "FAIL: install targetcli-fb" >&2; exit 1; }
[[ -n $EGRESS ]] || { echo "FAIL: cannot determine egress interface" >&2; exit 1; }

sudo -n sysctl -w net.ipv4.ip_forward=1 >/dev/null
sudo -n iptables -t nat -C POSTROUTING -s "$GUEST_IP/32" -o "$EGRESS" -j MASQUERADE 2>/dev/null || \
  sudo -n iptables -t nat -A POSTROUTING -s "$GUEST_IP/32" -o "$EGRESS" -j MASQUERADE

[[ -d $EXPORT ]] || { echo "FAIL: NFS export missing: $EXPORT" >&2; exit 1; }
sudo -n exportfs -v | grep -F "$EXPORT" >/dev/null || { echo "FAIL: $EXPORT is not exported" >&2; exit 1; }
printf '%s\n' "$SESSION" | sudo -n tee "$CANARY" >/dev/null
sudo -n chmod 666 "$CANARY"

if sudo -n targetcli ls | grep -F "$IQN" >/dev/null; then
  sudo -n targetcli ls | grep -F "$LUN_FILE" >/dev/null || {
    echo "FAIL: $IQN exists with a different backing file" >&2
    exit 1
  }
else
  [[ ! -e $LUN_FILE ]] || { echo "FAIL: unowned LUN file already exists: $LUN_FILE" >&2; exit 1; }
  truncate -s 512M "$LUN_FILE"
  sudo -n targetcli /backstores/fileio create "$BACKSTORE" "$LUN_FILE" 512M write_back=false
  sudo -n targetcli /iscsi create "$IQN"
  sudo -n targetcli "/iscsi/$IQN/tpg1/luns" create "/backstores/fileio/$BACKSTORE"
  sudo -n targetcli "/iscsi/$IQN/tpg1" set attribute authentication=0 generate_node_acls=1 cache_dynamic_acls=1 demo_mode_write_protect=0
  sudo -n targetcli saveconfig
fi

sudo -n ss -ltn | grep -q ':3260 ' || { echo "FAIL: iSCSI is not listening" >&2; exit 1; }
printf 'nfs_export=%s\nnfs_canary=%s\niscsi_iqn=%s\niscsi_backing=%s\n' \
  "$EXPORT" "$CANARY" "$IQN" "$LUN_FILE" >"$RUN/host-services.manifest"
echo "PASS: PPP egress, writable NFS canary, and 512 MiB iSCSI target are prepared"

