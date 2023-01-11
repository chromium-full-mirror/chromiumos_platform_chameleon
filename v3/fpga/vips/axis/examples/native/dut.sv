/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////
// example's DUT - just passing packets //
//////////////////////////////////////////

// ACK_TIME adds possibility to set delay after which DUT would accept incomming data
module dut #(
  parameter ACK_TIME = 1
)
(
  input logic     clk,
  input logic     rst,
  gaxis_if.master i_axis_in,
  gaxis_if.slave  i_axis_out
);
  if (ACK_TIME == 0) begin
    always_comb begin
      i_axis_out.tvalid = i_axis_in.tvalid;
      i_axis_in.tready = i_axis_out.tready;

      i_axis_out.tdata = i_axis_in.tdata;
      i_axis_out.tkeep = i_axis_in.tkeep;
      i_axis_out.tuser = i_axis_in.tuser;
      i_axis_out.tstrb = i_axis_in.tstrb;
      i_axis_out.tid   = i_axis_in.tid;
      i_axis_out.tdest = i_axis_in.tdest;
      i_axis_out.tlast = i_axis_in.tlast;
    end
  end
  else begin
    logic [$clog2(ACK_TIME)-1:0] ack_cnt;
    assign i_axis_in.tready = !i_axis_out.tvalid && !rst && ack_cnt == 0;
    always_ff @(posedge clk) begin
      if (rst) begin
        i_axis_out.tvalid <= 1'b0;
        ack_cnt <= ACK_TIME;
      end
      else begin
        if (ack_cnt && i_axis_in.tvalid) begin
          ack_cnt <= ack_cnt - 1;
        end

        if (i_axis_in.tvalid && i_axis_in.tready) begin
          i_axis_out.tvalid <= 1'b1;
          ack_cnt <= ACK_TIME;
        end
        if (i_axis_out.tvalid && i_axis_out.tready) begin
          i_axis_out.tvalid <= 1'b0;

        end
      end
    end

    always_ff @(posedge clk) begin
      if (i_axis_in.tvalid && i_axis_in.tready) begin
        i_axis_out.tdata <= i_axis_in.tdata;
        i_axis_out.tkeep <= i_axis_in.tkeep;
        i_axis_out.tuser <= i_axis_in.tuser;
        i_axis_out.tstrb <= i_axis_in.tstrb;
        i_axis_out.tid   <= i_axis_in.tid;
        i_axis_out.tdest <= i_axis_in.tdest;
        i_axis_out.tlast <= i_axis_in.tlast;
      end
    end
  end

endmodule : dut
