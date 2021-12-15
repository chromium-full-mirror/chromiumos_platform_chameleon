/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#include "videomux_service.h"

// Method definitions for videomux_service.
::pw::Status videomux_service::get( const ::Empty& request, ::videomux_get_response& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status videomux_service::set( const ::videomux_set_request& request, ::videomux_service_set_response& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}

::pw::Status videomux_service::all_off( const ::Empty& request, ::Empty& response) {
  // TODO: Read the request as appropriate for your application
  static_cast<void>(request);
  // TODO: Fill in the response as appropriate for your application
  static_cast<void>(response);
  return ::pw::Status::Unimplemented();
}
