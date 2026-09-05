# guest-chand acknowledgement-wait coalescing

## Evidence and scope

The earlier OpenIndiana DTrace profile found approximately 0.9–1.0 ms per
raw hsimd request, nearly independent of size. Raw 64 MiB reads measured
3.77 MiB/s with 4 KiB requests and 107 MiB/s with 128 KiB requests.
The measured hypercall function duration was only 24–28 microseconds; with
the loaded async driver this is not a measurement of backend completion.
ZFS already batched file writes into mostly 128 KiB driver requests.

The network profile recorded 179 approximately 6 KiB guest-to-host payload
frames for a 1 MiB SSH transfer. This motivates batching at the socket/channel
boundary before considering disk-driver caching. The loaded driver reports
`v0.0.6_aio2`; correspondence to the vendored driver source remains unproved.

Original evidence remains on TedDeck in
`$HOME/vms/openindiana-io-profile-20260905/`. The earlier full report is in the
9401 worktree, `notes/OPENINDIANA-HSIMD-IO-PROFILE-2026-09-05.md`.

## Candidate change

Previously, guest-chand stopped reading its socket whenever it had any staged
outbound bytes. It retained that first chunk while waiting for the previous
frame's acknowledgement, even when more socket data was available.

The daemon now appends immediately available socket bytes to the existing
staging buffer, bounded by the protocol's 523,776-byte frame capacity. The
publication gate still requires acknowledgement of the previous frame.
The read loop stops at EAGAIN or capacity and services inbound traffic next.
Interrupted reads are retried. There is no new timer or intentional batching
delay, and the existing polling schedule and wire protocol are unchanged.

This can combine data queued during acknowledgement waits. It does not ensure
large frames when the socket supplies only one small chunk before each publish,
and it does not remove the existing polling latency. The controlled VM test
below measures the benefit for one chunked socket workload.

The host implementation also reads one socket chunk into an empty pending
buffer. Its larger frames in the earlier profile are observed behavior, not
evidence of an explicit timed coalescing algorithm on the host.

## Verification

Run `python3 tests/test-guest-chand-coalescing.py` on a Unix host with a C
compiler. The test compiles the actual daemon and uses a disposable regular
carrier file and Unix socket with native-endian control blocks.

- Before the patch: failed because the first published frame held 6,144 bytes
  instead of the two queued chunks totaling 12,288 bytes.
- After the patch: passes coalescing, withholding publication until ack,
  inbound progress while outbound is blocked, final-fragment flush at EOF,
  reconnection, and exact-byte delivery of more than two frame capacities.
- Native compilation uses `-O2 -Wall -Wextra` and produced no diagnostics.

The file-backed test establishes behavior and integrity, not raw-device timing
or SPARC binary compatibility.

## Live lab test

Verified TedDeck's `openindiana-sparc64` container and guest SSH are reachable.
Guest channels 0 and 1 are still served by PIDs 632 and 633. Their daemons were
not replaced. Temporary test daemons and PID-filtered DTrace ran on spare
channel 2. Only that channel's region was backed up and initialized for tests.

The working native compiler is `/jack/gcc13`, GCC 13.4.0. It was recovered
from prior notes after checks of conventional compiler paths missed it.
Baseline and candidate both compiled with `-O2 -Wall -Wextra -lsocket -lnsl`
to 64-bit SPARCV9 executables in `/var/tmp/chand-coalesce-a9c7/`.
See [important-facts.md](../important-facts.md) for the verified wrapper and
access details.

Both binaries used the same toolchain and flags. SHA-256:

```text
8696665fbd1fc2869c83b2a7693babbb1834b73375a9404b05fe00787bdabc72  baseline
38ee90a6174f376211d67507e8c1c3b3bcd9d9b33364d0291df162d65635a065  candidate
```

The guest producer sent 512 chunks of 6,144 bytes through a Unix socket to
the test daemon, with a 1 ms pause between chunks. The container-side test
receiver read raw channel frames and delayed each acknowledgement by 20 ms.
Timing starts with the first received frame and ends after the last ack;
SSH setup is excluded. All 3,145,728 bytes were compared against the expected
payload. Both results have SHA-256
`f4cbdc142097d87bbbb292dbde16768323caa1818a0ee995191b63fe55b99d83`.

| Measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Transfer time | 14.4537 s | 2.3621 s |
| Throughput | 0.2076 MiB/s | 1.2701 MiB/s |
| Payload frames / DTrace payload writes | 509 | 77 |
| 512-byte control writes | 509 | 77 |
| 512-byte control reads | 2,032 | 307 |

This is a 6.1x throughput improvement. Baseline frames were 508 x 6 KiB and
one 24 KiB frame; the candidate mostly published 36-48 KiB frames. DTrace
write sizes match the receiver's frame counts. Per-request costs remain
around a millisecond; the improvement comes from issuing fewer requests and
waiting for fewer acknowledgements.

The two preliminary baseline measurements were 0.2036 and 0.1940 MiB/s,
both with 510 frames. Their tracing procedure needed correction: first wait
for the probe-attachment message before sending data, then use SIGTERM and
verify tracer exit. Background tracers ignored SIGINT. The final baseline
and candidate above used the corrected procedure. Temporary earlier tracers
were stopped before those final measurements.

Raw results, final traces, and the exact lab scripts are preserved in
[the evidence directory](evidence/guest-chand-coalescing-20260905/).
The scripts contain run-specific hosts, paths and channel selection; recheck
those before reusing them.

This establishes a benefit for a controlled socket/channel workload on the
actual hsimd path. It does not measure PPP/SSH throughput or interactive RTT,
and the polling-delay outliers remain. No kernel driver change was made.

Cleanup passed: channel 2 was restored byte-for-byte from its backup, no
DTrace or test daemon remained, the original channel daemons were still
running, and the SSH service reported `online`.

Verified mapping: guest device `/dev/rdsk/c1d0s2`, host carrier
`/run/unit100/carrier-unit100.raw`, host channel-region byte offset 327680.
The live binary has a patched default guest base block of 640. A source build
must explicitly set `NIAG_CHAN_GUEST_BLK=640` in addition to the device override;
the source header's Solaris 10 default is not this VM's layout.

Next, test interactive round-trip latency and PPP/SSH separately; the spare
channel result alone cannot prove the end-to-end TCP improvement.
