/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#include "it68051_service.h"

// Method definitions for it68051_service.
::pw::Status it68051_service::select_port( const ::it68051_port_num_request& request, ::Empty& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::set_hpd( const ::it68051_hpd_request& request, ::Empty& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::set_edid_idx( const ::it68051_edid_idx_request& request, ::Empty& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status it68051_service::write_edid( const ::it68051_raw_edid_request& request, ::Empty& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}
