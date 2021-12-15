/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#ifndef __BOARD_SERVICE_H
#define __BOARD_SERVICE_H

#include "proto/v3.rpc.pb.h"

// Implementation class for board_service.
class board_service : public pw_rpc::nanopb::board_service::Service<board_service> {
 public:
  ::pw::Status get_board_version( const ::Empty& request, ::board_service_version_response& response);

  ::pw::Status get_sysmon( const ::Empty& request, ::sysmon_response& response);

  ::pw::Status get_hpd( const ::Empty& request, ::hpd_response& response);
};

#endif
