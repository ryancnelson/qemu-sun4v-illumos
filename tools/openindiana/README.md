# OpenIndiana archive helpers

These are development-stage helpers used to build and observe the Niagara
OpenIndiana live image.  They are not yet a portable, one-command ISO builder.

- `patch-media-fs-root.py` adds the `hsimd` installation-media fallback.
- `patch-guest-chand-default.py` changes one verified big-endian placement word
  in a recovered SPARC binary; it refuses ambiguous inputs.
- `install-goodies-in-archive.sh` runs inside the Solaris donor with the PCFS
  exchange slice mounted at `/x`.
- `build-archive-*.exp` drive disposable Solaris donor VMs through their Unix
  console sockets.
- `guest-start.sh` is the OpenIndiana startup payload for channels 0 and 1.
- `boot-observe.exp` records an uninterrupted verbose boot.

The donor scripts write filesystems and use fixed device paths.  Read each
script, verify the console socket and disk layout, and use disposable images.
Do not run them against an irreplaceable Solaris VM or disk.  Their exact input
hashes and remaining packaging work are tracked in
`../../notes/OPENINDIANA-NEXT-ISO-TODO.md`.
