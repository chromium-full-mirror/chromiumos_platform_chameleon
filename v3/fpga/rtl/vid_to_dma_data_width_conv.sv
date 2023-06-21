/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module converts video stream width (192b) to DMA width (128b).
 */
module vid_to_dma_data_width_conv #(
    parameter int PixelDataWidth = vid_rx_pkg::PixelDataWidth,
    parameter int PixelKeepWidth = vid_rx_pkg::PixelKeepWidth,
    parameter int DmaDataWidth   = vid_rx_pkg::DmaDataWidth,
    parameter int DmaKeepWidth   = vid_rx_pkg::DmaKeepWidth,
    parameter reg_handshake_pkg::reg_type_e OutputRegType  = reg_handshake_pkg::kBypass
) (
    input  logic  clk,
    input  logic  rst,
    axis_i.agent  i_axis_in,
    axis_i.host   i_axis_out
);
  import vid_rx_pkg::*;

  localparam int ShiftRegSize = 2;

  // synthesis translate_off
  if (PixelDataWidth != 192 || DmaDataWidth != 128) begin
    $fatal(1, "Module parameters don't meet module requirements.");
  end
  // synthesis translate_on

  typedef struct packed {
    logic [PixelDataWidth/3-1:0] high;
    logic [PixelDataWidth/3-1:0] mid;
    logic [PixelDataWidth/3-1:0] low;
  } pixel_raw_data_t;

  typedef struct packed {
    logic [DmaDataWidth/2-1:0] high;
    logic [DmaDataWidth/2-1:0] low;
  } dma_raw_data_t;

  axis_i #(.Tdata(pixel_raw_data_t),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_axis_comb();

  axis_i #(.Tdata(dma_raw_data_t),
           .KeepWidth(DmaKeepWidth),
           .Tuser(vid_meta_t)) i_axis_out_reg();

  typedef struct packed {
    logic valid;
    logic [DmaDataWidth/2-1:0] data;
  } buffer_t;

  buffer_t [ShiftRegSize-1:0] buffer;
  logic first_done;
  logic was_eol;
  logic was_last;
  logic last_to_send;

  always_comb begin
    i_axis_comb.tvalid = i_axis_in.tvalid;
    i_axis_in.tready   = i_axis_comb.tready;
    i_axis_comb.tdata  = i_axis_in.tdata;
    i_axis_comb.tkeep  = i_axis_in.tkeep;
    i_axis_comb.tuser  = i_axis_in.tuser;
    i_axis_comb.tlast  = i_axis_in.tlast;
  end

  assign i_axis_comb.tready = i_axis_out_reg.tready && !was_last &&
                              !(buffer[0].valid && buffer[1].valid) &&
                              !(buffer[0].valid && !buffer[1].valid && was_last);

  always @(posedge clk) begin
    if (rst) begin
      i_axis_out_reg.tvalid <= 1'b0;
      first_done            <= '0;
      buffer[0].valid       <= '0;
      buffer[1].valid       <= '0;
      was_last              <= '0;
      was_eol               <= '0;
      last_to_send          <= '0;
    end else begin

      if (i_axis_out_reg.tready) begin
        i_axis_out_reg.tvalid <= 1'b0;
      end

      if (i_axis_comb.tvalid && i_axis_comb.tready) begin
        first_done <= 1'b1;
        i_axis_out_reg.tuser <= i_axis_comb.tuser; // Pass tuser on first beat
        i_axis_out_reg.tuser.vid.eof <= '0;
        i_axis_out_reg.tuser.vid.eol <= '0;
        i_axis_out_reg.tlast <= 1'b0;
        if (i_axis_comb.tuser.vid.eol) begin
          was_eol <= 1'b1;
        end
        if (i_axis_comb.tlast) begin
          was_last <= 1'b1;
        end
        if (first_done && buffer[0].valid) begin
          i_axis_out_reg.tvalid     <= 1'b1;
          i_axis_out_reg.tdata.high <= i_axis_comb.tdata.low;
          i_axis_out_reg.tdata.low  <= buffer[0].data;
          for (int k = 0; k < PixelsInBeat; k++) begin
            if (i_axis_comb.tkeep[k]) begin
              i_axis_out_reg.tkeep[k*(DmaKeepWidth/4)+:(DmaKeepWidth/4)] <= {(DmaKeepWidth/4){1'b1}};
            end
          end
          buffer[0].valid <= 1'b1;
          buffer[0].data  <= i_axis_comb.tdata.mid;
          buffer[1].valid <= 1'b1;
          buffer[1].data  <= i_axis_comb.tdata.high;
        end else begin
          i_axis_out_reg.tvalid     <= 1'b1;
          i_axis_out_reg.tdata.high <= i_axis_comb.tdata.mid;
          i_axis_out_reg.tdata.low  <= i_axis_comb.tdata.low;
          for (int k = 0; k < PixelsInBeat; k++) begin
            if (i_axis_comb.tkeep[k]) begin
              i_axis_out_reg.tkeep[k*(DmaKeepWidth/PixelsInBeat)+:(DmaKeepWidth/PixelsInBeat)] <=
                {(DmaKeepWidth/PixelsInBeat){1'b1}};
            end
          end
          buffer[0].valid <= 1'b1;
          buffer[0].data  <= i_axis_comb.tdata.high;
        end
      end

      if (buffer[0].valid && buffer[1].valid && i_axis_out_reg.tready) begin
        i_axis_out_reg.tvalid     <= 1'b1;
        i_axis_out_reg.tdata.high <= buffer[1].data;
        i_axis_out_reg.tdata.low  <= buffer[0].data;
        buffer[0].valid <= 1'b0;
        buffer[1].valid <= 1'b0;
        if (was_eol) begin
          i_axis_out_reg.tuser.vid.eol <= 1'b1;
          was_eol <= '0;
        end
        if (was_last) begin
          i_axis_out_reg.tlast <= 1'b1;
          i_axis_out_reg.tuser.vid.eof <= 1'b1;
          was_last <= 1'b0;
          first_done <= 1'b0;
        end
      end else if (buffer[0].valid && !buffer[1].valid &&
                   was_last && i_axis_out_reg.tready) begin
        i_axis_out_reg.tvalid        <= 1'b1;
        i_axis_out_reg.tdata.high    <= '0;
        i_axis_out_reg.tdata.low     <= buffer[0].data;
        i_axis_out_reg.tkeep[DmaKeepWidth-1:DmaKeepWidth/2] <= '0;
        i_axis_out_reg.tlast         <= 1'b1;
        i_axis_out_reg.tuser.vid.eof <= 1'b1;
        i_axis_out_reg.tuser.vid.eol <= was_eol;
        was_eol                      <= 1'b0;
        was_last                     <= 1'b0;
        first_done                   <= 1'b0;
        buffer[0].valid              <= 1'b0;
      end
    end
  end

  axis_reg_handshake #(
      .RegType  ( OutputRegType   )
  ) u_out_reg_slice (
      .clk      ( clk             ),
      .rst      ( rst             ),
      .axis_in  ( i_axis_out_reg  ),
      .axis_out ( i_axis_out      )
  );

endmodule : vid_to_dma_data_width_conv
