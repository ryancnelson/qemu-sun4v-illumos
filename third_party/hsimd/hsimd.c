/*
* ========== Copyright Header Begin ==========================================
* 
* OpenSPARC T2 Processor File: hsimd.c
* Copyright (c) 2006 Sun Microsystems, Inc.  All Rights Reserved.
* DO NOT ALTER OR REMOVE COPYRIGHT NOTICES.
* 
* The above named program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License version 2 as published by the Free Software Foundation.
* 
* The above named program is distributed in the hope that it will be 
* useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
* 
* You should have received a copy of the GNU General Public
* License along with this work; if not, write to the Free Software
* Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
* 
* ========== Copyright Header End ============================================
*/
/*
 * Copyright 2004 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 */

#pragma ident	"@(#)hsimd.c	1.1	06/02/06 SMI"

/*
 * Source code for the HSIMD "SPARC simulator" Dummy driver
 *	uses systems calls via simulator to accomplish
 *	base level open, seek, read, and write operations
 */


#include <sys/types.h>
#include <sys/dklabel.h>
#include <sys/errno.h>
#include <sys/uio.h>
#include <sys/buf.h>
#include <sys/modctl.h>
#include <sys/open.h>
#include <sys/poll.h>
#include <sys/conf.h>
#include <sys/cmn_err.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/ddi.h>
#include <sys/sunddi.h>

#include <sys/nexusdebug.h>
#include <sys/debug.h>

#include <sys/dkbad.h>
#include <sys/dklabel.h>
#include <sys/dkio.h>
#include <sys/vtoc.h>
#include <sys/file.h>

#define	HSIMD_UNIT(x)	(getminor(x) >> 3)
#define	HSIMD_SLICE(x)	(getminor(x) & 0x7)
#define	HSIMD_NSLICES	8

struct hsimd_label {
	daddr_t blockno;	/* Starting block number */
	daddr_t nblocks;	/* Number of blocks */
};

struct hsimd_unit {			/* unit structure - one per unit */
	dev_info_t	*dip;		/* opaque devinfo info. */

	kmutex_t	hsimd_mutex;	/* mutex to protect condition var */
	kcondvar_t	hsimd_cnd;	/* Used to protect device */
	int		device_busy;
	struct buf	*active;	/* currently active buf */
	struct hsimd_label label[8];	/* slice information */
	uint_t		flags;
	struct	dk_map32 hsimd_map[NDKMAP];
	struct	dk_vtoc hsimd_vtoc;
	struct	dk_geom hsimd_g;
	uchar_t hsimd_asciilabel[LEN_DKL_ASCII];
	uint8_t hsimd_lvalid;
};

#define	HSIMD_ATTACH		0x1
#define	HSIMD_RW		0x2

void	*hsimd_state_head;	/* opaque handle top of state structs */
#define	getsoftc(unit) \
	((struct hsimd_unit *)ddi_get_soft_state(hsimd_state_head, (unit)))


/* Autoconfig Declarations */
static int hsimd_getinfo(dev_info_t *dip, ddi_info_cmd_t infocmd,
			void *arg, void **result);
static int hsimd_attach(dev_info_t *dip, ddi_attach_cmd_t cmd);
static int hsimd_detach(dev_info_t *, ddi_detach_cmd_t);

/* Driver function Declarations */
static	int	hsimd_read(dev_t dev, struct uio *uiop, cred_t *credp);
static	int	hsimd_write(dev_t dev, struct uio *uiop, cred_t *credp);
static	int	hsimd_strategy(register struct buf *bp);
static 	int 	hsimd_dump(dev_t dev, caddr_t addr, daddr_t blkno, int nblk);
static	int	hsimd_ioctl(dev_t, int, intptr_t, int, cred_t *, int *);
static	int	hsimd_prop_op(dev_t dev, dev_info_t *dip,
	    ddi_prop_op_t prop_op, int mod_flags, char *name,
	    caddr_t valuep, int *lengthp);

static int hsimd_get_valid_geometry(struct hsimd_unit *hsimd_p);

#ifdef DEBUG
static int debug_info;
static int debug_print_level;
#endif

static struct driver_minor_data {
	char    *name;
	int	minor;
	int	type;
} hsimd_minor_data[] = {
	{"a", 0, S_IFBLK},
	{"b", 1, S_IFBLK},
	{"c", 2, S_IFBLK},
	{"d", 3, S_IFBLK},
	{"e", 4, S_IFBLK},
	{"f", 5, S_IFBLK},
	{"g", 6, S_IFBLK},
	{"h", 7, S_IFBLK},
	{"a,raw", 0, S_IFCHR},
	{"b,raw", 1, S_IFCHR},
	{"c,raw", 2, S_IFCHR},
	{"d,raw", 3, S_IFCHR},
	{"e,raw", 4, S_IFCHR},
	{"f,raw", 5, S_IFCHR},
	{"g,raw", 6, S_IFCHR},
	{"h,raw", 7, S_IFCHR},
	{0}
};

/*
 * The hsimd_cb_ops struct enables the kernel to find the
 * rest of the driver entry points.
 */
static struct cb_ops    hsimd_cb_ops = {
	nulldev,		/*	driver open routine		*/
	nulldev,		/*	driver close routine		*/
	hsimd_strategy,		/* driver strategy routine - block devs only */
	nodev,			/*	driver print routine	*/
	hsimd_dump,		/*	driver dump routine	*/
	hsimd_read,		/*	driver read routine	*/
	hsimd_write,		/*	driver write routine	*/
	hsimd_ioctl,		/*	driver ioctl routine	*/
	nodev,			/*	driver devmap routine	*/
	nulldev,		/*	driver mmap routine	*/
	nulldev,		/*	driver segmap routine	*/
	nochpoll,		/*	driver chpoll routine	*/
	hsimd_prop_op,		/*	driver prop_op routine	*/
	0,			/* driver cb_str - STREAMS only */
	D_NEW | D_MP,		/* driver compatibility flag    */
};

/*
 * The hsimd_ops struct enables the kernel to find the
 * hsimd loadable module routines.
 */
static struct dev_ops hsimd_ops =
{
	DEVO_REV,			/*	revision number	*/
	0,				/*	device reference count	*/
	hsimd_getinfo,			/*	driver get_dev_info	*/
	nulldev,			/*	confirm device ID	*/
	nulldev,			/*	device probe for non-self-id */
	hsimd_attach,			/*	attach routine		*/
	hsimd_detach,			/*	device detach		*/
	nodev,				/*	device reset		*/
	&hsimd_cb_ops,			/*	device oper struct	*/
	(struct bus_ops *)0,		/*	bus operations		*/
};

extern  struct  mod_ops mod_driverops;
/*
 * The hsimd_drv structure provides the linkage between the vd driver
 * (for loadable drivers) and the dev_ops structure for this driver
 * (hsimd_ops).
 */
static  struct modldrv modldrv = {
	&mod_driverops,				/* type of module - driver */
	"hsimd",					/* name of module  */
	&hsimd_ops				/* *Drv_dev_ops		*/
};

static  struct modlinkage modlinkage = {
	MODREV_1,  (void *)&modldrv, NULL
};

/*
 * _init is called by the autoloading code when the special file is
 * first opened, or by modload().
 */
int
_init(void)
{
	register int    error;
	if ((error = ddi_soft_state_init(&hsimd_state_head,
	    sizeof (struct hsimd_unit), 1)) != 0) {
		return (error);
	}
	if ((error = mod_install(&modlinkage)) != 0)
		ddi_soft_state_fini(&hsimd_state_head);
	return (error);
}

/*
 * _info is called by modinfo().
 */
int
_info(struct modinfo *modinfop)
{
	return (mod_info(&modlinkage, modinfop));
}

/*
 * _fini is called by
 * modunload() just before the driver is unloaded from system memory.
 */
int
_fini(void)
{
	int status;

	if ((status = mod_remove(&modlinkage)) != 0)
		return (status);
	ddi_soft_state_fini(&hsimd_state_head);
	return (status);
}


/*
 *      hsimd_attach()
 *
 * Allocate unit structures.
 * Map the hsimd device registers into kernel virtual memory.
 * Add the hsimd driver to the level X interrupt chain.
 * Initialize the hsimd device
 * Turn on the interrupts.
 */
static int
hsimd_attach(dev_info_t *dip, ddi_attach_cmd_t cmd)
{
	struct	hsimd_unit *hsimd_p;
	struct driver_minor_data *dmdp;
	int unit_no;		/* attaching unit's number */
	int i;
	int nblks;
	struct dk_map32	*lmap;

	unit_no = ddi_get_instance(dip);

	if (cmd != DDI_ATTACH)
		return (DDI_FAILURE);

	DPRINTF(HSIMD_ATTACH, ("hsimd attaching instance %u\n", unit_no));

	/*
	 * Allocate a unit structure for this unit.
	 * Each hsimd_unit struct is allocated as zeroed memory.
	 * Store away its address for future use.
	 */
	if (ddi_soft_state_zalloc(hsimd_state_head, unit_no) != 0)
		return (DDI_FAILURE);

	/* assign a pointer to this unit's state struct */
	hsimd_p = getsoftc(unit_no);
	hsimd_p->flags = 0;
	hsimd_p->dip = dip;

	/*
	 * Initialize the unit structures. The unit structure for
	 * each unit is initialized when hsimd_attach is called for that unit.
	 */

	/*
	 * Initialize the hsimd mutex.
	 */
	mutex_init(&hsimd_p->hsimd_mutex, "hsimd mutex",
	    MUTEX_DRIVER, NULL);

	cv_init(&hsimd_p->hsimd_cnd, "hsimd condition variable", CV_DRIVER,
	    NULL);

	/*
	 * Get geometry and label from disk
	 */
	if (hsimd_get_valid_geometry(hsimd_p) != 0) {
		cmn_err(CE_WARN, "hsimd: attach: label not valid");
		mutex_destroy(&hsimd_p->hsimd_mutex);
		ddi_soft_state_free(hsimd_state_head, unit_no);
		return (DDI_FAILURE);
	}

	hsimd_p->hsimd_lvalid = 1; /* mark label valid */
	lmap = hsimd_p->hsimd_map;
	nblks = hsimd_p->hsimd_g.dkg_nsect * hsimd_p->hsimd_g.dkg_nhead;
	for (i = 0; i < V_NUMPAR; i++) {
		hsimd_p->label[i].blockno = lmap->dkl_cylno * nblks;
		hsimd_p->label[i].nblocks = lmap->dkl_nblk;
		lmap++;
	}
	/* The driver is now commited - all sanity checks done */

	for (dmdp = hsimd_minor_data; dmdp->name != NULL; dmdp++) {
		if (ddi_create_minor_node(dip, dmdp->name, dmdp->type,
		    (unit_no << 3) | dmdp->minor,
		    DDI_NT_BLOCK, NULL) == DDI_FAILURE) {
			ddi_remove_minor_node(dip, NULL);
			cmn_err(CE_NOTE,
			    "ddi_create_minor_node failed for unit %d\n",
			    unit_no);

			mutex_destroy(&hsimd_p->hsimd_mutex);
			ddi_soft_state_free(hsimd_state_head, unit_no);
			DPRINTF(HSIMD_ATTACH, ("hsimd attach failed\n"));
			return (DDI_FAILURE);
		}
	}
	ddi_report_dev(dip);

	DPRINTF(HSIMD_ATTACH, ("hsimd attach done\n"));
	return (DDI_SUCCESS);
}

static int
hsimd_detach(dev_info_t *devi, ddi_detach_cmd_t cmd)
{
	int instance;

	switch (cmd) {
	case DDI_DETACH:

		instance = ddi_get_instance(devi);

		ddi_remove_minor_node(devi, NULL);
		ddi_soft_state_free(hsimd_state_head, instance);
		return (DDI_SUCCESS);

	case DDI_SUSPEND:
		return (DDI_SUCCESS);
	}
	cmn_err(CE_CONT,
		"%s: detach failed.\n", "hsimd");
	return (DDI_FAILURE);
}

/*
 * xx_getinfo is called from the framework to determine the devinfo pointer
 * or instance number corresponding to a given dev_info_t.
 */
/*ARGSUSED*/
static int
hsimd_getinfo(dev_info_t *dip, ddi_info_cmd_t infocmd, void *arg, void **result)
{
	int error;
	struct hsimd_unit *hsimd_p;
	int instance;

	switch (infocmd) {
	case DDI_INFO_DEVT2DEVINFO:
		instance = HSIMD_UNIT(getminor((dev_t)arg));

		if ((hsimd_p = getsoftc(instance)) == NULL) {
			*result = NULL;
			error = DDI_FAILURE;
		} else {
			*result = hsimd_p->dip;
			error = DDI_SUCCESS;
		}
		break;
	case DDI_INFO_DEVT2INSTANCE:
		instance = HSIMD_UNIT(getminor((dev_t)arg));
		*result = (void *) instance;
		error = DDI_SUCCESS;
		break;
	default:
		error = DDI_FAILURE;
	}

	return (error);
}

/*	Normal Device Driver routines	*/

/*
 * Read system call.
 */
/*ARGSUSED*/
static  int
hsimd_read(dev_t dev, struct uio *uiop, cred_t *credp)
{
	int retval = 0;	/* return value (errno) for system call */

	retval = physio(hsimd_strategy, (struct buf *)0, dev,
	    B_READ, minphys, uiop);

	return (retval);
}


/*
 * Write system call.
 */
/*ARGSUSED*/
static  int
hsimd_write(dev_t dev, struct uio *uiop, cred_t *credp)
{
	uint_t retval = 0;	/* return value (errno) for system call */

	retval = physio(hsimd_strategy, (struct buf *)0, dev,
	    B_WRITE, minphys, uiop);

	return (retval);
}

/*
 * Setup and start a transfer on the device.
 * 	checks operation, hangs buf struct off hsimd_unit, calls hsimdstart
 *	if not already busy.
 */

static int
hcall_diskio(int dir, uint64_t pa, size_t size, off_t offset)
{
	size_t osize = size;
	extern size_t hv_disk_read(uint64_t, uint64_t, size_t);
	extern size_t hv_disk_write(uint64_t, uint64_t, size_t);

	if (dir) {
		size = hv_disk_read(offset, pa, size);
		DPRINTF(HSIMD_RW, ("hsimd Disk Read from offset %lx, "
		    "%lx bytes into RA %lx, size=%lx\n",
		    offset, osize, pa, size));
	} else {
		size = hv_disk_write(offset, pa, size);
		DPRINTF(HSIMD_RW, ("hsimd Disk Write to offset %lx, "
		    "%lx bytes from RA %lx, size=%lx\n",
		    offset, osize, pa, size));
	}
	if (size == (size_t)-1) {
		cmn_err(CE_WARN, "hsimd: hcall_diskio error from hv_disk_%s"
		    "(offset=%lx pa=%lx size=%lx)\n",
		    (dir ? "read" : "write"), offset, pa, osize);
	}
	return (size);
}

#define	va2tsize(v) (MMU_PAGESIZE - ((uint64_t)(v) & MMU_PAGEOFFSET))

static ssize_t
hsimd_diskio(int dir, caddr_t vadr, size_t sz, off_t offset)
{
	caddr_t va;
	uint64_t pa;
	size_t size, tsize;
	size_t asize;
	va = vadr;
	size = sz;

	DPRINTF(HSIMD_RW, ("hsimd vadr %p sz = %lx\n", vadr, sz));

	while (size) {
		pa = va_to_pa(va);
		if (pa == (uint64_t)-1)
			return (sz - size);

		tsize = min(size, va2tsize(va));

		DPRINTF(HSIMD_RW, ("hsimd va = %p, pa = %lx, tsize = %lx\n",
		    va, pa, tsize));
		asize = hcall_diskio(dir, pa, tsize, offset);

		if (asize == (size_t)-1 || asize == 0)
			return (sz - size);

		size -= asize;
		va += asize;
		offset += asize;
	}
	DPRINTF(HSIMD_RW, ("\n"));
	return (sz);
}

static int
hsimd_dump(dev_t dev, caddr_t addr, daddr_t blkno, int nblk)
{
	struct	hsimd_unit	*hsimd_p;
	uint_t  unit_no;
	uint_t 	slice_no;
	off_t	diskoffset;	/* Byte offset into the disk */
	size_t	size;		/* Transfer size in bytes */

	unit_no = HSIMD_UNIT(dev);
	slice_no = HSIMD_SLICE(dev);

	hsimd_p = getsoftc(unit_no);
	if (hsimd_p == NULL) {
		cmn_err(CE_WARN, "hsimd: no softstate for unit %d", unit_no);
		return (ENXIO);
	}

	if (!hsimd_p->hsimd_lvalid) {
		cmn_err(CE_WARN, "hsimd: invalid disk label %d", unit_no);
		return (ENXIO);
	}

	if (blkno >= hsimd_p->label[slice_no].nblocks) {
		return (ENOSPC);
	}

	if ((blkno + nblk) > hsimd_p->label[slice_no].nblocks) {
		return (ENOSPC);
	}

	size = nblk * DEV_BSIZE;
	diskoffset = (hsimd_p->label[slice_no].blockno + blkno) * DEV_BSIZE;
	(void) hsimd_diskio(B_WRITE & B_READ, addr, size, diskoffset);

	return (0);
}

/*ARGSUSED*/
static int
hsimd_strategy(struct buf *bp)
{
	struct	hsimd_unit	*hsimd_p;
	uint_t   unit_no;
	uint_t 	slice_no;
	uint_t	blk_no;

	off_t	diskoffset;	/* Byte offset into the disk */
	size_t	size;		/* Transfer size in bytes */
	caddr_t	addr;		/* Buffer virtual address */
	ssize_t	tsize;		/* Actual transfer size */

	unit_no = HSIMD_UNIT(bp->b_edev);
	slice_no = HSIMD_SLICE(bp->b_edev);
	hsimd_p = getsoftc(unit_no);
	if (hsimd_p == NULL) {
		cmn_err(CE_WARN, "hsimd: no softstate for unit %d", unit_no);
		bp->b_error = ENXIO;
		goto bad;
	}

	if (!hsimd_p->hsimd_lvalid) {
		cmn_err(CE_WARN, "hsimd: invalid disk label %d", unit_no);
		bp->b_error = ENXIO;
		goto bad;
	}

	blk_no = (uint_t)bp->b_blkno;

	/* error if requested blk past end of partition */
	/* XXX - end of requested blk */
	if ((blk_no) >= hsimd_p->label[slice_no].nblocks) {
		bp->b_error = ENOSPC;
		goto bad;
	}

	/* error if requested blk past end of partition */
	/* XXX - end of requested blk */
	if ((blk_no + (bp->b_bcount / DEV_BSIZE)) >
	    hsimd_p->label[slice_no].nblocks) {
		bp->b_error = ENOSPC;
		goto bad;
	}

	/* error if transfer count not multiple of sector size */
	if (bp->b_bcount & (DEV_BSIZE - 1)) {
		bp->b_error = EINVAL;
		goto bad;
	}

	/*
	 * Put buf request in the controller's queue, FIFO
	 */

	mutex_enter(&hsimd_p->hsimd_mutex);
	while (hsimd_p->device_busy) {
		cv_wait(&hsimd_p->hsimd_cnd, &hsimd_p->hsimd_mutex);
	}
	hsimd_p->device_busy = 1;
	mutex_exit(&hsimd_p->hsimd_mutex);


	if (bp->b_flags & B_READ) {
		hsimd_p->flags = DDI_DMA_READ;
		DPRINTF(HSIMD_RW, ("hsimd read xfer instance 0x%x slice %d "
		    "block no 0x%x data count 0x%x Data addr 0x%p\n",
		    unit_no, slice_no, blk_no, bp->b_bcount, bp->b_un.b_addr));
	} else {
		hsimd_p->flags = DDI_DMA_WRITE;
		DPRINTF(HSIMD_RW, ("hsimd write xfer instance 0x%x slice %d "
		    "block no 0x%x data count 0x%x Data addr 0x%p\n",
		    unit_no, slice_no, blk_no, bp->b_bcount, bp->b_un.b_addr));
	}


	/*
	 * bp->b_blkno : Disk Block number relative to the slice
	 * bp->b_bcount : byte count
	 */

	hsimd_p->active = bp;


	/*
	 *  hypervisor call(s) to do the transfer
	 */
	bp_mapin(bp);
	addr = bp->b_un.b_addr;
	diskoffset = (hsimd_p->label[slice_no].blockno + blk_no) * DEV_BSIZE;
	size = bp->b_bcount;
	tsize = hsimd_diskio(bp->b_flags & B_READ, addr, size, diskoffset);
	bp_mapout(bp);

	bp->b_resid = 0;

	if (tsize != size) {
		bp->b_resid = size;
		bp->b_flags |= B_ERROR;
	}

	(void) biodone(bp);

	mutex_enter(&hsimd_p->hsimd_mutex);

	hsimd_p->device_busy = 0;

	cv_signal(&hsimd_p->hsimd_cnd);

	mutex_exit(&hsimd_p->hsimd_mutex);

	return (0);

bad:
	bp->b_resid = bp->b_bcount;
	bp->b_flags |= B_ERROR;
	(void) biodone(bp);
	return (0);
}

static int
hsimd_get_valid_geometry(struct hsimd_unit *hsimd_p)
{
	struct dk_label *dkl;
	caddr_t	addr;
	uint_t diskoffset;
	size_t	size, tsize;

	dkl = kmem_zalloc(sizeof (struct dk_label),
	    KM_SLEEP);
	addr = (caddr_t)dkl;
	diskoffset = 0;		/* first block */
	size = sizeof (*dkl);
	tsize = hsimd_diskio(B_READ, addr, size, diskoffset);
	if (tsize <  sizeof (*dkl)) {
		cmn_err(CE_WARN, "hsimd:get_valid_geometry can't get vtoc");
		kmem_free(dkl, sizeof (struct dk_label));
		return (-1);
	}
	/*
	 * Check magic number of the label
	 */
	if (dkl->dkl_magic != DKL_MAGIC) {
		kmem_free(dkl,  sizeof (*dkl));
		return (-1);
	}
	/*
	 * Fill in disk geometry from label.
	 */
	hsimd_p->hsimd_g.dkg_ncyl = dkl->dkl_ncyl;
	hsimd_p->hsimd_g.dkg_acyl = dkl->dkl_acyl;
	hsimd_p->hsimd_g.dkg_bcyl = 0;
	hsimd_p->hsimd_g.dkg_nhead = dkl->dkl_nhead;
	hsimd_p->hsimd_g.dkg_bhead = dkl->dkl_bhead;
	hsimd_p->hsimd_g.dkg_nsect = dkl->dkl_nsect;

	/*
	 * Fill in partition table.
	 */

	bcopy(dkl->dkl_map, hsimd_p->hsimd_map,
	    NDKMAP * sizeof (struct dk_map32));

	/*
	 * Fill in VTOC Structure.
	 */
	bcopy((caddr_t)&dkl->dkl_vtoc, (caddr_t)&hsimd_p->hsimd_vtoc,
	    sizeof (struct dk_vtoc));
	bcopy(dkl->dkl_asciilabel,
	    hsimd_p->hsimd_asciilabel, LEN_DKL_ASCII);

	kmem_free(dkl, sizeof (*dkl));
	return (0);
}

static void
hsimd_build_user_vtoc(struct hsimd_unit *un, struct vtoc *vtoc)
{

	int i;
	int nblks;
	struct dk_map2 *lpart;
	struct dk_map32	*lmap;
	struct partition *vpart;


	/*
	 * Return vtoc structure fields in the provided VTOC area, addressed
	 * by *vtoc.
	 *
	 */

	bzero((caddr_t)vtoc, sizeof (struct vtoc));

	vtoc->v_bootinfo[0] = un->hsimd_vtoc.v_bootinfo[0];
	vtoc->v_bootinfo[1] = un->hsimd_vtoc.v_bootinfo[1];
	vtoc->v_bootinfo[2] = un->hsimd_vtoc.v_bootinfo[2];

	vtoc->v_sanity		= VTOC_SANE;
	vtoc->v_version		= un->hsimd_vtoc.v_version;

	bcopy((caddr_t)un->hsimd_vtoc.v_volume, (caddr_t)vtoc->v_volume,
	    LEN_DKL_VVOL);

	vtoc->v_sectorsz = DEV_BSIZE;
	vtoc->v_nparts = un->hsimd_vtoc.v_nparts;

	bcopy((caddr_t)un->hsimd_vtoc.v_reserved, (caddr_t)vtoc->v_reserved,
	    sizeof (vtoc->v_reserved));
	/*
	 * Convert partitioning information.
	 *
	 * Note the conversion from starting cylinder number
	 * to starting sector number.
	 */
	lmap = un->hsimd_map;
	lpart = un->hsimd_vtoc.v_part;
	vpart = vtoc->v_part;

	nblks = un->hsimd_g.dkg_nsect * un->hsimd_g.dkg_nhead;
	for (i = 0; i < V_NUMPAR; i++) {
		vpart->p_tag	= lpart->p_tag;
		vpart->p_flag	= lpart->p_flag;
		vpart->p_start	= lmap->dkl_cylno * nblks;
		vpart->p_size	= lmap->dkl_nblk;

		lmap++;
		lpart++;
		vpart++;
		vtoc->timestamp[i] = (time_t)un->hsimd_vtoc.v_timestamp[i];
	}

	bcopy((caddr_t)un->hsimd_asciilabel, (caddr_t)vtoc->v_asciilabel,
	    LEN_DKL_ASCII);

}

/* ARGSUSED3 */
static int
hsimd_ioctl(dev_t dev, int cmd, intptr_t arg, int flag,
	cred_t *cred_p, int *rval_p)
{
	struct	hsimd_unit	*hsimd_p;
	struct dk_cinfo *info;
	struct vtoc vtoc;
	uint_t	unit_no, slice_no;

	unit_no = HSIMD_UNIT(dev);
	slice_no = HSIMD_SLICE(dev);
	hsimd_p = getsoftc(unit_no);
	if (hsimd_p == NULL) {
		cmn_err(CE_WARN, "hsimd: no softstate for unit %d", unit_no);
		return (ENXIO);
	}

	switch (cmd) {

	case DKIOCINFO:
		/*
		 * Controller Information
		 */
		info = (struct dk_cinfo *)
		    kmem_zalloc(sizeof (struct dk_cinfo), KM_SLEEP);
		info->dki_ctype = DKC_DIRECT;
		info->dki_cnum = ddi_get_instance(ddi_get_parent(hsimd_p->dip));
		(void) strcpy(info->dki_cname,
		    ddi_get_name(ddi_get_parent(hsimd_p->dip)));
		/*
		 * Unit Information
		 */
		info->dki_unit = ddi_get_instance(hsimd_p->dip);
		info->dki_slave = 0;
		(void) strcpy(info->dki_dname, ddi_get_name(hsimd_p->dip));
		info->dki_flags = DKI_FMTVOL;
		info->dki_partition = slice_no;

		/*
		 * Max Transfer size of this device in blocks
		 */
		info->dki_maxtransfer = PAGESIZE / DEV_BSIZE;
		info->dki_addr = 0;
		info->dki_space = 0;
		info->dki_prio = 0;
		info->dki_vec = 0;
		if (ddi_copyout((caddr_t)info, (caddr_t)arg,
		    sizeof (struct dk_cinfo), flag)) {
			kmem_free(info, sizeof (struct dk_cinfo));
			return (EFAULT);
		} else	{
			kmem_free(info, sizeof (struct dk_cinfo));
			return (0);
		}
	case DKIOCGVTOC:
		/*
		 * Get the label (vtoc, geometry and partition map) directly
		 * from the disk, in case if it got modified by another host
		 * sharing the disk in a multi initiator configuration.
		 */
		if (!hsimd_p->hsimd_lvalid) {
			cmn_err(CE_WARN, "hsimd: invalid disk label %d",
			    unit_no);
			return (ENXIO);
		}
		mutex_enter(&hsimd_p->hsimd_mutex);
		hsimd_build_user_vtoc(hsimd_p, &vtoc);
		mutex_exit(&hsimd_p->hsimd_mutex);

#ifdef _MULTI_DATAMODEL
		switch (ddi_model_convert_from(flag & FMODELS)) {
		case DDI_MODEL_ILP32: {
			struct vtoc32 vtoc32;

			vtoctovtoc32(vtoc, vtoc32);
			if (ddi_copyout(&vtoc32, (void *)arg,
				sizeof (struct vtoc32), flag))
				return (EFAULT);
			break;
		}

		case DDI_MODEL_NONE:
			if (ddi_copyout(&vtoc, (void *)arg,
				sizeof (struct vtoc), flag))
				return (EFAULT);
			break;
		}
#else
		if (ddi_copyout((caddr_t)&vtoc, (caddr_t)arg,
		    sizeof (struct vtoc), flag))
			return (EFAULT);
#endif
		return (0);
	case DKIOCGGEOM:
		if (ddi_copyout((caddr_t)&hsimd_p->hsimd_g,
		    (caddr_t)arg, sizeof (struct dk_geom), flag))
			return (EFAULT);
		else
			return (0);
	default:
		cmn_err(CE_WARN, "hsimd_ioctl: cmd %x not implemented",
		    cmd);
	}
	return (0);
}

static int
hsimd_prop_op(dev_t dev, dev_info_t *dip, ddi_prop_op_t prop_op, int mod_flags,
    char *name, caddr_t valuep, int *lengthp)
{
	int nblocks, length, km_flags;
	caddr_t buffer;
	struct hsimd_unit *hsimd_p;
	int instance;

	if (dev != DDI_DEV_T_ANY)
		instance = HSIMD_UNIT(dev);
	else
		instance = ddi_get_instance(dip);

	hsimd_p = getsoftc(instance);

	if (!hsimd_p->hsimd_lvalid) {
		cmn_err(CE_CONT, "hsimd_prop_op: invalid label\n");
		return (DDI_PROP_NOT_FOUND);
	}

	if (strcmp(name, "nblocks") == 0) {
		mutex_enter(&hsimd_p->hsimd_mutex);
		nblocks = (int)hsimd_p->label[HSIMD_SLICE(dev)].nblocks;
		mutex_exit(&hsimd_p->hsimd_mutex);

		/*
		* get callers length set return length.
		*/
		length = *lengthp;		/* Get callers length */
		*lengthp = sizeof (int);	/* Set callers length */

		/*
		* If length only request or prop length == 0, get out now.
		* (Just return length, no value at this level.)
		*/
		if (prop_op == PROP_LEN)  {
			*lengthp = sizeof (int);
			return (DDI_PROP_SUCCESS);
		}

		/*
		* Allocate buffer, if required.	 Either way,
		* set `buffer' variable.
		*/
		switch (prop_op)  {

		case PROP_LEN_AND_VAL_ALLOC:

			km_flags = KM_NOSLEEP;

			if (mod_flags & DDI_PROP_CANSLEEP)
				km_flags = KM_SLEEP;

			buffer = (caddr_t)kmem_alloc((size_t)sizeof (int),
			km_flags);
			if (buffer == NULL)  {
				cmn_err(CE_WARN,
				    "no mem for property\n");
				return (DDI_PROP_NO_MEMORY);
			}
			*(caddr_t *)valuep = buffer; /* Set callers buf ptr */
			break;

		case PROP_LEN_AND_VAL_BUF:

			if (sizeof (int) > (length))
				return (DDI_PROP_BUF_TOO_SMALL);

			buffer = valuep; /* get callers buf ptr */
			break;
		}
		*((int *)buffer) = nblocks;
		return (DDI_PROP_SUCCESS);
	}

	/*
	 * not mine pass it on.
	 */
	return (ddi_prop_op(dev, dip, prop_op, mod_flags,
		name, valuep, lengthp));
}
