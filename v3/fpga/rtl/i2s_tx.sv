/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// I2S TX module
// Basically i2s_tx_serializer + buffer in front

module i2s_tx #(
  parameter int CounterWidth = 28
) (
    input  logic                    clk,
    input  logic                    rst,
    axis_i.agent                    i_axis_in,
    i2s_if.transmitter              i_i2s_out,
    output logic [CounterWidth-1:0] clk_counter,
    output logic [CounterWidth-1:0] ws_counter
);
  import i2s_pkg::sample_t;

  axis_i #(.Tdata(sample_t), .KeepWidth(1)) i_axis_audio();

  logic axis_i2s_tx_fifo_error;      //unused
  logic axis_i2s_tx_fifo_data_count; //unused

  axis_fifo #(
      .FifoDepth     ( 64     ),
      .DataCntWidth  ( 1      ),
      .OutputRegType ( reg_handshake_pkg::kPayload )
  ) u_axis_tx_audio_fifo (
      .clk        ( clk                         ),
      .rst        ( rst                         ),
      .axis_in    ( i_axis_in                   ),
      .axis_out   ( i_axis_audio                ),
      .error      ( axis_i2s_tx_fifo_error      ),
      .data_count ( axis_i2s_tx_fifo_data_count )
  );

  i2s_tx_serializer #(
      .CounterWidth ( CounterWidth )
  ) u_i2s_tx_serializer (
      .clk        ( clk           ),
      .rst        ( rst           ),
      .i_axis_in  ( i_axis_audio  ),
      .i_i2s_out  ( i_i2s_out     ),
      .clk_counter( clk_counter   ),
      .ws_counter ( ws_counter    )
  );

endmodule : i2s_tx
