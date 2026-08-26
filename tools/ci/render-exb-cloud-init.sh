#!/usr/bin/env bash
# Render Exabyte cloud-init with Biggie's ryan identity without committing
# password hashes or authorized keys to this repository.
set -euo pipefail

usage() {
    echo "usage: $0 OUTPUT [SOURCE_HOST]" >&2
    echo "  OUTPUT must be under the repository's ignored work/ directory." >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
base_cloud_init="$script_dir/exb-cloud-init.yaml"
output=$1
source_host=${2:-biggie}

case "$output" in
    /*) output_abs=$output ;;
    *) output_abs="$PWD/$output" ;;
esac
work_dir="$repo_dir/work"
mkdir -p "$work_dir"
work_dir=$(cd -- "$work_dir" && pwd)
output_parent=$(cd -- "$(dirname -- "$output_abs")" && pwd)
[[ "$output_parent" == "$work_dir" ]] || {
    echo "refusing sensitive rendered output outside $work_dir" >&2
    exit 2
}

umask 077
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT

passwd_file="$task_tmp/passwd"
shadow_file="$task_tmp/shadow"
keys_file="$task_tmp/authorized_keys"
rendered_tmp="$task_tmp/cloud-init.yaml"

ssh "$source_host" 'getent passwd ryan' > "$passwd_file"
ssh "$source_host" 'sudo getent shadow ryan' > "$shadow_file"
ssh "$source_host" 'cat /home/ryan/.ssh/authorized_keys' > "$keys_file"

IFS=: read -r user _ uid gid gecos home shell < "$passwd_file"
IFS=: read -r shadow_user password_hash _ < "$shadow_file"
[[ "$user" == ryan && "$shadow_user" == ryan ]] || {
    echo "source identity is not ryan" >&2
    exit 1
}
[[ "$uid" == 1000 && "$gid" == 1000 && "$home" == /home/ryan ]] || {
    echo "source ryan identity changed: expected uid/gid 1000 and /home/ryan" >&2
    exit 1
}
[[ ${#password_hash} -ge 100 && "$password_hash" != '!'* && "$password_hash" != '*'* ]] || {
    echo "source ryan password is locked or is not a supported hash" >&2
    exit 1
}
key_count=$(awk 'NF && $1 !~ /^#/ {n++} END {print n+0}' "$keys_file")
[[ "$key_count" -gt 0 ]] || {
    echo "source ryan has no authorized keys" >&2
    exit 1
}

python3 - "$base_cloud_init" "$rendered_tmp" "$password_hash" "$keys_file" <<'PY'
import json
import pathlib
import sys

base_path, output_path, password_hash, keys_path = sys.argv[1:]
base = pathlib.Path(base_path).read_text()
if not base.startswith("#cloud-config\n"):
    raise SystemExit("base cloud-init lacks #cloud-config header")

keys = []
for line in pathlib.Path(keys_path).read_text().splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        keys.append(line)
if not keys:
    raise SystemExit("no authorized keys to render")

user_lines = [
    "users:",
    "  - name: ryan",
    "    uid: 1000",
    "    gecos: ryan",
    "    groups: [adm, dialout, cdrom, sudo, dip, plugdev, users]",
    "    shell: /bin/bash",
    "    lock_passwd: false",
    f"    hashed_passwd: {json.dumps(password_hash)}",
    '    sudo: "ALL=(ALL:ALL) ALL"',
    "    ssh_authorized_keys:",
]
user_lines.extend(f"      - {json.dumps(key)}" for key in keys)
user_lines.extend([
    "  - name: ubuntu",
    "    uid: 1001",
    "    gecos: Ubuntu provider recovery account",
    "    groups: [adm, cdrom, sudo, dip]",
    "    shell: /bin/bash",
    "    lock_passwd: true",
])

rendered = "#cloud-config\n" + "\n".join(user_lines) + "\n" + base[len("#cloud-config\n"):]
pathlib.Path(output_path).write_text(rendered)
PY

install -m 0600 "$rendered_tmp" "$output_abs"
printf 'rendered %s with ryan uid=%s gid=%s and %s authorized keys\n' \
    "$output_abs" "$uid" "$gid" "$key_count"
printf 'contains a password hash; keep this file private and delete it after provisioning\n'
