# BBS KERMIT-GET

`KERMIT-GET` is the canonical spelling. `KERMET-GET` is accepted only as a
harmless compatibility alias. This command is deterministic and never calls
ASK or an LLM. Its argument must be one direct HTTP(S) URL; legacy `GET`
retains its existing behavior.

The BBS fetches into the configured run-owned `BBS_KERMIT_STAGE`, rejects an
unsafe or pre-existing basename, and replies with exactly:

```
KERMIT READY name=NAME size=DECIMAL sha256=64_LOWER_HEX timeout=45
```

Only then do both peers hand the existing channel-4 socket to G-Kermit. The
verified official G-Kermit 2.00 interface is `-X` for external protocol over
stdin/stdout, `-q -i`, host `-s PATH -a NAME`, and guest `-r -a TEMP`.
Transfers have a 45-second bound and one Session permits only one at a time.
The parent BBS retains the socket and resumes its prompt after DONE or FAILED.

The guest helper is `tools/chan/guest-kermit-get.pl`. It accepts only the
strict READY grammar and fixed timeout, receives into a new temporary regular
file below `/rpool/kermit`, verifies type, size, and SHA-256, attempts fsync
where supported, then atomically renames. It refuses existing destinations,
symlinks, traversal-bearing metadata, malformed replies, and absent tools.

## Bootstrap gap (2026-08-27)

Neither playbox nor the live OpenIndiana guest had `kermit`, `ckermit`, or
`gkermit` installed. No Perl or Python package with comparable maintained,
inspectable protocol coverage was identified. Do not install an unverified
binary into the live guest. The safest next step is a separate build gate for
the official `KermitProject/gkermit` 2.00 source: pin its commit and source
hash, build it for SPARC with the guest toolchain or a reproducible cross
toolchain, test host/guest interoperability on disposable sockets, record the
binary hash and runtime dependencies, and only then stage it for explicit
operator-approved guest installation.

The protocol, host sender handoff, guest receiver helper, validation, timeout,
cleanup, alias, and fake-process tests are implemented. They are **not live
accepted**: no real G-Kermit process has run at either endpoint and no file has
crossed channel 4 using this protocol. `KERMIT-GET` must return `NO_TOOL` until
both pinned binaries pass that separate gate. No live BBS restart or transfer
is part of this repository change.
