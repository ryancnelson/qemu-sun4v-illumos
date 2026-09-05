# Run 100: fresh boot blocked by host storage

Run 100, commit 5d315109f16622ccd7981b9fc27ce2e65699a37b, passed seed
preparation, freeze, and golden container build. Woodpecker step 1345
(`golden-amd64-test-first`) exited 137 before console output. The ec2cicd
kernel journal records `No space left on device` at 2026-09-05 18:10:50 UTC,
matching the failure. No OOM event was found in the inspected interval;
the precise cause of signal 9 is unproven because cleanup discarded Docker
state and startup output.

The next revision stages AMD64 runs under `/tank/niagara-ci/golden-volume/`
and updates ARM64's source path accordingly. After a verified freeze it
captures seed evidence and removes the seed container and writable volume,
avoiding two simultaneous extracted root volumes. Evidence now includes
Docker state and startup logs, and repeat cleanup preserves previous captures.

Neither architecture's customer cold-boot acceptance passed in run 100.

Run 106 (ace0cc7) successfully froze and booted payload root SHA-256
7152bf1485df6fe9f5365eede290144a333a2fb184b9c31cad6f2f5f0e3e9ca1.
The fresh boot reached login and passed runtime/release-readiness checks,
but still printed the generic.xml apply warning. Clean-boot acceptance remains
failed. The next diagnostic captures manifest/profile service logs at the
failure gate. Completed run 100 was moved intact to
/tank/niagara-ci/golden-volume-archive/golden-volume-amd64-100 to recover
root filesystem space during run 106 extraction.

Run 108 captured the cause of the remaining warning: generic.xml line 44
includes missing /etc/svc/profile/name_service.xml. Manifest-import logs
report the missing XInclude on both seed and frozen-volume boots. Restore the
missing link to the guest's own ns_dns.xml (matching the appliance DNS policy),
record its contents and hash, and validate generic.xml. The repair refuses to
overwrite any existing file or symlink. Subsequent cold boots still must pass
the unchanged warning rejection gate.
