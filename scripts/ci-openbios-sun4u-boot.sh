#!/usr/bin/env bash

set -euo pipefail

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
container=${SUN4U_CONTAINER_NAME:-sun4u-openbios-ci-${CI_PIPELINE_NUMBER:-manual}-$$}
console_log=$run_dir/console.log
console_socket=$run_dir/console.sock
ram_mib=${SUN4U_RAM_MIB:-1536}
case "$ram_mib" in
    512|1024|1536) ;;
    *) echo "unsupported SUN4U_RAM_MIB: $ram_mib (expected 512, 1024 or 1536)" >&2; exit 2 ;;
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

actual_qemu_sha256=$(
    docker run --rm --entrypoint /usr/bin/sha256sum "$image" \
        /usr/bin/qemu-system-sparc64 | awk '{print $1}'
)
if [ "$actual_qemu_sha256" != "$qemu_sha256" ]; then
    echo "wrong qemu-system-sparc64: expected $qemu_sha256, got $actual_qemu_sha256" >&2
    exit 1
fi

mkdir -p "$run_dir"
if [ -e "$console_log" ] || [ -e "$console_socket" ]; then
    echo "run directory is not fresh: $run_dir" >&2
    exit 1
fi

cleanup() {
    docker stop -t 5 "$container" >/dev/null 2>&1 || true
    docker rm -f "$container" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d \
    --name "$container" \
    --cpus 1 \
    --memory 2048m \
    --mount "type=bind,src=$iso,dst=/media/textinstall-134-sparc.iso,readonly" \
    --mount "type=bind,src=$(dirname "$firmware"),dst=/firmware,readonly" \
    --mount "type=bind,src=$run_dir,dst=/run/sun4u" \
    --entrypoint /usr/bin/qemu-system-sparc64 \
    "$image" \
    -M sun4u \
    -m "$ram_mib" \
    -smp 1 \
    -boot d \
    -vga none \
    -bios "/firmware/$(basename "$firmware")" \
    -cdrom /media/textinstall-134-sparc.iso \
    -prom-env input-device=ttya \
    -prom-env output-device=ttya \
    -prom-env 'auto-boot?=false' \
    -display none \
    -monitor unix:/run/sun4u/monitor.sock,server=on,wait=off \
    -chardev socket,id=console,path=/run/sun4u/console.sock,server=on,wait=off,logfile=/run/sun4u/console.log,logappend=on \
    -serial chardev:console \
    >"$run_dir/container-id.txt"

wait_for_console() {
    pattern=$1
    limit=$2
    elapsed=0

    while ! grep -Fq "$pattern" "$console_log" 2>/dev/null; do
        if [ "$(docker inspect "$container" --format '{{.State.Running}}' 2>/dev/null || true)" != true ]; then
            echo "QEMU container stopped before console pattern: $pattern" >&2
            docker logs "$container" >&2 || true
            return 1
        fi
        if [ "$elapsed" -ge "$limit" ]; then
            echo "timed out after ${limit}s waiting for console pattern: $pattern" >&2
            tail -100 "$console_log" >&2 || true
            return 1
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
