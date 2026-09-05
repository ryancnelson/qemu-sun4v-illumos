#!/sbin/sh
# Apply only during image assembly; startup and CI use check (read-only).
set -eu
policy_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$policy_dir/network-policy.env"
mode=${1:-check}
case "$mode" in
apply)
    [ "$(id -u)" = 0 ]
    cp -p /etc/resolv.conf /etc/resolv.conf.before-niagara-policy
    cp -p /etc/nsswitch.conf /etc/nsswitch.conf.before-niagara-policy
    printf 'nameserver %s\n' "$DNS_IP" > /etc/resolv.conf
    /usr/bin/nawk -v hosts="$NSS_HOSTS" -v ipnodes="$NSS_IPNODES" '
        /^[ \t]*(hosts|ipnodes):/ { next }
        { print }
        END { print "hosts: " hosts; print "ipnodes: " ipnodes }
    ' /etc/nsswitch.conf > /etc/nsswitch.conf.niagara
    chown root:sys /etc/nsswitch.conf.niagara /etc/resolv.conf
    chmod 0644 /etc/nsswitch.conf.niagara /etc/resolv.conf
    mv /etc/nsswitch.conf.niagara /etc/nsswitch.conf
    ;;
check) ;;
*) echo 'usage: NETWORK_POLICY.sh apply|check' >&2; exit 2 ;;
esac
/usr/bin/nawk -v expected="$DNS_IP" '
    $1 == "nameserver" { count++; if ($2 != expected) bad=1 }
    END { exit !(count == 1 && !bad) }
' /etc/resolv.conf || { echo 'NETWORK_POLICY=FAIL field=resolv.conf'; exit 1; }
for database in hosts ipnodes; do
    case "$database" in hosts) expected=$NSS_HOSTS ;; ipnodes) expected=$NSS_IPNODES ;; esac
    /usr/bin/nawk -v database="$database:" -v expected="$expected" '
        { sub(/#.*/, "") }
        $1 == database {
            count++; actual="";
            for (i=2; i<=NF; i++) actual=actual (i==2 ? "" : " ") $i;
            if (actual != expected) bad=1
        }
        END { exit !(count == 1 && !bad) }
    ' /etc/nsswitch.conf || { echo "NETWORK_POLICY=FAIL field=$database"; exit 1; }
done
echo "NETWORK_POLICY=PASS id=$NETWORK_POLICY_ID resolver=$DNS_IP"
