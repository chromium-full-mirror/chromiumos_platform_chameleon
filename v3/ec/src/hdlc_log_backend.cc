/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/logging/log.h>
#include <zephyr/logging/log_backend.h>
#include <zephyr/logging/log_backend_std.h>

#include "pw_hdlc/rpc_channel.h"
#include "pw_stream/sys_io_stream.h"

#include "hdlc.h"

static constexpr size_t kStdoutAddress = 1;
static constexpr size_t kOutputBufferSize = 8192;

static uint8_t hdlc_output_buf[kOutputBufferSize];

static int hdlc_char_out(uint8_t *data, size_t length, void *ctx)
{
	if (k_mutex_lock(&hdlc_uart_mutex, K_FOREVER) != 0) {
		printk("Can't lock HDLC UART mutex\n");
		return 0;
	}

	pw::ConstByteSpan payload((std::byte*)data, length);
	pw::hdlc::WriteUIFrame(kStdoutAddress, payload, hdlc_writer);

	k_mutex_unlock(&hdlc_uart_mutex);
	return length;
}

LOG_OUTPUT_DEFINE(log_output_hdlc,
		  hdlc_char_out,
		  hdlc_output_buf,
		  sizeof(hdlc_output_buf));

static void hdlc_log_process(const struct log_backend *const backend,
			     union log_msg_generic *msg)
{
	uint32_t flags = log_backend_std_get_flags();

	log_format_func_t log_output_func = log_format_func_t_get(0);
	log_output_func(&log_output_hdlc, &msg->log, flags);
}

static const struct log_backend_api hdlc_log_api = {
	.process = hdlc_log_process,
};

LOG_BACKEND_DEFINE(HDLC_LOG, hdlc_log_api, 1);
