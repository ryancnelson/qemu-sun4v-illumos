	.section ".text"
	.align 4
	.global patch_get_bootpath_prop
	.type patch_get_bootpath_prop,#function
patch_get_bootpath_prop:
	sethi %hi(0x2f766972), %g1
	or %g1, %lo(0x2f766972), %g1
	st %g1, [%o0 + 0]
	sethi %hi(0x7475616c), %g1
	or %g1, %lo(0x7475616c), %g1
	st %g1, [%o0 + 4]
	sethi %hi(0x2d646576), %g1
	or %g1, %lo(0x2d646576), %g1
	st %g1, [%o0 + 8]
	sethi %hi(0x69636573), %g1
	or %g1, %lo(0x69636573), %g1
	st %g1, [%o0 + 12]
	sethi %hi(0x40313030), %g1
	or %g1, %lo(0x40313030), %g1
	st %g1, [%o0 + 16]
	sethi %hi(0x2f646973), %g1
	or %g1, %lo(0x2f646973), %g1
	st %g1, [%o0 + 20]
	sethi %hi(0x6b40303a), %g1
	or %g1, %lo(0x6b40303a), %g1
	st %g1, [%o0 + 24]
	sethi %hi(0x61000000), %g1
	or %g1, %lo(0x61000000), %g1
	st %g1, [%o0 + 28]
	retl
	 clr %o0
	.size patch_get_bootpath_prop, .-patch_get_bootpath_prop

	.align 4
	.global patch_get_fstype_prop
	.type patch_get_fstype_prop,#function
patch_get_fstype_prop:
	sethi %hi(0x75667300), %g1
	or %g1, %lo(0x75667300), %g1
	st %g1, [%o0]
	retl
	 clr %o0
	.size patch_get_fstype_prop, .-patch_get_fstype_prop
