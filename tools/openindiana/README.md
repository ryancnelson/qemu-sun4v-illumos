# OpenIndiana archive helpers

These are development-stage helpers used to build and observe the Niagara
OpenIndiana live image.  They are not yet a portable, one-command ISO builder.

- `patch-media-fs-root.py` adds the `hsimd` installation-media fallback.
- `patch-noninteractive-console.py` converts the stock blocking keyboard and
  language questions to fixed development defaults without changing the UFS
  file length.
- `patch-guest-chand-default.py` changes one verified big-endian placement word
  in a recovered SPARC binary; it refuses ambiguous inputs.
- `install-goodies-in-archive.sh` runs inside the Solaris donor with the PCFS
  exchange slice mounted at `/x`.  It now fails closed unless the exchange
  slice also contains `RWGATE.SH` and `RWDEV.SH`, copied respectively from
  `../install-tribblix-devfsadm-rw-gate.sh` and
  `../tribblix-devfsadm-rw-wrapper.sh`.  The 8.3 names are deliberate for the
  PCFS handoff.  The builder verifies the wrapper marker and preserved real
  binary before it will publish an archive.
- `build-archive-*.exp` drive disposable Solaris donor VMs through their Unix
  console sockets.
- `guest-start.sh` is the OpenIndiana startup payload for channels 0 and 1.
- `boot-observe.exp` records an uninterrupted verbose boot.

The donor scripts write filesystems and use fixed device paths.  Read each
script, verify the console socket and disk layout, and use disposable images.
Do not run them against an irreplaceable Solaris VM or disk.  Their exact input
hashes and remaining packaging work are tracked in
`../../notes/OPENINDIANA-NEXT-ISO-TODO.md`.
