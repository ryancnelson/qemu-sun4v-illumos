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
