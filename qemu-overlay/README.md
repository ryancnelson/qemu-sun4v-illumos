# QEMU overlay

These files implement the host half of the OpenSPARC T1 SNET FIFO. Apply them
to the Murayama Niagara QEMU tree with `scripts/apply-snet-qemu-overlay.sh`.
The script refuses an unexpected tree and makes no commit.

After applying, configure the Niagara VM with one NIC, for example:

```sh
-nic user,model=sun4v-snet,mac=02:53:4e:45:54:01
```

The machine instantiates only the first configured NIC at `0xfff0c2c050`, the
physical address already described by the current hypervisor MD.

On the Biggie builder, `scripts/build-snet-qemu.sh` checks out the pinned
Murayama base, applies the overlay, builds only `qemu-system-sparc64`, and
verifies that QEMU recognizes the device.
