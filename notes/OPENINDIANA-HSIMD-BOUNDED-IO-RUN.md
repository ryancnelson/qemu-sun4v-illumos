# OpenIndiana hSIMD bounded-I/O run

## Goal

Boot a fresh OpenIndiana text installer under KMDB with a featureless,
adequately sized destination pool and prevent ZFS from submitting an hSIMD I/O
larger than 128 KiB.  Prove the storage path in the installer shell before
starting installation.

## Hypotheses

- **H1:** The prior panic was caused by ZFS submitting a `0xa6800`-byte request
  to hSIMD's IOV path, whose stale assertion only accepts 128 KiB.
- **H2:** Setting `zfs:zfs_vdev_aggregation_limit=0x20000` before ZFS loads will
  keep vdev strategy requests at or below the driver's current limit and avoid
  that panic.
- **H3:** A featureless 20 GiB pool with `recordsize=8K`, `compression=off`,
  `atime=off`, and `sync=always` will import on OpenIndiana and provide a clean,
  measurable destination independent of the text installer's disk labelling.
- **H4:** Small dataset records alone are insufficient; the aggregation tunable
  is the control that bounds adjacent vdev I/O.

## Artifacts and isolation policy

- Create a new sparse 20 GiB raw file; never reuse the crashed run's disk.
- Create the probe pool with `zpool create -d` so all feature flags begin
  disabled, and export it cleanly before attachment.
- Modify a new boot-archive/firmware copy, never the release template in place.
- Record hashes and exact paths before launch.
- Use a new tmux session owned by a persistent shell.  QEMU runs in a separate
  named window so QEMU exit cannot destroy the observable session.

## Mandatory boot and shell gates

1. Boot the installer medium with `-k -v`; capture console proof of KMDB mode.
2. Select the shell before the installer.
3. Establish that `/`, `/etc`, `/etc/dev`, `/devices`, and `/dev` are writable
   where the live environment requires writes.  ISO-backed `/.cdrom`, `/usr`,
   and `/mnt/misc` may remain read-only.
4. Confirm the intended unit-100 device identity without trusting broken
   `format`, `dladm`, or other unsupported-ioctl output in isolation.
5. `zpool import` the featureless probe pool and capture `zpool status`,
   `zpool get all`, and relevant `zfs get` properties.
6. Write, `sync`, and read back a named canary.
7. Capture hSIMD strategy-request sizes with DTrace/FBT if available; otherwise
   use KMDB or a temporary instrumented driver.  The acceptance limit is
   `b_bcount <= 0x20000` throughout the bounded run.
8. Return to the installer only after all shell gates pass.

## Acceptance and falsifiers

Pass requires a successful pool import, durable canary, no hSIMD assertion, no
request above 128 KiB in the bounded run, and continued progress into install.
Any larger request falsifies H2.  A panic at or below 128 KiB disproves the
current size-only diagnosis.  An import failure with valid featureless labels
separates a device/label/geometry defect from the large-I/O defect.

## Live record

This section is append-only for artifact identities, commands, timestamps, and
observed results from the run.  Do not replace hypotheses with conclusions
until the corresponding evidence is captured.

- The immediate Tribblix diagnostic reboot used
  `boot /virtual-devices@100/disk@3:d -a -k -v -B rootdev=/ramdisk-root:a`.
  This syntax did **not** override the root.  The console reported
  `krtld: Ignoring invalid kernel option -B` and
  `Unused kernel arguments: rootdev=/ramdisk-root:a`.  Do not repeat this
  spelling/order as though it were proven.  The durable boot-archive fix
  remains required.

## Tribblix default-prompt remediation

The current Tribblix candidate is not acceptable: pressing Return at the
interactive root prompt selects `/virtual-devices@100/disk@0:a` and panics.
The replacement boot archive must make the RAM root authoritative, remove any
stale physical-root directive, and make the live device tree writable before
`devfsadm`:

```text
set root_is_ramdisk=1
rootdev:/ramdisk-root:a
```

Preserve the artifact's verified `ramdisk_size`.  Before `devfsadm`, remount
the actual `/ramdisk-root:a` root read/write and require this gate to pass:

```sh
touch /etc/dev/.devfsadm_write_test || exit 1
rm /etc/dev/.devfsadm_write_test
```

The diagnostic cold boot uses `-a -k -v` and must display these defaults:

```text
Name of system file [/etc/system]:
Retire store [/etc/devices/retire_store]:
root filesystem type [ufs]:
Enter physical name of root device [/ramdisk-root:a]:
```

Pressing Return at every prompt must mount `root on /ramdisk-root:a fstype
ufs`, pass the `/etc/dev` write gate, complete `devfsadm`, and reach the
installer menu.  The subsequent acceptance boot removes `-a` and must reach
the installer menu unattended.  Until the archive passes this gate, an
explicit `-B rootdev=/ramdisk-root:a` is a diagnostic override, not a release
fix.
