/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#include "board_service.h"
#include "io.h"
#include "misc_io.h"
#include "source_presence.h"
#include "sysmon.h"

// Method definitions for board_service.
::pw::Status
board_service::get_board_version(const ::Empty &request,
				 ::board_service_version_response &response)
{
	static_cast<void>(request);
	response.version = misc_io_get_board_version();
	return ::pw::OkStatus();
}

::pw::Status board_service::get_sysmon(const ::Empty &request,
				       ::sysmon_response &response)
{
	static_cast<void>(request);
	response.vmon_12v = sysmon_get_val(SYSMON_VMON_12V);
	response.cmon_som = sysmon_get_val(SYSMON_CMON_SOM);
	response.cmon_board = sysmon_get_val(SYSMON_CMON_BOARD);
	response.vmon_1v2 = sysmon_get_val(SYSMON_VMON_PP1200);
	response.cmon_pp1200 = sysmon_get_val(SYSMON_CMON_PP1200);
	response.cmon_pp3300 = sysmon_get_val(SYSMON_CMON_PP3300);
	response.vmon_9v = sysmon_get_val(SYSMON_VMON_9V);
	response.vmon_5v = sysmon_get_val(SYSMON_VMON_5V);
	response.vmon_3v3 = sysmon_get_val(SYSMON_VMON_3V3);
	response.vmon_1v8 = sysmon_get_val(SYSMON_VMON_PP1800);
	response.som_vmon = sysmon_get_val(SYSMON_SOM_VMON);
	response.som_vmon_1v2 = sysmon_get_val(SYSMON_SOM_VMON_1V2);
	response.som_vmon_mgt = sysmon_get_val(SYSMON_SOM_VMON_MGT);
	response.som_vmon_1v8a = sysmon_get_val(SYSMON_SOM_VMON_1V8A);
	response.som_vmon_c8 = sysmon_get_val(SYSMON_SOM_VMON_C8);
	response.vref_cs1 = sysmon_get_val(SYSMON_SOM_VREF_CS1);
	response.vref_cs2 = sysmon_get_val(SYSMON_SOM_VREF_CS2);
	response.vref_cs3 = sysmon_get_val(SYSMON_SOM_VREF_CS3);
	return ::pw::OkStatus();
}

::pw::Status
board_service::get_source_presence(const ::Empty &request,
				   ::source_presence_response &response)
{
	static_cast<void>(request);
	response.hdmi2 = gpio_get_level(hdmi2_pp3300);
	response.hdmi1 = gpio_get_level(hdmi1_pp3300);
	response.dp2 = get_dp2_present() ? 1 : 0;
	response.dp1 = get_dp1_present() ? 1 : 0;
	return ::pw::OkStatus();
}
