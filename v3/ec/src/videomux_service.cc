/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#include <sys/__assert.h>
#include "videomux_service.h"
#include "videomux.h"

/**
 * @brief Convert  a video_dest_t to a videomux_dest enum
 *
 * The RPC calls have a different enum than the videomux C API. Convert
 * between enums.
 *
 * @param dest The enum from the videomux C API
 * @return enum suitable for returning to the RPC call
 */
static enum _videomux_get_response_videomux_dest
video_dest_t_to_videomux_dest(video_dest_t dest)
{
	if (dest == FPGA_MGT) {
		return videomux_get_response_videomux_dest_FPGA;
	} else if (dest == HDMI_RECEIVER) {
		return videomux_get_response_videomux_dest_RX;
	}
	return videomux_get_response_videomux_dest_DISCONNECTED;
}

/**
 * @brief Convert the videomux_dest enum to a video_dest_t
 *
 * The RPC calls have a different enum than the videomux C API. Convert
 * between enums.
 * Note that NO_CHANGE is invalid as the videomux C API doesn't have
 * that option. This function shouldn't be called for NO_CHANGE.
 *
 * @param dest The enum from the RPC call
 * @return enum suitable for calling the videomux C API
 */
static video_dest_t
videomux_dest_to_video_dest_t(enum _videomux_set_request_videomux_dest dest)
{
	__ASSERT(dest != videomux_set_request_videomux_dest_NO_CHANGE,
		 "NO_CHANGE not allowed");

	if (dest == videomux_set_request_videomux_dest_FPGA) {
		return FPGA_MGT;
	}
	return HDMI_RECEIVER;
}

// Method definitions for videomux_service.
::pw::Status videomux_service::get(const ::Empty &request,
				   ::videomux_get_response &response)
{
	static_cast<void>(request);
	response.hdmi1 = video_dest_t_to_videomux_dest(videomux_get(HDMI1));
	response.hdmi2 = video_dest_t_to_videomux_dest(videomux_get(HDMI2));
	response.dp1 = video_dest_t_to_videomux_dest(videomux_get(DP1));
	response.dp2 = video_dest_t_to_videomux_dest(videomux_get(DP2));
	return ::pw::OkStatus();
}

::pw::Status videomux_service::set(const ::videomux_set_request &request,
				   ::videomux_service_set_response &response)
{
	/*
	 * Check if the assignment is valid; We can't route both HDMI and
	 * DisplayPort to the same destination.
	 */
	response.result = 1;
	if ((request.hdmi1 == request.dp1) &&
	    (request.hdmi1 != videomux_set_request_videomux_dest_NO_CHANGE)) {
		response.result = 0;
	}
	if ((request.hdmi2 == request.dp2) &&
	    (request.hdmi2 != videomux_set_request_videomux_dest_NO_CHANGE)) {
		response.result = 0;
	}

	if (request.hdmi1 != videomux_set_request_videomux_dest_NO_CHANGE) {
		(void)videomux_select(
			HDMI1, videomux_dest_to_video_dest_t(request.hdmi1));
	}

	if (request.hdmi2 != videomux_set_request_videomux_dest_NO_CHANGE) {
		(void)videomux_select(
			HDMI2, videomux_dest_to_video_dest_t(request.hdmi2));
	}

	if (request.dp1 != videomux_set_request_videomux_dest_NO_CHANGE) {
		(void)videomux_select(
			DP1, videomux_dest_to_video_dest_t(request.dp1));
	}

	if (request.dp2 != videomux_set_request_videomux_dest_NO_CHANGE) {
		(void)videomux_select(
			DP2, videomux_dest_to_video_dest_t(request.dp2));
	}

	return ::pw::OkStatus();
}

::pw::Status videomux_service::all_off(const ::Empty &request,
				       ::Empty &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	videomux_disconnect_all();
	return ::pw::OkStatus();
}
