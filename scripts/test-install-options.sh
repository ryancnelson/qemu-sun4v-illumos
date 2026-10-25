#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/install-target-options.sh"
scratch=$(mktemp -d)
cleanup_tests() {
    # Exact fixture paths only; no recursive deletion.
    rm -f "$scratch/success/install-target/install.qcow2"
    rm -f "$scratch/scsi/install-target/install.qcow2"
    rmdir "$scratch/scsi/install-target" "$scratch/scsi" 2>/dev/null || true
    rmdir "$scratch/success/install-target" "$scratch/success" \
        "$scratch/existing/install-target" "$scratch/existing" \
        "$scratch/low" "$scratch" 2>/dev/null || true
}
trap cleanup_tests EXIT
unset SUN4U_INSTALL_TARGET_GIB SUN4U_KEEP_GUEST SUN4U_INSTALL_OBSERVE_SECONDS SUN4U_INSTALL_BUS
parse_install_options
[[ "$install_target_gib" == 0 && "$keep_guest" == 0 ]]
[[ ${#target_mount_args[@]} == 0 && ${#target_qemu_args[@]} == 0 ]]
if (SUN4U_KEEP_GUEST=1; parse_install_options); then exit 1; fi
if (SUN4U_INSTALL_TARGET_GIB=bogus; parse_install_options); then exit 1; fi
if (SUN4U_INSTALL_BUS=bogus; parse_install_options); then echo 'FAIL: invalid bus accepted'; exit 1; fi
if (SUN4U_INSTALL_OBSERVE_SECONDS=601; parse_install_options); then exit 1; fi
if (SUN4U_INSTALL_OBSERVE_SECONDS=-1; parse_install_options); then exit 1; fi
if (SUN4U_INSTALL_OBSERVE_SECONDS='x;true'; parse_install_options); then exit 1; fi

SUN4U_INSTALL_TARGET_GIB=8
SUN4U_KEEP_GUEST=1
parse_install_options
mkdir -p "$scratch/existing/install-target" "$scratch/low" "$scratch/success"
run_dir="$scratch/existing"
if prepare_install_target; then exit 1; fi
run_dir="$scratch/low"
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfake 10000000 9999000 1000 99%% /\n'; }
if prepare_install_target; then exit 1; fi
[[ ! -e "$run_dir/install-target" ]]
run_dir="$scratch/success"
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfake 20000000 1000000 19000000 5%% /\n'; }
image='mock-image-never-run'
docker() {
    [[ "$*" == *'create -f qcow2 /target/install.qcow2 8G'* ]] || return 1
    # Nonempty fixture, deliberately not a real disk. No Docker process runs.
    cp "${BASH_SOURCE[0]}" "$target_dir/install.qcow2"
}
prepare_install_target
[[ "${target_qemu_args[*]}" == '-drive file=/target/install.qcow2,if=ide,index=0,format=qcow2' ]]
[[ "$keep_guest" == 1 && "$preserve_ready" == 0 ]]
if prepare_install_target; then exit 1; fi
echo 'INSTALL_OPTIONS_TEST=PASS (mocked Docker, no VM launch)'
SUN4U_INSTALL_BUS=lsi53c810
parse_install_options
run_dir="$scratch/scsi"
mkdir "$run_dir"
prepare_install_target
[[ "${target_qemu_args[*]}" == '-device lsi53c810,id=install-scsi -drive file=/target/install.qcow2,if=none,id=install-disk,format=qcow2 -device scsi-hd,drive=install-disk,bus=install-scsi.0,scsi-id=0,lun=0' ]]
[[ "${target_qemu_args[*]}" != *'if=ide'* ]]
echo 'INSTALL_SCSI_OPTIONS_TEST=PASS (mocked Docker, no VM launch)'
