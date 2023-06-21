/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module translates input format from DP/HDMI data to DMA-aligned packets.
 */
module vid_format_selector #(
    parameter int PixelDataWidth = vid_rx_pkg::PixelDataWidth,
    parameter int PixelKeepWidth = vid_rx_pkg::PixelKeepWidth,
    parameter reg_handshake_pkg::reg_type_e OutputRegType  = reg_handshake_pkg::kPayload
) (
    input  logic                        clk,
    input  logic                        rst,
    input  vid_rx_pkg::vid_dma_format_e vid_format,
    axis_i.agent                        i_axis_in,
    axis_i.host                         i_axis_out
);
  import vid_rx_pkg::*;

  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_axis_reg();

  axis_i #(.Tdata(vid_dma_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_axis_comb();

  logic first_valid_8bpc;
  always @(posedge clk) begin
    if (rst) begin
      first_valid_8bpc <= '0;
    end else begin
      if (i_axis_in.tvalid && i_axis_in.tready) begin
        first_valid_8bpc <= ~first_valid_8bpc;
      end
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      i_axis_reg.tdata <= '0;
    end else begin
      if (i_axis_in.tvalid && i_axis_in.tready) begin
        i_axis_reg.tdata <= i_axis_in.tdata;
        i_axis_reg.tuser <= i_axis_in.tuser;
      end
    end
  end

  always_comb begin
    i_axis_comb.tvalid = 1'b0;
    i_axis_comb.tdata  = '0;
    i_axis_comb.tuser  = '0;
    i_axis_comb.tkeep  = '0;
    i_axis_comb.tlast  = 1'b0;
    if (i_axis_in.tvalid && i_axis_in.tready) begin
      i_axis_comb.tuser = i_axis_in.tuser;
      i_axis_comb.tkeep = i_axis_in.tkeep;
      i_axis_comb.tlast = i_axis_in.tlast;
      case (vid_format)
        k8bpc: begin
          if (first_valid_8bpc) begin
            for (int i = 0; i < PixelsInBeat; i++) begin
              i_axis_comb.tdata.format8bpc.upper[i].b = i_axis_in.tdata.format8bpc_444[i].b;
              i_axis_comb.tdata.format8bpc.upper[i].g = i_axis_in.tdata.format8bpc_444[i].g;
              i_axis_comb.tdata.format8bpc.upper[i].r = i_axis_in.tdata.format8bpc_444[i].r;
              i_axis_comb.tdata.format8bpc.lower[i].b = i_axis_reg.tdata.format8bpc_444[i].b;
              i_axis_comb.tdata.format8bpc.lower[i].g = i_axis_reg.tdata.format8bpc_444[i].g;
              i_axis_comb.tdata.format8bpc.lower[i].r = i_axis_reg.tdata.format8bpc_444[i].r;
            end

            i_axis_comb.tuser.vid.sof = i_axis_reg.tuser.vid.sof;
            i_axis_comb.tuser.vid.sol = i_axis_reg.tuser.vid.sol;
            i_axis_comb.tuser.vid.eol = i_axis_in.tuser.vid.eol;
            i_axis_comb.tuser.vid.eof = i_axis_in.tuser.vid.eof;

            i_axis_comb.tvalid = 1'b1;
          end
        end
        k10bpcUpper: begin
          for (int i = 0; i < PixelsInBeat; i++) begin
            i_axis_comb.tdata.format10bpc_upper[i].b = i_axis_in.tdata.format10bpc_444[i].b;
            i_axis_comb.tdata.format10bpc_upper[i].g = i_axis_in.tdata.format10bpc_444[i].g;
            i_axis_comb.tdata.format10bpc_upper[i].r = i_axis_in.tdata.format10bpc_444[i].r;
          end
          i_axis_comb.tvalid = 1'b1;
        end
        k10bpcLower: begin
          for (int i = 0; i < PixelsInBeat; i++) begin
            i_axis_comb.tdata.format10bpc_lower[i].b = i_axis_in.tdata.format10bpc_444[i].b;
            i_axis_comb.tdata.format10bpc_lower[i].g = i_axis_in.tdata.format10bpc_444[i].g;
            i_axis_comb.tdata.format10bpc_lower[i].r = i_axis_in.tdata.format10bpc_444[i].r;
          end
          i_axis_comb.tvalid = 1'b1;
        end
        k12bpcUpper: begin
          for (int i = 0; i < PixelsInBeat; i++) begin
            i_axis_comb.tdata.format12bpc_upper[i].b = i_axis_in.tdata.format12bpc_444[i].b;
            i_axis_comb.tdata.format12bpc_upper[i].g = i_axis_in.tdata.format12bpc_444[i].g;
            i_axis_comb.tdata.format12bpc_upper[i].r = i_axis_in.tdata.format12bpc_444[i].r;
          end
          i_axis_comb.tvalid = 1'b1;
        end
        k12bpcLower: begin
          for (int i = 0; i < PixelsInBeat; i++) begin
            i_axis_comb.tdata.format12bpc_lower[i].b = i_axis_in.tdata.format12bpc_444[i].b;
            i_axis_comb.tdata.format12bpc_lower[i].g = i_axis_in.tdata.format12bpc_444[i].g;
            i_axis_comb.tdata.format12bpc_lower[i].r = i_axis_in.tdata.format12bpc_444[i].r;
          end
          i_axis_comb.tvalid = 1'b1;
        end
        k16bpc: begin
          for (int i = 0; i < PixelsInBeat; i++) begin
            i_axis_comb.tdata.format16bpc[i].b = i_axis_in.tdata.format16bpc_444[i].b;
            i_axis_comb.tdata.format16bpc[i].g = i_axis_in.tdata.format16bpc_444[i].g;
            i_axis_comb.tdata.format16bpc[i].r = i_axis_in.tdata.format16bpc_444[i].r;
          end
          i_axis_comb.tvalid = 1'b1;
        end
        kRaw: begin
          i_axis_comb.tdata = i_axis_in.tdata;
          i_axis_comb.tvalid = 1'b1;
        end
      endcase
    end
  end

  assign i_axis_in.tready = 1'b1;

  axis_reg_handshake #(
      .RegType  ( OutputRegType )
  ) u_axis_reg_handshake (
      .clk      ( clk             ),
      .rst      ( rst             ),
      .axis_in  ( i_axis_comb     ),
      .axis_out ( i_axis_out      )
  );

endmodule : vid_format_selector
