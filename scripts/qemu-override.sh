#!/usr/bin/env bash
# Explicit binary-only override. Never changes image, entrypoint or QEMU flags.
prepare_qemu_override() {
    qemu_mount_args=()
    qemu_compat_args=()
    qemu_override=0
    qemu_b134_compat=${SUN4U_CMD646_B134_COMPAT:-0}
    case "$qemu_b134_compat" in 0|1) ;; *)
        echo 'SUN4U_CMD646_B134_COMPAT must be 0 or 1' >&2; return 2 ;;
    esac
    qemu_binary=${SUN4U_QEMU_BINARY:-}
    local expected=${SUN4U_QEMU_SHA256:-} actual
    if [[ -z "$qemu_binary" && -z "$expected" ]]; then
        if [[ "$qemu_b134_compat" == 1 ]]; then
            echo 'B134 compatibility requires explicit validated QEMU binary override' >&2; return 2
        fi
        return 0
    fi
    if [[ -z "$qemu_binary" || ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        echo 'QEMU override requires SUN4U_QEMU_BINARY and lowercase 64-hex SUN4U_QEMU_SHA256' >&2
        return 2
    fi
    # --mount uses CSV syntax: reject ambiguous path delimiters, not spaces.
    if [[ "$qemu_binary" != /* || "$qemu_binary" == *','* ||
          "$qemu_binary" == *$'\n'* || "$qemu_binary" == *$'\r'* ||
          ! -f "$qemu_binary" || ! -x "$qemu_binary" || -L "$qemu_binary" ]]; then
        echo 'QEMU override must be an absolute regular executable (no symlink/comma/newline)' >&2
        return 2
    fi
    actual=$(sha256sum <"$qemu_binary") || return 2
    actual=${actual%% *}
    if [[ "$actual" != "$expected" ]]; then
        echo "QEMU override host hash mismatch: expected $expected, got $actual" >&2
        return 2
    fi
    command -v timeout >/dev/null || { echo 'QEMU override requires timeout' >&2; return 2; }
    qemu_mount_args=(--mount "type=bind,src=$qemu_binary,dst=/usr/bin/qemu-system-sparc64,readonly")
    qemu_sha256=$expected
    qemu_override=1
    if [[ "$qemu_b134_compat" == 1 ]]; then
        qemu_compat_args=(-global cmd646-ide.x-b134-status-compat=on)
    fi
}

verify_qemu_override_runtime() {
    [[ "$qemu_override" == 1 ]] || return 0
    local actual
    actual=$(timeout -k 5 30 docker run --rm --cpus 1 --memory 2048m \
        "${qemu_mount_args[@]}" --entrypoint /usr/bin/sha256sum "$image" \
        /usr/bin/qemu-system-sparc64) || return 2
    actual=${actual%% *}
    if [[ "$actual" != "$qemu_sha256" ]]; then
        echo "QEMU override runtime hash mismatch: expected $qemu_sha256, got $actual" >&2
        return 2
    fi
    # Loader/architecture/shared-library smoke only: --version starts no guest.
    qemu_override_version=$(timeout -k 5 30 docker run --rm --cpus 1 --memory 2048m \
        "${qemu_mount_args[@]}" --entrypoint /usr/bin/qemu-system-sparc64 \
        "$image" --version) || return 2
    if [[ "$qemu_b134_compat" == 1 ]]; then
        local properties
        # Device property help exits without instantiating a guest machine.
        properties=$(timeout -k 5 30 docker run --rm --cpus 1 --memory 2048m \
            "${qemu_mount_args[@]}" --entrypoint /usr/bin/qemu-system-sparc64 \
            "$image" -device cmd646-ide,help 2>&1) || return 2
        if ! grep -Eq '^[[:space:]]*x-b134-status-compat=<bool>([[:space:]]|$)' <<<"$properties"; then
            echo 'Override binary lacks confirmed boolean x-b134-status-compat property' >&2
            return 2
        fi
    fi
}
