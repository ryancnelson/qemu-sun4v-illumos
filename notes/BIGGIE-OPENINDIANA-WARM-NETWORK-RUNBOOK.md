# Biggie OpenIndiana warm-network runbook

This is the preserved **legacy shared-carrier** runbook that reproduced the
Exabyt `oi-archive-builder-exa-01` capability on Biggie without modifying or
reusing another live run. New managed trials use a dedicated unit-101 channel
disk and `tools/openindiana/launch-biggie-warm-60g.sh`; this launcher requires
an explicit `ALLOW_LEGACY_SHARED_CARRIER=1` acknowledgement. The working trial was
`OI-WARM-NET-BIGGIE-20260826-01`, visible in tmux session
`oi-warm-network-biggie-01`.

## Acceptance gates

1. QEMU owns run-local QEMU, firmware/NVRAM, unit-100 carrier and installer
   files.  The run-local installer copy is attached writable as hSIMD unit 103
   because the current hSIMD/media preparation path fails before `/.cdrom` and
   `/usr` when the backend is read-only.  QEMU has no controlling
   terminal and exposes Unix serial and monitor sockets.
2. Boot from OBP with `boot /virtual-devices@100/disk@3:d -k -v`.
3. At the installer menu choose shell.  `/` must be a writable RAM root;
   `/.cdrom` must be unit-103 slice 0; `/usr` and `/mnt/misc` must be lofi
   mounts.
4. Extract the pre-staged payload from unit 100.  Keep serial commands below
   256 characters:

       dd if=/dev/rdsk/c4d0s2 of=/tmp/p.tar bs=512 skip=131072 count=600
       tar xpf /tmp/p.tar -C /
       chown -R root:sys /lib/niag /etc/rc2.d/S99niagara
       chmod 755 /lib/niag/* /etc/rc2.d/S99niagara

5. The shared-disk channel is at byte 327680 of the same safe unit-100 carrier.
   Start the guest side with:

       NIAG_CHAN_DEV=/dev/rdsk/c4d0s2 /etc/rc2.d/S99niagara start

6. Confirm `ppp0` has guest `10.0.5.15`, add default route if absent, and write
   `/etc/resolv.conf`.  All pings are bounded:

       /usr/sbin/ping 10.0.5.1 56 3
       /usr/bin/perl -e 'alarm 10; exec @ARGV' /usr/sbin/ping -s 8.8.8.8 56 3

7. Biggie must have IPv4 forwarding and an exact-source NAT rule for
   `10.0.5.15/32`.  Its writable NFS export is `/export/solaris`.
   Prepare and verify NFS plus the disposable 512 MiB iSCSI target with:

       tools/openindiana/prepare-biggie-oi-services.sh SESSION

   Mount NFS in the guest and prove both read and write:

       mkdir -p /mnt/nfs
       mount -F nfs -o vers=3,proto=tcp 10.0.5.1:/export/solaris /mnt/nfs

   Discover the target with the native initiator.  Discovery alone is not the
   acceptance gate: confirm the LUN appears and perform a bounded disposable
   read/write probe before marking iSCSI passed.
8. Record UTC timestamps for launch request, boot command, shell ready, PPP up,
   Internet gate, NFS gate and iSCSI gate in the run's `timestamps.log`.

## Gilfoyle hypothesis log

For every gate write: hypothesis, one discriminating observation, result, and
next action.  Activity is not evidence.  A successful boot is not evidence of
PPP; a PPP interface is not evidence of Internet routing; discovery is not
evidence that an iSCSI LUN is writable.

## Safety

- Never type into a Solaris donor console.
- Never send Control-C to a QEMU terminal.  The owner script deliberately gives
  QEMU no controlling terminal.  Use the monitor socket for explicit stop/quit.
- Never use unbounded `ping` on a serial console.
- Do not write a backing image while QEMU owns it except through the established
  shared channel region.
- Every launch gets a new run directory, carrier copy, firmware copy and tmux
  session.  A pre-existing path is a launch failure, not permission to reuse it.
