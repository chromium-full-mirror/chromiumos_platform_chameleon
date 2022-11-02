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

	it68051_port_select(port);

	return ::pw::OkStatus();
}

::pw::Status
it68051_service::get_selected_port(const ::Empty &request,
				   ::it68051_port_num_response &response)
{
	static_cast<void>(request);

	enum it68051_port port = it68051_get_selected_port();
	if (port == PORT2) {
		response.port = it68051_port_num_PORT2;
	} else if (port == PORT1) {
		response.port = it68051_port_num_PORT1;
	} else {
		return ::pw::Status::InvalidArgument();
	}

	return ::pw::OkStatus();
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

	it68051_set_hpd(port, (request.on_off != 0));

	return ::pw::OkStatus();
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

	response.on_off = it68051_get_hpd(port) ? 1 : 0;

	return ::pw::OkStatus();
}

::pw::Status
it68051_service::set_edid_idx(const ::it68051_edid_idx_request &request,
			      ::Empty &response)
{
	static_cast<void>(response);

	it68051_edid_select(request.edid_idx);
	it68051_edid_init();

	return ::pw::OkStatus();
}

::pw::Status
it68051_service::write_edid(const ::it68051_raw_edid_request &request,
			    ::Empty &response)
{
	static_cast<void>(response);

	it68051_edid_write_block(request.raw_edid);

	return ::pw::OkStatus();
}

::pw::Status
it68051_service::get_link_status(const ::Empty &request,
				 ::it68051_link_status_response &response)
{
	static_cast<void>(request);
	response.active = it68051_get_link_active();
	return ::pw::OkStatus();
}
