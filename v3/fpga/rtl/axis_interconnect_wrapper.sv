/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module axis_interconnect_wrapper #(
    parameter int InputNum = 2,
    parameter int DataWidth = 128,
    parameter int DataWithMetaWidth = DataWidth + $bits(axis_to_aximm_pkg::meta_t)
) (
    input  logic clk,
    input  logic rst,
    output logic [$clog2(InputNum)-1:0] ch_id,
    axis_i.agent i_axis_in[InputNum-1:0],
    axis_i.host  i_axis_out
);

  localparam int KeepWidth = DataWithMetaWidth/8;
  localparam int EmptyWidth = $clog2(KeepWidth);
  logic axis_out_sop;
  logic [EmptyWidth-1:0] axis_out_empty;
  logic [InputNum-1:0] axis_in_sop;
  logic [InputNum-1:0][KeepWidth-1:0] axis_in_keep;
  logic [InputNum-1:0][EmptyWidth-1:0] axis_in_empty;

  typedef struct packed {
    logic [DataWidth-1:0]     data;
    axis_to_aximm_pkg::meta_t user;
  } data_t;

  data_t [InputNum-1:0] axis_in_data;
  data_t axis_out_data;

  function logic [EmptyWidth-1:0] keep_to_empty(input logic [KeepWidth-1:0] keep);
    keep_to_empty = KeepWidth - $countones(keep);
    return keep_to_empty;
  endfunction : keep_to_empty

  function logic [KeepWidth-1:0] empty_to_keep(input logic [EmptyWidth-1:0] empty);
    empty_to_keep = '1;
    if (empty == '0) begin
      return empty_to_keep;
    end
    for (int i = KeepWidth-1; i > (KeepWidth - 1 - empty); i--) begin
      empty_to_keep[i] = 1'b0;
    end
    return empty_to_keep;
  endfunction : empty_to_keep

  generate
    always_comb begin
      i_axis_out.tdata           = axis_out_data.data;
      i_axis_out.tuser.addr      = axis_out_data.user.addr;
      i_axis_out.tuser.data_size = axis_out_data.user.data_size;
      i_axis_out.tkeep           = empty_to_keep(axis_out_empty);
    end

    for (genvar i = 0; i < InputNum; i++) begin
      axis_tfirst u_tfirst(clk, rst,
                           i_axis_in[i].tvalid, i_axis_in[i].tready,
                           i_axis_in[i].tlast, axis_in_sop[i]);
      always_comb begin
        axis_in_data[i].data           = i_axis_in[i].tdata;
        axis_in_data[i].user.addr      = i_axis_in[i].tuser.addr;
        axis_in_data[i].user.data_size = i_axis_in[i].tuser.data_size;
        axis_in_keep[i]                = {i_axis_in[i].tkeep, 6'h3f}; // meta is always valid
        axis_in_empty[i]               = keep_to_empty(axis_in_keep[i]);
      end
    end

    if (InputNum == 2) begin
      ap_multiplexer_2x1 u_ic_2x1 (
          .clk                       ( clk                 ),
          .reset_n                   ( ~rst                ),
          .out_data                  ( axis_out_data       ),
          .out_valid                 ( i_axis_out.tvalid   ),
          .out_ready                 ( i_axis_out.tready   ),
          .out_startofpacket         ( axis_out_sop        ),
          .out_endofpacket           ( i_axis_out.tlast    ),
          .out_empty                 ( axis_out_empty      ),
          .out_channel               ( ch_id               ),
          .in0_data                  ( axis_in_data[0]     ),
          .in0_valid                 ( i_axis_in[0].tvalid ),
          .in0_ready                 ( i_axis_in[0].tready ),
          .in0_startofpacket         ( axis_in_sop[0]      ),
          .in0_endofpacket           ( i_axis_in[0].tlast  ),
          .in0_empty                 ( axis_in_empty[0]    ),
          .in1_data                  ( axis_in_data[1]     ),
          .in1_valid                 ( i_axis_in[1].tvalid ),
          .in1_ready                 ( i_axis_in[1].tready ),
          .in1_startofpacket         ( axis_in_sop[1]      ),
          .in1_endofpacket           ( i_axis_in[1].tlast  ),
          .in1_empty                 ( axis_in_empty[1]    )
      );
    end else if (InputNum == 4) begin
      ap_multiplexer_4x1 u_ic_4x1 (
          .clk                       ( clk                 ),
          .reset_n                   ( ~rst                ),
          .out_data                  ( axis_out_data       ),
          .out_valid                 ( i_axis_out.tvalid   ),
          .out_ready                 ( i_axis_out.tready   ),
          .out_startofpacket         ( axis_out_sop        ),
          .out_endofpacket           ( i_axis_out.tlast    ),
          .out_empty                 ( axis_out_empty      ),
          .out_channel               ( ch_id               ),
          .in0_data                  ( axis_in_data[0]     ),
          .in0_valid                 ( i_axis_in[0].tvalid ),
          .in0_ready                 ( i_axis_in[0].tready ),
          .in0_startofpacket         ( axis_in_sop[0]      ),
          .in0_endofpacket           ( i_axis_in[0].tlast  ),
          .in0_empty                 ( axis_in_empty[0]    ),
          .in1_data                  ( axis_in_data[1]     ),
          .in1_valid                 ( i_axis_in[1].tvalid ),
          .in1_ready                 ( i_axis_in[1].tready ),
          .in1_startofpacket         ( axis_in_sop[1]      ),
          .in1_endofpacket           ( i_axis_in[1].tlast  ),
          .in1_empty                 ( axis_in_empty[1]    ),
          .in2_data                  ( axis_in_data[2]     ),
          .in2_valid                 ( i_axis_in[2].tvalid ),
          .in2_ready                 ( i_axis_in[2].tready ),
          .in2_startofpacket         ( axis_in_sop[2]      ),
          .in2_endofpacket           ( i_axis_in[2].tlast  ),
          .in2_empty                 ( axis_in_empty[2]    ),
          .in3_data                  ( axis_in_data[3]     ),
          .in3_valid                 ( i_axis_in[3].tvalid ),
          .in3_ready                 ( i_axis_in[3].tready ),
          .in3_startofpacket         ( axis_in_sop[3]      ),
          .in3_endofpacket           ( i_axis_in[3].tlast  ),
          .in3_empty                 ( axis_in_empty[3]    )
      );
    end
  endgenerate
endmodule : axis_interconnect_wrapper
