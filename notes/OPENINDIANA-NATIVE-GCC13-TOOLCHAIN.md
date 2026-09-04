## Native gcc-13 on oi-basecamp, without pkg

Related but separate from the boot-path story above: got a native C compiler working on the running OpenIndiana/Niagara guest (`oi-basecamp`), bypassing `pkg` entirely.

### Why `pkg install` doesn't work

Every native toolchain package on this host's repo (`pkg.openindiana.aurora-opencloud.org/oi-sparc`) is currently blocked:

- `developer/gcc-7`, `developer/gcc-13`, and `developer/illumos-gcc` all require `developer/gnu-binutils`.
- `metapackages/build-essential` requires `compress/lzip`.
- Both `gnu-binutils@2.46.1-2026.0.0.0` and `compress/lzip@1.26-2026.0.0.0` are rejected by the solver as "excluded by installed incorporation `consolidation/userland/userland-incorporation@0.5.11-2026.0.0.32451`" — even after `pkg refresh --full`.

This isn't a local misconfiguration. Verified via `pkg contents -r -m developer/gnu-binutils` that the rejected package is a real, sparc-native build (every binary tagged `elfarch=sparc elfbits=64`, proper `usr/gnu/lib/sparcv9/` paths) — the repo's `userland-incorporation` snapshot has simply moved to a newer build baseline than the last time `gnu-binutils`/`compress/lzip` were rebuilt for sparc, and `pkg list -a` shows only one version of each (no older matching pair to fall back to). It's a build-lineage gap on the mirror, not something fixable client-side.

### What actually worked

The `dlc.openindiana.aurora-opencloud.org/SPARC/` tree has prebuilt toolchain tarballs that sidestep `pkg` completely:

1. **gcc itself**: `gcc-13.4.0.tar.xz` from that mirror, extracted to `/jack/13`. Self-contained gcc/g++/cc1/etc targeting `sparcv9-sun-solaris2.11`, but it does *not* bundle an assembler or base C runtime startup objects.

2. **`as`**: pulled the actual file content out of the (otherwise pkg-solver-blocked) `developer/gnu-binutils` package with `pkgrecv --raw` — `pkgrecv` fetches package content directly without dependency solving, so the incorporation block never applies. Located the file by its content hash from the package manifest (`pkg contents -r -m developer/gnu-binutils`) and copied it to `/jack/localbin/as`.

3. **`crt1.o`, `crti.o`, `crtn.o`, `values-Xa.o`, `values-xpg6.o`**: not shipped by the gcc tarball, and genuinely absent anywhere on this image (this appears to be a minimal/live-media root, not a full `pkg install entire` target). Extracted from `illumos-sysroot-sparc-20260117-31d3d510d0-v1.tar.gz` on the same `dlc.` mirror (despite the `.tar.gz` name, that file is actually xz-compressed — `gtar -xJf`, not `-xzf`).

### Wrapper

`/jack/gcc13` (symlinked as `/jack/g++13` / `/jack/c++13`) wires up `PATH` and `-B` so it's a drop-in `gcc`/`g++`:

```bash
#!/bin/bash
export PATH="/jack/localbin:$PATH"

case "$(basename "$0")" in
    g++13|c++13)
        exec /jack/13/bin/g++ -B/jack/sysroot/usr/lib/sparcv9 "$@"
        ;;
    *)
        exec /jack/13/bin/gcc -B/jack/sysroot/usr/lib/sparcv9 "$@"
        ;;
esac
```

Confirmed working: `/jack/gcc13 t.c -o t && ./t` compiles and runs a native SPARC binary.

**Known gap**: `g++13` currently fails — `sys/ccompile.h` (a base `/usr/include` system header, not part of the gcc tarball) is missing. Same category of problem as the crt objects; just haven't pulled it yet.

All of this survived a container restart intact (`/jack` sits on `distpool/ROOT/openindiana`'s persistent zpool), so it doesn't need to be redone per boot — just re-run `BRING_UP_NETWORKING.sh` first if you need to fetch anything new, since PPP networking doesn't come up automatically on its own.
