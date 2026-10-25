# DAD firmware coldboot: optional retained serial console

`scripts/coldboot-dad-retained.py` is distinct from the original diagnostic assets. It pins compiled dad-only firmware e235a3bbfdff9e5b4c364bf46757a0975265ff4ea52c95d891238b4be36813dc, QEMU1d5d578dd82a402be1a56d1eb52b29d59e50e7c4674a571a0ac4e3505e3e5abe and image56dac302ff0a10a576bd39f9df942e3833b759c5eb1b525ebd86f548f7bf022f. Deploy adjacent retention.py unchanged. Script SHA2562d058c758ab669d19ee049b7e60ad5eba6c9c3a0939f7d66b16eb1ebc6c57966; helper1a73b6e73faa3f8830d1af0888af2c5837966b5ee5febd9d48644bf8fda4022d.

Default mode retains bounded diagnostic stop/kill behavior. Only explicit --keep-running selects detached runtime with no Docker stdin, QEMU serial.sock/serial.log in the fresh evidence mount, and no automatic stop on controller deadline/EOF/cancellation. Never convert an active controller by editing its file. No mode declares boot PASS.

Owner launch requires an existing installed8GiB qcow2, independently established clean shutdown/offline disk identity, complete writer exclusion and exclusive-host contract. It never creates/resets a disk or attaches an ISO. This example is manual owner operation, never a CI step:

```sh
sudo python3 scripts/coldboot-dad-retained.py \
  --disk "${COLD_DISK:?verified existing disk}" \
  --firmware /mnt/disk-images/woodpecker/firmware132-dadcompat-kestrel/artifacts/openbios-sparc64.candidate \
  --qemu /home/niagara/devel/macapp-sun4u-001-cmd646-compat/artifacts/qemu-system-sparc64.candidate \
  --evidence "${COLD_EVIDENCE:?new short absolute evidence path}" \
  --offline-clean-shutdown-confirmed --exclusive-host-confirmed \
  --deadline 2100 --keep-running
sudo socat STDIO,raw,echo=0 "UNIX-CONNECT:$COLD_EVIDENCE/serial.sock"
sudo python3 scripts/coldboot-dad-retained.py reconcile \
  --evidence "$COLD_EVIDENCE" --owner "${EXACT_OWNER_TOKEN:?from retention.json}"
```

One console client at a time. Raw Ctrl-C may reach the guest; it is not a guaranteed detach action. Tested transport: pinned QEMU wrote266 bytes before any client, survived Unix disconnect/reconnect/EOF and socat1.8 stdin EOF, with log continuity. This was diskless firmware-only, not full retained OS acceptance. Smoke teardown needed exact-CID Docker stop after monitor-quit polling; exit0 did not prove monitor-only shutdown. Never use that teardown on a mounted installed guest. Owner clean in-guest halt, verified exact container exit and reconciliation remain required.

Retention records exact CID/owner/host-boot/preflight/configuration before start. Only observed OomKillDisable false/null representation change is normalized; true and all other fields remain compared. Sidecar lock ends with the controller; QEMU disk locking/no_openers and host exclusivity still matter. Serial logfile is uncapped and can contain credentials; owner must monitor space and retain restricted evidence. Host/storage failure remains outside guarantees. Reconcile is read-only with respect to guest lifetime and never stops/restarts/removes a retained container.

Run finite offline validation from any cwd:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/validate-dad-retained-assets.py
```

It pins source/tests/fixtures and the existing recorded firmware artifact under notes/firmware132-dadcompat-build, runs39 tests under a60-second limit, and rejects subprocess/socket operations. The Woodpecker coldboot-assets workflow runs this command only on its existing asset-validation branch. Result means assetvalidation; installed coldboot success is NOT_TESTED. No Docker, guest, installed-disk access or native workflow is added. Firmware provenance is the existing producer bundle, not a rebuild or a later recipe artifact containing extra patches.
