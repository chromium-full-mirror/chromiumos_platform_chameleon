/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module dp_port #(
    parameter bit MstSupport = 1,
    parameter int MstCount = MstSupport ? vid_rx_pkg::MstCount : 1
) (
    input  logic                            clk,
    input  logic                            rst,

    output port_registers_pkg::vid_status_t vid_status,

    output logic [MstCount-1:0][3:0]        fb_irq,
    output i2s_pkg::irq_source_t            aud_irq[MstCount-1:0],
    dp_video_i.agent                        i_dp_vid[MstCount-1:0],
    dp_audio_i.agent                        i_dp_audio[MstCount-1:0],
    axil_i.subordinate                      i_fb_csr[MstCount-1:0],
    aximm_i.manager                         i_fb_dp_dma[MstCount-1:0],
    axil_i.subordinate                      i_aud_dp_csr[MstCount-1:0],
    aximm_i.manager                         i_aud_dp_dma
);

  import vid_rx_pkg::*;
  import framebuffer_pkg::*;

  logic rst_local[MstCount-1:0];

  framebuffer_registers_pkg::dim_t           height[MstCount-1:0];
  framebuffer_registers_pkg::dim_t           width[MstCount-1:0];
  framebuffer_registers_pkg::enable_t        en[MstCount-1:0];
  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_a[MstCount-1:0];
  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_b[MstCount-1:0];
  framebuffer_registers_pkg::buffer_size_t   buffer_size[MstCount-1:0];
  framebuffer_registers_pkg::rst_t           reset_from_register[MstCount-1:0];
  framebuffer_registers_pkg::errors_t        errors[MstCount-1:0];
  framebuffer_registers_pkg::errors_t        errors_adapter[MstCount-1:0];
  framebuffer_registers_pkg::errors_t        errors_dma[MstCount-1:0];
  framebuffer_registers_pkg::dma_format_t    dma_format[MstCount-1:0];
  logic [BufferCount-1:0]                    buffer_write[MstCount-1:0];

  logic [MstCount-1:0][3:0]                  fb_irq_eof;
  logic [MstCount-1:0][3:0]                  fb_irq_status;
  logic [MstCount-1:0][1:0]                  burst_eof_hit;
  logic [MstCount-1:0]                       burst_overflow;
  logic [MstCount-1:0]                       aud_write_done;
  logic                                      write_done;

  axis_i #(.DataWidth(DmaDataWidth),
           .WordWidth(8),
           .Tuser(vid_meta_t)) i_dp_dma[MstCount-1:0]();

  axis_i  #(.DataWidth(framebuffer_pkg::PixelsInBeat*framebuffer_pkg::PixelDataWidth),
            .WordWidth(framebuffer_pkg::PixelDataWidth),
            .Tuser(fb_adapter_meta_t)) i_adapter_out[MstCount-1:0]();

  /* Framebuffer DisplayPort interfaces */
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(framebuffer_pkg::fb_dma_meta_t))       i_axis_dp_dma[MstCount-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_dp_dma_burst[MstCount-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_dp_dma_02[MstCount/2-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_dp_dma_13[MstCount/2-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_dp_dma_ic_out[MstCount-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_dp_dma_rq_dummy[MstCount-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_axis_dp_dma_resp_dummy[MstCount-1:0]();

  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_aud_dp_write[MstCount-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_aud_dp_reg[MstCount-1:0]();
  axis_i  #(.DataWidth(DmaDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))            i_aud_dp_write_out();
  axis_i #(.DataWidth(1),            .WordWidth(1),
           .Tuser(axis_to_aximm_pkg::meta_t))             i_aud_read_rq_dummy();
  axis_i #(.DataWidth(1),            .WordWidth(1),
           .UserWidth(1))                                 i_aud_read_resp_dummy();
  logic [1:0] ch_id;

  assign vid_status.sink_type = MstSupport ? kSinkDpMst : kSinkDpSst;

  assign i_aud_read_rq_dummy.tvalid = 1'b0;
  assign i_aud_read_resp_dummy.tready = 1'b0;
  assign i_aud_read_rq_dummy.tdata = '0;
  assign i_aud_read_rq_dummy.tkeep = '0;
  assign i_aud_read_rq_dummy.tuser = '0;
  assign i_aud_read_rq_dummy.tlast = '0;

  generate
  if (MstSupport) begin
    for (genvar i = 0; i < MstCount; i++) begin
      always @(posedge clk) begin
        rst_local[i] <= rst | reset_from_register[i].rst;
      end

      assign errors_adapter[i].adapter_error = vid_status.overflow[i] | burst_overflow[i];
      assign errors[i] = errors_adapter[i] | errors_dma[i];

      always_comb begin
        i_adapter_out[i].tvalid           = i_dp_dma[i].tvalid;
        i_dp_dma[i].tready                = i_adapter_out[i].tready;
        i_adapter_out[i].tdata            = i_dp_dma[i].tdata;
        i_adapter_out[i].tkeep            = '1; // TODO(ka): Align framebuffer keep!
        i_adapter_out[i].tuser.sof        = i_dp_dma[i].tuser.vid.sof;
        i_adapter_out[i].tuser.sol        = i_dp_dma[i].tuser.vid.sol;
        i_adapter_out[i].tuser.eof        = i_dp_dma[i].tuser.vid.eof;
        i_adapter_out[i].tuser.eol        = i_dp_dma[i].tuser.vid.eol;
        i_adapter_out[i].tuser.data_valid = i_dp_dma[i].tuser.vid.data_valid;
        i_adapter_out[i].tlast            = i_dp_dma[i].tlast;
      end

      always_comb begin
        fb_irq_eof[i] = '0;
        fb_irq_eof[i][kIrqBuff0] = burst_eof_hit[i][0];
        fb_irq_eof[i][kIrqBuff1] = burst_eof_hit[i][1];
        fb_irq[i] = fb_irq_status[i] | fb_irq_eof[i];
      end

      dp_to_dma_adapter u_dp_to_dma_adapter (
          .clk           ( clk                      ),
          .rst           ( rst_local[i]             ),
          .vid_format    ( dma_format[i].format     ),
          .overflow      ( vid_status.overflow[i]   ),
          .i_dp_vid      ( i_dp_vid[i]              ),
          .i_dp_dma      ( i_dp_dma[i]              )
      );

      dp_audio_adapter u_dp_audio_adapter (
          .clk             ( clk                        ),
          .rst             ( rst                        ),
          .aud_clk         ( i_dp_vid[i].clk            ),
          .write_done      ( aud_write_done[i]          ),
          .i_dp_audio      ( i_dp_audio[i]              ),
          .irq             ( aud_irq[i]                 ),
          .i_aud_dp_csr    ( i_aud_dp_csr[i]            ),
          .i_aud_dp_write  ( i_aud_dp_write[i]          )
      );

      axis_reg_handshake #(
          .RegType ( reg_handshake_pkg::kPayloadCtrl )
      ) u_aud_dp_reg (
          .clk      ( clk ),
          .rst      ( rst ),
          .axis_in  ( i_aud_dp_write[i] ),
          .axis_out ( i_aud_dp_reg[i]   )
      );

      framebuffer_registers u_fb_dp_regs (
          .clk                  ( clk                     ),
          .rst                  ( rst                     ),
          .height               ( height[i]               ),
          .width                ( width[i]                ),
          .en                   ( en[i]                   ),
          .buffer_addr_a        ( buffer_addr_a[i]        ),
          .buffer_addr_b        ( buffer_addr_b[i]        ),
          .buffer_size          ( buffer_size[i]          ),
          .reset_from_register  ( reset_from_register[i]  ),
          .errors               ( errors[i]               ),
          .io_color             (                         ),
          .data_rate            (                         ),
          .pixel_mode           (                         ),
          .sync_polarity        (                         ),
          .dma_format           ( dma_format[i]           ),
          .buffer_write         ( buffer_write[i]         ),
          .i_axi_lite           ( i_fb_csr[i]             )
      );

      framebuffer_dma u_fb_dp_dma (
          .clk            ( clk               ),
          .rst            ( rst_local[i]      ),
          .irq            ( fb_irq_status[i]  ),
          .height         ( height[i]         ),
          .width          ( width[i]          ),
          .en             ( en[i]             ),
          .buffer_addr_a  ( buffer_addr_a[i]  ),
          .buffer_addr_b  ( buffer_addr_b[i]  ),
          .buffer_write   ( buffer_write[i]   ),
          .buffer_size    ( buffer_size[i]    ),
          .errors         ( errors_dma[i]     ),
          .dma_format     ( dma_format[i]     ),
          .i_data_in      ( i_adapter_out[i]  ),
          .i_data_out     ( i_axis_dp_dma[i]  )
      );

      axis_burst_adapter u_burst_adapter (
          .clk            ( clk                     ),
          .reset          ( rst                     ),
          .max_burst_size ( 6'd16                   ),
          .overflow       ( burst_overflow[i]       ),
          .eof_hit        ( burst_eof_hit[i]        ),
          .i_axis_in      ( i_axis_dp_dma[i]        ),
          .i_axis_out     ( i_axis_dp_dma_burst[i]  )
      );
    end

    axis_interconnect_wrapper #(
        .InputNum ( 4 )
    ) u_ic_4x1_aud (
        .clk        ( clk                 ),
        .rst        ( rst                 ),
        .ch_id      ( ch_id               ),
        .i_axis_in  ( i_aud_dp_reg        ),
        .i_axis_out ( i_aud_dp_write_out  )
    );

    always @(posedge clk) begin
      aud_write_done <= '0;
      if (i_aud_dp_write_out.tvalid && i_aud_dp_write_out.tready) begin
        aud_write_done[ch_id] <= 1'b1;
      end
    end

    axis_to_aximm #(
        .Id           ( MstSupport ? axis_to_aximm_pkg::kIdFbDpMstAud :
                                     axis_to_aximm_pkg::kIdFbDpSstAud),
        .DataWidth    ( DmaDataWidth                   )
    ) u_aud_axis_to_aximm (
        .clk          ( clk                   ),
        .rst          ( rst                   ),
        .i_write      ( i_aud_dp_write_out    ),
        .write_done   ( write_done            ),
        .i_read_rq    ( i_aud_read_rq_dummy   ),
        .i_read_resp  ( i_aud_read_resp_dummy ),
        .i_mm         ( i_aud_dp_dma          )
    );

    always_comb begin : assign_02_13_ic_input
      i_axis_dp_dma_02[0].tvalid = i_axis_dp_dma_burst[0].tvalid;
      i_axis_dp_dma_burst[0].tready = i_axis_dp_dma_02[0].tready;
      i_axis_dp_dma_02[0].tdata  = i_axis_dp_dma_burst[0].tdata;
      i_axis_dp_dma_02[0].tkeep  = i_axis_dp_dma_burst[0].tkeep;
      i_axis_dp_dma_02[0].tuser  = i_axis_dp_dma_burst[0].tuser;
      i_axis_dp_dma_02[0].tlast  = i_axis_dp_dma_burst[0].tlast;

      i_axis_dp_dma_02[1].tvalid = i_axis_dp_dma_burst[2].tvalid;
      i_axis_dp_dma_burst[2].tready = i_axis_dp_dma_02[1].tready;
      i_axis_dp_dma_02[1].tdata  = i_axis_dp_dma_burst[2].tdata;
      i_axis_dp_dma_02[1].tkeep  = i_axis_dp_dma_burst[2].tkeep;
      i_axis_dp_dma_02[1].tuser  = i_axis_dp_dma_burst[2].tuser;
      i_axis_dp_dma_02[1].tlast  = i_axis_dp_dma_burst[2].tlast;

      i_axis_dp_dma_13[0].tvalid = i_axis_dp_dma_burst[1].tvalid;
      i_axis_dp_dma_burst[1].tready = i_axis_dp_dma_13[0].tready;
      i_axis_dp_dma_13[0].tdata  = i_axis_dp_dma_burst[1].tdata;
      i_axis_dp_dma_13[0].tkeep  = i_axis_dp_dma_burst[1].tkeep;
      i_axis_dp_dma_13[0].tuser  = i_axis_dp_dma_burst[1].tuser;
      i_axis_dp_dma_13[0].tlast  = i_axis_dp_dma_burst[1].tlast;

      i_axis_dp_dma_13[1].tvalid = i_axis_dp_dma_burst[3].tvalid;
      i_axis_dp_dma_burst[3].tready = i_axis_dp_dma_13[1].tready;
      i_axis_dp_dma_13[1].tdata  = i_axis_dp_dma_burst[3].tdata;
      i_axis_dp_dma_13[1].tkeep  = i_axis_dp_dma_burst[3].tkeep;
      i_axis_dp_dma_13[1].tuser  = i_axis_dp_dma_burst[3].tuser;
      i_axis_dp_dma_13[1].tlast  = i_axis_dp_dma_burst[3].tlast;
    end

    axis_interconnect_wrapper #(
        .InputNum ( 2 )
    ) u_ic_2x1_02 (
        .clk        ( clk ),
        .rst        ( rst ),
        .i_axis_in  ( i_axis_dp_dma_02 ),
        .i_axis_out ( i_axis_dp_dma_ic_out[0] )
    );

    axis_interconnect_wrapper #(
        .InputNum ( 2 )
    ) u_ic_2x1_13 (
        .clk        ( clk ),
        .rst        ( rst ),
        .i_axis_in  ( i_axis_dp_dma_13 ),
        .i_axis_out ( i_axis_dp_dma_ic_out[1] )
    );

    for (genvar i = 0; i < MstCount; i++) begin
      assign i_axis_dp_dma_rq_dummy[i].tvalid = 1'b0;
      assign i_axis_dp_dma_resp_dummy[i].tready = 1'b0;
      assign i_axis_dp_dma_rq_dummy[i].tdata = '0;
      assign i_axis_dp_dma_rq_dummy[i].tkeep = '0;
      assign i_axis_dp_dma_rq_dummy[i].tuser = '0;
      assign i_axis_dp_dma_rq_dummy[i].tlast = '0;

      axis_to_aximm #(
          .Id           ( axis_to_aximm_pkg::kIdFbDpMst02 + i ),
          .DataWidth    ( DmaDataWidth                        )
      ) u_fb_axis_to_aximm (
          .clk          ( clk                                 ),
          .rst          ( rst                                 ),
          .i_write      ( i_axis_dp_dma_ic_out[i]             ),
          .write_done   (                                     ),
          .i_read_rq    ( i_axis_dp_dma_rq_dummy[i]           ),
          .i_read_resp  ( i_axis_dp_dma_resp_dummy[i]         ),
          .i_mm         ( i_fb_dp_dma[i]                      )
      );
    end
  end else begin
    always @(posedge clk) begin
      rst_local[0] <= rst | reset_from_register[0].rst;
    end

    assign errors_adapter[0].adapter_error = vid_status.overflow[0] | burst_overflow[0];
    assign errors[0] = errors_adapter[0] | errors_dma[0];

    always_comb begin
      i_adapter_out[0].tvalid           = i_dp_dma[0].tvalid;
      i_dp_dma[0].tready                = i_adapter_out[0].tready;
      i_adapter_out[0].tdata            = i_dp_dma[0].tdata;
      i_adapter_out[0].tkeep            = '1; // TODO(ka): Align framebuffer keep!
      i_adapter_out[0].tuser.sof        = i_dp_dma[0].tuser.vid.sof;
      i_adapter_out[0].tuser.sol        = i_dp_dma[0].tuser.vid.sol;
      i_adapter_out[0].tuser.eof        = i_dp_dma[0].tuser.vid.eof;
      i_adapter_out[0].tuser.eol        = i_dp_dma[0].tuser.vid.eol;
      i_adapter_out[0].tuser.data_valid = i_dp_dma[0].tuser.vid.data_valid;
      i_adapter_out[0].tlast            = i_dp_dma[0].tlast;
    end

    always_comb begin
      fb_irq_eof[0] = '0;
      fb_irq_eof[0][kIrqBuff0] = burst_eof_hit[0][0];
      fb_irq_eof[0][kIrqBuff1] = burst_eof_hit[0][1];
      fb_irq[0] = fb_irq_status[0] | fb_irq_eof[0];
    end

    always_comb begin
      i_axis_dp_dma_rq_dummy[0].tvalid = 1'b0;
      i_axis_dp_dma_resp_dummy[0].tready = 1'b0;
      i_axis_dp_dma_rq_dummy[0].tdata = '0;
      i_axis_dp_dma_rq_dummy[0].tkeep = '0;
      i_axis_dp_dma_rq_dummy[0].tuser = '0;
      i_axis_dp_dma_rq_dummy[0].tlast = '0;
    end

    dp_to_dma_adapter u_dp_to_dma_adapter (
        .clk           ( clk                      ),
        .rst           ( rst_local[0]             ),
        .vid_format    ( dma_format[0].format     ),
        .overflow      ( vid_status.overflow[0]   ),
        .i_dp_vid      ( i_dp_vid[0]              ),
        .i_dp_dma      ( i_dp_dma[0]              )
    );

    dp_audio_adapter u_dp_audio_adapter (
        .clk             ( clk                        ),
        .rst             ( rst                        ),
        .aud_clk         ( i_dp_vid[0].clk            ),
        .write_done      ( write_done                 ),
        .i_dp_audio      ( i_dp_audio[0]              ),
        .irq             ( aud_irq[0]                 ),
        .i_aud_dp_csr    ( i_aud_dp_csr[0]            ),
        .i_aud_dp_write  ( i_aud_dp_write_out         )
    );

    axis_to_aximm #(
        .Id           ( axis_to_aximm_pkg::kIdFbDpSstAud ),
        .DataWidth    ( DmaDataWidth                     )
    ) u_aud_axis_to_aximm (
        .clk          ( clk                   ),
        .rst          ( rst                   ),
        .i_write      ( i_aud_dp_write_out    ),
        .write_done   ( write_done            ),
        .i_read_rq    ( i_aud_read_rq_dummy   ),
        .i_read_resp  ( i_aud_read_resp_dummy ),
        .i_mm         ( i_aud_dp_dma          )
    );

    framebuffer_registers u_fb_dp_regs (
        .clk                  ( clk                     ),
        .rst                  ( rst                     ),
        .height               ( height[0]               ),
        .width                ( width[0]                ),
        .en                   ( en[0]                   ),
        .buffer_addr_a        ( buffer_addr_a[0]        ),
        .buffer_addr_b        ( buffer_addr_b[0]        ),
        .buffer_size          ( buffer_size[0]          ),
        .reset_from_register  ( reset_from_register[0]  ),
        .errors               ( errors[0]               ),
        .io_color             (                         ),
        .data_rate            (                         ),
        .pixel_mode           (                         ),
        .sync_polarity        (                         ),
        .dma_format           ( dma_format[0]           ),
        .buffer_write         ( buffer_write[0]         ),
        .i_axi_lite           ( i_fb_csr[0]             )
    );

    framebuffer_dma u_fb_dp_dma (
        .clk            ( clk               ),
        .rst            ( rst_local[0]      ),
        .irq            ( fb_irq_status[0]  ),
        .height         ( height[0]         ),
        .width          ( width[0]          ),
        .en             ( en[0]             ),
        .buffer_addr_a  ( buffer_addr_a[0]  ),
        .buffer_addr_b  ( buffer_addr_b[0]  ),
        .buffer_write   ( buffer_write[0]   ),
        .buffer_size    ( buffer_size[0]    ),
        .errors         ( errors_dma[0]     ),
        .dma_format     ( dma_format[0]     ),
        .i_data_in      ( i_adapter_out[0]  ),
        .i_data_out     ( i_axis_dp_dma[0]  )
    );

    axis_burst_adapter u_burst_adapter (
        .clk            ( clk                     ),
        .reset          ( rst                     ),
        .max_burst_size ( 6'd16                   ),
        .overflow       ( burst_overflow[0]       ),
        .eof_hit        ( burst_eof_hit[0]        ),
        .i_axis_in      ( i_axis_dp_dma[0]        ),
        .i_axis_out     ( i_axis_dp_dma_burst[0]  )
    );

    axis_to_aximm #(
        .Id           ( axis_to_aximm_pkg::kIdFbDpSst ),
        .DataWidth    ( DmaDataWidth                  )
    ) u_fb0_axis_to_aximm (
        .clk          ( clk                           ),
        .rst          ( rst                           ),
        .i_write      ( i_axis_dp_dma_burst[0]        ),
        .write_done   (                               ),
        .i_read_rq    ( i_axis_dp_dma_rq_dummy[0]     ),
        .i_read_resp  ( i_axis_dp_dma_resp_dummy[0]   ),
        .i_mm         ( i_fb_dp_dma[0]                )
    );
    end
  endgenerate
endmodule : dp_port
