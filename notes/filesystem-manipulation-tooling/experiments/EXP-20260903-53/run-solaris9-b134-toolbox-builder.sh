#!/bin/bash

set -euo pipefail

base=/mnt/disk-images/solaris9-sun4m-trial/Data
carrier=/mnt/disk-images/solaris9-sun4m-trial/b134-layout-carrier.iso
trial=/mnt/disk-images/solaris9-b134-ufsboot-trial-001
loader=$trial/b134-wanboot.iso
payload=$trial/b134-hsimd-payload.iso
candidate=$trial/candidate-hsimd-tools.raw
run_root=$trial/toolbox-runs
image=solaris9-sun4m-workbench:arm64
name=solaris9-b134-toolbox-builder
stamp=$(date -u +%Y%m%dT%H%M%SZ)
run=$run_root/$stamp

test -r "$base/disk-0.qcow2"
test -r "$base/ss5.bin"
test -r "$carrier"
test -r "$loader"
test -r "$payload"
test -f "$candidate"
mkdir -p "$run"
docker rm -f "$name" >/dev/null 2>&1 || true

date -u +SOLARIS9_TOOLBOX_BUILDER_START_UTC=%Y-%m-%dT%H:%M:%SZ | tee "$run/timing.txt"

docker run -d --rm \
  --name "$name" \
  --cpus 1 \
  --memory 768m \
  --mount type=bind,src="$base",dst=/base,readonly \
  --mount type=bind,src="$carrier",dst=/carrier.iso,readonly \
  --mount type=bind,src="$loader",dst=/loader.iso,readonly \
  --mount type=bind,src="$payload",dst=/payload.iso,readonly \
  --mount type=bind,src="$trial",dst=/candidate \
  --mount type=bind,src="$run",dst=/run \
  "$image" \
  -name 'Solaris 9 B134 boot-archive toolbox builder' \
  -machine SS-5,graphics=off \
  -accel tcg,tb-size=64 \
  -smp cpus=1,sockets=1,cores=1,threads=1 \
  -m 256 \
  -rtc base=localtime \
  -bios /base/ss5.bin \
  -prom-env 'auto-boot?=false' \
  -prom-env 'boot-device=disk0' \
  -prom-env 'input-device=ttya' \
  -prom-env 'output-device=ttya' \
  -device scsi-hd,bus=scsi.0,channel=0,scsi-id=0,drive=drive0,bootindex=0 \
  -drive if=none,media=disk,id=drive0,format=qcow2,snapshot=on,file=/base/disk-0.qcow2 \
  -device scsi-hd,bus=scsi.0,channel=0,scsi-id=1,drive=drive1 \
  -drive if=none,media=disk,id=drive1,format=qcow2,snapshot=on,file=/base/disk-1.qcow2 \
  -device scsi-hd,bus=scsi.0,channel=0,scsi-id=2,drive=drive2 \
  -drive if=none,media=disk,id=drive2,format=qcow2,snapshot=on,file=/base/disk-2.qcow2 \
  -device scsi-hd,bus=scsi.0,channel=0,scsi-id=3,drive=drive3 \
  -drive if=none,media=disk,id=drive3,format=qcow2,snapshot=on,file=/base/disk-3.qcow2 \
  -device scsi-hd,bus=scsi.0,channel=0,scsi-id=4,drive=drive4 \
  -drive if=none,media=disk,id=drive4,format=qcow2,snapshot=on,file=/base/disk-4.qcow2 \
  -device scsi-hd,bus=scsi.0,channel=0,scsi-id=5,drive=candidate \
  -drive if=none,media=disk,id=candidate,format=raw,cache=writeback,file=/candidate/candidate-hsimd-tools.raw \
  -device scsi-cd,bus=scsi.0,channel=0,scsi-id=6,drive=payload \
  -drive if=none,media=cdrom,id=payload,format=raw,readonly=on,file=/payload.iso \
  -net nic,model=lance,macaddr=4E:B0:83:C6:5F:69 \
  -net user \
  -display none \
  -serial unix:/run/console.sock,server=on,wait=off \
  -monitor unix:/run/monitor.sock,server=on,wait=off \
  -qmp unix:/run/qmp.sock,server=on,wait=off \
  > "$run/container.id"

ln -sfn "$run" "$run_root/latest"
echo "SOLARIS9_TOOLBOX_BUILDER_RUN=$run"
echo "SOLARIS9_TOOLBOX_BUILDER_CANDIDATE=$candidate"
