#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/install-target-options.sh"
parse_install_options
source "$(dirname "${BASH_SOURCE[0]}")/cmd646-trace.sh"

usage() {
    echo "usage: $0 OPENBIOS_FIRMWARE RUN_DIR" >&2
    exit 2
}

if [ "$#" -ne 2 ]; then
    usage
fi

firmware=$1
run_dir=$2
iso=${B134_ISO:-/mnt/disk-images/solaris9-b134-ufsboot-trial-001/textinstall-134-sparc.iso}
iso_sha256=c1ac3fb8bae47d4b8421d7a5506a33b05b1189c9ba731e0e560f78b140f228e0
image=${SUN4U_WORKBENCH_IMAGE:-solaris9-sun4m-workbench:arm64}
image_id=sha256:56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f
qemu_sha256=902dc13a3dbc23a6057cd8f98109632fcbf11ad80a2ad6e0934f48b8b8305d40
source "$(dirname "${BASH_SOURCE[0]}")/qemu-override.sh"
prepare_qemu_override
container=${SUN4U_CONTAINER_NAME:-sun4u-openbios-ci-${CI_PIPELINE_NUMBER:-manual}-$$}
console_log=$run_dir/console.log
console_socket=$run_dir/console.sock
ram_mib=${SUN4U_RAM_MIB:-1536}
case "$ram_mib" in
    512|1024|1088|1536) ;;
    *) echo "unsupported SUN4U_RAM_MIB: $ram_mib (expected 512, 1024, 1088 or 1536)" >&2; exit 2 ;;
esac
echo "guest_ram_mib=$ram_mib"

for tool in docker grep sha256sum socat stat; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing required runtime tool: $tool" >&2
        exit 1
    fi
done

if [ ! -s "$firmware" ]; then
    echo "missing OpenBIOS firmware: $firmware" >&2
    exit 1
fi

if [ ! -f "$iso" ]; then
    echo "missing immutable B134 installer ISO: $iso" >&2
    exit 1
fi

printf '%s  %s\n' "$iso_sha256" "$iso" | sha256sum -c -

actual_image_id=$(docker image inspect "$image" --format '{{.Id}}')
if [ "$actual_image_id" != "$image_id" ]; then
    echo "wrong workbench image: expected $image_id, got $actual_image_id" >&2
    exit 1
fi

if [[ "$qemu_override" == 1 ]]; then
    verify_qemu_override_runtime
else
actual_qemu_sha256=$(
    docker run --rm --entrypoint /usr/bin/sha256sum "$image" \
        /usr/bin/qemu-system-sparc64 | awk '{print $1}'
)
if [ "$actual_qemu_sha256" != "$qemu_sha256" ]; then
    echo "wrong qemu-system-sparc64: expected $qemu_sha256, got $actual_qemu_sha256" >&2
    exit 1
fi
fi

mkdir -p "$run_dir"
if [[ -e "$console_log" || -L "$console_log" || -e "$console_socket" ||
      -e "$run_dir/owned-container.cid" || -L "$run_dir/owned-container.cid" ||
      -e "$run_dir/container-id.txt" || -L "$run_dir/container-id.txt" ]]; then
    echo "run directory is not fresh: $run_dir" >&2
    exit 1
fi

source "$(dirname "${BASH_SOURCE[0]}")/console-outcomes.sh"
if [[ "$qemu_override" == 1 ]]; then
    printf 'host_binary=%s\nsha256=%s\nimage_id=%s\nb134_status_compat=%s\n%s\n' \
        "$qemu_binary" "$qemu_sha256" "$actual_image_id" "$qemu_b134_compat" "$qemu_override_version" >"$run_dir/qemu-override.txt"
fi

cleanup() {
    # Opt-in trace finalization already performed bounded exact-CID cleanup.
    # Retain the stopped container and its evidence; never retry by name.
    [[ "$trace_enabled" != 1 ]] || return 0
    if [[ "$outcome" == PASS && "$outcome_code" == 0 && "$guest_live_non_oom" == 1 &&
          "$keep_guest" == 1 && "$preserve_ready" == 1 ]]; then
        cleanup_preserved=1
        echo "INTERACTIVE_GUEST_PRESERVED=$container"
        echo "console_socket=$console_socket"
        echo 'No installer choices beyond keyboard/language were sent.'
        return
    fi
    if [[ "${keep_maintenance:-0}" == 1 && "$outcome" == MAINTENANCE &&
          "$outcome_code" == 21 && "$guest_live_non_oom" == 1 ]]; then
        cleanup_preserved=1
        echo "MAINTENANCE_GUEST_PRESERVED=$container"
        echo "console_socket=$console_socket"
        echo 'Diagnostic maintenance state preserved; this is not PASS.'
        return
    fi
    [[ "$container_created" == 1 ]] || return 0
    docker stop -t 5 "$container" >/dev/null 2>&1 || true
    docker rm -f "$container" >/dev/null 2>&1 || true
}
trap 'finalize_run $?' EXIT
trap 'cancel_run 130' INT
trap 'cancel_run 143' TERM
trap 'cancel_run 129' HUP

prepare_install_target
prepare_trace

docker run -d \
    --cidfile "$run_dir/owned-container.cid" \
    --name "$container" \
    --cpus 1 \
    --memory 2048m \
    --mount "type=bind,src=$iso,dst=/media/textinstall-134-sparc.iso,readonly" \
    --mount "type=bind,src=$(dirname "$firmware"),dst=/firmware,readonly" \
    --mount "type=bind,src=$run_dir,dst=/run/sun4u" \
    "${target_mount_args[@]}" \
    "${qemu_mount_args[@]}" \
    --entrypoint /usr/bin/qemu-system-sparc64 \
    "$image" \
    -M sun4u \
    -m "$ram_mib" \
    -smp 1 \
    -boot d \
    -vga none \
    -bios "/firmware/$(basename "$firmware")" \
    -cdrom /media/textinstall-134-sparc.iso \
    "${target_qemu_args[@]}" \
    "${qemu_compat_args[@]}" \
    "${trace_qemu_args[@]}" \
    -prom-env input-device=ttya \
    -prom-env output-device=ttya \
    -prom-env 'auto-boot?=false' \
    -display none \
    -monitor unix:/run/sun4u/monitor.sock,server=on,wait=off \
    -chardev socket,id=console,path=/run/sun4u/console.sock,server=on,wait=off,logfile=/run/sun4u/console.log,logappend=on \
    -serial chardev:console \
    >"$run_dir/container-id.txt"
container_created=1
start_trace_watch

wait_for_console() {
    local pattern=$1 limit=$2 elapsed=0
    while true; do
        check_trace || return $?
        check_guest_health || return $?
        if grep -Fq "$pattern" "$console_log" 2>/dev/null; then
            return 0
        fi
        if ((elapsed >= limit)); then
            capture_outcome TIMEOUT 23
            return 23
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
}

send_console() {
    text=$1
    printf '%b' "$text" | socat -T 2 - "UNIX-CONNECT:$console_socket" >/dev/null || true
}

wait_for_console "Welcome to OpenBIOS v1.1" 120
wait_for_console "0 >" 30

# Prove that the compiled firmware exposes the path Solaris later resolves.
send_console 'dev /pci@1f,0/pci@1,1/ebus@1/su@14,3f8\rpwd\r'
wait_for_console "/pci@1f,0/pci@1,1/ebus@1/su@14,3f8 ok" 30

# These are separate known sun4u firmware defects, deliberately kept visible.
send_console 'dev /pci@1f,0/pci@1,1/ebus@1/power@14,7240\r" interrupts" delete-property\r'
send_console 'dev /pci@1f,0/pci@1,1/ebus@1/fdthree@0,0\r" fdthree-disabled" device-name\r'
send_console 'boot cdrom -v\r'

wait_for_console "To select the keyboard layout" 1200
send_console '46\r'
wait_for_console "To select the language you wish to use" 120
send_console '7\r'
wait_for_console "Configuring devices." 300

grep -F "pcipsy0 is /pci@1f,0" "$console_log"
grep -F "ebus0 is /pci@1f,0/pci@1,1/ebus@1" "$console_log"
grep -F "su0 is /pci@1f,0/pci@1,1/ebus@1/su@14,3f8" "$console_log"
grep -F "User selected: English" "$console_log"
grep -F "Configuring devices." "$console_log"

docker inspect "$container" >"$run_dir/container-inspect-running.json"
sha256sum "$firmware" "$console_log" >"$run_dir/SHA256SUMS"

echo "SUN4U_OPENBIOS_BOOT=PASS"
echo "container=$container"
echo "firmware=$firmware"
echo "firmware_bytes=$(stat -c %s "$firmware")"
echo "console_log=$console_log"

if [[ "$install_target_gib" != 0 ]]; then
    echo "Observing next installer screen for ${observe_seconds}s; sending no further input."
    elapsed=0
    while ((elapsed < observe_seconds)); do
        check_trace
        check_guest_health
        sleep 2
        elapsed=$((elapsed + 2))
    done
    check_guest_health
    tail -120 "$console_log"
    docker inspect "$container" >"$run_dir/container-inspect-observed.json"
    sha256sum "$firmware" "$console_log" >"$run_dir/SHA256SUMS"
    echo 'SUN4U_INSTALLER_OBSERVATION=RECORDED_NOT_INSTALLATION_PROVEN'
    # Only explicit KEEP_GUEST=1 plus a healthy completed observation may
    # bypass cleanup; baseline and all failed runs retain automatic cleanup.
    preserve_ready=1
fi
