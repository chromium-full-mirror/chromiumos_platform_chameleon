/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#ifndef __VIDEOMUX_SERVICE_H
#define __VIDEOMUX_SERVICE_H

#include "proto/v3.rpc.pb.h"

// Implementation class for videomux_service.
class videomux_service : public pw_rpc::nanopb::videomux_service::Service<videomux_service> {
 public:
  ::pw::Status get( const ::Empty& request, ::videomux_get_response& response);

  ::pw::Status set( const ::videomux_set_request& request, ::videomux_service_set_response& response);

  ::pw::Status all_off( const ::Empty& request, ::Empty& response);
};

#endif
