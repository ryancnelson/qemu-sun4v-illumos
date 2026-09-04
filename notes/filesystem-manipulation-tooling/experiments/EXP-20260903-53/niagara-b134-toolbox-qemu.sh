#!/bin/bash

set -euo pipefail

mkdir -p /state/firmware
cp -a /opt/illumos-appliance/firmware/. /state/firmware/
cp -p /opt/illumos-appliance/firmware/nvram1 /state/nvram.bin
if [[ -f /state/firmware/md.bin.manual ]]; then
    cp -p /state/firmware/md.bin.manual /state/firmware/md.bin
fi

exec /usr/local/bin/qemu-system-sparc64 \
    -name b134-hsimd-toolbox-v3-test-010 \
    -D /state/qemu-debug.log \
    -d guest_errors \
    -M niagara,nvram-file=/state/nvram.bin \
    -L /state/firmware \
    -m 3072 \
    -smp 1 \
    -display none \
    -monitor none \
    -qmp unix:/state/qmp.sock,server=on,wait=off \
    -serial file:/state/serial0.log \
  -chardev socket,id=guestconsole,path=/state/console.sock,server=on,wait=off,logfile=/state/console.log,logappend=on \
  -serial chardev:guestconsole \
  -drive id=carrier100,format=raw,if=none,bus=0,unit=100,readonly=off,cache=none,file.locking=off,file=/state/carrier-unit100.img \
  -drive id=b134boot,format=raw,if=none,bus=0,unit=106,readonly=on,cache=none,file.locking=off,file=/candidate/candidate-proven-hsimd-toolbox-v3-b134.raw \
  -drive id=b134media,format=raw,if=none,bus=0,unit=107,readonly=on,cache=none,file.locking=off,file=/candidate/textinstall-134-sparc.iso
