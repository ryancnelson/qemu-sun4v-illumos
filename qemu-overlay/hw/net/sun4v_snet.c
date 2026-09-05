/*
 * OpenSPARC T1 SNET FIFO network frontend.
 *
 * Copyright 2026 Ryan Nelson
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "qemu/osdep.h"
#include "hw/net/sun4v_snet.h"
#include "hw/qdev-properties.h"
#include "hw/sysbus.h"
#include "net/net.h"
#include "qemu/log.h"
#include "qemu/module.h"
#include "qom/object.h"

#define SNET_MAGIC          0x534eU
#define SNET_VERSION        1U
#define SNET_FRAME_MIN      14U
#define SNET_FRAME_MAX      1518U
#define SNET_WORD_BYTES     8U
#define SNET_HEADER(len)    (((uint64_t)SNET_MAGIC << 48) | \
                             ((uint64_t)SNET_VERSION << 32) | (len))

typedef struct Sun4vSnetState Sun4vSnetState;
DECLARE_INSTANCE_CHECKER(Sun4vSnetState, SUN4V_SNET, TYPE_SUN4V_SNET)

struct Sun4vSnetState {
    SysBusDevice parent_obj;
    MemoryRegion mmio;
    NICState *nic;
    NICConf conf;

    uint8_t tx[SNET_FRAME_MAX + SNET_WORD_BYTES];
    uint32_t tx_len;
    uint32_t tx_have;

    uint8_t rx[SNET_FRAME_MAX + SNET_WORD_BYTES];
    uint32_t rx_len;
    uint32_t rx_pos;
    bool rx_header;

    uint64_t tx_packets;
    uint64_t rx_packets;
    uint64_t malformed;
    uint64_t dropped;
};

static bool snet_valid_length(uint32_t len)
{
    return len >= SNET_FRAME_MIN && len <= SNET_FRAME_MAX;
}

static int snet_can_receive(NetClientState *nc)
{
    Sun4vSnetState *s = qemu_get_nic_opaque(nc);
    return s->rx_len == 0;
}

static ssize_t snet_receive(NetClientState *nc, const uint8_t *buf,
                            size_t size)
{
    Sun4vSnetState *s = qemu_get_nic_opaque(nc);

    if (!snet_valid_length(size) || !snet_can_receive(nc)) {
        s->dropped++;
        return 0;
    }
    memcpy(s->rx, buf, size);
    memset(s->rx + size, 0, ROUND_UP(size, SNET_WORD_BYTES) - size);
    s->rx_len = size;
    s->rx_pos = 0;
    s->rx_header = true;
    s->rx_packets++;
    return size;
}

static uint64_t snet_read(void *opaque, hwaddr addr, unsigned size)
{
    Sun4vSnetState *s = opaque;
    uint64_t word;

    if (size != SNET_WORD_BYTES || addr != 0 || s->rx_len == 0) {
        return 0;
    }
    if (s->rx_header) {
        s->rx_header = false;
        return SNET_HEADER(s->rx_len);
    }

    word = ldq_be_p(s->rx + s->rx_pos);
    s->rx_pos += SNET_WORD_BYTES;
    if (s->rx_pos >= ROUND_UP(s->rx_len, SNET_WORD_BYTES)) {
        s->rx_len = 0;
        s->rx_pos = 0;
        qemu_flush_queued_packets(qemu_get_queue(s->nic));
    }
    return word;
}

static void snet_write(void *opaque, hwaddr addr, uint64_t value,
                       unsigned size)
{
    Sun4vSnetState *s = opaque;
    uint32_t len;

    if (size != SNET_WORD_BYTES || addr != 0) {
        s->malformed++;
        return;
    }
    if (s->tx_len == 0) {
        len = value & 0xffffffffU;
        if ((value >> 48) != SNET_MAGIC ||
            ((value >> 32) & 0xffffU) != SNET_VERSION ||
            !snet_valid_length(len)) {
            if (value != 0) {
                s->malformed++;
            }
            return;
        }
        s->tx_len = len;
        s->tx_have = 0;
        return;
    }

    stq_be_p(s->tx + s->tx_have, value);
    s->tx_have += SNET_WORD_BYTES;
    if (s->tx_have >= ROUND_UP(s->tx_len, SNET_WORD_BYTES)) {
        qemu_send_packet(qemu_get_queue(s->nic), s->tx, s->tx_len);
        s->tx_packets++;
        s->tx_len = 0;
        s->tx_have = 0;
    }
}

static const MemoryRegionOps snet_ops = {
    .read = snet_read,
    .write = snet_write,
    .endianness = DEVICE_BIG_ENDIAN,
    .valid.min_access_size = SNET_WORD_BYTES,
    .valid.max_access_size = SNET_WORD_BYTES,
    .impl.min_access_size = SNET_WORD_BYTES,
    .impl.max_access_size = SNET_WORD_BYTES,
};

static NetClientInfo snet_net_info = {
    .type = NET_CLIENT_DRIVER_NIC,
    .size = sizeof(NICState),
    .can_receive = snet_can_receive,
    .receive = snet_receive,
};

static void snet_reset(DeviceState *dev)
{
    Sun4vSnetState *s = SUN4V_SNET(dev);
    s->tx_len = s->tx_have = 0;
    s->rx_len = s->rx_pos = 0;
    s->rx_header = false;
}

static void snet_realize(DeviceState *dev, Error **errp)
{
    Sun4vSnetState *s = SUN4V_SNET(dev);
    SysBusDevice *sbd = SYS_BUS_DEVICE(dev);

    memory_region_init_io(&s->mmio, OBJECT(dev), &snet_ops, s,
                          TYPE_SUN4V_SNET, SNET_WORD_BYTES);
    sysbus_init_mmio(sbd, &s->mmio);
    s->nic = qemu_new_nic(&snet_net_info, &s->conf,
                          object_get_typename(OBJECT(dev)), dev->id,
                          &dev->mem_reentrancy_guard, s);
    qemu_format_nic_info_str(qemu_get_queue(s->nic), s->conf.macaddr.a);
}

static Property snet_properties[] = {
    DEFINE_NIC_PROPERTIES(Sun4vSnetState, conf),
    DEFINE_PROP_END_OF_LIST(),
};

static void snet_class_init(ObjectClass *klass, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    dc->realize = snet_realize;
    dc->reset = snet_reset;
    dc->desc = "OpenSPARC T1 SNET FIFO Ethernet";
    set_bit(DEVICE_CATEGORY_NETWORK, dc->categories);
    device_class_set_props(dc, snet_properties);
}

static const TypeInfo snet_type_info = {
    .name = TYPE_SUN4V_SNET,
    .parent = TYPE_SYS_BUS_DEVICE,
    .instance_size = sizeof(Sun4vSnetState),
    .class_init = snet_class_init,
};

static void snet_register_types(void)
{
    type_register_static(&snet_type_info);
}
type_init(snet_register_types)

void sun4v_snet_init(NICInfo *nd, hwaddr base)
{
    DeviceState *dev = qdev_new(TYPE_SUN4V_SNET);
    SysBusDevice *sbd = SYS_BUS_DEVICE(dev);

    qdev_set_nic_properties(dev, nd);
    sysbus_realize_and_unref(sbd, &error_fatal);
    sysbus_mmio_map(sbd, 0, base);
}

