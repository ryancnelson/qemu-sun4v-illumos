# Nevada B134 resumption — 2026-10-24

Objective: install B134 on a disposable disk and cold-boot it with generic
QEMU sun4u and OpenBIOS, using Woodpecker for repeatable gates.

Recovered Woodpecker repository 2 runs 55, 58, and 67 from the controller's
read-only database. All passed. Run 67 commit is 5aee07f599; its source was
recovered from Biggie's existing Git object database. The private CI branch
subsequently added only documentation in 8baadcb.

The saved run67 artifacts on playbox passed their original SHA256 manifest:
firmware f56f9a3d8da8521f82ec162f4fe3cb5b1ae0d478da69e8aab551aa56ffd8d2f9.
The pinned workbench image is still present with the expected image ID.
Playbox was initially offline; Ryan started it on the MacBook Pro.

The original acceptance boundary is keyboard selection, language selection,
and Configuring devices. It does not prove installation or installed boot.
The harness deletes the power node's interrupts property and renames fdthree
before booting. Preserve those operations in the control experiment.

This isolated branch changes only the Woodpecker branch selector for the first
replay. Existing Tribblix graphics edits on Minnie remain untouched.
Replay first; then add a private installation disk and extend the gates to
installer completion, cold disk boot, writable root, networking, and reboot.
Do not report any of those later gates as passed without console evidence.

Before installation, check real disk allocation: playbox currently has 9.5 GiB
free on its 70 GiB data filesystem and 5.1 GiB free on its root filesystem.

## Baseline replay and browser-oriented RAM experiment

Run 132 reached SUN4U_OPENBIOS_BOOT=PASS at 1536 MiB: keyboard and
language selection followed by Configuring devices. Installation remains unproven.
Its rebuilt firmware differs from run 67; do not claim byte-identical recovery.

Ryan requested a 512 MiB trial, with Infinite Mac as a browser-port reference.
The harness retains 1536 MiB as its default; this CI trial explicitly selects
512 MiB and logs the selection. Keep the container limit at 2048 MiB to avoid
confounding guest-memory reduction with host process limits. The existing
acceptance gate is unchanged. A pass proves early installer boot/input only,
not sufficient memory for installation, installed operation, or WebAssembly.

Infinite Mac references:
- https://github.com/mihaip/infinite-mac
- https://blog.persistent.info/2025/03/infinite-mac-os-x.html

Its README documents worker-separated emulation and chunked disk images.
Its cores include PearPC, DingusPPC, and Previous, not QEMU. Study and reuse
applicable worker/disk/persistence patterns; separately validate a SPARC64
QEMU WebAssembly CPU execution backend. Native 512 MiB testing comes first.

The Infinite Mac OS X post documents pure-interpreter PearPC/DingusPPC
optimization and explicitly points to https://github.com/ktock/qemu-wasm
as an encouraging QEMU browser port. Evaluate this existing work before
inventing a new backend; SPARC64 compatibility has not been established.

## 512 MiB diagnosis; next trial 1024 MiB

Run 133 panicked: `no nucleus hblk8 to allocate`. Reproduced with the exact
run132 firmware in `/mnt/disk-images/woodpecker/b134-hblk-512-control`.
An instrumented 1536 MiB control using that same firmware passed the original
boot/input gate. Docker reported no OOM kill for the initial failing run.

B134 kernel symbols were read from its own boot archive, mounted read-only.
Debugger inspection found nucleus_hblk8 index=len=3185, hblk1 index=2,len=157,
and hblk_alloc_dynamic=0 at failure. segkmem_lpszc=0 at 512 MiB versus 3 at
1536 MiB; segkmem_lpminphysmem=0x40000000 (1 GiB).
The failure breakpoint at 0x1032d98 caught vaddr=0x70000650000, inside kmem64
(base=0x70000000000, end=0x70000942000). The translation list needs 3084
distinct small-page hme blocks before kmem64; another 101 blocks exhaust
the pool exactly at this address. Startup budgets kmem64 in larger-page
records but the below-1-GiB heap setting makes its remapping consume small-
page records instead. This is early mapping-pool sizing, not host OOM.

Diagnostic artifacts are in playbox's woodpecker/b134-hblk-* directories;
512-mappings.log and 512-failure.log were also captured on the laptop.
A RAM-only extra-128-records experiment was started, but Ryan redirected
work to simply trying 1 GiB before its result was established. No ISO or
on-disk kernel patches were made. CI now explicitly selects 1024 MiB;
the harness retains its 1536 MiB default. Passing at exactly 1 GiB still
requires testing: installed RAM and kernel usable-page accounting differ.

Run134 at 1024 MiB also produced the same nucleus_hblk8 panic (not host OOM).
Filed project issue: http://biggie:3000/ryan/niagra-qemu-solaris-project/issues/2.
Independent review: the small-page policy is the trigger, but ownership of
the accounting defect is unresolved. The post-panic boot_virtavail only
covers low virtual addresses, omitting coverage of high heap/kmem64 claims;
size_virtalloc cannot count allocations outside supplied range coverage.
Capture the list at the sizing breakpoint before asserting the precise
kernel-vs-firmware contract violation. A constant pool increase is only a
diagnostic experiment, not the proposed production fix.

Tooling note: no Gitea-specific service wrapper was found. safe-curl itself
was blocked by its raw-curl check, so its documented per-invocation
GUARDRAIL_BYPASS=1 exception was used with .netrc authentication for issue
lookup/creation. No credentials were printed.

Run134 debugger confirmation: physmem@0x1810f18=128185 pages, or
1001.4453125 MiB at 8192 bytes/page. segkmem_lpszc@0x181621c=0;
segkmem_lpminphysmem@0x18125b8=0x40000000. Thus 1024 MiB configured
still leaves usable physmem below the large-page policy threshold.
The exact source of all excluded pages was not independently measured.

Ryan authorized parallel browser-port work: isolated Emscripten SPARC64
build on Biggie, local serial browser harness, and independent backend/
performance review. Use qemu-wasm's hybrid interpreter/Wasm TCG backend;
keep these experiments separate from the known native baseline.
