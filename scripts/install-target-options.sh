#!/usr/bin/env bash
# Sourced by the proposed harness; no actions are performed by sourcing.
parse_install_options() {
    install_target_gib=${SUN4U_INSTALL_TARGET_GIB:-0}
    install_bus=${SUN4U_INSTALL_BUS:-ide}
    keep_guest=${SUN4U_KEEP_GUEST:-0}
    keep_maintenance=${SUN4U_KEEP_MAINTENANCE:-0}
    observe_seconds=${SUN4U_INSTALL_OBSERVE_SECONDS:-120}
    case "$install_target_gib" in 0|4|8|16) ;; *) echo 'Target GiB must be 0 (off), 4, 8, or 16' >&2; return 2 ;; esac
    case "$install_bus" in ide|lsi53c810) ;; *) echo 'Install bus must be ide or lsi53c810' >&2; return 2 ;; esac
    case "$keep_guest" in 0|1) ;; *) echo 'KEEP_GUEST must be 0 or 1' >&2; return 2 ;; esac
    if [[ ! "$observe_seconds" =~ ^[0-9]{1,3}$ ]] || ((10#$observe_seconds > 600)); then
        echo 'Observation must be integer seconds, 0..600' >&2; return 2
    fi
    observe_seconds=$((10#$observe_seconds))
    if [[ "$install_target_gib" == 0 && "$keep_guest" == 1 ]]; then
        echo 'Guest preservation requires explicit install-target mode' >&2; return 2
    fi
    case "$keep_maintenance" in 0|1) ;; *) echo 'KEEP_MAINTENANCE must be 0 or 1' >&2; return 2 ;; esac
    target_mount_args=()
    target_qemu_args=()
    preserve_ready=0
}

prepare_install_target() {
    [[ "$install_target_gib" != 0 ]] || return 0
    # Require capacity for the entire virtual disk plus 1 GiB host reserve,
    # not just the sparse qcow2 header. This is not a guarantee against other
    # concurrent writers: recheck available storage before beginning installation.
    target_dir="$run_dir/install-target"
    if [[ -e "$target_dir" || -L "$target_dir" ]]; then
        echo "Refusing existing target directory: $target_dir" >&2; return 1
    fi
    available_kib=$(df -Pk "$run_dir" | awk 'END {print $4}')
    [[ "$available_kib" =~ ^[0-9]+$ ]] || { echo 'Cannot determine free space' >&2; return 1; }
    required_kib=$(((install_target_gib + 1) * 1024 * 1024))
    if ((available_kib < required_kib)); then
        echo "Insufficient disk headroom: available=${available_kib}KiB required=${required_kib}KiB" >&2
        return 1
    fi
    # Atomic directory creation prevents two invocations claiming one target.
    mkdir "$target_dir"
    docker run --rm --mount "type=bind,src=$target_dir,dst=/target" \
        --entrypoint /usr/bin/qemu-img "$image" \
        create -f qcow2 /target/install.qcow2 "${install_target_gib}G"
    [[ -s "$target_dir/install.qcow2" ]] || { echo 'qemu-img produced no disk' >&2; return 1; }
    target_mount_args=(--mount "type=bind,src=$target_dir,dst=/target")
    case "$install_bus" in
        ide)
            target_qemu_args=(-drive 'file=/target/install.qcow2,if=ide,index=0,format=qcow2') ;;
        lsi53c810)
            # Leave the boot CD on its original IDE controller. This tests
            # kernel discovery; firmware bootability is a separate gate.
            target_qemu_args=(-device 'lsi53c810,id=install-scsi,bus=pciB,addr=1'
                -drive 'file=/target/install.qcow2,if=none,id=install-disk,format=qcow2'
                -device 'scsi-hd,drive=install-disk,bus=install-scsi.0,scsi-id=0,lun=0') ;;
    esac
    echo "install_target_bus=$install_bus"
    echo "fresh_install_target=$target_dir/install.qcow2"
    echo "target_virtual_gib=$install_target_gib host_available_kib=$available_kib"
}
