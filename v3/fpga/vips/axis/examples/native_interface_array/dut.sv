/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////////////////////////
// example's DUT with interface array - simple demux module //
//////////////////////////////////////////////////////////////

// NUM specifies the number of slaves for demux module.
module dut #(
  parameter NUM = 2
)
(
  input logic     clk,
  input logic     rst,
  gaxis_if.master i_axis_in,
  gaxis_if.slave  i_axis_out[NUM-1:0]
);

  logic                   axis_in_tfirst;
  logic [$clog2(NUM)-1:0] dest;
  logic [$clog2(NUM)-1:0] dest_reg;
  logic [NUM-1:0]         axis_out_tready;

  always @(posedge clk) begin
    if (rst) begin
      axis_in_tfirst <= 1'b1;
    end
    else begin    
      if (i_axis_in.tvalid && i_axis_in.tready) begin
        axis_in_tfirst <= i_axis_in.tlast;
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      dest_reg <= '0;
    end
    else begin    
      if (i_axis_in.tvalid && i_axis_in.tready && axis_in_tfirst) begin
        dest_reg <= dest;
      end
    end
  end

  assign dest = axis_in_tfirst ? i_axis_in.tdest : dest_reg;
  assign i_axis_in.tready = axis_out_tready[dest];

  generate
    for (genvar i=0; i < NUM; i++) begin : ASSIGN_OUTPUT
      assign axis_out_tready[i]   = i_axis_out[i].tready;
      assign i_axis_out[i].tvalid = dest == i ? i_axis_in.tvalid : 1'b0;
      assign i_axis_out[i].tdata  = i_axis_in.tdata;
      assign i_axis_out[i].tkeep  = i_axis_in.tkeep;
      assign i_axis_out[i].tstrb  = i_axis_in.tstrb;
      assign i_axis_out[i].tuser  = i_axis_in.tuser;
      assign i_axis_out[i].tid    = i_axis_in.tid;
      assign i_axis_out[i].tdest  = i_axis_in.tdest;
      assign i_axis_out[i].tlast  = i_axis_in.tlast;
    end
  endgenerate

endmodule : dut
