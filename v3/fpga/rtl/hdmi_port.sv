/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module hdmi_port (
    input  logic                                    clk,
    input  logic                                    rst,

    input  logic                                    vid_clk,
    input  logic                                    aud_clk,

    output port_registers_pkg::vid_status_t         vid_status,

    input logic                                     tmds_valid,
    input logic [hdmi_rx_pkg::TmdsMeasureWidth-1:0] tmds_measure,
    output logic [3:0]                              fb_irq,
    output i2s_pkg::irq_source_t                    aud_irq,
    hdmi_data_i.agent                               i_hdmi_vid,
    hdmi_audio_i.agent                              i_hdmi_audio,
    axil_i.subordinate                              i_fb_csr,
    aximm_i.manager                                 i_fb_hdmi_dma,
    axil_i.subordinate                              i_aud_hdmi_csr,
    aximm_i.manager                                 i_aud_hdmi_dma
);

  import vid_rx_pkg::*;
  import framebuffer_pkg::*;

  logic rst_local;

  framebuffer_registers_pkg::dim_t           height;
  framebuffer_registers_pkg::dim_t           width;
  framebuffer_registers_pkg::enable_t        en;
  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_a;
  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_b;
  framebuffer_registers_pkg::buffer_size_t   buffer_size;
  framebuffer_registers_pkg::rst_t           reset_from_register;
  framebuffer_registers_pkg::errors_t        errors;
  framebuffer_registers_pkg::errors_t        errors_dma;
  framebuffer_registers_pkg::dma_format_t    dma_format;
  logic [BufferCount-1:0]                    buffer_write;

  logic [3:0]                                fb_irq_eof;
  logic [3:0]                                fb_irq_status;
  logic [1:0]                                burst_eof_hit;
  logic                                      burst_overflow;

  axis_i #(.DataWidth(DmaDataWidth),
           .WordWidth(8),
           .Tuser(vid_meta_t)) i_hdmi_dma();
  axis_i  #(.DataWidth(framebuffer_pkg::PixelsInBeat*framebuffer_pkg::PixelDataWidth),
            .WordWidth(framebuffer_pkg::PixelDataWidth),
            .Tuser(fb_adapter_meta_t)) i_adapter_out();

  /* Framebuffer HDMI interfaces */
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(framebuffer_pkg::fb_dma_meta_t))       i_axis_hdmi_dma();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_hdmi_dma_burst();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_hdmi_dma_rq_dummy();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_hdmi_dma_resp_dummy();

  assign vid_status.sink_type = kSinkHdmi;
  assign rst_local = rst | reset_from_register.rst;
  assign errors.adapter_error = vid_status.overflow[0] | burst_overflow;
  assign errors.dma_fifo_overflow = errors_dma.dma_fifo_overflow;

  always_comb begin
    i_adapter_out.tvalid           = i_hdmi_dma.tvalid;
    i_hdmi_dma.tready              = i_adapter_out.tready;
    i_adapter_out.tdata            = i_hdmi_dma.tdata;
    i_adapter_out.tkeep            = '1;
    i_adapter_out.tuser.sof        = i_hdmi_dma.tuser.vid.sof;
    i_adapter_out.tuser.sol        = i_hdmi_dma.tuser.vid.sol;
    i_adapter_out.tuser.eof        = i_hdmi_dma.tuser.vid.eof;
    i_adapter_out.tuser.eol        = i_hdmi_dma.tuser.vid.eol;
    i_adapter_out.tuser.data_valid = i_hdmi_dma.tuser.vid.data_valid;
    i_adapter_out.tlast            = i_hdmi_dma.tlast;
  end

  always_comb begin
    fb_irq_eof = '0;
    fb_irq_eof[kIrqBuff0] = burst_eof_hit[0];
    fb_irq_eof[kIrqBuff1] = burst_eof_hit[1];
    fb_irq = fb_irq_status | fb_irq_eof;
  end

  always_comb begin
    i_axis_hdmi_dma_rq_dummy.tvalid = 1'b0;
    i_axis_hdmi_dma_resp_dummy.tready = 1'b0;
    i_axis_hdmi_dma_rq_dummy.tdata = '0;
    i_axis_hdmi_dma_rq_dummy.tkeep = '0;
    i_axis_hdmi_dma_rq_dummy.tuser = '0;
    i_axis_hdmi_dma_rq_dummy.tlast = '0;
  end

  hdmi_to_dma_adapter u_hdmi_to_dma_adapter (
      .clk           ( clk                    ),
      .rst           ( rst_local              ),
      .vid_clk       ( vid_clk                ),
      .vid_format    ( dma_format.format      ),
      .overflow      ( vid_status.overflow[0] ),
      .i_hdmi_vid    ( i_hdmi_vid             ),
      .i_hdmi_dma    ( i_hdmi_dma             )
  );

  hdmi_audio_adapter u_hdmi_audio_adapter (
      .clk             ( clk                        ),
      .rst             ( rst                        ),
      .aud_clk         ( aud_clk                    ),
      .tmds_valid      ( tmds_valid                 ),
      .tmds_measure    ( tmds_measure               ),
      .i_hdmi_audio    ( i_hdmi_audio               ),
      .irq             ( aud_irq                    ),
      .i_aud_hdmi_csr  ( i_aud_hdmi_csr             ),
      .i_aud_hdmi_dma  ( i_aud_hdmi_dma             )
  );

  framebuffer_registers u_fb_hdmi_regs (
      .clk                  ( clk                     ),
      .rst                  ( rst                     ),
      .height               ( height                  ),
      .width                ( width                   ),
      .en                   ( en                      ),
      .buffer_addr_a        ( buffer_addr_a           ),
      .buffer_addr_b        ( buffer_addr_b           ),
      .buffer_size          ( buffer_size             ),
      .reset_from_register  ( reset_from_register     ),
      .errors               ( errors                  ),
      .io_color             (                         ),
      .data_rate            (                         ),
      .pixel_mode           (                         ),
      .sync_polarity        (                         ),
      .dma_format           ( dma_format              ),
      .buffer_write         ( buffer_write            ),
      .i_axi_lite           ( i_fb_csr                )
  );

  framebuffer_dma u_fb_hdmi_dma (
      .clk            ( clk               ),
      .rst            ( rst_local         ),
      .irq            ( fb_irq_status     ),
      .height         ( height            ),
      .width          ( width             ),
      .en             ( en                ),
      .buffer_addr_a  ( buffer_addr_a     ),
      .buffer_addr_b  ( buffer_addr_b     ),
      .buffer_write   ( buffer_write      ),
      .buffer_size    ( buffer_size       ),
      .errors         ( errors_dma        ),
      .dma_format     ( dma_format        ),
      .i_data_in      ( i_adapter_out     ),
      .i_data_out     ( i_axis_hdmi_dma   )
  );


  axis_burst_adapter u_burst_adapter (
      .clk            ( clk                     ),
      .reset          ( rst                     ),
      .max_burst_size ( 6'd16                   ),
      .overflow       ( burst_overflow          ),
      .eof_hit        ( burst_eof_hit           ),
      .i_axis_in      ( i_axis_hdmi_dma         ),
      .i_axis_out     ( i_axis_hdmi_dma_burst   )
  );

  axis_to_aximm #(
      .Id           ( axis_to_aximm_pkg::kIdFbDpSst  ),
      .DataWidth    ( DmaDataWidth                   )
  ) u_fb0_axis_to_aximm (
      .clk          ( clk                           ),
      .rst          ( rst                           ),
      .i_write      ( i_axis_hdmi_dma_burst         ),
      .write_done   (                               ),
      .i_read_rq    ( i_axis_hdmi_dma_rq_dummy      ),
      .i_read_resp  ( i_axis_hdmi_dma_resp_dummy    ),
      .i_mm         ( i_fb_hdmi_dma                 )
  );

endmodule : hdmi_port
