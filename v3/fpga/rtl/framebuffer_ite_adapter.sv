/*
 * Copyright 2021-2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module responsible for translation of ITE interface on pixel_clk
 * to clk domain on AXIStream interface.
 */

module framebuffer_ite_adapter (
    input  logic clk,
    input  logic rst,

    input  logic pixel_clk,
    input  framebuffer_pkg::io_map_t pixel_data,

    input  framebuffer_registers_pkg::color_depth_e     io_color_depth,
    input  framebuffer_registers_pkg::data_rate_e       data_rate,
    input  framebuffer_registers_pkg::sync_polarity_t   sync_polarity,
    input  framebuffer_registers_pkg::pixel_mode_e      pixel_mode,
    output framebuffer_registers_pkg::errors_t          errors,

    axis_i.host   i_data_out
);
  import framebuffer_pkg::*;
  import framebuffer_registers_pkg::*;

  pixel_word_t pixel_repacked, pixel_map, pixel_out;

  logic any_de_pre_align, any_de_pre_align_d;
  logic align_req, align_req_d;
  io_map_t pixel_data_d, pixel_data_aligned, pixel_data_inv;

  logic inv_polarity_hsync, inv_polarity_vsync;

  logic any_de;
  logic any_vsync, any_vsync_d;
  logic any_hsync, any_hsync_d;
  logic pixel_data_inv_valid;

  io_map_t     cdc_data_pre_map;
  logic        cdc_valid;
  logic        cdc_valid_pre_map;
  logic        cdc_any_de;
  logic        cdc_any_vsync, cdc_any_vsync_d, cdc_any_vsync_d2;
  logic        cdc_any_hsync, cdc_any_hsync_d, cdc_any_hsync_d2;

  logic [1:0] pixel_valid_idx;
  logic pixel_valid, pixel_shift_reinit, pixel_shift_clear;
  logic [PixelsInBeat-1:0] pixel_shift;

  //-----------------------------------------------------------------------------------------------
  // Align low and high part of data after DDR if required
  assign any_de_pre_align = pixel_data.ddio.high.ctrl.de || pixel_data.ddio.low.ctrl.de;

  always_comb begin
    if (!any_de_pre_align_d) begin
      align_req = pixel_data.ddio.high.ctrl.de && !pixel_data.ddio.low.ctrl.de;
    end else begin
      align_req = align_req_d;
    end
  end

  always_ff @(posedge pixel_clk) begin
    any_de_pre_align_d <= any_de_pre_align;
    pixel_data_d <= pixel_data;
    align_req_d <= align_req;
  end

  always_ff @(posedge pixel_clk) begin
    if (align_req) begin
      // if align requied we need to shift low and high part in terms of two clocks cycles
      pixel_data_aligned.ddio.high = pixel_data.ddio.low;
      pixel_data_aligned.ddio.low  = pixel_data_d.ddio.high;
    end else begin
      pixel_data_aligned.ddio.high = pixel_data.ddio.high;
      pixel_data_aligned.ddio.low  = pixel_data.ddio.low;
    end
  end

  //-----------------------------------------------------------------------------------------------
  // Detect the polarity of the VSYNC/HSYNC signals

  always @(posedge pixel_clk) begin
    if (pixel_data_aligned.ddio.high.ctrl.de) begin
      if (pixel_data_aligned.ddio.high.ctrl.hsync) begin
        inv_polarity_hsync <= 1'b1;
      end else begin
        inv_polarity_hsync <= 1'b0;
      end

      if (pixel_data_aligned.ddio.high.ctrl.vsync) begin
        inv_polarity_vsync <= 1'b1;
      end else begin
        inv_polarity_vsync <= 1'b0;
      end
    end
  end

  always_comb begin
    pixel_data_inv = pixel_data_aligned;
    if (sync_polarity.state == kDetect) begin
      if (inv_polarity_vsync) begin
        pixel_data_inv.ddio.high.ctrl.vsync = ~pixel_data_aligned.ddio.high.ctrl.vsync;
        pixel_data_inv.ddio.low.ctrl.vsync  = ~pixel_data_aligned.ddio.low.ctrl.vsync;
      end
      if (inv_polarity_hsync) begin
        pixel_data_inv.ddio.high.ctrl.hsync = ~pixel_data_aligned.ddio.high.ctrl.hsync;
        pixel_data_inv.ddio.low.ctrl.hsync  = ~pixel_data_aligned.ddio.low.ctrl.hsync;
      end
    end else begin // kForce
      if (sync_polarity.vsync_inv) begin
        pixel_data_inv.ddio.high.ctrl.vsync = ~pixel_data_aligned.ddio.high.ctrl.vsync;
        pixel_data_inv.ddio.low.ctrl.vsync  = ~pixel_data_aligned.ddio.low.ctrl.vsync;
      end
      if (sync_polarity.hsync_inv) begin
        pixel_data_inv.ddio.high.ctrl.hsync = ~pixel_data_aligned.ddio.high.ctrl.hsync;
        pixel_data_inv.ddio.low.ctrl.hsync  = ~pixel_data_aligned.ddio.low.ctrl.hsync;
      end
    end
  end

  //-----------------------------------------------------------------------------------------------
  // Synchronize data to correct clock domain
  assign any_de    = pixel_data_inv.ddio.high.ctrl.de || pixel_data_inv.ddio.low.ctrl.de;
  assign any_vsync = pixel_data_inv.ddio.high.ctrl.vsync ||
                     pixel_data_inv.ddio.low.ctrl.vsync;
  assign any_hsync = pixel_data_inv.ddio.high.ctrl.hsync ||
                     pixel_data_inv.ddio.low.ctrl.hsync;

  always_ff @(posedge pixel_clk) begin
    any_hsync_d <= any_hsync;
    any_vsync_d <= any_vsync;
  end

  // we are only interested in the valid pixels or sync signals
  assign pixel_data_inv_valid = any_de || (any_vsync && !any_vsync_d) ||
                                          (any_hsync && !any_hsync_d);

  cdc_synchronizer_data #(
      .Width ( $bits(io_map_t) )
  ) input_pixels_cdc (
      .in_clk    ( pixel_clk             ),
      .out_clk   ( clk                   ),
      .in_valid  ( pixel_data_inv_valid  ),
      .in_data   ( pixel_data_inv        ),
      .out_valid ( cdc_valid_pre_map     ),
      .out_data  ( cdc_data_pre_map      )
  );

  //-----------------------------------------------------------------------------------------------
  // Map data based on mode
  framebuffer_mode_mapper u_mode_mapper (
      .color_depth ( io_color_depth      ),
      .input_word  ( cdc_data_pre_map    ),
      .ddr         ( data_rate           ),
      .dpm         ( pixel_mode          ),
      .repacked    ( pixel_map           )
  );

  assign cdc_any_de    = cdc_data_pre_map.ddio.high.ctrl.de    || cdc_data_pre_map.ddio.low.ctrl.de;
  assign cdc_any_vsync = cdc_data_pre_map.ddio.high.ctrl.vsync || cdc_data_pre_map.ddio.low.ctrl.vsync;
  assign cdc_any_hsync = cdc_data_pre_map.ddio.high.ctrl.hsync || cdc_data_pre_map.ddio.low.ctrl.hsync;

  always_ff @(posedge clk) begin
    cdc_valid <= cdc_valid_pre_map;
    cdc_any_vsync_d <= cdc_any_vsync;
    cdc_any_hsync_d <= cdc_any_hsync;
    cdc_any_vsync_d2 <= cdc_any_vsync_d;
    cdc_any_hsync_d2 <= cdc_any_hsync_d;
  end

  always_ff @(posedge clk) begin
      if (cdc_valid_pre_map && cdc_any_de) begin
        unique case({data_rate, pixel_mode})
          {kDdr, kDpm} : begin
                         pixel_out.pixel <= {pixel_map.pixel[3], pixel_map.pixel[1],
                                             pixel_map.pixel[2], pixel_map.pixel[0]};
                         end
          {kSdr, kDpm} : begin
                         pixel_out.pixel <= {pixel_map.pixel[2],pixel_map.pixel[0],
                                             pixel_out.pixel[PixelsInBeat-1:2]};
                         end
          {kDdr, kSpm} : begin
                         pixel_out.pixel <= {pixel_map.pixel[1:0],
                                             pixel_out.pixel[PixelsInBeat-1:2]};
                         end
          {kSdr, kSpm} : begin
                         pixel_out.pixel <= {pixel_map.pixel[0],
                                             pixel_out.pixel[PixelsInBeat-1:1]};
                         end
        endcase
      end
  end

  always_comb begin
    if ((data_rate == kDdr) && (pixel_mode == kDpm)) pixel_valid_idx = 0;
    else if ((data_rate == kDdr) || (pixel_mode == kDpm)) pixel_valid_idx = 1;
    else pixel_valid_idx = 3;
  end

  always_comb begin
    pixel_valid        = pixel_shift[pixel_valid_idx];
    pixel_shift_reinit = (pixel_shift == 4'b0) || pixel_valid;
    pixel_shift_clear  = (!cdc_any_vsync_d && cdc_any_vsync) || pixel_valid;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pixel_shift <= '0;
    end else begin
      if (cdc_valid_pre_map && cdc_any_de) begin
        if (pixel_shift_reinit) begin
          pixel_shift <= 4'd1;
        end else begin
          pixel_shift <= pixel_shift << 1;
        end
      end else if (pixel_shift_clear) begin
        pixel_shift <= '0;
      end
    end
  end

  always_comb begin : output_always_ready
    i_data_out.tvalid = cdc_valid;
    i_data_out.tdata  = pixel_out.pixel;
    i_data_out.tuser.sol = '0;
    i_data_out.tuser.sof = '0;
    i_data_out.tuser.eol = !cdc_any_hsync_d2 && cdc_any_hsync_d;
    i_data_out.tuser.eof = !cdc_any_vsync_d2 && cdc_any_vsync_d;
    i_data_out.tuser.data_valid = pixel_valid;
    i_data_out.tkeep = 4'hf;
    i_data_out.tlast = 1'b1;
  end

  always @(posedge clk) begin
    if (rst) begin
      errors <= '0;
    end else begin
      if (i_data_out.tvalid && ~i_data_out.tready) begin
        errors.adapter_error <= 1'b1;
      end
    end
  end

endmodule : framebuffer_ite_adapter
