/*
 * Copyright 2023 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module delay_register #(
    parameter int Delay = 1,
    parameter int DataWidth = 1
) (
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 in_valid,
    input  logic [DataWidth-1:0] in_data,
    output logic                 out_valid,
    output logic [DataWidth-1:0] out_data
);

  logic [Delay-1:0]                delay_valid;
  logic [Delay-1:0][DataWidth-1:0] delay_data;

  always @(posedge clk) begin
    delay_valid <= {delay_valid, in_valid};
    delay_data  <= {delay_data,  in_data};
  end

  assign out_valid = delay_valid[Delay-1];
  assign out_data  = delay_data[Delay-1];

endmodule : delay_register

