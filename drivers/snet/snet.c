/*
 * Experimental GLDv3 driver for the OpenSPARC T1 SNET FIFO.
 *
 * Copyright 2026 Ryan Nelson
 * SPDX-License-Identifier: GPL-2.0-only
 */

#include <sys/types.h>
#include <sys/conf.h>
#include <sys/ddi.h>
#include <sys/sunddi.h>
#include <sys/modctl.h>
#include <sys/stream.h>
#include <sys/strsun.h>
#include <sys/ethernet.h>
#include <sys/mac_provider.h>
#include <sys/mac_ether.h>
#include <sys/vlan.h>
#include <sys/sysmacros.h>
#include <sys/machparam.h>
#include <sys/kmem.h>

#define SNET_MAGIC          0x534eU
#define SNET_VERSION        1U
#define SNET_FRAME_MIN      14U
#define SNET_FRAME_MAX      1518U
#define SNET_WORD_BYTES     8U
#define SNET_POLL_USEC      1000U
#define SNET_HEADER(len)    (((uint64_t)SNET_MAGIC << 48) | \
                             ((uint64_t)SNET_VERSION << 32) | (len))
#define SNET_ROUNDUP(n)     (((n) + 7U) & ~7U)

typedef struct snet {
	dev_info_t *dip;
	mac_handle_t mh;
	kmutex_t lock;
	boolean_t started;
	timeout_id_t poll_id;
	uint8_t *page_alloc;
	uint8_t *buf;
	uint8_t addr[ETHERADDRL];
	uint64_t ipackets;
	uint64_t opackets;
	uint64_t rbytes;
	uint64_t obytes;
	uint64_t ierrors;
	uint64_t oerrors;
	uint64_t read_hv_errors;
	uint64_t write_hv_errors;
} snet_t;

static void *snet_state;

extern size_t hv_snet_read(uint64_t, size_t);
extern size_t hv_snet_write(uint64_t, size_t);
extern uint64_t va_to_pa(void *);

/* Keep a C call boundary: SPARC FBT cannot probe the leaf trap stubs. */
static __attribute__((noinline, noclone)) size_t
snet_hcall(snet_t *sp, boolean_t write, size_t count)
{
	uint64_t pa = va_to_pa(sp->buf);
	size_t result = write ? hv_snet_write(pa, count) : hv_snet_read(pa, count);

	/* All callers hold sp->lock. Count errors without flooding the console. */
	if (result != count) {
		if (write)
			sp->write_hv_errors++;
		else
			sp->read_hv_errors++;
	}
	return (result);
}

static int snet_attach(dev_info_t *, ddi_attach_cmd_t);
static int snet_detach(dev_info_t *, ddi_detach_cmd_t);
static int snet_quiesce(dev_info_t *);
static int snet_m_stat(void *, uint_t, uint64_t *);
static int snet_m_start(void *);
static void snet_m_stop(void *);
static int snet_m_promisc(void *, boolean_t);
static int snet_m_multicst(void *, boolean_t, const uint8_t *);
static int snet_m_unicst(void *, const uint8_t *);
static mblk_t *snet_m_tx(void *, mblk_t *);
static void snet_poll(void *);

static mac_callbacks_t snet_callbacks = {
	0,
	snet_m_stat,
	snet_m_start,
	snet_m_stop,
	snet_m_promisc,
	snet_m_multicst,
	snet_m_unicst,
	snet_m_tx,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL
};

DDI_DEFINE_STREAM_OPS(snet_devops, nulldev, nulldev, snet_attach,
    snet_detach, nodev, NULL, D_MP, NULL, snet_quiesce);

static struct modldrv snet_modldrv = {
	&mod_driverops,
	"OpenSPARC SNET Ethernet",
	&snet_devops
};

static struct modlinkage snet_modlinkage = {
	MODREV_1,
	{ &snet_modldrv, NULL }
};

int
_init(void)
{
	int error;
	mac_init_ops(&snet_devops, "snet");
	if ((error = ddi_soft_state_init(&snet_state, sizeof (snet_t), 1)) != 0) {
		mac_fini_ops(&snet_devops);
		return (error);
	}
	if ((error = mod_install(&snet_modlinkage)) != 0) {
		ddi_soft_state_fini(&snet_state);
		mac_fini_ops(&snet_devops);
	}
	return (error);
}

int
_fini(void)
{
	int error;
	if ((error = mod_remove(&snet_modlinkage)) != 0)
		return (error);
	ddi_soft_state_fini(&snet_state);
	mac_fini_ops(&snet_devops);
	return (0);
}

int
_info(struct modinfo *mip)
{
	return (mod_info(&snet_modlinkage, mip));
}

static int
snet_attach(dev_info_t *dip, ddi_attach_cmd_t cmd)
{
	mac_register_t *macp;
	snet_t *sp;
	int instance = ddi_get_instance(dip);
	uintptr_t aligned;

	if (cmd != DDI_ATTACH ||
	    ddi_soft_state_zalloc(snet_state, instance) != DDI_SUCCESS)
		return (DDI_FAILURE);
	sp = ddi_get_soft_state(snet_state, instance);
	sp->dip = dip;
	mutex_init(&sp->lock, NULL, MUTEX_DRIVER, NULL);

	/* One physically contiguous page contains every SNET transfer. */
	sp->page_alloc = kmem_zalloc(PAGESIZE * 2, KM_SLEEP);
	aligned = P2ROUNDUP((uintptr_t)sp->page_alloc, PAGESIZE);
	sp->buf = (uint8_t *)aligned;

	sp->addr[0] = 0x02;
	sp->addr[1] = 0x53;
	sp->addr[2] = 0x4e;
	sp->addr[3] = 0x45;
	sp->addr[4] = 0x54;
	sp->addr[5] = instance & 0xff;

	if ((macp = mac_alloc(MAC_VERSION)) == NULL)
		goto fail;
	macp->m_type_ident = MAC_PLUGIN_IDENT_ETHER;
	macp->m_driver = sp;
	macp->m_dip = dip;
	macp->m_src_addr = sp->addr;
	macp->m_callbacks = &snet_callbacks;
	macp->m_min_sdu = 0;
	macp->m_max_sdu = ETHERMTU;
	macp->m_margin = VLAN_TAGSZ;
	if (mac_register(macp, &sp->mh) != 0) {
		mac_free(macp);
		goto fail;
	}
	mac_free(macp);
	ddi_report_dev(dip);
	return (DDI_SUCCESS);

fail:
	if (sp->page_alloc != NULL)
		kmem_free(sp->page_alloc, PAGESIZE * 2);
	mutex_destroy(&sp->lock);
	ddi_soft_state_free(snet_state, instance);
	return (DDI_FAILURE);
}

static int
snet_detach(dev_info_t *dip, ddi_detach_cmd_t cmd)
{
	snet_t *sp = ddi_get_soft_state(snet_state, ddi_get_instance(dip));
	if (cmd != DDI_DETACH || sp == NULL)
		return (DDI_FAILURE);
	if (mac_unregister(sp->mh) != 0)
		return (DDI_FAILURE);
	kmem_free(sp->page_alloc, PAGESIZE * 2);
	mutex_destroy(&sp->lock);
	ddi_soft_state_free(snet_state, ddi_get_instance(dip));
	return (DDI_SUCCESS);
}

static int
snet_quiesce(dev_info_t *dip)
{
	snet_t *sp = ddi_get_soft_state(snet_state, ddi_get_instance(dip));
	if (sp != NULL)
		sp->started = B_FALSE;
	return (DDI_SUCCESS);
}

static int
snet_m_start(void *arg)
{
	snet_t *sp = arg;
	mutex_enter(&sp->lock);
	if (!sp->started) {
		sp->started = B_TRUE;
		sp->poll_id = timeout(snet_poll, sp, drv_usectohz(SNET_POLL_USEC));
	}
	mutex_exit(&sp->lock);
	mac_link_update(sp->mh, LINK_STATE_UP);
	return (0);
}

static void
snet_m_stop(void *arg)
{
	snet_t *sp = arg;
	timeout_id_t id;
	mutex_enter(&sp->lock);
	sp->started = B_FALSE;
	id = sp->poll_id;
	sp->poll_id = 0;
	mutex_exit(&sp->lock);
	if (id != 0)
		(void) untimeout(id);
	if (sp->mh != NULL)
		mac_link_update(sp->mh, LINK_STATE_DOWN);
}

static void
snet_poll(void *arg)
{
	snet_t *sp = arg;
	uint64_t *header = (uint64_t *)sp->buf;
	uint32_t len;
	size_t padded;
	mblk_t *mp = NULL;

	mutex_enter(&sp->lock);
	if (!sp->started)
		goto out;
	*header = 0;
	if (snet_hcall(sp, B_FALSE, SNET_WORD_BYTES) != SNET_WORD_BYTES)
		goto reschedule;
	if (*header == 0)
		goto reschedule;
	len = *header & 0xffffffffU;
	if ((*header >> 48) != SNET_MAGIC ||
	    ((*header >> 32) & 0xffffU) != SNET_VERSION ||
	    len < SNET_FRAME_MIN || len > SNET_FRAME_MAX) {
		sp->ierrors++;
		goto reschedule;
	}
	padded = SNET_ROUNDUP(len);
	if (snet_hcall(sp, B_FALSE, padded) != padded) {
		sp->ierrors++;
		goto reschedule;
	}
	if ((mp = allocb(len, BPRI_MED)) == NULL) {
		sp->ierrors++;
		goto reschedule;
	}
	bcopy(sp->buf, mp->b_wptr, len);
	mp->b_wptr += len;
	sp->ipackets++;
	sp->rbytes += len;

reschedule:
out:
	mutex_exit(&sp->lock);
	if (mp != NULL)
		mac_rx(sp->mh, NULL, mp);
	/* Keep this callback's ID until its last MAC call has returned. */
	mutex_enter(&sp->lock);
	sp->poll_id = 0;
	if (sp->started)
		sp->poll_id = timeout(snet_poll, sp, drv_usectohz(SNET_POLL_USEC));
	mutex_exit(&sp->lock);
}

static mblk_t *
snet_m_tx(void *arg, mblk_t *chain)
{
	snet_t *sp = arg;
	mblk_t *mp, *next, *bp;
	size_t len, padded, copied;
	uint64_t *header = (uint64_t *)sp->buf;

	for (mp = chain; mp != NULL; mp = next) {
		next = mp->b_next;
		mp->b_next = NULL;
		len = msgdsize(mp);
		if (len < SNET_FRAME_MIN || len > SNET_FRAME_MAX) {
			mutex_enter(&sp->lock);
			sp->oerrors++;
			mutex_exit(&sp->lock);
			freemsg(mp);
			continue;
		}
		mutex_enter(&sp->lock);
		*header = SNET_HEADER(len);
		copied = 0;
		for (bp = mp; bp != NULL; bp = bp->b_cont) {
			bcopy(bp->b_rptr, sp->buf + SNET_WORD_BYTES + copied,
			    MBLKL(bp));
			copied += MBLKL(bp);
		}
		padded = SNET_ROUNDUP(len);
		bzero(sp->buf + SNET_WORD_BYTES + len, padded - len);
		/* q.bin validates the whole transfer before writing any FIFO word. */
		if (snet_hcall(sp, B_TRUE, SNET_WORD_BYTES + padded) !=
		    SNET_WORD_BYTES + padded) {
			sp->oerrors++;
			mutex_exit(&sp->lock);
			/* A hypercall error is a drop, not recoverable MAC backpressure. */
			freemsg(mp);
			continue;
		}
		sp->opackets++;
		sp->obytes += len;
		mutex_exit(&sp->lock);
		freemsg(mp);
	}
	return (NULL);
}

static int
snet_m_stat(void *arg, uint_t stat, uint64_t *value)
{
	snet_t *sp = arg;
	switch (stat) {
	case MAC_STAT_IPACKETS: *value = sp->ipackets; break;
	case MAC_STAT_OPACKETS: *value = sp->opackets; break;
	case MAC_STAT_RBYTES: *value = sp->rbytes; break;
	case MAC_STAT_OBYTES: *value = sp->obytes; break;
	case MAC_STAT_IERRORS: *value = sp->ierrors; break;
	case MAC_STAT_OERRORS: *value = sp->oerrors; break;
	case ETHER_STAT_LINK_DUPLEX: *value = LINK_DUPLEX_FULL; break;
	case MAC_STAT_IFSPEED: *value = 1000000000ULL; break;
	default: return (ENOTSUP);
	}
	return (0);
}

static int snet_m_promisc(void *arg, boolean_t on) { return (0); }
static int snet_m_multicst(void *arg, boolean_t add, const uint8_t *addr) { return (0); }
static int
snet_m_unicst(void *arg, const uint8_t *addr)
{
	snet_t *sp = arg;
	bcopy(addr, sp->addr, ETHERADDRL);
	return (0);
}
