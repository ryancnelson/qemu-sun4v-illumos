# Frozen fresh-launch serial candidate

Owned local directory: `~/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/fresh-serial-boot-trellis`.
Runtime files: `coldboot_fresh.py`, `fresh_serial.py`, `boot_protocol.py`, `retention.py` together. No shared edits, commit/push or installed-disk execution.

Hashes:
- harness `992eeabb90c143bf0388cc8bac568d9f1820556d1178814d9e33f9b49fa828ee`
- driver `d8d69a4e7f141ceea99a84d0bf0ecad65772b301a8e8305a746f7643a53858df`
- protocol `5bf439b36d4af616ebe41c5d11d8f5828bee8cde7335d94c7a0578e68681d46c`
- unchanged retention helper `a028fd3d728f89a59b2b81e86cb38e84cfc14882c0dca2f95504371c8a1b1600`
- patch `efd4abae1c75054e7cead5c65e2215868390339fae82d92336504234a57fb753`
- exact baseline current owner topology harness `18b38242fdcf31b448b8690c887a697e40257fcc2ec45bc83f8f6ee976b4cb81`.

`manifest.json`/`SHA256SUMS` contain all test/native evidence hashes. Patch applies to a copy of baseline renamed `coldboot_fresh.py`, adds driver/protocol; copy unchanged retention helper alongside. Standalone files are ready without patch application.

## Owner-only fresh installed-clone invocation — NOT executed here

```
sudo -n python3 /OWNER/NEW/CODE/coldboot_fresh.py \
  --disk /OWNER/OFFLINE/INSTALLED-CLONE.qcow2 \
  --firmware /mnt/disk-images/woodpecker/firmware132-dad-topology-kestrel/artifacts/openbios-sparc64.candidate \
  --qemu /home/niagara/devel/macapp-sun4u-001-cmd646-compat/artifacts/qemu-system-sparc64.candidate \
  --evidence /mnt/disk-images/woodpecker/OWNER-NEW-SHORT-UNIQUE-DIRECTORY \
  --offline-clean-shutdown-confirmed --exclusive-host-confirmed \
  --keep-running --serial-boot --exclusive-console-confirmed --deadline 2100
```

Replace OWNER paths only after clean shutdown/offline clone identity approval. Evidence must NOT exist; keep its Unix socket pathname within Linux length limits. No ISO, disk creation/reset or existing guest attach. Expected controller exit2, never automatic PASS. Default no-serial-boot argv/session behavior unchanged. Reconcile uses unchanged `reconcile --evidence ... --owner ...` command, read-only export.

`--serial-boot` requires retention and explicit operator-exclusive-console contract. Fresh0700 evidence and exclusive controller lock precede container creation. Only serial chardev changes to `server=on,wait=on`; inherited monitor/debug remain unchanged. Exact CID/owner, retained fingerprint/bootID/preflight and firmware bind hash checked before connect. Exact firmware1537670b... and QEMU1d5d578d... remain pinned. Wait source proof: saved exact QEMU char-socket.c SHA6926e236... lines1221-1223 synchronously accept first client before open returns, versus wait-off callback. Same source path/hashes in prior serial-driver report.

Trusted host contract excludes other active/queued serial clients until controller closes; passive logfile tail viewers allowed. Lock does NOT exclude privileged/manual bypass or clients ignoring ownership. No claim of adversarial atomic admission. Driver only handles its fresh launch; no attach CLI. On timeout/EOF/cancel/error it closes client, retains QEMU and reconciles; does not auto-stop. Controller lock releases on exit; owner then takes console responsibility. Existing uncapped QEMU logfile/storage responsibility remains.

Driver waits for fresh OpenBIOS banner/prompt, exact command echo+ok acknowledgements, sends original power interrupts deletion, fdthree-disabled rename and `boot disk -v` without -a. No postboot input. RX raw and TX intent/completion journals retained. LOGIN means prompt only, never authentication or PASS; ROOT_MOUNT/PANIC observations preserved. Socket loop bounded by requested deadline,1MiB RX cap; inherited Docker validation/export calls separately bounded30s each, so total finalization can exceed the loop deadline. Delayed/partial send is explicitly uncertain in journal; no retries. Evidence-write failure cannot invoke guest stop.

## Tests/native result — no hidden success claim

51/51 host tests PASS, `full-tests.log`:
`python3 -m unittest -v test_fresh_serial.py test_retention_existing.py test_default_existing.py`
Includes default argv equality with baseline, mandatory flags, private/existing lock refusal, identity/firmware/wait mismatch, exact prep, failed send journal, EOF/cancel/deadline retained behavior, output failure, panic/login limits, inherited retention/ownership/disk refusal. Existing old test expectation `if=ide` updated only in owned fixture to current proven `if=none`+ide-hd topology; original mismatch log retained.

ONE diskless native smoke used exact pinned image/QEMU/topology firmware,128MiB/1CPU/512MiB cap/noNIC/networknone/no disk/ISO/OS. Remote code (same runtime bytes): `/mnt/disk-images/woodpecker/fsb-code-f6ac75fae86e42d5b91d83a9205b1184`.
Evidence `/mnt/disk-images/woodpecker/fsb-26a883d383bb48fead680935e629ee4c`; local `native-evidence/`, `native-evidence.tar`, `native-run.log`, `native-verified.json`.
Owner `26a883d383bb48fead680935e629ee4c`; exact CID `b29d94114dfe72f9453f2971e61bc3f9fd53ef55585a6c40f682f40fc6d15754`.

Verified zero serial bytes before first client; first banner/prompt received; all five command sends/acks recorded; raw622bytes exactly equals daemon serial logfile. Diskless `boot disk -v` produced Exception30/Stopping execution, correctly classified PANIC. Driver closed connection; cleanup-before inspect proves QEMU still Running=true. Only then authorized smoke-only `docker stop --time3` executed. Final Running=false/OOMfalse, container retained.

IMPORTANT: original smoke wrapper aggregate FAIL is preserved: it wrongly expected TIMEOUT rather than diskless PANIC. Subsequent reconnect and native reconcile assertions therefore did NOT execute. `verify_native.py` verifies the actual recorded first-client/log/disconnect/lifecycle milestones offline without rewriting result. No second guest launched. Not a full smoke PASS or installed-OS execution claim. Candidate source unchanged after that native run; owner installed-clone test/review remains separate.
