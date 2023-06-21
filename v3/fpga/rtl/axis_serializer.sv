/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module axis_serializer #(
  parameter int InputNum = 2,
  parameter reg_handshake_pkg::reg_type_e InputRegType = reg_handshake_pkg::kBypass,
  parameter reg_handshake_pkg::reg_type_e OutputRegType = reg_handshake_pkg::kBypass
) (
    input logic    clk,
    input logic    rst,
    axis_i.agent   i_axis_in[InputNum],
    axis_i.host    i_axis_out
);
  localparam int InputNumWidth = $clog2(InputNum);

  localparam int TdataWidth = i_axis_out.TdataWidth;
  localparam int TkeepWidth = i_axis_out.TkeepWidth;
  localparam int TuserWidth = i_axis_out.TuserWidth;

  axis_i #(.DataWidth(TdataWidth), .KeepWidth(TkeepWidth),
           .UserWidth(TuserWidth)) i_axis_in_d[InputNum]();
  axis_i #(.DataWidth(TdataWidth), .KeepWidth(TkeepWidth),
           .UserWidth(TuserWidth)) i_axis_out_d();

  logic[InputNumWidth-1:0]            source_id;

  logic[InputNum-1:0]                 tvalid;
  logic[InputNum-1:0]                 tready;
  logic[InputNum-1:0][TdataWidth-1:0] tdata;
  logic[InputNum-1:0][TkeepWidth-1:0] tkeep;
  logic[InputNum-1:0][TuserWidth-1:0] tuser;
  logic[InputNum-1:0]                 tlast;

  generate
    for (genvar i=0; i < InputNum; i++) begin : g_input_reg
      axis_reg_handshake #(
        .RegType ( InputRegType   )
      )
      u_input_axis_reg_handshake (
        .clk     ( clk            ),
        .rst     ( rst            ),
        .axis_in ( i_axis_in[i]   ),
        .axis_out( i_axis_in_d[i] )
      );

      assign i_axis_in_d[i].tready = tready[i];
      assign tvalid[i] = i_axis_in_d[i].tvalid;
      assign tdata[i]  = i_axis_in_d[i].tdata;
      assign tkeep[i]  = i_axis_in_d[i].tkeep;
      assign tuser[i]  = i_axis_in_d[i].tuser;
      assign tlast[i]  = i_axis_in_d[i].tlast;
    end
  endgenerate

  always_ff @(posedge clk) begin : source_selector
    if (rst) begin
      source_id <= '0;
    end else if (tvalid[source_id] && tready[source_id] && tlast[source_id]) begin
      source_id <= source_id+1;
      if (source_id == InputNum-1) begin
        source_id <= '0;
      end
    end
  end

  always_comb begin
    tready = '0;

    tready[source_id]   = i_axis_out_d.tready;
    i_axis_out_d.tvalid = tvalid[source_id];
    i_axis_out_d.tdata  = tdata[source_id];
    i_axis_out_d.tkeep  = tkeep[source_id];
    i_axis_out_d.tuser  = tuser[source_id];
    i_axis_out_d.tlast  = tlast[source_id] && source_id == (InputNum-1);
  end

  axis_reg_handshake #(
    .RegType ( OutputRegType )
  )
  u_output_axis_reg_handshake (
    .clk     ( clk           ),
    .rst     ( rst           ),
    .axis_in ( i_axis_out_d  ),
    .axis_out( i_axis_out    )
  );

endmodule : axis_serializer
