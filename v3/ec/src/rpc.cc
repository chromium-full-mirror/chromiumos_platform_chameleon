/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr/kernel.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/logging/log.h>

#include "pw_hdlc/rpc_channel.h"
#include "pw_hdlc/rpc_packets.h"
#include "pw_rpc/server.h"
#include "pw_status/status.h"
#include "pw_stream/sys_io_stream.h"

#include "board_service.h"
#include "videomux_service.h"
#include "it68051_service.h"

#include "hdlc.h"

LOG_MODULE_REGISTER(rpc);

/**
 * Define priority for the RPC task
 */
#define RPC_PRIORITY 10

/**
 * Define the size of the stack for the RPC task.
 */
#define RPC_STACK_SIZE 4096

/**
 * Zephyr macro to allocate the stack area.
 */
K_THREAD_STACK_DEFINE(rpc_stack_area, RPC_STACK_SIZE);

/**
 * Internal data structure for tracking the RPC task.
 */
static struct k_thread rpc_thread_data;

constexpr size_t kMaxTransmissionUnit = 2560;

/* Declare a buffer for decoding incoming HDLC frames. */
std::array<std::byte, kMaxTransmissionUnit> input_buffer;

pw::hdlc::RpcChannelOutput hdlc_channel_output(hdlc_writer,
					       pw::hdlc::kDefaultRpcAddress,
					       "HDLC output");

pw::rpc::Channel channels[] = { pw::rpc::Channel::Create<1>(
	&hdlc_channel_output) };

/* Declare the pw_rpc server with the HDLC channel. */
pw::rpc::Server server(channels);

board_service board_service_inst;
videomux_service videomux_service_inst;
it68051_service it68051_service_inst;

/**
 * @brief Run the FPGA power/boot state machine
 *
 * This task controls the FPGA power/boot sequence. The task listens on a
 * message queue for events: requests from callers and messages from
 * interrupt handlers for GPIO inputs. When it gets an event from the queue,
 * it passes that to the state machine, and then takes the output `actions`
 * and does the things that the bitfields indicate should be done.

 * @param unused1 Required by the Zephyr thread API. Unused.
 * @param unused2 Required by the Zephyr thread API. Unused.
 * @param unused3 Required by the Zephyr thread API. Unused.
 */
static void rpc_task(void *unused1, void *unused2, void *unused3)
{
	ARG_UNUSED(unused1);
	ARG_UNUSED(unused2);
	ARG_UNUSED(unused3);

	k_thread_name_set(NULL, "rpc_task");

	/* Register the RPC services. */
	server.RegisterService(board_service_inst);
	server.RegisterService(videomux_service_inst);
	server.RegisterService(it68051_service_inst);

	pw::hdlc::Decoder decoder(input_buffer);
	LOG_INF("Starting pw_rpc server");
	for (;;) {
		std::byte data;
		pw::Status status = pw::sys_io::ReadByte(&data);

		if (!status.ok()) {
			if (!status.IsUnavailable()) {
				LOG_ERR("Error getting UART byte");
			}

			continue;
		}

		if (auto result = decoder.Process(data); result.ok()) {
			pw::hdlc::Frame& frame = result.value();
			if (frame.address() == pw::hdlc::kDefaultRpcAddress) {
				k_mutex_lock(&hdlc_uart_mutex, K_FOREVER);
				server.ProcessPacket(frame.data()).IgnoreError();
				k_mutex_unlock(&hdlc_uart_mutex);
			}
		}
	}
}

/**
 * @brief Start the RPC task
 *
 * @retval 0
 * No error
 */
static int rpc_init(void)
{
	/* Create the RPC task and start it. */
	k_thread_create(&rpc_thread_data, rpc_stack_area,
			K_THREAD_STACK_SIZEOF(rpc_stack_area), rpc_task, NULL,
			NULL, NULL, RPC_PRIORITY, 0, K_NO_WAIT);

	return 0;
}
SYS_INIT(rpc_init, APPLICATION, 95);
