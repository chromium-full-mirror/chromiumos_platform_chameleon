/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Synchronizer module for data vector with valid signal
 * - synchronization for slow signals
 * - synchronization on valid signal
 * - data latch at valid after synchronization with synthesis false path attribute
 */
module cdc_synchronizer_slow_data_with_valid #(
    parameter int DataWidth = 8
) (
    input  logic                in_clk,
    input  logic                out_clk,
    input  logic                reset,

    input  logic                in_valid,
    input  logic[DataWidth-1:0] in_data,

    output logic                out_valid,
    output logic[DataWidth-1:0] out_data
);

  logic valid_sync;
  logic valid_sync_d;
  logic valid_sync_risign_edge;

  altera_std_synchronizer synchronizer(
    .clk     ( out_clk    ),
    .reset_n ( ~reset     ),
    .din     ( in_valid   ),
    .dout    ( valid_sync )
  );

  // we only synchronize valid signal and data should be not consider by Quartus
  (* altera_attribute = {"-name ADV_NETLIST_OPT_ALLOWED NEVER_ALLOW; -name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON; -name SDC_STATEMENT \"set_false_path -to [get_keepers {*valid_data_synchronizer:*|dreg}]\" "} *) reg [DataWidth-1:0] dreg;

  assign valid_sync_risign_edge = valid_sync & ~valid_sync_d;

  always_ff @(posedge out_clk) begin
    if (valid_sync_risign_edge) begin
      out_data <= dreg;
    end
    dreg <= in_data;
    valid_sync_d <= valid_sync;
    out_valid <= valid_sync;
  end

endmodule : cdc_synchronizer_slow_data_with_valid
