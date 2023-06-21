/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module framebuffer_registers #(
    parameter int AddrWidth = framebuffer_registers_pkg::AddrWidth,
    parameter int DataWidth = gaxilite_pkg::DataWidth
) (
    input  logic                                      clk,
    input  logic                                      rst,
    input  framebuffer_registers_pkg::dim_t           height,
    input  framebuffer_registers_pkg::dim_t           width,
    output framebuffer_registers_pkg::enable_t        en,
    output framebuffer_registers_pkg::buffer_addr_t   buffer_addr_a,
    output framebuffer_registers_pkg::buffer_addr_t   buffer_addr_b,
    output logic [framebuffer_pkg::BufferCount-1:0]   buffer_write,
    output framebuffer_registers_pkg::buffer_size_t   buffer_size,
    output framebuffer_registers_pkg::rst_t           reset_from_register,
    input  framebuffer_registers_pkg::errors_t        errors,
    output framebuffer_registers_pkg::color_depth_e   io_color,
    output framebuffer_registers_pkg::data_rate_e     data_rate,
    output framebuffer_registers_pkg::pixel_mode_e    pixel_mode,
    output framebuffer_registers_pkg::sync_polarity_t sync_polarity,
    output framebuffer_registers_pkg::dma_format_t    dma_format,
    axil_i.subordinate                                i_axi_lite
);

  import gaxilite_pkg::*;
  import framebuffer_registers_pkg::*;

  logic [AddrWidth-1:0]           axil_addr;
  logic                           axil_wr_en;
  logic [DataWidth-1:0]           axil_wr_data;
  resp_t                          axil_wr_resp;
  logic                           axil_rd_resp_en;
  logic [AddrWidth-1:0]           axil_rd_resp_addr;
  logic [DataWidth-1:0]           axil_rd_resp_data;
  resp_t                          axil_rd_resp;

  axi_lite_manager #(
    .RegType        ( reg_handshake_pkg::kPayloadCtrl ), // only to ease timing requirements
    .RrespDelay     ( 2             ), // delay Rresp by this number of cycles, to ease timing
                                         // on output
    .RrespFifoDepth ( 8             )  // store up to 8 Rresp messages
  ) u_axi_lite_manager (
    .clk          ( clk               ),
    .rst          ( rst               ),
    .axi          ( i_axi_lite        ),
    .addr         ( axil_addr         ),
    .wr_en        ( axil_wr_en        ),
    .wr_data      ( axil_wr_data      ),
    .wr_resp      ( axil_wr_resp      ),
    .rd_resp_en   ( axil_rd_resp_en   ),
    .rd_resp_addr ( axil_rd_resp_addr ),
    .rd_resp_data ( axil_rd_resp_data ),
    .rd_resp      ( axil_rd_resp      )
  );

  ////////////////////////////////////////////////////////////////////////////
  // Handle AXI Lite write request/response
  always_ff @(posedge clk) begin
    buffer_write <= '0;
    if (axil_wr_en) begin
      axil_wr_resp <= kOkay;
      unique case (axil_addr)
        AddrEn:             en                    <= enable_t'(axil_wr_data);
        AddrBufferA: begin
          buffer_addr_a                           <= buffer_addr_t'(axil_wr_data);
          buffer_write[kBufferA]                  <= 1'b1;
        end
        AddrBufferB: begin
          buffer_addr_b                           <= buffer_addr_t'(axil_wr_data);
          buffer_write[kBufferB]                  <= 1'b1;
        end
        AddrBufferSize:     buffer_size           <= buffer_size_t'(axil_wr_data);
        AddrReset:          reset_from_register   <= rst_t'(axil_wr_data);
        AddrIOColor:        io_color              <= color_depth_e'(axil_wr_data);
        AddrIODataRate:     data_rate             <= data_rate_e'(axil_wr_data);
        AddrIOPixelMode:    pixel_mode            <= pixel_mode_e'(axil_wr_data);
        AddrSyncPolarity:   sync_polarity         <= sync_polarity_t'(axil_wr_data);
        AddrDmaFormat:      dma_format            <= dma_format_t'(axil_wr_data);
        default:            axil_wr_resp          <= kDecErr;
      endcase
    end

    if (rst | reset_from_register.rst) begin
      axil_wr_resp        <= kOkay;
      en                  <= '0;
      buffer_addr_a       <= 32'hdeadbeef;
      buffer_addr_b       <= 32'hdeadbeef;
      buffer_size         <= '0;
      reset_from_register <= '0;
      io_color            <= k24b;
      data_rate           <= kSdr;
      pixel_mode          <= kSpm;
      sync_polarity       <= '0;
      dma_format.format   <= vid_rx_pkg::k8bpcPad;
    end

  end

  ////////////////////////////////////////////////////////////////////////////
  // Handle AXI Lite read response
  always_ff @(posedge clk) begin
    if (axil_rd_resp_en) begin
      axil_rd_resp <= kOkay;
      axil_rd_resp_data <= '0;
      unique case (axil_rd_resp_addr) inside
        AddrDimHeight:    axil_rd_resp_data <= height;
        AddrDimWidth:     axil_rd_resp_data <= width;
        AddrEn:           axil_rd_resp_data <= en;
        AddrBufferA:      axil_rd_resp_data <= buffer_addr_a;
        AddrBufferB:      axil_rd_resp_data <= buffer_addr_b;
        AddrBufferSize:   axil_rd_resp_data <= buffer_size;
        AddrReset:        axil_rd_resp_data <= reset_from_register;
        AddrErrorStatus:  axil_rd_resp_data <= errors;
        AddrIOColor:      axil_rd_resp_data <= io_color;
        AddrIODataRate:   axil_rd_resp_data <= data_rate;
        AddrIOPixelMode:  axil_rd_resp_data <= pixel_mode;
        AddrSyncPolarity: axil_rd_resp_data <= sync_polarity;
        AddrDmaFormat:    axil_rd_resp_data <= dma_format;
        AddrVersion:      axil_rd_resp_data <= FramebufferVersion;
        default: begin
          axil_rd_resp      <= kOkay;
          axil_rd_resp_data <= WrongAddrReadValue;
        end
      endcase
    end

    if (rst) begin
      axil_rd_resp_data <= '0;
      axil_rd_resp <= kOkay;
    end
  end

endmodule : framebuffer_registers

