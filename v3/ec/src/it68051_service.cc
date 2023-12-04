/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#include "it68051_service.h"
#include "it68051.h"
#include "it68051_edid.h"
#include "it68051_i2c.h"

// Method definitions for it68051_service.
::pw::Status
it68051_service::select_port(const ::it68051_port_num_request &request,
			     ::Empty &response)
{
	static_cast<void>(response);

	/* Translate from protobuf's enum to IT68051 C API enum */
	enum it68051_port port;
	if (request.port == it68051_port_num_PORT2) {
		port = PORT2;
	} else if (request.port == it68051_port_num_PORT1) {
		port = PORT1;
	} else {
		return ::pw::Status::InvalidArgument();
	}

	lock();
	it68051_port_select(port);

	return unlock();
}

::pw::Status
it68051_service::get_selected_port(const ::Empty &request,
				   ::it68051_port_num_response &response)
{
	static_cast<void>(request);

	lock();
	auto port = it68051_get_selected_port();
	auto result = unlock();

	if (port == PORT2) {
		response.port = it68051_port_num_PORT2;
	} else if (port == PORT1) {
		response.port = it68051_port_num_PORT1;
	} else if (result.ok()) {
		return ::pw::Status::InvalidArgument();
	}

	return result;
}

::pw::Status it68051_service::set_hpd(const ::it68051_hpd_request &request,
				      ::Empty &response)
{
	static_cast<void>(response);

	/* Translate from protobuf's enum to IT68051 C API enum */
	enum it68051_port port;
	if (request.port == it68051_port_num_PORT2) {
		port = PORT2;
	} else if (request.port == it68051_port_num_PORT1) {
		port = PORT1;
	} else {
		return ::pw::Status::InvalidArgument();
	}

	lock();
	it68051_set_hpd(port, (request.on_off != 0));

	return unlock();
}

::pw::Status it68051_service::get_hpd(const ::it68051_port_num_request &request,
				      ::it68051_hpd_response &response)
{
	/* Translate from protobuf's enum to IT68051 C API enum */
	enum it68051_port port;
	if (request.port == it68051_port_num_PORT2) {
		port = PORT2;
	} else if (request.port == it68051_port_num_PORT1) {
		port = PORT1;
	} else {
		return ::pw::Status::InvalidArgument();
	}

	lock();
	response.on_off = it68051_get_hpd(port) ? 1 : 0;

	return unlock();
}

::pw::Status
it68051_service::set_edid_idx(const ::it68051_edid_idx_request &request,
			      ::Empty &response)
{
	static_cast<void>(response);

	lock();
	it68051_edid_select(request.edid_idx);
	it68051_edid_init();

	return unlock();
}

::pw::Status
it68051_service::write_edid(const ::it68051_raw_edid_request &request,
			    ::Empty &response)
{
	static_cast<void>(response);

	lock();
	it68051_edid_write_block(request.raw_edid);

	return unlock();
}

::pw::Status
it68051_service::get_link_status(const ::Empty &request,
				 ::it68051_link_status_response &response)
{
	static_cast<void>(request);

	lock();
	response.active = it68051_get_link_active();

	return unlock();
}

::pw::Status it68051_service::read_edid(const ::Empty &request,
					::it68051_raw_edid_request &response)
{
	static_cast<void>(request);

	lock();
	it68051_edid_read_block(response.raw_edid);

	return unlock();
}

::pw::Status it68051_service::get_video_params(const ::Empty &request,
					       ::it68051_vid_aud_info &response)
{
	static_cast<void>(request);

	struct vtiming vt;
	struct atiming at;
	struct aviif info;

	lock();
	it68051_get_vid_info(&vt);
	it68051_get_aud_info(&at);
	it68051_get_aviif(&info);
	auto result = unlock();

	response.tmdsclk = vt.tmdsclk;
	response.pclk = vt.pclk;

	response.h_active = vt.h_active;
	response.v_active = vt.v_active;
	response.h_total = vt.h_total;
	response.v_total = vt.v_total;
	response.h_front_porch = vt.h_front_porch;
	response.h_sync_width = vt.h_sync_width;
	response.h_back_porch = vt.h_back_porch;
	response.v_front_porch = vt.v_front_porch;
	response.v_sync_width = vt.v_sync_width;
	response.v_back_porch = vt.v_back_porch;
	response.frame_rate = (float)vt.frame_rate;

	response.is_progressive = (vt.scan_mode == 0);
	response.v_sync_polarity_is_positive = (vt.v_polarity == 1);
	response.h_sync_polarity_is_positive = (vt.h_polarity == 1);

	/* YUV420 requires doubling the horizontal pixel counts. */
	if (info.aviif_input_color_format == COLOR_FORMAT_YUV420) {
		response.h_active *= 2;
		response.h_total *= 2;
		response.h_front_porch *= 2;
		response.h_sync_width *= 2;
		response.h_back_porch *= 2;
	}

	// Translate AVIIF enums into protobuf enums
	switch (info.aviif_input_color_format) {
	case COLOR_FORMAT_RGB:
		response.color_format =
			it68051_vid_aud_info_it68051_color_format_RGB;
		break;
	case COLOR_FORMAT_YUV422:
		response.color_format =
			it68051_vid_aud_info_it68051_color_format_YUV422;
		break;
	case COLOR_FORMAT_YUV444:
		response.color_format =
			it68051_vid_aud_info_it68051_color_format_YUV444;
		break;
	case COLOR_FORMAT_YUV420:
		response.color_format =
			it68051_vid_aud_info_it68051_color_format_YUV420;
		break;
	case COLOR_FORMAT_BYPASS_CSC:
	default:
		response.color_format =
			it68051_vid_aud_info_it68051_color_format_BYPASS_CSC;
		break;
	}

	switch (info.aviif_colorimetry) {
	case COLORIMETRY_ITU601:
		response.colorimetry =
			it68051_vid_aud_info_it68051_colorimetry_ITU601;
		break;
	case COLORIMETRY_ITU709:
		response.colorimetry =
			it68051_vid_aud_info_it68051_colorimetry_ITU709;
		break;
	case COLORIMETRY_EXTEND:
		response.colorimetry =
			it68051_vid_aud_info_it68051_colorimetry_EXTENDED;
		break;
	case COLORIMETRY_UNKNOWN:
	default:
		response.colorimetry =
			it68051_vid_aud_info_it68051_colorimetry_UNKNOWN_COLORIMETRY;
		break;
	}

	switch (info.aviif_rgb_quantization_range) {
	case RGB_RANGE_DEPENDED_ON_VIC:
		response.rgb_quantization =
			it68051_vid_aud_info_it68051_quantization_VIC;
		break;
	case RGB_RANGE_LIMIT:
		response.rgb_quantization =
			it68051_vid_aud_info_it68051_quantization_RANGE_LIMIT;
		break;
	case RGB_RANGE_FULL:
		response.rgb_quantization =
			it68051_vid_aud_info_it68051_quantization_RANGE_FULL;
		break;
	case RGB_RANGE_RESERVE:
	default:
		response.rgb_quantization =
			it68051_vid_aud_info_it68051_quantization_UNKNOWN_QUANTIZATION;
		break;
	}

	switch (info.aviif_yuv_quantization_range) {
	case YUV_RANGE_LIMIT:
		response.yuv_quantization =
			it68051_vid_aud_info_it68051_quantization_RANGE_LIMIT;
		break;
	case YUV_RANGE_FULL:
		response.yuv_quantization =
			it68051_vid_aud_info_it68051_quantization_RANGE_FULL;
		break;
	case YUV_RANGE_RESERVE1:
	case YUV_RANGE_RESERVE2:
	default:
		response.yuv_quantization =
			it68051_vid_aud_info_it68051_quantization_UNKNOWN_QUANTIZATION;
		break;
	}

	response.extended_colorimetry = info.aviif_extended_colorimetry;
	response.vic = info.aviif_vic;

	response.is_audio_3d = at.aud_3d_on;
	response.is_multichannel_audio = at.mult_aud_on;
	response.is_hbr_audio = at.hbr_aud;
	response.is_dsd_audio = at.dsd_aud;

	response.audio_channels = at.aud_ch;

	response.audio_fs = at.aud_fs;

	return result;
}

void it68051_service::lock()
{
	it68051_lock();
	errors_count = it68051_get_i2c_error_count();
}

::pw::Status it68051_service::unlock()
{
	auto status = ::pw::OkStatus();

	if (errors_count != it68051_get_i2c_error_count()) {
		status = ::pw::Status::Internal();
	}
	it68051_unlock();

	return status;
}
