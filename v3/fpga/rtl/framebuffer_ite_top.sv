/*
 * Copyright 2021-2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Parallel pixel data input with an output to a DMA framebuffer
// + set of registers to control it.
//
// Module is able to receive input stream from IT68051 in various configurations
// Supported configurations:
//   - Single Pixel Mode (SPM) or Dual Pixel Mode (DPM)
//   - Single Data Rate (SDR) or Dual Data Rate (DDR)
//   - RGB 24bit or RGB 30bit
// any combination of above confiturations are valid
// Please check IT68051 datasheet (V0.9.2) Table 5-1 (p.12) for video formats in each configuration
//
// On other side module generates one beat AXIS writes transactions where at tdata four consecutive
// pixels are placed. Each pixel is extended to 32bit width. Tuser holds memory address for these
// four pixels calculated based on pixel index and registers configuration.
// Frames pixels are saved to ping-pong buffer (addresses of buffers are configurated via AXILite
// interface). At the End Of Frame (EOF) appropriate flag is send by tuser signal

module framebuffer_ite_top (
    input  logic                      clk,
    input  logic                      rst,

    input  logic                      pixel_clk,
    input  framebuffer_pkg::io_map_t  pixel_data,

    axis_i.host                       i_fb_dma,
    axil_i.subordinate                      i_fb_csr,
    output logic [3:0]                irq
);
  import framebuffer_pkg::*;

  framebuffer_registers_pkg::dim_t           height;
  framebuffer_registers_pkg::dim_t           width;
  framebuffer_registers_pkg::enable_t        en;
  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_a;
  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_b;
  framebuffer_registers_pkg::buffer_size_t   buffer_size;
  framebuffer_registers_pkg::rst_t           reset_from_register;
  framebuffer_registers_pkg::errors_t        errors;
  framebuffer_registers_pkg::errors_t        errors_adapter;
  framebuffer_registers_pkg::errors_t        errors_dma;
  framebuffer_registers_pkg::color_depth_e   io_color_depth;
  framebuffer_registers_pkg::data_rate_e     data_rate;
  framebuffer_registers_pkg::pixel_mode_e    pixel_mode;
  framebuffer_registers_pkg::sync_polarity_t sync_polarity;
  framebuffer_registers_pkg::dma_format_t    dma_format;
  logic [BufferCount-1:0]                    buffer_write;

  axis_i  #(.DataWidth(PixelsInBeat*PixelDataWidth),
            .WordWidth(PixelDataWidth),
            .Tuser(fb_adapter_meta_t)) i_adapter_out();

  logic rst_local;

  assign rst_local = rst | reset_from_register.rst;
  assign errors = errors_adapter | errors_dma;

  framebuffer_registers u_fb_regs (
      .clk                  ( clk                  ),
      .rst                  ( rst                  ),
      .height               ( height               ),
      .width                ( width                ),
      .en                   ( en                   ),
      .buffer_addr_a        ( buffer_addr_a        ),
      .buffer_addr_b        ( buffer_addr_b        ),
      .buffer_size          ( buffer_size          ),
      .reset_from_register  ( reset_from_register  ),
      .errors               ( errors               ),
      .io_color             ( io_color_depth       ),
      .data_rate            ( data_rate            ),
      .pixel_mode           ( pixel_mode           ),
      .sync_polarity        ( sync_polarity        ),
      .dma_format           ( dma_format           ),
      .buffer_write         ( buffer_write         ),
      .i_axi_lite           ( i_fb_csr             )
  );

  framebuffer_ite_adapter u_fb_ite_adapter (
    .clk            ( clk             ),
    .rst            ( rst_local       ),
    .pixel_clk      ( pixel_clk       ),
    .pixel_data     ( pixel_data      ),
    .io_color_depth ( io_color_depth  ),
    .data_rate      ( data_rate       ),
    .sync_polarity  ( sync_polarity   ),
    .pixel_mode     ( pixel_mode      ),
    .errors         ( errors_adapter  ),
    .i_data_out     ( i_adapter_out   )
  );

  framebuffer_dma u_fb_dma (
    .clk            ( clk             ),
    .rst            ( rst_local       ),
    .irq            ( irq             ),
    .height         ( height          ),
    .width          ( width           ),
    .en             ( en              ),
    .buffer_addr_a  ( buffer_addr_a   ),
    .buffer_addr_b  ( buffer_addr_b   ),
    .buffer_write   ( buffer_write    ),
    .buffer_size    ( buffer_size     ),
    .errors         ( errors_dma      ),
    .dma_format     ( dma_format      ),
    .i_data_in      ( i_adapter_out   ),
    .i_data_out     ( i_fb_dma        )
  );

endmodule : framebuffer_ite_top
