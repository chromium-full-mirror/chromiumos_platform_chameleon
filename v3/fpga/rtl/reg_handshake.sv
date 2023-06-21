/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Register module to handle handshake interfaces (like AMBA AXI).
 */

module reg_handshake #(
    parameter reg_handshake_pkg::reg_type_e Type = reg_handshake_pkg::kBypass,
    parameter int DataWidth = 1
) (
    input  logic clk,
    input  logic rst,

    input  logic in_valid,
    output logic in_ready,
    input  logic [DataWidth-1:0] in_data,

    output logic out_valid,
    input  logic out_ready,
    output logic [DataWidth-1:0] out_data
);
  import reg_handshake_pkg::*;

  logic rst_local;

  generate
    if (Type == kBypass) begin

      always_comb begin : bypass
        out_data  = in_data;
        out_valid = in_valid;
        in_ready  = out_ready;
      end

    end else if (Type == kPayload) begin

      always @(posedge clk) begin
        rst_local <= rst;
      end

      assign in_ready = (!out_valid || out_ready) && !rst_local;
      always @(posedge clk) begin : payload
        if (out_ready) begin
          out_valid <= 1'b0;
        end
        if (in_valid & in_ready) begin
          out_valid <= 1'b1;
          out_data <= in_data;
        end

        if (rst_local) begin
          out_valid <= 1'b0;
        end
      end

    end else if (Type == kPayloadCtrl) begin
      logic in_valid_id = 1'b0;
      logic out_valid_id = 1'b0;
      logic [1:0] buf_valid;
      logic [1:0][DataWidth-1:0] buf_reg;

      always @(posedge clk) begin
        rst_local <= rst;
      end

      assign in_ready  = !(&buf_valid) & !rst_local;
      assign out_valid = |buf_valid;
      assign out_data  = buf_reg[out_valid_id];

      always @(posedge clk) begin
        if (in_valid & in_ready) begin
          buf_valid[in_valid_id] <= 1'b1;
          in_valid_id <= !in_valid_id;
          buf_reg[in_valid_id] <= in_data;
        end

        if (out_valid & out_ready) begin
          out_valid_id <= !out_valid_id;
          buf_valid[out_valid_id] <= 1'b0;
        end

        if (rst_local) begin
          in_valid_id  <= 1'b0;
          out_valid_id <= 1'b0;
          buf_valid    <= '0;
        end
      end

    end

  endgenerate

endmodule : reg_handshake
