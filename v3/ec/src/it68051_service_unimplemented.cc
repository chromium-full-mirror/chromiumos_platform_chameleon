/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 *
 * This implementation returns Umimplemented for all calls, to allow
 * building a binary without the proprietary IT68051 code.
 */

#include "it68051_service.h"

// Method definitions for it68051_service.
::pw::Status
it68051_service::select_port(const ::it68051_port_num_request &request,
			     ::Empty &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status
it68051_service::get_selected_port(const ::Empty &request,
				   ::it68051_port_num_response &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::set_hpd(const ::it68051_hpd_request &request,
				      ::Empty &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::get_hpd(const ::it68051_port_num_request &request,
				      ::it68051_hpd_response &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status
it68051_service::set_edid_idx(const ::it68051_edid_idx_request &request,
			      ::Empty &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status
it68051_service::write_edid(const ::it68051_raw_edid_request &request,
			    ::Empty &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status
it68051_service::get_link_status(const ::Empty &request,
				 ::it68051_link_status_response &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::read_edid(const ::Empty &request,
					::it68051_raw_edid_request &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::get_video_params(const ::Empty &request,
					       ::it68051_vid_aud_info &response)
{
	static_cast<void>(request);
	static_cast<void>(response);
	return ::pw::Status::Unimplemented();
}
