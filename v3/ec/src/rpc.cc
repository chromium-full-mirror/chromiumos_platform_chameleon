/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <zephyr.h>
#include "pw_hdlc/rpc_channel.h"
#include "pw_hdlc/rpc_packets.h"
#include "pw_log/log.h"
#include "pw_rpc/server.h"
#include "pw_status/status.h"
#include "pw_stream/sys_io_stream.h"

#include "rpc.h"
#include "board_service.h"
#include "videomux_service.h"
#include "it68051_service.h"

pw::stream::SysIoWriter writer;

constexpr size_t kMaxTransmissionUnit = 2560;

/* Declare a buffer for decoding incoming HDLC frames. */
std::array<std::byte, kMaxTransmissionUnit> input_buffer;

pw::hdlc::RpcChannelOutput hdlc_channel_output(writer, input_buffer,
					       pw::hdlc::kDefaultRpcAddress,
					       "HDLC output");

pw::rpc::Channel channels[] = { pw::rpc::Channel::Create<1>(
	&hdlc_channel_output) };

/* Declare the pw_rpc server with the HDLC channel. */
pw::rpc::Server server(channels);

board_service board_service_inst;
videomux_service videomux_service_inst;
it68051_service it68051_service_inst;

void rpc_start(void)
{
	/* Register the RPC services. */
	server.RegisterService(board_service_inst);
	server.RegisterService(videomux_service_inst);
	server.RegisterService(it68051_service_inst);

	PW_LOG_INFO("Starting pw_rpc server");
	pw::hdlc::ReadAndProcessPackets(server, hdlc_channel_output,
					input_buffer);
}
