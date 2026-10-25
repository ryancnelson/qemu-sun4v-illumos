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
