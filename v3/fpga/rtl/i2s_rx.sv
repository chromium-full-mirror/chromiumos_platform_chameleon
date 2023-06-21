/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Connects i2s rx side modules

module i2s_rx #(
  parameter int CounterWidth = 28
) (
    input logic                     clk,
    input logic                     rst,
    i2s_if.receiver                 i_i2s_in,
    axis_i.host                     i_axis_samples_out,
    output logic                    overflow,
    output logic [CounterWidth-1:0] clk_counter,
    output logic [CounterWidth-1:0] ws_counter
);
  import i2s_pkg::sample_t;

  axis_i #(.Tdata(sample_t), .KeepWidth(1)) i_axis_samples();

  logic sample_axis_fifo_error; //unused
  logic sample_axis_fifo_data_count; //unused

  i2s_rx_deserializer #(
      .CounterWidth ( CounterWidth )
  )  u_i2s_rx_deserializer (
      .clk               (clk           ),
      .rst               (rst           ),
      .i_i2s_in          (i_i2s_in      ),
      .i_axis_samples_out(i_axis_samples),
      .overflow          (overflow      ),
      .clk_counter       (clk_counter   ),
      .ws_counter        (ws_counter    )
  );

  axis_fifo #(
    .FifoDepth     (64    ),
    .DataCntWidth  (1     ),
    .OutputRegType ( reg_handshake_pkg::kPayloadCtrl )

  ) u_sample_axis_fifo (
    .clk       (clk                        ),
    .rst       (rst                        ),
    .axis_in   (i_axis_samples             ),
    .axis_out  (i_axis_samples_out         ),
    .error     (sample_axis_fifo_error     ),
    .data_count(sample_axis_fifo_data_count)
  );


endmodule : i2s_rx
