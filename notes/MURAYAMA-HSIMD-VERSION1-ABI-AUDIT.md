# Modern hsimd (Murayama build) ABI audit — evidence note, 2026-08-25

Status: audit complete for the purpose of unblocking Basecamp restoration.
NOT compiled, NOT loaded, NOT applied to any live guest. Basecamp
restoration on playbox takes priority per chief-engineer order; this note
preserves the finding so it is not lost.

## Root cause, proven

`hsimd.masa.driver` (SHA-256 `c01ffda8cdab0d0e003600a77fcf0f70bbb3c057eb6ce8cba6e1e1e7acc5c3d0`,
byte-identical to the shar-embedded original in `dist-pkg/hsimd.pkg.shar`,
built 2026-08-01 JST by root@takeshi) was compiled selecting the
`TG_DK_OPS_VERSION_0` branch of `hsimd.c` (confirmed via symbol table: local
symbols `hsimd_tg_getphygeom`/`getvirtgeom`/`getcapacity`/`getattribute`
present; `hsimd_tg_getinfo`, the VERSION_1 dispatcher, absent).

The target guest kernel (`illumos-31d3d510d0`, exact commit
`31d3d510d0d442d3e0ff619d2c80269ab236be55`, 2025-02-17, "13095 ZFS ARC
minimum size is too large") has, in its `cmlb_attach()`
(`usr/src/uts/common/io/cmlb.c`, verified at this EXACT commit via
`/export/solaris/illumos-ppp-src`, a real illumos-gate clone whose
`cmlb.h`/`cmlb.c` are diff-empty against that exact commit):

```c
if (tgopsp->tg_version < TG_DK_OPS_VERSION_1)
    return (EINVAL);
```

This is an unconditional version gate. A driver passing `tg_version =
TG_DK_OPS_VERSION_0` (0) is rejected before any read/write/geometry logic
runs. `hsimd_attach()`'s own `cmn_err` size/cap prints happen BEFORE this
call and are unaffected — they are real and correct, and do not indicate
`cmlb_attach()` succeeded.

## Fix identified: build-configuration only, NO source edit needed

`hsimd.c` itself never defines `TG_DK_OPS_VERSION_1`; it only tests
`#ifdef TG_DK_OPS_VERSION_1` (12 conditional regions across the file,
lines 222, 338, 508, 553, 669, 1075, 1148, 1302, 1487, 1613, 1621, 2136,
2151, 2164). The VERSION_1 code paths are ALREADY FULLY WRITTEN and
correct (e.g. `hsimd_tg_getinfo()` at ~line 1621 is a complete dispatcher
calling the same underlying getter functions as the VERSION_0 path) — not
stubs.

The `OS_OI`/`#else` branches in `hsimd.c` (lines 37, 64) both resolve to
the identical `#include <sys/cmlb.h>` — the only real difference is a
`sigset32_t` typedef workaround needed under `OS_OI`. This proves
`TG_DK_OPS_VERSION_1`'s definedness is controlled ENTIRELY by which
`cmlb.h` the compiler's include path resolves, not by any macro internal
to hsimd.c.

`Makefile` (`guest-util/hsimd/Makefile`) already has a prepared
`${BINDIR64_OI}/hsimd` OpenIndiana build rule with `-DOS_OI -I/export/code/illumos-gate/usr/src/uts/common`
— but `all:` targets only `${BINDIR64}/${DRV}` (the plain Solaris rule);
the OI rule is present but INACTIVE, and its `-I` path
(`/export/code/illumos-gate/...`) does not exist on biggie.

**Minimal fix:** rebuild with `-DOS_OI` and `-I` pointed at the confirmed
correct, exact-revision-matching header source:
`/export/solaris/illumos-ppp-src/usr/src/uts/common` (+ `.../uts/sun4v`),
widened via `git sparse-checkout add` from that repo's existing clone
(local op, commit `4cbfa3d9c1d7c65917609680798c9d756df4eb04`, `cmlb.h`
diff-empty against `31d3d510d0...`). No edit to `hsimd.c` should be
required.

## Candidate location (prepared, unmodified)

`/home/ryan/devel/masa-sun4v/hsimd-version1-candidate/hsimd.c` — byte-exact
copy of the original, SHA-256 `b7af2cba8ba12c8ecd5cd6355d8cffb3b18bb1cc9ae06feb7f076f596fbe1167`.

## Toolchain question, NOT resolved

Makefile assumes SunStudio `cc`/`/usr/ccs/bin/ld`. The proven working
toolchain in this project is GCC 7.3.0 / Binutils 2.39 on the Tribblix
donor (biggie PID 2064334), used for the custom 64-bit pppd build. Full
`CFLAGS64`/`KFLAGS_SUNCC` reconciliation against GCC flags is unresolved
and must happen before any compile attempt.

## Explicitly NOT done

- No compile, no `.o`, no link.
- No load into any guest.
- No edit to the original `hsimd.c` or `Makefile`.
- No fake-geometry or removable-media flag changes.
