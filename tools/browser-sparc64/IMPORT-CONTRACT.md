# Pinned artifact import

`bash import-artifacts.sh /path/to/exported-build` now requires all three QEMU
companions to match the adjacent shipped `ASSET-SHA256SUMS` before creating or
changing `assets/`. Syntax, Wasm magic, and existing-file collision checks remain.

For a separately reviewed candidate bundle, deliberately supply its independent
pins: `bash import-artifacts.sh '/path/to/candidate build' --expected-manifest
'/path/to/reviewed/SHA256SUMS'` (one shell command). Do not generate a manifest
from untrusted inputs as a substitute for independent expected identities.

The manifest requires exactly one SHA256 entry for each canonical name:

- `assets/qemu-system-sparc64.js`
- `assets/qemu-system-sparc64.wasm`
- `assets/qemu-system-sparc64.worker.js`

Format: 64 hexadecimal characters, two spaces, canonical name. An optional
`assets/openbios-sparc64.patched` entry is accepted to support the shipped full
manifest, but is neither imported nor validated by this three-companion importer.
Unknown names, blank/malformed lines, duplicates and incomplete sets fail closed.
The source JS may still be extensionless; its expected identity uses the canonical
`.js` name. No destination/name override exists. Python 3 is now required in
addition to the existing Bash, Node, rg and core utilities.

Run `python3 test-import-artifacts.py` for tiny actual-script host fixtures.
Matching hashes establish expected byte identity only, not ABI compatibility,
browser execution, firmware boot, or an independently trustworthy manifest.

All input, syntax and collision refusals precede destination mutation, including
a mismatch in the last companion. This is not a transactional filesystem import:
I/O failures during copying may leave a partial set, and concurrent source or
destination changes are not locked out. Use stable source files and an exclusively
owned destination; preserve existing collision refusal rather than overwriting.
