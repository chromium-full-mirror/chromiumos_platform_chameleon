/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module axis_reg_handshake
#(
    parameter reg_handshake_pkg::reg_type_e RegType = reg_handshake_pkg::kBypass
)
(
    input logic   clk,
    input logic   rst,
    axis_i.agent  axis_in,
    axis_i.host   axis_out
);

  typedef struct packed {
      logic [axis_in.TdataWidth-1:0] tdata;
      logic [axis_in.TkeepWidth-1:0] tkeep;
      logic [axis_in.TuserWidth-1:0] tuser;
      logic                          tlast;
  } reg_data_t;

  reg_data_t axis_in_data;
  reg_data_t axis_out_data;

  always_comb begin
    axis_in_data.tdata = axis_in.tdata;
    axis_in_data.tkeep = axis_in.tkeep;
    axis_in_data.tuser = axis_in.tuser;
    axis_in_data.tlast = axis_in.tlast;

    axis_out.tdata = axis_out_data.tdata;
    axis_out.tkeep = axis_out_data.tkeep;
    axis_out.tuser = axis_out_data.tuser;
    axis_out.tlast = axis_out_data.tlast;
  end

  reg_handshake #(
      .Type      ( RegType           ),
      .DataWidth ( $bits(reg_data_t) )
  ) u_reg_handshake (
      .clk       ( clk               ),
      .rst       ( rst               ),
      .in_valid  ( axis_in.tvalid    ),
      .in_ready  ( axis_in.tready    ),
      .in_data   ( axis_in_data      ),
      .out_valid ( axis_out.tvalid   ),
      .out_ready ( axis_out.tready   ),
      .out_data  ( axis_out_data     )
  );

endmodule : axis_reg_handshake
