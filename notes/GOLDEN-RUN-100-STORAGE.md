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
