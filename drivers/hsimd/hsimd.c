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
#ifdef OS_OI
typedef	unsigned int sigset32_t;
#endif
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

//#include <sys/nexusdebug.h>
#include <sys/debug.h>

#include <sys/dkbad.h>
#include <sys/dklabel.h>
#include <sys/dkio.h>
#include <sys/cdio.h>
#include <sys/vtoc.h>
#include <sys/file.h>

#ifdef OS_OI
//#include "/export/code/illumos-gate/usr/src/uts/common/sys/cmlb.h"
//#include "sys_oi/cmlb.h"
#include <sys/cmlb.h>
#else
#include <sys/cmlb.h>
#endif
#include <sys/dktp/dadkio.h>
#include <sys/scsi/impl/uscsi.h>

char    ident[] = "hsimd v" VERSION;

//#define CONFIG_GLOBALLOCK
#define	CONFIG_HAT_BUG
#undef CONFIG_SOFT_INTR		/* hunged */
#define CONFIG_HARD_INTR		/* hunged */
#define CONFIG_START
#define CONFIG_IOQUE

/* compat */
#ifndef DTYPE_DIRECT
#define DTYPE_DIRECT	0
#endif
#ifndef DTYPE_RODIRECT
#define DTYPE_RODIRECT	5
#endif

#ifndef B_PRIVATE
#define B_PRIVATE	0x10000000	/* "opaque" driver private flag */
#endif
#define	HSIMD_B_ABSOLUTE B_PRIVATE

#define	HSIMD_UNIT(x)	(getminor(x) >> 3)
#define	HSIMD_SLICE(x)	(getminor(x) & 0x7)
#define	HSIMD_NSLICES	8

#define HSIMD_MULTIUNIT
#define	CONFIG_LOCAL_PARTINFO	/* mandatory for solaris10 */

/* imported from qmemu/target/sparc/int64_helper.c */
#define HCALL_DISKIO_DIR_MASK 8
#define HCALL_DISKIO_UNIT_MASK 56
#define HCALL_DISKIO_UNIT_SHIFT 8

#define HSIMD_CMD_DATAIO        0UL
#define HSIMD_CMD_READCAPACITY  1UL
#define HSIMD_CMD_DATAIO_ASYNC  2UL
#define HSIMD_CMD_GET_CAP       3UL
#define         HSIMD_CAP_ASYNC 0x0001
#define         HSIMD_CAP_CDROM 0x0002
#define         HSIMD_CAP_IOV	0x0004
#define HSIMD_CMD_GET_IOSTATUS  4UL
#define         HSIMD_IOSTATUS_OK       0
#define         HSIMD_IOSTATUS_NOAIO    1
#define         HSIMD_IOSTATUS_ERR      2
#define         HSIMD_IOSTATUS_BUSY	3
#define HSIMD_CMD_IOV           5UL
#define HSIMD_CMD_IOV_ASYNC     6UL
#define HSIMD_CMD_SHIFT         60
#define HSIMD_CMD_MASK          0xf
#define HSIMD_UNIT_SHIFT        32
#define HSIMD_UNIT_MASK         0x0fffffffULL
#define HSIMD_SIZE_SHIFT        0
#define HSIMD_SIZE_MASK         0xffffffffULL
/* end of import */

static uint64_t hsimd_read_capacity(size_t unit_no);
static uint64_t hsimd_get_cap(uint_t unit_no);
static uint64_t hsimd_get_iostatus(uint_t unit_no);

struct hsimd_label {
	daddr_t blockno;	/* Starting block number */
	daddr_t nblocks;	/* Number of blocks */
};

struct hsimd_unit {			/* unit structure - one per unit */
	dev_info_t	*hsimd_dip;		/* opaque devinfo info. */

#ifndef CONFIG_GLOBALLOCK
	kmutex_t	hsimd_mutex;	/* mutex to protect condition var */
	kcondvar_t	hsimd_cnd;	/* Used to protect device */
#ifdef notdef
	int		device_busy;
#define	HSIMD_BUSY(p)	((p)->device_busy)
#else
#define	HSIMD_BUSY(p)	((p)->hsimd_active)
#endif
#define	HSIMD_MUTEX(p)	((p)->hsimd_mutex)
#define	HSIMD_COND(p)	((p)->hsimd_cnd)
#endif
	struct buf	*hsimd_active;	/* currently active buf */
#ifdef CONFIG_LOCAL_PARTINFO
	struct hsimd_label label[NDKMAP];	/* slice information */
	uint8_t		hsimd_lvalid;
#endif
#ifdef notdef
	uint_t		hsimd_flags;
	struct dk_map32 hsimd_map[NDKMAP];
	struct dk_vtoc	hsimd_vtoc;
	struct dk_geom	hsimd_g;
	uchar_t hsimd_asciilabel[LEN_DKL_ASCII];
#endif
	uint64_t	hsimd_size;
	uint64_t	hsimd_cap;
	cmlb_handle_t	hsimd_dklbhandle;	/* Handle for disk label */
#ifdef CONFIG_SOFT_INTR
	ddi_softintr_t		hsimd_softint_id;
	ddi_iblock_cookie_t	hsimd_iblock;
#endif
	caddr_t		hsimd_iov;
	timeout_id_t	hsimd_to;
	int		hsimd_need_retry;
};

#ifdef CONFIG_GLOBALLOCK
kmutex_t	hsimd_mutex;	/* mutex to protect condition var */
kcondvar_t	hsimd_cnd;	/* Used to protect device */
struct buf	*hsimd_active;	/* Used to protect device */
#define	HSIMD_MUTEX(p)	hsimd_mutex
#define	HSIMD_COND(p)	hsimd_cnd
#define	HSIMD_BUSY(p)	hsimd_active
#endif /* CONFIG_GLOBALLOCK */

/*
 * Debugging
 */
#define	HSIMD_ATTACH		0x1
#define	HSIMD_RW		0x2
#ifdef DEBUG_LEVEL
static int	hsimd_debug = 0 /* | HSIMD_ATTACH | HSIMD_RW */;
#define DPRINTF(n, args)        if (hsimd_debug & (n)) printf args
#else
#define DPRINTF(n, args)
#endif

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
#if 0
static int hsimd_get_valid_geometry(struct hsimd_unit *hsimd_p);
#endif
#ifdef TG_DK_OPS_VERSION_1
/* Function prototypes for cmlb */
static int hsimd_tg_rdwr(dev_info_t *devi, uchar_t cmd, void *bufaddr,
	    diskaddr_t start_block, size_t reqlength, void *tg_cookie);
static int hsimd_tg_getinfo(dev_info_t *devi, int cmd, void *arg,
	    void *tg_cookie);
#else
/* TG_DK_OPS_VERSION_0 */
static int hsimd_tg_rdwr(dev_info_t *devi, uchar_t cmd, void *bufp,
            diskaddr_t start_block, size_t reqlength);
static int hsimd_tg_getphygeom(dev_info_t *devi, cmlb_geom_t *phygeomp);
static int hsimd_tg_getvirtgeom(dev_info_t *devi, cmlb_geom_t *virtgeomp);
static int hsimd_tg_getcapacity(dev_info_t *devi, diskaddr_t *capp);
static int hsimd_tg_getattribute(dev_info_t *devi, tg_attribute_t *tgattribute);
#endif

static int
hsimd_phys_rdwr(dev_t dev, int rw, void *buf_addr,
    diskaddr_t start_block, size_t reqlength, int mode);

#ifdef CONFIG_START
static int hsimd_start(struct hsimd_unit *hsimd_p, struct buf *bp);
#endif
#ifdef CONFIG_SOFT_INTR
static uint_t hsimd_intr(caddr_t arg);
#endif
#ifdef CONFIG_HARD_INTR
static uint_t hsimd_hard_intr(caddr_t arg);
#endif

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
	ident,					/* name of module  */
	&hsimd_ops				/* *Drv_dev_ops		*/
};

static  struct modlinkage modlinkage = {
	MODREV_1,  (void *)&modldrv, NULL
};

static cmlb_tg_ops_t hsimd_tgops = {
#ifdef TG_DK_OPS_VERSION_1
	TG_DK_OPS_VERSION_1,
	hsimd_tg_rdwr,
	hsimd_tg_getinfo
#else
	TG_DK_OPS_VERSION_0,
	hsimd_tg_rdwr,
        hsimd_tg_getphygeom,
	hsimd_tg_getvirtgeom,
	hsimd_tg_getcapacity,
	hsimd_tg_getattribute,
#endif
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
#include <sys/ddi_intr_impl.h>

static int
hsimd_attach(dev_info_t *dip, ddi_attach_cmd_t cmd)
{
	struct hsimd_unit	*hsimd_p;
	struct driver_minor_data	*dmdp;
	uint_t	unit_no;		/* attaching unit's number */
	int	i;
	int	nblks;
	struct dk_map32	*lmap;
	int	err;

	unit_no = ddi_get_instance(dip);

	if (cmd != DDI_ATTACH) {
		/* illegal request */
		return (DDI_FAILURE);
	}

	DPRINTF(HSIMD_ATTACH, ("hsimd%d: attaching instance\n", unit_no));

	/*
	 * Allocate a unit structure for this unit.
	 * Each hsimd_unit struct is allocated as zeroed memory.
	 * Store away its address for future use.
	 */
	if (ddi_soft_state_zalloc(hsimd_state_head, unit_no) != 0) {
		return (DDI_FAILURE);
	}

	/* assign a pointer to this unit's state struct */
	hsimd_p = getsoftc(unit_no);
#ifdef notdef
	hsimd_p->hsimd_flags = 0;
#endif
	hsimd_p->hsimd_dip = dip;
#ifdef CONFIG_LOCAL_PARTINFO
	hsimd_p->hsimd_lvalid = B_FALSE;
#endif
	/* check if disk exists */
	hsimd_p->hsimd_size = hsimd_read_capacity(unit_no);
	if (hsimd_p->hsimd_size == 0) {
		cmn_err(CE_NOTE, "!hsimd%d: %s: no disk",
		    unit_no, __func__);
		ddi_soft_state_free(hsimd_state_head, unit_no);
		return (DDI_FAILURE);
	}

	hsimd_p->hsimd_cap = hsimd_get_cap(unit_no);
	cmn_err(CE_CONT, "hsimd%d: %s: size:0x%llx, cap:0x%llx\n",
	    unit_no, __func__, hsimd_p->hsimd_size, hsimd_p->hsimd_cap);

	hsimd_p->hsimd_iov = kmem_alloc(MMU_PAGESIZE * 2, KM_SLEEP);

	/*
	 * Initialize the unit structures. The unit structure for
	 * each unit is initialized when hsimd_attach is called for that unit.
	 */

	/*
	 * Initialize the hsimd mutex.
	 */
#ifdef CONFIG_SOFT_INTR
	/* get soft iblock cookie */
	if (ddi_get_soft_iblock_cookie(dip, DDI_SOFTINT_LOW,
	    &hsimd_p->hsimd_iblock) != DDI_SUCCESS)  {
		/* clean up */
		return (DDI_FAILURE); /* fail attach */
	}

	/* initialize low-level mutex */
	mutex_init(&HSIMD_MUTEX(hsimd_p), "hsimd low mutex", MUTEX_DRIVER,
	    (void *)&hsimd_p->hsimd_iblock);

	/* add low level routine - xxsoftintr() */
	if (ddi_add_softintr(dip, DDI_SOFTINT_LOW, &hsimd_p->hsimd_softint_id,
	    NULL, NULL, hsimd_intr, (caddr_t)hsimd_p) != DDI_SUCCESS) {
		/* cleanup */
		return (DDI_FAILURE);  /* fail attach */
	}

	cv_init(&HSIMD_COND(hsimd_p), "hsimd condition variable", CV_DRIVER,
	    NULL);
#else
# ifdef CONFIG_GLOBALLOCK
	if (unit_no == 0) {
		mutex_init(&HSIMD_MUTEC(hsimd_p), "hsimd mutex",
		    MUTEX_DRIVER, NULL);
		cv_init(&HSIMD_COND(hsimd_p), "hsimd condition variable", CV_DRIVER,
		    NULL);
	}
# else
	mutex_init(&HSIMD_MUTEX(hsimd_p), "hsimd mutex",
	    MUTEX_DRIVER, NULL);
	cv_init(&HSIMD_COND(hsimd_p), "hsimd condition variable", CV_DRIVER,
	    NULL);
#endif /* CONFIG_GLOBALLOCK */
#endif /* !CONFIG_SOFT_INTR */

	/*
	 * Get geometry and label from disk
	 */
        cmlb_alloc_handle(&hsimd_p->hsimd_dklbhandle);

#ifdef TG_DK_OPS_VERSION_1
	if (cmlb_attach(dip,
	    &hsimd_tgops,
	    (((hsimd_p->hsimd_cap & HSIMD_CAP_CDROM) == 0) ?
	        DTYPE_DIRECT : DTYPE_RODIRECT),
	    B_FALSE,
	    B_FALSE,
	    DDI_NT_BLOCK /* DDI_NT_BLOCK_CHAN */,
	    0 /* CMLB_FAKE_GEOM_LABEL_IOCTLS_VTOC8 */,
	    hsimd_p->hsimd_dklbhandle,
	    0) != 0) {
		cmlb_free_handle(&hsimd_p->hsimd_dklbhandle);
		goto err;
	}
	err = cmlb_validate(hsimd_p->hsimd_dklbhandle, 0, (void *)0);
#else
	if (cmlb_attach(dip,
	    &hsimd_tgops,
	    (((hsimd_p->hsimd_cap & HSIMD_CAP_CDROM) == 0) ?
	        DTYPE_DIRECT : DTYPE_RODIRECT),
	    B_FALSE,
	    DDI_NT_BLOCK /* DDI_NT_BLOCK_CHAN */,
	    0 /* CMLB_FAKE_GEOM_LABEL_IOCTLS_VTOC8 */,
	    hsimd_p->hsimd_dklbhandle) != 0) {
		cmlb_free_handle(&hsimd_p->hsimd_dklbhandle);
		goto err;
	}

	err = cmlb_validate(hsimd_p->hsimd_dklbhandle);
#endif /* TG_DK_OPS_VERSION_1 */
	if (err != 0 && err != EINVAL) {
		cmn_err(CE_CONT, "?hsims%d: %s:cmlb_valid: failed, err=%d\n",
		    unit_no, __func__, err);

		cmlb_free_handle(&hsimd_p->hsimd_dklbhandle);
		goto err;
	}
#ifdef CONFIG_LOCAL_PARTINFO
	if (err == 0) {
		diskaddr_t nblocks;
		diskaddr_t sblock;
		char	*pname;
		uint16_t tag;

		for (i = 0; i < NDKMAP; i++) {
#ifdef TG_DK_OPS_VERSION_1
			err = cmlb_partinfo(hsimd_p->hsimd_dklbhandle,
			    i, &nblocks, &sblock, &pname, &tag, 0);
#else
			err = cmlb_partinfo(hsimd_p->hsimd_dklbhandle,
			    i, &nblocks, &sblock, &pname, &tag);
#endif
			if (err) {
				/* no valid partition */
				cmn_err(CE_CONT,
				    "?hsimd%d:  %s: part %d not valid err:%d\n",
				    unit_no, __func__, i, err);
				hsimd_p->label[i].blockno = 0;
				hsimd_p->label[i].nblocks = 0;
				continue;
			}

			cmn_err(CE_CONT,
			    "?hsimd%d: %s: part %d %lld - %lld %s 0x%x\n",
			    unit_no, __func__, i,
			    sblock, nblocks, pname, tag);

			/* save valid partition range */
			hsimd_p->label[i].blockno = sblock;
			hsimd_p->label[i].nblocks = nblocks;
			hsimd_p->hsimd_lvalid = B_TRUE;
		}
	}
#endif /* CONFIG_LOCAL_PARTINFO */
#ifdef CONFIG_HARD_INTR
{
	int	type;
	int	ret;
	int	nintr;
	void	*htable;
	int	actual;
	uint_t	intr_pri;
	ddi_intr_handle_impl_t	*hdlp;
	ddi_iblock_cookie_t	iblock_cookie;
	ddi_idevice_cookie_t	idevice_cookie;

	type = 0;
	ret = ddi_intr_get_supported_types(dip, &type);
	cmn_err(CE_CONT, "hsimd%d: %s: intr type: %d, ret:%d\n",
	    unit_no, __func__, type, ret);

	nintr = 0;
	ret = ddi_intr_get_nintrs(dip, type, &nintr);
	cmn_err(CE_CONT, "hsimd%d: %s: intr nintr: %d, ret:%d\n",
	    unit_no, __func__, nintr, ret);

        htable = kmem_zalloc(nintr * sizeof (ddi_intr_handle_t), KM_SLEEP);

        ret = ddi_intr_alloc(dip, htable,
            DDI_INTR_TYPE_FIXED, 0, nintr, &actual, 0);

        if ((ret != DDI_SUCCESS) || (actual != 1)) {
                cmn_err(CE_WARN, "!hsimd%d: %s: ddi_intr_alloc() failed 0x%x",
		    unit_no, __func__, ret);
		goto fail;
        }
	for (i = 0; i < actual; i++) {
		hdlp = (void *)((intptr_t *)htable)[i];
		cmn_err(CE_CONT,
		    "hsimd%d: type:%d pri:%d cap:0x%x ver:%d state:0x%x,\n"
		    " dip:%p, inum:%d vector:0x%x, target:%d\n",
		    unit_no,
		    hdlp->ih_type, hdlp->ih_pri,
		    hdlp->ih_cap, hdlp->ih_ver,
		    hdlp->ih_state, hdlp->ih_dip,
		    hdlp->ih_inum, hdlp->ih_vector,
		    hdlp->ih_target);
	}

        /* Get the priority of the interrupt */
        if (ddi_intr_get_pri(((void **)htable)[0], &intr_pri) != DDI_SUCCESS) {
                cmn_err(CE_WARN, "!hsimd%d: %s: ddi_intr_alloc() failed 0x%x",
                    unit_no, __func__, ret);
		goto fail;
        }
	cmn_err(CE_CONT,
	    "hsimd%d: %s: pri:0x%x\n", unit_no, __func__, intr_pri);

	err = ddi_add_intr(dip, 0, &iblock_cookie, &idevice_cookie,
	    hsimd_hard_intr, (caddr_t)hsimd_p);
	if (err != DDI_SUCCESS) {
		cmn_err(CE_CONT, "hsimd%d: add_intr failed err:%d\n",
		    unit_no, err);
		goto fail;
	}
}
fail:
#endif /* CONFIG_HARD_INTR */

	ddi_report_dev(dip);

	DPRINTF(HSIMD_ATTACH, ("hsimd attach done\n"));
	return (DDI_SUCCESS);

err:
	mutex_destroy(&HSIMD_MUTEX(hsimd_p));
	ddi_soft_state_free(hsimd_state_head, unit_no);
	return (DDI_FAILURE);
}

static int
hsimd_detach(dev_info_t *devi, ddi_detach_cmd_t cmd)
{
	int instance;
	struct	hsimd_unit *hsimd_p;

	switch (cmd) {
	case DDI_DETACH:

		instance = ddi_get_instance(devi);
		hsimd_p = getsoftc(instance);
#ifdef TG_DK_OPS_VERSION_1
		cmlb_detach(hsimd_p->hsimd_dklbhandle, 0);
#else
		cmlb_detach(hsimd_p->hsimd_dklbhandle);
#endif
		cmlb_free_handle(&hsimd_p->hsimd_dklbhandle);
		ddi_remove_minor_node(devi, NULL);
		ddi_soft_state_free(hsimd_state_head, instance);
		return (DDI_SUCCESS);

	case DDI_SUSPEND:
		return (DDI_SUCCESS);
	}
	cmn_err(CE_CONT,
		"?%s: detach failed.\n", "hsimd");
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
			*result = hsimd_p->hsimd_dip;
			error = DDI_SUCCESS;
		}
		break;
	case DDI_INFO_DEVT2INSTANCE:
		instance = HSIMD_UNIT(getminor((dev_t)arg));
		*result = (void *)(uintptr_t) instance;
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

#ifdef HSIMD_MULTIUNIT
static int
hcall_diskio(int dir, uint64_t pa, size_t size, off_t offset, size_t unit_no)
#else
static int
hcall_diskio(int dir, uint64_t pa, size_t size, off_t offset)
#endif
{
	size_t osize = size;
	extern size_t hv_disk_read(uint64_t, uint64_t, size_t);
	extern size_t hv_disk_write(uint64_t, uint64_t, size_t);

	if (dir) {
#ifdef HSIMD_MULTIUNIT
		size = hv_disk_read(offset, pa, size | (unit_no << 32));
#else
		size = hv_disk_read(offset, pa, size);
#endif
		DPRINTF(HSIMD_RW, ("hsimd Disk Read from offset %lx, "
		    "%lx bytes into RA %lx, size=%lx\n",
		    offset, osize, pa, size));
	} else {
#ifdef HSIMD_MULTIUNIT
		size = hv_disk_write(offset, pa, size | (unit_no << 32));
#else
		size = hv_disk_write(offset, pa, size);
#endif
		DPRINTF(HSIMD_RW, ("hsimd Disk Write to offset %lx, "
		    "%lx bytes from RA %lx, size=%lx\n",
		    offset, osize, pa, size));
	}
	if (size == (size_t)-1) {
		cmn_err(CE_WARN, "?hsimd: hcall_diskio error from hv_disk_%s"
		    "(offset=%lx pa=%lx size=%lx)\n",
		    (dir ? "read" : "write"), offset, pa, osize);
	}
	return (size);
}

#define	va2tsize(v) (MMU_PAGESIZE - ((uint64_t)(v) & MMU_PAGEOFFSET))
#define	PAGE_ROUNDUP(val)	(((val) + MMU_PAGEOFFSET) & MMU_PAGEMASK)

#ifdef HSIMD_MULTIUNIT
static ssize_t
hsimd_diskio_iov(int dir, struct buf *bp, caddr_t vadr, size_t sz,
    off_t offset, uint64_t unit_no)
{
	struct hsimd_unit *hsimd_p = getsoftc(unit_no);
	caddr_t		va;
	uint64_t	pa;
	size_t		size;
	size_t		tsize;
	size_t		asize;
	iovec_t		*iov;
	int		i;
	uint64_t	cmd;
#ifdef	CONFIG_HAT_BUG
	struct page	*pp;
#endif
	ASSERT(sz <= 128*1024);

	iov = (iovec_t *)PAGE_ROUNDUP((long)hsimd_p->hsimd_iov);
	va = vadr;
	size = sz;

	cmd = HSIMD_CMD_IOV;
	if (hsimd_p->hsimd_cap & HSIMD_CAP_ASYNC) {
		cmd = HSIMD_CMD_IOV_ASYNC;
	}
#if 0
	cmn_err(CE_CONT, "hsimd%d %s: vadr %p sz = %lx\n",
	    unit_no, __func__, vadr, sz);
#endif
#ifdef	CONFIG_HAT_BUG
	pp = NULL;
	if (bp && bp->b_flags & B_PAGEIO) {
		pp = bp->b_pages;
	}
#endif
	i = 0;
	while (size) {
#ifdef	CONFIG_HAT_BUG
		if (bp && (bp->b_flags & B_PAGEIO)) {
			pa = ptob(pp->p_pagenum) + ((uintptr_t)va & PAGEOFFSET);
			pp = pp->p_next;
		} else
#endif /* CONFIG_HAT_BUG */
		{
			pa = va_to_pa(va);
		}

		if (pa == (uint64_t)-1) {
			/* error: failed to get physical address */
			asize = 0;
			goto done;
		}

		/* trim size */
		tsize = min(size, va2tsize(va));

		/* add iovec entry */
		iov[i].iov_base = (void *)pa;
		iov[i].iov_len  = tsize;
#if 0
		cmn_err(CE_CONT, "hsimd%d: %s: [%d] 0x%llx + 0x%llx\n",
		    unit_no, __func__, i, pa, tsize);
#endif
		size -= tsize;
		va += tsize;
		i++;
	}

	asize = hcall_diskio(dir, va_to_pa((caddr_t)iov),
	    cmd << HSIMD_CMD_SHIFT | i, offset, unit_no);

	if (asize == (size_t)-1 || asize == 0) {
		/* I/O error */
		asize = 0;
		goto done;
	}

	if (cmd == HSIMD_CMD_IOV_ASYNC) {
		uint64_t	ret;
		i = 0;
		while ((ret = hsimd_get_iostatus(unit_no)) ==
		    HSIMD_IOSTATUS_BUSY) {
			if (i < 10) {
				i++;
				continue;
			}
			delay(drv_usectohz(1000));
		}

		if (ret != HSIMD_IOSTATUS_OK) {
			cmn_err(CE_CONT, "hsimd%d: %s: timeout: %d\n",
			    unit_no, __func__, asize);
			asize = 0;
		}
	}
done:
	DPRINTF(HSIMD_RW, ("\n"));
	return (asize);
}

static ssize_t
hsimd_diskio(int dir, struct buf *bp, caddr_t vadr, size_t sz, off_t offset, size_t unit_no)
#else
static ssize_t
hsimd_diskio(int dir, caddr_t vadr, size_t sz, off_t offset)
#endif
{
	caddr_t		va;
	uint64_t	pa;
	size_t		size, tsize;
	size_t		asize;	/* actual size */
	int		cap;
	uint64_t	cmd;
#ifdef	CONFIG_HAT_BUG
	struct page	*pp;
#endif
	struct hsimd_unit *hsimd_p = getsoftc(unit_no);

	cap = hsimd_p->hsimd_cap & (HSIMD_CAP_ASYNC | HSIMD_CAP_IOV);
	if (cap & HSIMD_CAP_IOV) {
		return (hsimd_diskio_iov(
		    dir, bp, vadr, sz, offset, unit_no));
	}
	cmd = HSIMD_CMD_DATAIO;
#if 0
	if (cap & HSIMD_CAP_ASYNC) {
		cmd = HSIMD_CMD_DATAIO_ASYNC;	/* slow */
	}
#endif
	va = vadr;
	size = sz;

#ifdef	CONFIG_HAT_BUG
	pp = NULL;
	if (bp && bp->b_flags & B_PAGEIO) {
		pp = bp->b_pages;
	}
#endif
	DPRINTF(HSIMD_RW, ("hsimd vadr %p sz = %lx\n", vadr, sz));

	while (size) {
#ifdef	CONFIG_HAT_BUG
		if (bp && (bp->b_flags & B_PAGEIO)) {
			pa = ptob(pp->p_pagenum) + ((uintptr_t)va & PAGEOFFSET);
			pp = pp->p_next;
		} else
#endif /* CONFIG_HAT_BUG */
		{
			pa = va_to_pa(va);
		}
		if (pa == (uint64_t)-1) {
			return (sz - size);
		}
		tsize = min(size, va2tsize(va));

		DPRINTF(HSIMD_RW, ("hsimd va = %p, pa = %lx, tsize = %lx\n",
		    va, pa, tsize));
#ifdef HSIMD_MULTIUNIT
		asize = hcall_diskio(dir, pa,
		    cmd << HSIMD_CMD_SHIFT | tsize, offset, unit_no);
#else
		asize = hcall_diskio(dir, pa, tsize, offset);
#endif
		if (asize == (size_t)-1 || asize == 0) {
			return (sz - size);
		}
#ifdef HSIMD_MULTIUNIT
		if (cmd == HSIMD_CMD_DATAIO_ASYNC) {
			uint64_t	ret;

			while ((ret = hsimd_get_iostatus(unit_no))
			    == HSIMD_IOSTATUS_BUSY) {
				delay(1 * drv_usectohz(1000));
			}

			if (ret != HSIMD_IOSTATUS_OK) {
				/* something wrong happened */
				return (sz - size);
			}
		}
#endif
		size -= asize;
		va += asize;
		offset += asize;
	}
	DPRINTF(HSIMD_RW, ("\n"));
	return (sz);
}

static uint64_t
hsimd_read_capacity(size_t unit_no)
{
	uint64_t size;
	extern size_t hv_disk_read(uint64_t, uint64_t, size_t);

	/* return disk size in bytes */
	size = hv_disk_read(0, 0,
	     (unit_no << HSIMD_UNIT_SHIFT) |
	    HSIMD_CMD_READCAPACITY << HSIMD_CMD_SHIFT);
#if 0
	cmn_err(CE_CONT, "hsimd%d: %s: capacity 0x%llx bytes\n",
	    unit_no, __func__, size);
#endif
	return (size);
}

static uint64_t
hsimd_get_cap(uint_t unit_no)
{
	uint64_t cap;
	extern size_t hv_disk_read(uint64_t, uint64_t, size_t);

	/* return qemu disk driver capabilities */
	cap = hv_disk_read(0, 0,
	     ((uint64_t)unit_no) << HSIMD_UNIT_SHIFT |
	    HSIMD_CMD_GET_CAP << HSIMD_CMD_SHIFT);
#if 0
	cmn_err(CE_CONT, "hsimd%d: %s: cap 0x%lx\n",
	    unit_no, __func__, cap);
#endif
	return (cap);
}

static uint64_t
hsimd_get_iostatus(uint_t unit_no)
{
	uint64_t status;
	extern size_t hv_disk_read(uint64_t, uint64_t, size_t);

	/* return aio status */
	status = hv_disk_read(0, 0,
	     ((uint64_t)unit_no) << HSIMD_UNIT_SHIFT |
	    HSIMD_CMD_GET_IOSTATUS << HSIMD_CMD_SHIFT);
#if 0
	cmn_err(CE_CONT, "hsimd%d: %s: status 0x%lx\n",
	    unit_no, __func__, status);
#endif
	return (status);
}

static int
hsimd_dump(dev_t dev, caddr_t addr, daddr_t blkno, int nblk)
{
	struct hsimd_unit *hsimd_p;
	uint_t  	unit_no;
	uint_t 		slice_no;
	off_t		diskoffset;	/* Byte offset into the disk */
	size_t		size;		/* Transfer size in bytes */
	diskaddr_t	nblks;
	diskaddr_t	start_block;
	
	unit_no = HSIMD_UNIT(dev);
	slice_no = HSIMD_SLICE(dev);

	hsimd_p = getsoftc(unit_no);
	if (hsimd_p == NULL) {
		cmn_err(CE_WARN, "hsimd: no softstate for unit %d", unit_no);
		return (ENXIO);
	}

#ifdef CONFIG_LOCAL_PARTINFO
	if (!hsimd_p->hsimd_lvalid) {
		cmn_err(CE_WARN, "hsimd: invalid disk label %d", unit_no);
		return (ENXIO);
	}

	nblks = hsimd_p->label[slice_no].nblocks;
	start_block = hsimd_p->label[slice_no].blockno;
#else
#ifdef TG_DK_OPS_VERSION_1
	(void) cmlb_partinfo(hsimd_p->hsimd_dklbhandle, slice_no,
	    &nblks, &start_block, NULL, NULL, NULL);
#else
	(void) cmlb_partinfo(hsimd_p->hsimd_dklbhandle, slice_no,
	    &nblks, &start_block, NULL, NULL);
#endif /* TG_DK_OPS_VERSION_1 */
#endif /* CONFIG_LOCAL_PARTINFO */

	if (blkno >= nblks) {
		return (ENXIO);
	}

	if ((blkno + nblk) > nblks) {
		return (ENXIO);
	}

	size = nblk * DEV_BSIZE;
	diskoffset = (start_block + blkno) * DEV_BSIZE;
#ifdef HSIMD_MULTIUNIT
	(void) hsimd_diskio(0, NULL, addr, size, diskoffset, unit_no);
#else
	(void) hsimd_diskio(0, addr, size, diskoffset);
#endif
	return (0);
}

/*ARGSUSED*/
static int
hsimd_strategy(struct buf *bp)
{
	struct	hsimd_unit	*hsimd_p;
	uint_t		unit_no;
	uint_t 		slice_no;
	uint_t		blk_no;
	off_t		diskoffset;	/* Byte offset into the disk */
	size_t		size;		/* Transfer size in bytes */
	caddr_t		addr;		/* Buffer virtual address */
	ssize_t		tsize;		/* Actual transfer size */
	diskaddr_t	nblocks;
	diskaddr_t	partition_offset;
	struct buf	*nbp;

	unit_no = HSIMD_UNIT(bp->b_edev);
	slice_no = HSIMD_SLICE(bp->b_edev);

	hsimd_p = getsoftc(unit_no);
	if (hsimd_p == NULL) {
		cmn_err(CE_WARN, "hsimd%d: no softstate for unit", unit_no);
		bioerror(bp, EIO);
		goto bad;
	}

	if (hsimd_p->hsimd_size == 0) {
		cmn_err(CE_WARN, "hsimd%d: %s: no disk", __func__, unit_no);
		bioerror(bp, ENXIO);
		goto bad;
	}

	/* error if transfer count not multiple of sector size */
	if (bp->b_bcount & (DEV_BSIZE - 1)) {
		bioerror(bp, EINVAL);
		goto bad;
	}

	blk_no = (uint_t)bp->b_blkno;
	size = bp->b_bcount;

#ifdef CONFIG_LOCAL_PARTINFO
	nblocks = hsimd_p->label[slice_no].nblocks;
	partition_offset = hsimd_p->label[slice_no].blockno;
#else
	nblocks = 0;
#ifdef TG_DK_OPS_VERSION_1
        (void) cmlb_partinfo(hsimd_p->hsimd_dklbhandle, slice_no,
            &nblocks, &partition_offset, NULL, NULL, NULL);
#else
        (void) cmlb_partinfo(hsimd_p->hsimd_dklbhandle, slice_no,
            &nblocks, &partition_offset, NULL, NULL);
#endif /* TG_DK_OPS_VERSION_1 */
#endif /* CONFIG_LOCAL_PARTINFO */

	if (nblocks &&
	    (bp->b_flags & HSIMD_B_ABSOLUTE) == 0) {

		/* partition cache is valid and use it */

		if (blk_no > nblocks) {
			/*
			 * Error if beginning of requested blk past
			 * end of partition + 1
			 */
			bioerror(bp, ENXIO);
			goto bad;
		}

		if ((blk_no + (bp->b_bcount / DEV_BSIZE)) > nblocks) {
			/*
			 * Trim transfer size if end of requested blk past
			 * end of partition
			 */
			size = (nblocks - blk_no) * DEV_BSIZE;
		}
		diskoffset = (partition_offset + blk_no) * DEV_BSIZE;
	}
	else {
		/* no label */
		if ((blk_no + bp->b_bcount / DEV_BSIZE)
		    > hsimd_p->hsimd_size / DEV_BSIZE) {

			/* trim transfer size */
			size = hsimd_p->hsimd_size - blk_no * DEV_BSIZE;
		}
		diskoffset = blk_no * DEV_BSIZE;
	}

	if (size == 0) {
		goto bad;
	}

	/*
	 * Put buf request in the controller's queue, FIFO
	 */
	bp->av_forw = NULL;
#ifdef CONFIG_SOFT_INTR
	bp->b_private = (void *)0;
#endif
	mutex_enter(&HSIMD_MUTEX(hsimd_p));
#ifdef CONFIG_IOQUE
	if (HSIMD_BUSY(hsimd_p)) {
		hsimd_p->hsimd_active->av_back->av_forw = bp;
		hsimd_p->hsimd_active->av_back = bp;
		mutex_exit(&HSIMD_MUTEX(hsimd_p));
		return (0);
	}
#else
	while (HSIMD_BUSY(hsimd_p)) {
		cv_wait(&HSIMD_COND(hsimd_p), &HSIMD_MUTEX(hsimd_p));
	}
#endif
#ifdef CONFIG_IOQUE
	bp->av_back = bp;
#endif
	HSIMD_BUSY(hsimd_p) = bp;

	mutex_exit(&HSIMD_MUTEX(hsimd_p));

	/*
	 *  hypervisor call(s) to do the transfer
	 */
#ifdef CONFIG_IOQUE
again:
#endif
#ifdef CONFIG_START
	hsimd_start(hsimd_p, bp);
#else
	bp_mapin(bp);
	addr = bp->b_un.b_addr;

#ifdef HSIMD_MULTIUNIT
	tsize = hsimd_diskio(bp->b_flags & B_READ,
	    bp, addr, size, diskoffset, unit_no);
#else
	tsize = hsimd_diskio(bp->b_flags & B_READ, addr, size, diskoffset);
#endif
	bp->b_resid = bp->b_bcount - tsize;
#endif /* CONFIG_START */

#ifdef CONFIG_SOFT_INTR
	bp->b_private = (void *)B_TRUE;
	ddi_trigger_softintr(hsimd_p->hsimd_softint_id);
#else
	mutex_enter(&HSIMD_MUTEX(hsimd_p));
	nbp = bp->av_forw;;
	if (nbp) {
		/* keep pointer to tail */
		nbp->av_back = bp->av_back;
	}
	HSIMD_BUSY(hsimd_p) = nbp;
	mutex_exit(&HSIMD_MUTEX(hsimd_p));

	bp_mapout(bp);
	(void) biodone(bp);

#ifdef CONFIG_IOQUE
	if (nbp) {
		bp = nbp;
		goto again;
	}
#else
	cv_signal(&HSIMD_COND(hsimd_p));
#endif /* CONFIG_IOQUE*/
#endif /* CONFIG_SOFT_INTR */

	return (0);

bad:
	bp->b_resid = bp->b_bcount;
	(void) biodone(bp);
	return (0);
}

#ifdef CONFIG_START
static int
hsimd_start(struct hsimd_unit *hsimd_p, struct buf *bp)
{
	uint_t		unit_no;
	uint_t 		slice_no;
	uint64_t	blk_no;
	off_t		diskoffset;	/* Byte offset into the disk */
	size_t		size;		/* Transfer size in bytes */
	caddr_t		addr;		/* Buffer virtual address */
	ssize_t		tsize;		/* Actual transfer size */
	diskaddr_t	nblocks;
	diskaddr_t	partition_offset;

	unit_no = HSIMD_UNIT(bp->b_edev);
	slice_no = HSIMD_SLICE(bp->b_edev);

	blk_no = bp->b_blkno;
	size = bp->b_bcount;

#ifdef CONFIG_LOCAL_PARTINFO
	nblocks = hsimd_p->label[slice_no].nblocks;
	partition_offset = hsimd_p->label[slice_no].blockno;
#else
	nblocks = 0;
#ifdef TG_DK_OPS_VERSION_1
        (void) cmlb_partinfo(hsimd_p->hsimd_dklbhandle, slice_no,
            &nblocks, &partition_offset, NULL, NULL, NULL);
#else
        (void) cmlb_partinfo(hsimd_p->hsimd_dklbhandle, slice_no,
            &nblocks, &partition_offset, NULL, NULL);
#endif /* TG_DK_OPS_VERSION_1 */
#endif /* CONFIG_LOCAL_PARTINFO */

	if (nblocks && (bp->b_flags & HSIMD_B_ABSOLUTE) == 0) {
		/* partition cache is valid and use it */
		if ((blk_no + (bp->b_bcount / DEV_BSIZE)) > nblocks) {
			/*
			 * Trim transfer size if end of requested blk past
			 * end of partition
			 */
			size = (nblocks - blk_no) * DEV_BSIZE;
		}
		diskoffset = (partition_offset + blk_no) * DEV_BSIZE;
	} else {
		/* no label */
		if ((blk_no + bp->b_bcount / DEV_BSIZE)
		    > hsimd_p->hsimd_size / DEV_BSIZE) {

			/* trim transfer size */
			size = hsimd_p->hsimd_size - blk_no * DEV_BSIZE;
		}
		diskoffset = blk_no * DEV_BSIZE;
	}

	bp_mapin(bp);
	addr = bp->b_un.b_addr;

#ifdef HSIMD_MULTIUNIT
	tsize = hsimd_diskio(bp->b_flags & B_READ,
	    bp, addr, size, diskoffset, unit_no);
#else
	tsize = hsimd_diskio(bp->b_flags & B_READ, addr, size, diskoffset);
#endif
	bp->b_resid = bp->b_bcount - tsize;
	return (0);
}
#endif /* CONFIG_START */

#ifdef CONFIG_SOFT_INTR
static uint_t
hsimd_intr(caddr_t arg)
{
	struct hsimd_unit	*hsimd_p;
	struct buf	*bp;
	struct buf	*nbp;

	hsimd_p = (void *)arg;
again:	
	mutex_enter(&HSIMD_MUTEX(hsimd_p));
	if ((bp = HSIMD_BUSY(hsimd_p)) == NULL) {
		mutex_exit(&HSIMD_MUTEX(hsimd_p));
		/* not for me */
		return (DDI_INTR_UNCLAIMED);
	}

	if (bp->b_private == (void *)0) {
		/* still busy */
		mutex_exit(&HSIMD_MUTEX(hsimd_p));
		/* not for me */
		return (DDI_INTR_UNCLAIMED);
	}

	nbp = bp->av_forw;
	if (nbp) {
		/* keep pointer to tail */
		nbp->av_back = bp->av_back;
	}
	HSIMD_BUSY(hsimd_p) = nbp;
	mutex_exit(&HSIMD_MUTEX(hsimd_p));
#ifndef CONFIG_IOQUE
	ASSERT(nbp == NULL);
#endif
	bp_mapout(bp);

	(void) biodone(bp);
#ifdef CONFIG_IOQUE
	/* issue next request */
	if (nbp) {
		hsimd_start(hsimd_p, nbp);
		bp->b_private = (void *)B_TRUE;
#if 0
		ddi_trigger_softintr(hsimd_p->hsimd_softint_id);
#else
		goto again;
#endif
	}
#else
	cv_signal(&HSIMD_COND(hsimd_p));
#endif
	return (DDI_INTR_CLAIMED);
}
#endif /* CONFIG_SOFT_INTR */

#ifdef CONFIG_HARD_INTR
static uint_t
hsimd_hard_intr(caddr_t arg)
{
	struct hsimd_unit	*hsimd_p;

	hsimd_p = (void *)arg;

	return (DDI_INTR_CLAIMED);
}
#endif /* CONFIG_HARD_INTR*/

#if 0
static int
hsimd_get_valid_geometry(struct hsimd_unit *hsimd_p)
{
	struct dk_label *dkl;
	caddr_t	addr;
	uint_t diskoffset;
	size_t	size, tsize;
	uint_t unit_no;

	unit_no = ddi_get_instance(hsimd_p->hsimd_dip);
	size = hsimd_read_capacity(unit_no);
	if (size == 0) {
		cmn_err(CE_WARN, "hsimd%d: %s can't get capacity",
		    unit_no, __func__);
		return (-1);
	}
	hsimd_p->hsimd_size = size;

	dkl = kmem_zalloc(sizeof (struct dk_label),
	    KM_SLEEP);
	addr = (caddr_t)dkl;
	diskoffset = 0;		/* first block */
	size = sizeof (*dkl);
#ifdef HSIMD_MULTIUNIT
	tsize = hsimd_diskio(1, NULL, addr, size, diskoffset, unit_no);
#else
	tsize = hsimd_diskio(1, addr, size, diskoffset);
#endif
	if (tsize <  sizeof (*dkl)) {
		cmn_err(CE_WARN, "hsimd%d: %s can't get vtoc",
		    unit_no, __func__);
		kmem_free(dkl, sizeof (struct dk_label));
		return (-1);
	}
	/*
	 * Check magic number of the label
	 */
	if (dkl->dkl_magic != DKL_MAGIC) {
		cmn_err(CE_WARN, "hsimd%d: %s bad magic no:%x",
		    unit_no, __func__, dkl->dkl_magic);
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
#endif

static int
#ifdef TG_DK_OPS_VERSION_1
hsimd_tg_rdwr(dev_info_t *dip, uchar_t cmd, void *bufp,
    diskaddr_t start_block, size_t reqlength, void *tg_cookie)
#else
hsimd_tg_rdwr(dev_info_t *dip, uchar_t cmd, void *bufp,
    diskaddr_t start_block, size_t reqlength)
#endif
{
	int	unit_no;
	int	ret;
	uint64_t	status;
	struct hsimd_unit	*hsimd_p;

	unit_no = ddi_get_instance(dip);
	hsimd_p = getsoftc(unit_no);
#if 0
	cmn_err(CE_CONT, "hsimd%d: "
	    "dev:%d,%d: %s: called cmd:%d buf:0x%llp dblk:%lld - %lld\n",
	    unit_no,
	   ((struct dev_info *)dip)->devi_major, unit_no << 3,
	    __func__, cmd, bufp, start_block, reqlength);
#endif
	ret = hsimd_phys_rdwr(
	    makedevice(((struct dev_info *)dip)->devi_major, unit_no << 3),
	    cmd == TG_READ ? B_READ : B_WRITE,
	    bufp,
	    start_block, reqlength, FKIOCTL);

	return (ret);
}

static int
hsimd_tg_getphygeom(dev_info_t *dip, cmlb_geom_t *phygeomp)
{
	struct hsimd_unit	*hsimd_p;
	struct dk_label	*dkl;
	size_t		tsize;
	uint64_t	unit_no;
	cmlb_handle_t	*clp;
	int		err;
	size_t		spc;

	unit_no = ddi_get_instance(dip);
#ifdef notdef
	cmn_err(CE_CONT, "?hsimd%d: %s: called\n",unit_no,  __func__);
#endif
	hsimd_p = getsoftc(unit_no);
	err = 0;

	phygeomp->g_nhead = 3;
	phygeomp->g_nsect = 128;
	do {
		phygeomp->g_nhead <<= 1;
		phygeomp->g_nsect <<= 1;
		spc = phygeomp->g_nhead * phygeomp->g_nsect * DEV_BSIZE;
		phygeomp->g_ncyl = hsimd_p->hsimd_size / spc;
	} while (phygeomp->g_ncyl >= (1<<16));

	phygeomp->g_ncyl -= 2;
	phygeomp->g_acyl = 2;
	phygeomp->g_secsize = DEV_BSIZE;
        phygeomp->g_capacity = hsimd_p->hsimd_size / DEV_BSIZE;
        phygeomp->g_intrlv = 1;
        phygeomp->g_rpm = 7200;

#ifdef notdef
	cmn_err(CE_CONT, "?hsimd%d: "
	    "%s: ncyl:%u acyl:%u nhead:%u nsect:%u secsize:%d cap:%llu\n",
	    unit_no,  __func__,
	    phygeomp->g_ncyl, phygeomp->g_acyl,
	    phygeomp->g_nhead, phygeomp->g_nsect,
	    phygeomp->g_secsize, phygeomp->g_capacity);
#endif
	return (err);
}

static int
hsimd_tg_getvirtgeom(dev_info_t *dip, cmlb_geom_t *virtgeomp)
{
#if 1
	/* not supported */
#ifdef notdef
	cmn_err(CE_CONT, "?hsimd%d: %s: called\n",
	    ddi_get_instance(dip), __func__);
#endif
	return (-1);
#else
	/* not impact */
	return (hsimd_tg_getphygeom(dip, virtgeomp));
#endif
}

static int
hsimd_tg_getcapacity(dev_info_t *dip, diskaddr_t *capp)
{
	int	unit_no;
	struct hsimd_unit	*hsimd_p;

	*capp = 0;

	unit_no = ddi_get_instance(dip);
	hsimd_p = getsoftc(unit_no);

	if ((hsimd_p->hsimd_size = hsimd_read_capacity(unit_no)) == 0ULL) {
		return (ENXIO);
	}

	*capp = hsimd_p->hsimd_size / DEV_BSIZE;

	return (0);
}

static int
hsimd_tg_getattribute(dev_info_t *dip, tg_attribute_t *tgattribute)
{
#if 0
	tgattribute->media_is_writable = B_TRUE;
#else
	int	unit_no;
	struct hsimd_unit	*hsimd_p;

	unit_no = ddi_get_instance(dip);
	hsimd_p = getsoftc(unit_no);

	tgattribute->media_is_writable =
	    !(hsimd_p->hsimd_cap & HSIMD_CAP_CDROM);
#ifdef TG_DK_OPS_VERSION_1
	tgattribute->media_is_solid_state = B_FALSE;
	tgattribute->media_is_rotational = B_TRUE;
#endif /* TG_DK_OPS_VERSION_1 */
#endif /* 0 */
	return (0);
}

#ifdef TG_DK_OPS_VERSION_1
static int
hsimd_tg_getinfo(dev_info_t *devi, int cmd, void *arg, void *tg_cookie)
{
	int	unit_no;
	struct hsimd_unit	*hsimd_p;
	int             ret = 0;

	unit_no = ddi_get_instance(devi);
	hsimd_p = getsoftc(unit_no);

	if (hsimd_p == NULL) {
		return (ENXIO);
	}

	switch (cmd) {
	case TG_GETPHYGEOM:
		ret = hsimd_tg_getphygeom(devi, (cmlb_geom_t *)arg);
		break;

	case TG_GETVIRTGEOM:
		ret = hsimd_tg_getvirtgeom(devi, (cmlb_geom_t *)arg);
		break;

	case TG_GETCAPACITY:
		ret = hsimd_tg_getcapacity(devi, (diskaddr_t *)arg);
		break;

	case TG_GETBLOCKSIZE:
		if ((hsimd_p->hsimd_cap & HSIMD_CAP_CDROM) == 0) {
			*(uint32_t *)arg = DEV_BSIZE;
		} else {
			*(uint32_t *)arg = 2048;
		}
		break;

	case TG_GETATTR:
#if 0
		((tg_attribute_t *)arg)->media_is_writable =
		    (hsimd_p->hsimd_cap & HSIMD_CAP_CDROM) == 0;
		((tg_attribute_t *)arg)->media_is_solid_state = B_FALSE;
		((tg_attribute_t *)arg)->media_is_rotational = B_TRUE;
		return (0);
#endif
		ret = hsimd_tg_getattribute(devi, (tg_attribute_t *)arg);
		break;

	default:
		return (ENOTTY);

	}
	return (ret);
}
#endif /* TG_DK_OPS_VERSION_1 */

int
hsimd_rwcmd_copyin(struct dadkio_rwcmd *rwcmdp, caddr_t inaddr, int flag)
{
	struct dadkio_rwcmd32 cmd32;

	if (ddi_copyin(inaddr, &cmd32, sizeof (struct dadkio_rwcmd32), flag)) {
		return (EFAULT);
	}

	if (ddi_model_convert_from(flag) == DDI_MODEL_ILP32) {
		rwcmdp->cmd = cmd32.cmd;
		rwcmdp->flags = cmd32.flags;
		rwcmdp->blkaddr = /* (blkaddr_t)*/cmd32.blkaddr;
		rwcmdp->buflen = cmd32.buflen;
		rwcmdp->bufaddr = (caddr_t)(intptr_t)cmd32.bufaddr;
	} else {
		if (ddi_copyin(inaddr, rwcmdp,
		    sizeof (struct dadkio_rwcmd), flag)) {
			return (EFAULT);
		}
	}

	bzero(&rwcmdp->status, sizeof (rwcmdp->status));
	return (0);
}

/*
 * scsi emulation support
 */
#include <sys/byteorder.h>
#include <sys/scsi/generic/commands.h>
#include <sys/scsi/impl/commands.h>

#ifndef DKIOCSEXTVTOC	/* u8 */
#define  DKIOCSEXTVTOC	(DKIOC|24)	/* Set extended VTOC, Write to Disk */
#endif
#ifndef DKIOCGEXTVTOC
#define DKIOCGEXTVTOC	(DKIOC|23)
#endif
#ifndef DKIOCGETEFI
#define DKIOCGETEFI	(DKIOC|18)
#endif
#ifndef DKIOCEXTPARTINFO
#define DKIOCEXTPARTINFO	(DKIOC|19)
#endif
#ifndef DKIOCFREE
#define DKIOCFREE	(DKIOC|50)
#endif
#ifndef DKIOC_CANFREE
#define DKIOC_CANFREE	(DKIOC|60)
#endif

static int
hsimd_phys_rdwr(dev_t dev, int rw, void *buf_addr,
    diskaddr_t start_block, size_t reqlength, int mode)
{
	struct iovec aiov;
	struct uio auio;
	int	status;
	int	unit_no;

	unit_no = HSIMD_UNIT(dev);

	bzero((caddr_t)&aiov, sizeof (struct iovec));
	aiov.iov_base   = buf_addr;
	aiov.iov_len    = reqlength;

	bzero((caddr_t)&auio, sizeof (struct uio));
	auio.uio_iov    = &aiov;
	auio.uio_iovcnt = 1;

	auio.uio_loffset = start_block * DEV_BSIZE;
	auio.uio_resid  = reqlength;
	auio.uio_segflg = (mode & FKIOCTL) ? UIO_SYSSPACE : UIO_USERSPACE;
#if 0
	cmn_err(CE_CONT,
	    "hsimd%d: %s: "
	    "rw:0x%x, buf_addr:0x%llx, reqlength:0x%x, "
	    "start_block:0x%llx mode:0x%x\n",
	    unit_no, __func__,
	    rw, buf_addr, reqlength, start_block, mode);
#endif
	status = physio(hsimd_strategy,
	    NULL, dev, rw | HSIMD_B_ABSOLUTE,  minphys, &auio);

	return (status);
}

static int
hsimd_uscsi_cmd(dev_t dev, caddr_t arg, int mode)
{
	struct uscsi_cmd	uscsi;
	struct uscsi_cmd32	uscsi32;
	union scsi_cdb		cdb;
	diskaddr_t		start_block;
	int			status;
	int			unit_no;

	unit_no = HSIMD_UNIT(dev);
#if 0
	cmn_err(CE_CONT, "hsimd%d: %s: called\n",
	    unit_no, __func__);
#endif
	if (ddi_model_convert_from(mode & FMODELS) == DDI_MODEL_ILP32) {
		if (ddi_copyin(arg, &uscsi32, sizeof (struct uscsi_cmd32),
		    mode)) {
			status = EFAULT;
			goto x;
		}
		uscsi_cmd32touscsi_cmd((&uscsi32), (&uscsi));
	} else {
		if (ddi_copyin(arg, &uscsi, sizeof (struct uscsi_cmd),
		    mode)) {
			status = EFAULT;
			goto x;
		}
	}

	if (ddi_copyin(uscsi.uscsi_cdb, &cdb, uscsi.uscsi_cdblen,
	    mode)) {
		status = EFAULT;
		goto x;
	}

	switch (CDB_GROUPID(cdb.scc_cmd)) {
	case 0:
		start_block = GETG0ADDR(&cdb);
		break;
	case 1:
		start_block = GETG1ADDR(&cdb);
		break;
	case 4:
		start_block = GETG4ADDR(&cdb);
		break;
	case 5:
		start_block = GETG5ADDR(&cdb);
		break;
	default:
		cmn_err(CE_CONT, "hsimd%d: %s: group:%d not supported\n",
		    unit_no, __func__, CDB_GROUPID(cdb.scc_cmd));
		status = EINVAL;
		goto x;
	}
#if 0
	cmn_err(CE_CONT, "hsimd%d: %s: scmd 0x%x\n",
	    unit_no, __func__, cdb.scc_cmd);
#endif
	switch (cdb.scc_cmd) {
	case SCMD_READ_G4:
	case SCMD_READ_G1:
	case SCMD_READ:
		status = hsimd_phys_rdwr(dev, B_READ, uscsi.uscsi_bufaddr,
		    start_block, uscsi.uscsi_buflen, mode);
		break;

	case SCMD_WRITE_G4:
	case SCMD_WRITE_G1:
	case SCMD_WRITE:
		status = hsimd_phys_rdwr(dev, B_WRITE, uscsi.uscsi_bufaddr,
		    start_block, uscsi.uscsi_buflen, mode);
		break;

	case SCMD_INQUIRY:
{
		struct scsi_inquiry *inq;
		inq = kmem_zalloc(sizeof (*inq), KM_SLEEP);
		inq->inq_dtype= DTYPE_DIRECT; /* or DTYPE_OPTICAL */
		inq->inq_len = sizeof (*inq) - 4;

		memcpy(inq->inq_vid,
		    "QEMU    ", sizeof (inq->inq_vid));
		memcpy(inq->inq_pid,
		    "VDISK           ", sizeof (inq->inq_pid));
		memcpy(inq->inq_revision,
		    "    ", sizeof (inq->inq_revision));

		status = ddi_copyout(inq, uscsi.uscsi_bufaddr,
		    min(uscsi.uscsi_buflen, sizeof (*inq)), mode);
		kmem_free(inq, sizeof (*inq));
		break;
}
	case SCMD_READ_CAPACITY:
{
		uint64_t	cap;
		struct scsi_capacity    cap8;
		cap = hsimd_read_capacity(unit_no)/DEV_BSIZE;
		if (cap > UINT32_MAX) {
			cap = UINT32_MAX;
		}
		cap8.capacity = (uint_t)cap;
		cap8.lbasize  = DEV_BSIZE;
		status = ddi_copyout(&cap8,
		    uscsi.uscsi_bufaddr, uscsi.uscsi_buflen, mode);

		break;
}
	case SCMD_SVC_ACTION_IN_G4:
		if (cdb.cdb_opaque[1] != SSVC_ACTION_READ_CAPACITY_G4) {
			/* not supporeted */
			status = ENOTSUP;
			break;
		}
{
		uint64_t	cap;
		struct scsi_capacity_16    cap16;
	
		cap = hsimd_read_capacity(unit_no)/DEV_BSIZE;
		cap16.sc_capacity = BE_64(cap);
		cap16.sc_lbasize = BE_32(DEV_BSIZE);

		status = ddi_copyout(&cap16,
		    uscsi.uscsi_bufaddr, uscsi.uscsi_buflen, mode);
		break;
}

	default:
		cmn_err(CE_CONT, "hsimd%d: %s: cmd:0x%x not supported\n",
		    unit_no, __func__, cdb.scc_cmd);
		status = EINVAL;
		break;
	}
	if (status) {
		goto x;
	}

	uscsi.uscsi_status = 0;
	uscsi.uscsi_rqstatus = 0;

	if (ddi_model_convert_from(mode & FMODELS) == DDI_MODEL_ILP32) {
		uscsi_cmdtouscsi_cmd32((&uscsi), (&uscsi32));
		if (ddi_copyout(&uscsi32, arg, sizeof (struct uscsi_cmd32),
		    mode)) {
			status = EFAULT;
			goto x;
		}
	} else {
		if (ddi_copyout(&uscsi, arg, sizeof (struct uscsi_cmd),
		    mode)) {
			status = EFAULT;
			goto x;
		}
	}
x:
	return (status);
}

/* ARGSUSED3 */
static int
hsimd_ioctl(dev_t dev, int cmd, intptr_t arg, int flag,
	cred_t *cred_p, int *rval_p)
{
	struct	hsimd_unit	*hsimd_p;
	struct dk_cinfo *info;
	struct vtoc	vtoc;
	uint_t		unit_no, slice_no;
	enum dkio_state dkstate;
	int		i;
	int		err = 0;

	unit_no = HSIMD_UNIT(dev);
	slice_no = HSIMD_SLICE(dev);
	hsimd_p = getsoftc(unit_no);
	if (hsimd_p == NULL) {
		cmn_err(CE_WARN, "hsimd%d: no softstate for this unit",
		    unit_no);
		return (ENXIO);
	}

	switch (cmd) {
	case DKIOCINFO:
		/*
		 * Controller Information
		 */
		info = (struct dk_cinfo *)
		    kmem_zalloc(sizeof (struct dk_cinfo), KM_SLEEP);
		if ((hsimd_p->hsimd_cap & HSIMD_CAP_CDROM) == 0) {
#if 0
			info->dki_ctype = DKC_DIRECT;	/* IDE disk */
#else
			info->dki_ctype = DKC_SCSI_CCS;	/* SCSI disk */
#endif
		} else {
			info->dki_ctype = DKC_CDROM;
		}
		info->dki_cnum =
		    ddi_get_instance(ddi_get_parent(hsimd_p->hsimd_dip));
		(void) strncpy(info->dki_cname,
		    ddi_get_name(ddi_get_parent(hsimd_p->hsimd_dip)),
		    DK_DEVLEN - 1);
		info->dki_cname[DK_DEVLEN - 1] = 0;

		/*
		 * Unit Information
		 */
		info->dki_unit = ddi_get_instance(hsimd_p->hsimd_dip);
		info->dki_slave = 0;
		(void) strcpy(info->dki_dname,
		    ddi_get_name(hsimd_p->hsimd_dip));

		info->dki_flags = DKI_FMTVOL;
		info->dki_partition = slice_no;

		/*
		 * Max Transfer size of this device in blocks
		 */
		info->dki_maxtransfer = (128*1024) / DEV_BSIZE;
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

#ifndef	DKIOCGMEDIAINFOEXT
#define	DKIOCGMEDIAINFOEXT      (DKIOC|48)
struct dk_minfo {
	uint_t          dki_media_type; /* Media type or profile info */
	uint_t          dki_lbsize;     /* Logical blocksize of media */
	diskaddr_t      dki_capacity;   /* Capacity as # of dki_lbsize blks */
};

struct dk_minfo_ext {
        uint_t          dki_media_type; /* Media type or profile info */
        uint_t          dki_lbsize;     /* Logical blocksize of media */
        diskaddr_t      dki_capacity;   /* Capacity as # of dki_lbsize blks */
        uint_t          dki_pbsize;     /* Physical blocksize of media */
};
#endif /* DKIOCGMEDIAINFOEXT */

	case DKIOCGMEDIAINFO:
	case DKIOCGMEDIAINFOEXT:
	{
		uint_t		dki_media_type;
		uint_t		dki_lbsize;
		diskaddr_t	dki_capacity;
		uint_t		dki_pbsize;

		if ((hsimd_p->hsimd_cap & HSIMD_CAP_CDROM) == 0) {
			dki_media_type = DK_FIXED_DISK;
			dki_lbsize = DEV_BSIZE;
			dki_capacity = hsimd_p->hsimd_size / dki_lbsize;
		} else {
			/* we shoud pretend as CDROM if read only */
			dki_media_type = DK_CDROM ;
			dki_lbsize = 2048;	/* right ? */
			dki_capacity = hsimd_p->hsimd_size / dki_lbsize;
			dki_pbsize = 2048;
		}

		if (cmd  == DKIOCGMEDIAINFO) {
			struct dk_minfo	mi;

			mi.dki_media_type = dki_media_type;
			mi.dki_lbsize = dki_lbsize;
			mi.dki_capacity = dki_capacity;

			if (ddi_copyout(&mi,
			    (void *)arg, sizeof (mi), flag)) {
				return (EFAULT);
			}
		} else {
			struct dk_minfo_ext	mie;

			mie.dki_media_type = dki_media_type;
			mie.dki_lbsize = dki_lbsize;
			mie.dki_capacity = dki_capacity;
			mie.dki_pbsize = dki_pbsize;

			if (ddi_copyout(&mie,
			    (void *)arg, sizeof (mie), flag)) {
				return (EFAULT);
			}
		}
		return (0);
	}
#if 0
	case DIOCTL_RWCMD:
{
		struct dadkio_rwcmd rwcmd;
		struct iovec aiov;
		struct uio auio;
		int	rw;
		int	rval;
		int	status = 0;
		struct buf *buf;
#if 0
		cmn_err(CE_CONT, "hsimd%d: %s: RWCMD: arg:0x%llx, flag:0x%x\n",
		    unit_no, __func__, arg, flag);
#endif
		if ((rval = hsimd_rwcmd_copyin(&rwcmd, (caddr_t)arg, flag))) {
			return (rval);
		}
#if 1
		cmn_err(CE_CONT, "hsimd%d: %s: rwcmd.cmd:%d\n",
		    unit_no, __func__, rwcmd.cmd);
#endif
		switch (rwcmd.cmd) {
		case DADKIO_RWCMD_READ:
			rw = B_READ;
			break;

		case DADKIO_RWCMD_WRITE:
			rw = B_WRITE;
			break;
		default:
			return (EINVAL);
		}

		status = hsimd_phys_rdwr(dev, rw, rwcmd.bufaddr,
		    rwcmd.blkaddr, rwcmd.buflen, flag);

		rwcmd.status.status = 0;

		if (ddi_model_convert_from(flag) == DDI_MODEL_ILP32) {
			struct dadkio_rwcmd32 cmd32;

			bzero(&cmd32, sizeof (cmd32));
			cmd32.cmd = rwcmd.cmd;
			cmd32.flags = rwcmd.flags;
			cmd32.blkaddr = rwcmd.blkaddr;
			cmd32.buflen = rwcmd.buflen;
			cmd32.bufaddr = (int)rwcmd.bufaddr;
			cmd32.status.status = rwcmd.status.status;
			if (ddi_copyout(&cmd32, (caddr_t)arg,
			    sizeof (cmd32), flag)) {
				return (EFAULT);
			}
		} else {
			if (ddi_copyout(&rwcmd, (caddr_t)arg,
			    sizeof (struct dadkio_rwcmd), flag)) {
				return (EFAULT);
			}
		}
		return (status);
}
#endif /* 0 */

	case DKIOCGGEOM:
	case DKIOCGVTOC:
	case DKIOCGEXTVTOC:
	case DKIOCGAPART:
	case DKIOCPARTINFO:
	case DKIOCEXTPARTINFO:
	case DKIOCSGEOM:
	case DKIOCSAPART:
	case DKIOCGETEFI:
	case DKIOCPARTITION:
	case DKIOCSVTOC:
	case DKIOCSEXTVTOC:
	case DKIOCSETEFI:
	case DKIOCGMBOOT:
	case DKIOCSMBOOT:
	case DKIOCG_PHYGEOM:
	case DKIOCG_VIRTGEOM:
#ifdef TG_DK_OPS_VERSION_1
		err = cmlb_ioctl(hsimd_p->hsimd_dklbhandle, dev,
		    cmd, arg, flag, cred_p, rval_p, 0);
#else
		err = cmlb_ioctl(hsimd_p->hsimd_dklbhandle, dev,
		    cmd, arg, flag, cred_p, rval_p);
#endif
		if ((err == 0) &&
		    (cmd == DKIOCSETEFI ||
		    cmd == DKIOCSGEOM ||
		    cmd == DKIOCSAPART || cmd == DKIOCSVTOC ||
		    cmd == DKIOCSEXTVTOC)) {
			int	ret;

			/* refill partition cache info */
#ifdef TG_DK_OPS_VERSION_1
			ret = cmlb_validate(hsimd_p->hsimd_dklbhandle, 0, 0);
#else
			ret = cmlb_validate(hsimd_p->hsimd_dklbhandle);
#endif
#ifdef CONFIG_LOCAL_PARTINFO
			if (ret == 0) {
				for (i = 0; i < NDKMAP; i++) {
					diskaddr_t nblocks;
					diskaddr_t sblock;
					char	*pname;
					uint16_t tag;

#ifdef TG_DK_OPS_VERSION_1
					if (cmlb_partinfo(
					    hsimd_p->hsimd_dklbhandle,
					    i, &nblocks, &sblock,
					    &pname, &tag, 0) != 0)
#else
					if (cmlb_partinfo(
					    hsimd_p->hsimd_dklbhandle,
					    i, &nblocks, &sblock,
					    &pname, &tag) != 0)
#endif
					{
						/* no valid partition */
						continue;
					}
					/* save valid partition range */
					hsimd_p->label[i].blockno = sblock;
					hsimd_p->label[i].nblocks = nblocks;
				}
				hsimd_p->hsimd_lvalid = B_TRUE;
			}
			else {
				/* invalidate partion cache */
				for (i = 0; i < NDKMAP; i++) {
					/* save valid partition range */
					hsimd_p->label[i].nblocks = 0;
				}
				hsimd_p->hsimd_lvalid = B_FALSE;
			}
#endif /* CONFIG_LOCAL_PARTINFO */
		}
		return (err);
#if 0
	case DKIOCLOCK:
		SD_TRACE(SD_LOG_IOCTL, un, "DKIOCLOCK\n");
		err = sd_send_scsi_DOORLOCK(ssc, SD_REMOVAL_PREVENT,
		    SD_PATH_STANDARD);
		goto done_with_assess;

	case DKIOCUNLOCK:
		SD_TRACE(SD_LOG_IOCTL, un, "DKIOCUNLOCK\n");
		err = sd_send_scsi_DOORLOCK(ssc, SD_REMOVAL_ALLOW,
		    SD_PATH_STANDARD);
		goto done_with_assess;
#endif

	case DKIOCSTATE:
		/* the file is always there */
		dkstate = DKIO_INSERTED;
		if (ddi_copyout(&dkstate, (void *)arg,
		    sizeof (enum dkio_state), flag)) {
			return (EFAULT);
		}
		return (0);

	case DKIOCREMOVABLE:
		i = 0;
		if (ddi_copyout(&i, (void *)arg, sizeof (i), flag)) {
			return (EFAULT);
		}
		return (0);
#if 0
	case DKIOCSOLIDSTATE:
		SD_TRACE(SD_LOG_IOCTL, un, "DKIOCSOLIDSTATE\n");
		i = un->un_f_is_solid_state ? 1 : 0;
		if (ddi_copyout(&i, (void *)arg, sizeof (int), flag) != 0) {
			err = EFAULT;
		} else {
			err = 0;
		}
		break;

	case DKIOCHOTPLUGGABLE:
		SD_TRACE(SD_LOG_IOCTL, un, "DKIOCHOTPLUGGABLE\n");
		i = un->un_f_is_hotpluggable ? 1 : 0;
		if (ddi_copyout(&i, (void *)arg, sizeof (int), flag) != 0) {
			err = EFAULT;
		} else {
			err = 0;
		}
		break;

	case DKIOCREADONLY:
		SD_TRACE(SD_LOG_IOCTL, un, "DKIOCREADONLY\n");
		i = 0;
		if ((ISCD(un) && !un->un_f_mmc_writable_media) ||
		    (sr_check_wp(dev) != 0)) {
			i = 1;
		}
		if (ddi_copyout(&i, (void *)arg, sizeof (int), flag) != 0) {
			err = EFAULT;
		} else {
			err = 0;
		}
		break;

	case DKIOCGTEMPERATURE:
		SD_TRACE(SD_LOG_IOCTL, un, "DKIOCGTEMPERATURE\n");
		err = sd_dkio_get_temp(dev, (caddr_t)arg, flag);
		break;
#endif
#if 0
	case MHIOCxxxx
	.....
#endif

	case USCSICMD:
		err = hsimd_uscsi_cmd(dev, (caddr_t)arg, flag);
		return (err);
#if 0
	case USCSIMAXXFER:
		SD_TRACE(SD_LOG_IOCTL, un, "USCSIMAXXFER\n");
		cr = ddi_get_cred();
		if ((drv_priv(cred_p) != 0) && (drv_priv(cr) != 0)) {
			err = EPERM;
		} else {
			const uscsi_xfer_t xfer = un->un_max_xfer_size;

			if (ddi_copyout(&xfer, (void *)arg, sizeof (xfer),
			    flag) != 0) {
				err = EFAULT;
			} else {
				err = 0;
			}
		}
		break;
#endif
#if 0
	case CDROMPAUSE:
	case CDROMRESUME:
		SD_TRACE(SD_LOG_IOCTL, un, "PAUSE-RESUME\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_pause_resume(dev, cmd);
		}
		break;

	case CDROMPLAYMSF:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMPLAYMSF\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_play_msf(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMPLAYTRKIND:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMPLAYTRKIND\n");
#if defined(__x86)
		/*
		 * not supported on ATAPI CD drives, use CDROMPLAYMSF instead
		 */
		if (!ISCD(un) || (un->un_f_cfg_is_atapi == TRUE)) {
#else
		if (!ISCD(un)) {
#endif
			err = ENOTTY;
		} else {
			err = sr_play_trkind(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMREADTOCHDR:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMREADTOCHDR\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_tochdr(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMREADTOCENTRY:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMREADTOCENTRY\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_tocentry(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMSTOP:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMSTOP\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sd_send_scsi_START_STOP_UNIT(ssc, SD_START_STOP,
			    SD_TARGET_STOP, SD_PATH_STANDARD);
			goto done_with_assess;
		}
		break;

	case CDROMSTART:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMSTART\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sd_send_scsi_START_STOP_UNIT(ssc, SD_START_STOP,
			    SD_TARGET_START, SD_PATH_STANDARD);
			goto done_with_assess;
		}
		break;

	case CDROMCLOSETRAY:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMCLOSETRAY\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sd_send_scsi_START_STOP_UNIT(ssc, SD_START_STOP,
			    SD_TARGET_CLOSE, SD_PATH_STANDARD);
			goto done_with_assess;
		}
		break;

	case FDEJECT:	/* for eject command */
	case DKIOCEJECT:
	case CDROMEJECT:
		SD_TRACE(SD_LOG_IOCTL, un, "EJECT\n");
		if (!un->un_f_eject_media_supported) {
			err = ENOTTY;
		} else {
			err = sr_eject(dev);
		}
		break;

	case CDROMVOLCTRL:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMVOLCTRL\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_volume_ctrl(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMSUBCHNL:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMSUBCHNL\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_subchannel(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMREADMODE2:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMREADMODE2\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else if (un->un_f_cfg_is_atapi == TRUE) {
			/*
			 * If the drive supports READ CD, use that instead of
			 * switching the LBA size via a MODE SELECT
			 * Block Descriptor
			 */
			err = sr_read_cd_mode2(dev, (caddr_t)arg, flag);
		} else {
			err = sr_read_mode2(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMREADMODE1:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMREADMODE1\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_mode1(dev, (caddr_t)arg, flag);
		}
		break;
#endif
	case CDROMREADOFFSET:
		return (ENOTTY);

#if 0
	case CDROMSBLKMODE:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMSBLKMODE\n");
		/*
		 * There is no means of changing block size in case of atapi
		 * drives, thus return ENOTTY if drive type is atapi
		 */
		if (!ISCD(un) || (un->un_f_cfg_is_atapi == TRUE)) {
			err = ENOTTY;
		} else if (un->un_f_mmc_cap == TRUE) {

			/*
			 * MMC Devices do not support changing the
			 * logical block size
			 *
			 * Note: EINVAL is being returned instead of ENOTTY to
			 * maintain consistancy with the original mmc
			 * driver update.
			 */
			err = EINVAL;
		} else {
			mutex_enter(SD_MUTEX(un));
			if ((!(un->un_exclopen & (1<<SDPART(dev)))) ||
			    (un->un_ncmds_in_transport > 0)) {
				mutex_exit(SD_MUTEX(un));
				err = EINVAL;
			} else {
				mutex_exit(SD_MUTEX(un));
				err = sr_change_blkmode(dev, cmd, arg, flag);
			}
		}
		break;

	case CDROMGBLKMODE:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMGBLKMODE\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else if ((un->un_f_cfg_is_atapi != FALSE) &&
		    (un->un_f_blockcount_is_valid != FALSE)) {
			/*
			 * Drive is an ATAPI drive so return target block
			 * size for ATAPI drives since we cannot change the
			 * blocksize on ATAPI drives. Used primarily to detect
			 * if an ATAPI cdrom is present.
			 */
			if (ddi_copyout(&un->un_tgt_blocksize, (void *)arg,
			    sizeof (int), flag) != 0) {
				err = EFAULT;
			} else {
				err = 0;
			}

		} else {
			/*
			 * Drive supports changing block sizes via a Mode
			 * Select.
			 */
			err = sr_change_blkmode(dev, cmd, arg, flag);
		}
		break;

	case CDROMGDRVSPEED:
	case CDROMSDRVSPEED:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMXDRVSPEED\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else if (un->un_f_mmc_cap == TRUE) {
			/*
			 * Note: In the future the driver implementation
			 * for getting and
			 * setting cd speed should entail:
			 * 1) If non-mmc try the Toshiba mode page
			 *    (sr_change_speed)
			 * 2) If mmc but no support for Real Time Streaming try
			 *    the SET CD SPEED (0xBB) command
			 *   (sr_atapi_change_speed)
			 * 3) If mmc and support for Real Time Streaming
			 *    try the GET PERFORMANCE and SET STREAMING
			 *    commands (not yet implemented, 4380808)
			 */
			/*
			 * As per recent MMC spec, CD-ROM speed is variable
			 * and changes with LBA. Since there is no such
			 * things as drive speed now, fail this ioctl.
			 *
			 * Note: EINVAL is returned for consistancy of original
			 * implementation which included support for getting
			 * the drive speed of mmc devices but not setting
			 * the drive speed. Thus EINVAL would be returned
			 * if a set request was made for an mmc device.
			 * We no longer support get or set speed for
			 * mmc but need to remain consistent with regard
			 * to the error code returned.
			 */
			err = EINVAL;
		} else if (un->un_f_cfg_is_atapi == TRUE) {
			err = sr_atapi_change_speed(dev, cmd, arg, flag);
		} else {
			err = sr_change_speed(dev, cmd, arg, flag);
		}
		break;

	case CDROMCDDA:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMCDDA\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_cdda(dev, (void *)arg, flag);
		}
		break;

	case CDROMCDXA:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMCDXA\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_cdxa(dev, (caddr_t)arg, flag);
		}
		break;

	case CDROMSUBCODE:
		SD_TRACE(SD_LOG_IOCTL, un, "CDROMSUBCODE\n");
		if (!ISCD(un)) {
			err = ENOTTY;
		} else {
			err = sr_read_all_subcodes(dev, (caddr_t)arg, flag);
		}
		break;


#endif
	case DKIOCFLUSHWRITECACHE:
		err = ENOTSUP;
		break;

	case DKIOCFREE:
		err = ENOTSUP;
                break;

	case DKIOC_CANFREE:
		i = 0;
		if (ddi_copyout(&i, (void *)arg, sizeof (int), flag) != 0) {
			err = EFAULT;
		} else {
			err = 0;
		}
		break;

	case DKIOCGETWCE: {
		int wce = 0;

		if (ddi_copyout(&wce, (void *)arg, sizeof (wce), flag)) {
			err = EFAULT;
		}
		break;
	}

        case DKIOCSETWCE:
		err = EINVAL;
		break;

	default:
		cmn_err(CE_WARN,
		    "hsimd%d: hsimd_ioctl: cmd 0x%x not implemented",
		    unit_no, cmd);
		return (ENOTTY);
	}
	return (err);
}

static int
hsimd_prop_op(dev_t dev, dev_info_t *dip, ddi_prop_op_t prop_op, int mod_flags,
    char *name, caddr_t valuep, int *lengthp)
{
	diskaddr_t		nblocks;
	diskaddr_t		sblock;
	int			length, km_flags;
	caddr_t			buffer;
	struct hsimd_unit	*hsimd_p;
	int			instance;

#if defined(TG_DK_OPS_VERSION_1)
	hsimd_p = getsoftc(ddi_get_instance(dip));
	if (hsimd_p == NULL) {
		return (ddi_prop_op(dev, dip, prop_op, mod_flags,
		    name, valuep, lengthp));
	}
	return (cmlb_prop_op(hsimd_p->hsimd_dklbhandle,
	    dev, dip, prop_op, mod_flags, name, valuep, lengthp,
	   HSIMD_SLICE(dev), (void *)0));
#else
	if (dev != DDI_DEV_T_ANY)
		instance = HSIMD_UNIT(dev);
	else
		instance = ddi_get_instance(dip);

	hsimd_p = getsoftc(instance);

#ifdef CONFIG_LOCAL_PARTINFO
	if (!hsimd_p->hsimd_lvalid) {
		cmn_err(CE_CONT, "hsimd%d: hsimd_prop_op: invalid label\n",
		    instance);
		return (DDI_PROP_NOT_FOUND);
	}
#endif /* CONFIG_LOCAL_PARTINFO */
	if (strcmp(name, "nblocks") == 0) {
#ifdef CONFIG_LOCAL_PARTINFO
		mutex_enter(&HSIMD_MUTEX(hsimd_p));
		nblocks = (int)hsimd_p->label[HSIMD_SLICE(dev)].nblocks;
		mutex_exit(&HSIMD_MUTEX(hsimd_p));
#else
		(void)cmlb_partinfo( hsimd_p->hsimd_dklbhandle,
		    HSIMD_SLICE(dev), &nblocks, &sblock, NULL, NULL);
#endif /* CONFIG_LOCAL_PARTINFO */

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
		*((int *)buffer) = (int)nblocks;
		return (DDI_PROP_SUCCESS);
	}

	/*
	 * not mine pass it on.
	 */
	return (ddi_prop_op(dev, dip, prop_op, mod_flags,
		name, valuep, lengthp));
#endif
}
