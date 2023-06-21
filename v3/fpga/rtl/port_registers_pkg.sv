/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package port_registers_pkg;

    parameter int AddrWidth = 'h8;

    typedef struct packed {
      logic hdmi_or_dp;
      logic hdmi_edid_ram_access;
    } port_id_t;

    typedef struct packed {
      logic [vid_rx_pkg::MstCount-1:0] overflow;
      vid_rx_pkg::vid_sink_e sink_type;
    } vid_status_t;

    localparam int AddrPortId = 'h0;
    localparam int AddrVidStatus = 'h4;

endpackage : port_registers_pkg
