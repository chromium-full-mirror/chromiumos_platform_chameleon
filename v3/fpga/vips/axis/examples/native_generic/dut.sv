/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////
// example's DUT - just passing packets //
//////////////////////////////////////////

module dut (
    input logic     clk,
    input logic     rst,
    gaxis_if.master i_axis_in,
    gaxis_if.slave  i_axis_out
);

    assign i_axis_in.tready = !i_axis_out.tvalid && !rst;
    always_ff @(posedge clk) begin
        if (rst) begin
            i_axis_out.tvalid <= 1'b0;
        end
        else begin
            if (i_axis_in.tvalid && i_axis_in.tready) begin
                i_axis_out.tvalid <= 1'b1;
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


endmodule : dut
