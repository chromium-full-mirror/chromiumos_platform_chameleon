/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2021 The ChromiumOS Authors
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

  ::pw::Status get_selected_port( const ::Empty& request, ::it68051_port_num_response& response);

  ::pw::Status set_hpd( const ::it68051_hpd_request& request, ::Empty& response);

  ::pw::Status get_hpd( const ::it68051_port_num_request& request, ::it68051_hpd_response& response);

  ::pw::Status set_edid_idx( const ::it68051_edid_idx_request& request, ::Empty& response);

  ::pw::Status write_edid( const ::it68051_raw_edid_request& request, ::Empty& response);

  ::pw::Status get_link_status( const ::Empty& request, ::it68051_link_status_response& response);

  ::pw::Status read_edid( const ::Empty& request, ::it68051_raw_edid_request& response);

  ::pw::Status get_video_params( const ::Empty& request, ::it68051_vid_aud_info& response);

 private:
  void lock();

  ::pw::Status unlock();

  uint32_t errors_count;
};

#endif
