# Two-CPU Niagara machine descriptions

The guest and hypervisor descriptions come from Masayuki Murayama's
`qemu-sun4v-dist-pkg` commit
`3eb7ce6cbda552ff2c03afc5fbb8a2bfede2cdd0`. The compiled `md.bin` and
`hv.bin` are byte-identical to the firmware used by the successful
`oi-basecamp` SMP run.

`2c8t_guest.pp.bak` was regenerated on the investigation host with `NCPUS=2`.
Its only difference from the upstream preprocessed file is compiler line-marker
noise; both compile to the checked-in `md.bin`. `2c8t_hv.pp.bak` records the
matching two-CPU hypervisor input.

The appliance firmware builder verifies these files, derives a guest MD that
auto-boots disk 5 with `-v`, and installs the checked-in two-CPU `hv.bin`.
