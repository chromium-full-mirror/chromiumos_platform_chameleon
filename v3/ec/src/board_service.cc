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

// Method definitions for board_service.
::pw::Status board_service::get_board_version( const ::Empty& request, ::board_service_version_response& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status board_service::get_sysmon( const ::Empty& request, ::sysmon_response& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status board_service::get_hpd( const ::Empty& request, ::hpd_response& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}
