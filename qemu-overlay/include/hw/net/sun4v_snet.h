/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef HW_NET_SUN4V_SNET_H
#define HW_NET_SUN4V_SNET_H

#include "net/net.h"
#include "exec/hwaddr.h"

#define TYPE_SUN4V_SNET "sun4v-snet"

void sun4v_snet_init(NICInfo *nd, hwaddr base);

#endif

