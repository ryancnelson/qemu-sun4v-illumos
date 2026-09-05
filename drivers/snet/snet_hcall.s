/*
 * OpenSPARC T1 SNET hypercall wrappers.
 * SPDX-License-Identifier: GPL-2.0-only
 */

#include <sys/asm_linkage.h>
#include <sys/hypervisor_api.h>

#define SNET_READ  0xf2
#define SNET_WRITE 0xf3

#if defined(lint) || defined(__lint)
size_t hv_snet_read(uint64_t pa, size_t size) { return (0); }
size_t hv_snet_write(uint64_t pa, size_t size) { return (0); }
#else

/* %o0 = guest real address, %o1 = byte count */
ENTRY(hv_snet_read)
	mov	SNET_READ, %o5
	ta	FAST_TRAP
	tst	%o0
	movz	%xcc, %o1, %o0
	retl
	movnz	%xcc, -1, %o0
	SET_SIZE(hv_snet_read)

ENTRY(hv_snet_write)
	mov	SNET_WRITE, %o5
	ta	FAST_TRAP
	tst	%o0
	movz	%xcc, %o1, %o0
	retl
	movnz	%xcc, -1, %o0
	SET_SIZE(hv_snet_write)

#endif

