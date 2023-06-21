/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module axis_tfirst (
    input  logic clk,
    input  logic rst,

    input  logic valid,
    input  logic ready,
    input  logic last,
    output logic tfirst
);

  always @(posedge clk) begin
    if (rst) begin
      tfirst <= 1'b1;
    end else begin
      if (valid & ready) begin
        tfirst <= last;
      end
    end
  end

endmodule : axis_tfirst
