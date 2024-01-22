/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#ifndef __HDLC_H
#define __HDLC_H

#include <zephyr/kernel.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/logging/log.h>

#include "pw_hdlc/rpc_channel.h"
#include "pw_rpc/server.h"
#include "pw_status/status.h"
#include "pw_stream/sys_io_stream.h"

extern pw::stream::SysIoWriter hdlc_writer;
extern k_mutex hdlc_uart_mutex;

#endif /* __HDLC_H */
