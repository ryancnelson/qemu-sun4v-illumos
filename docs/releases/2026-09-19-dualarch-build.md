# September 19 dual-architecture release attempt

The new release is not published. Woodpecker's repository-wide 60-minute
timeout killed run 127 during the final AMD64 image's first acceptance boot.
The guest reached login, but the rest of acceptance and publication did not run.

CI repository: `ryancnelson/niagara-qemu-solaris-lab`, branch
`codex/softint-dualarch-release`. The local `origin` points to the separate
`ryancnelson/qemu-sun4v-illumos` repository; updating only origin does not
trigger this CI pipeline.

## Attempts and verified fixes

- [125](http://biggie.lynx-eagle.ts.net:8110/repos/2/pipeline/125),
  `d6e5239b83c3c7b5b97f9a032b4300fb4074f891`: canceled during the slow
  remote archive transfer. Added local archive reuse with checksums before
  and after copying. Three Linux tests cover valid reuse, corrupt-cache
  fallback, and rejection of a corrupt download. Existing release-contract
  tests also passed (nine tests).
- [126](http://biggie.lynx-eagle.ts.net:8110/repos/2/pipeline/126),
  `aed3721c03aaf9600767b575b80296ff523cb19f`: native AMD64 build passed,
  but first login exceeded the 720-second deadline. Extraction and root-disk
  verification consumed about 144 seconds of that budget. Read-only QMP
  snapshots showed continued execution, and the container was not OOM-killed.
- [127](http://biggie.lynx-eagle.ts.net:8110/repos/2/pipeline/127),
  source prefix `e548197`: increased only the golden workflow's bounded login
  deadline to 1,800 seconds. Fresh boot reached login; helper installation,
  networking, both CPU checks, inventory, and both pinned toolchain archive
  checksums passed. The known SMF root-minimal maintenance state remained an
  advisory under the existing release policy.

## Shutdown observation

During run 127's freeze phase, the guest accepted `/usr/sbin/init 5` and
reported:

```text
The system is down. Shutdown took 135 seconds.
syncing file systems... done
WARNING: Unable to connect to Domain Service providers
WARNING: Unable to get LDOM Variable Updates
WARNING: Unable to update LDOM Variable
virtual-console not found.
```

The firmware then printed its startup banner and automatically booted
`/virtual-devices@100/disk@5:a -v` again. It loaded the kernel modules, then
reported `ERROR: Last Trap: Fast Data Access MMU Miss` and returned to
`{0} ok`. The existing shutdown gate observed the earlier filesystem sync
and this OpenBoot prompt, stopped QEMU, and reported
`OCI_GUEST_CLEAN_SHUTDOWN=PASS completion=openboot-returned`.
An intermediate snapshot before the trap incorrectly suggested the shutdown
would time out; the complete transcript supersedes that diagnosis.

Customer first/restart acceptance and ARM64 acceptance are still required.
Downloaded GCC archives are not an installed native toolchain.

## Preserved candidate and next run

Repository 2's `timeout` setting was verified to be 60 minutes. Run 127 ended
with status `killed` after 3,693 seconds, without a user cancellation identity.
Its cleanup step was also killed. The surviving acceptance container
`golden-amd64-127` was explicitly paused to retain its state without spending
host CPU. Its writable volume is `golden-amd64-127-state`; do not share this
volume with another running guest. The immutable frozen bundle is separate.

Preserved artifacts on Biggie:

- Image: `sparc64-qemu-openindiana-20g:golden-amd64-127`
- Image ID: `sha256:beef6698b0c0725016e7453f366299b0fcaae523e33d084354690b7fe9e3fc56`
- Frozen root SHA-256: `58c89b40318ba3e5b02d9343ac9878d94369c9dca1c38ffad56d5765c6680728`
- Frozen archive SHA-256: `7326fae86c4be295bb158f43c13cbcf81a0e40f7b32f64f58e7c536a4a1a309f`

The archive and manifests are under the run's `state/golden/` directory.
Evidence for the acceptance guest is in
`state/self-contained/container-state-golden-amd64-127/`.
A new run needs a larger CI repository timeout; 240 minutes has been proposed.
Changing that browser-managed setting is awaiting user confirmation.

Run 127 evidence is on Biggie under:

```text
/tmp/niagara-ci/golden-volume/golden-volume-amd64-127/state/self-contained/
  container-state-golden-amd64-127-seed/
    console.log
    container-state.json
    self-shutdown-console.log
    runtime-manifest.txt
```

Before these attempts, `latest` was verified to contain exactly these two
Linux architecture descriptors:

| Architecture | Digest |
| --- | --- |
| AMD64 | `sha256:29cadb0eb0f103fecb5f22ab0707d71e66986724a49d10f3b213b4f9ae7819fe` |
| ARM64 | `sha256:7e2ff63142e27c8763098d37fc62997a5122bca1ac8d70a93986d7bce134b4da` |

See the [appliance usage guide](../../appliances/sparc64-qemu-illumos-docker-guest/README.md)
for architecture selection, console login, networking, volumes, and upgrades.
