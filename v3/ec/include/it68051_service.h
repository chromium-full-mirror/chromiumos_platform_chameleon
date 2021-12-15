/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Copied from the implementation stubs section of
 * build/v3.protos/nanopb_rpc/proto/v3.rpc.pb.h
 */

#ifndef __IT68051_SERVICE_H
#define __IT68051_SERVICE_H

#include "proto/v3.rpc.pb.h"

// Implementation class for it68051_service.
class it68051_service : public pw_rpc::nanopb::it68051_service::Service<it68051_service> {
 public:
  ::pw::Status select_port( const ::it68051_port_num_request& request, ::Empty& response);

  ::pw::Status set_hpd( const ::it68051_hpd_request& request, ::Empty& response);

  ::pw::Status set_edid_idx( const ::it68051_edid_idx_request& request, ::Empty& response);

  ::pw::Status write_edid( const ::it68051_raw_edid_request& request, ::Empty& response);
};

#endif
