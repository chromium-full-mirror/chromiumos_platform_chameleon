/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module hdmi_audio_adapter #(
    parameter int MaxRingBytes  = 524228,
    parameter int MaxChannelNum = 8,
    parameter int I2sDmaId      = axis_to_aximm_pkg::kIdFbDpSstAud,
    parameter int LpcmDataWidth = 256,
    parameter int DataOutWidth  = 128
) (
    input  logic                                     clk,
    input  logic                                     rst,
    input  logic                                     aud_clk,
    input  logic                                     tmds_valid,
    input  logic [hdmi_rx_pkg::TmdsMeasureWidth-1:0] tmds_measure,
    hdmi_audio_i.agent                               i_hdmi_audio,
    output i2s_pkg::irq_source_t                     irq,
    axil_i.subordinate                               i_aud_hdmi_csr,
    aximm_i.manager                                  i_aud_hdmi_dma
);

  import i2s_registers_pkg::*;
  import axis_to_aximm_pkg::meta_t;
  import hdmi_rx_pkg::*;
  import aud_rx_pkg::SingleChannelWidth;

  /* Register definitions */
  rx_enable_t       rx_enable;
  rx_base_addr_t    rx_base_addr;
  rx_buffer_size_t  rx_buffer_size;
  rx_producer_idx_t rx_prod_idx;
  rx_consumer_idx_t rx_cons_idx;
  error_t           error;
  soft_reset_t      soft_reset;
  config_const_t    config_const;
  sampling_freq_t   sampling_freq;
  hdmi_n_t          n;
  hdmi_cts_t        cts;
  hdmi_tmds_clk_t   tmds_clk;
  /* Unused signals for registers */
  tx_enable_t       tx_enable;
  tx_base_addr_t    tx_base_addr;
  tx_buffer_size_t  tx_buffer_size;
  tx_producer_idx_t tx_prod_idx;
  tx_consumer_idx_t tx_cons_idx;
  counter_t                     tx_clk_counter;
  counter_t                     tx_ws_counter;
  counter_t [MaxChannelNum-1:0] rx_clk_counter;
  counter_t [MaxChannelNum-1:0] rx_ws_counter;
  irq_t             tx_irq_meta;
  irq_t             rx_irq_meta;
  irq_ro_t          tx_irq_const;
  irq_ro_t          rx_irq_const;

  /* Interfaces and signals */
  hdmi_audio_i i_hdmi_audio_cdc();
  axis_i  #(.DataWidth(LpcmDataWidth), .WordWidth(8))   i_hdmi_aud_axis();
  axis_i  #(.DataWidth(LpcmDataWidth), .WordWidth(8))   i_hdmi_aud_axis_fifo();
  axis_i  #(.DataWidth(DataOutWidth),  .WordWidth(8))   i_hdmi_aud_axis_width();
  axis_i #(.DataWidth(DataOutWidth), .WordWidth(8),
           .UserWidth(gaxilite_pkg::AddrWidth)) i_hdmi_aud_axis_write();
  axis_i #(.DataWidth(DataOutWidth), .WordWidth(8), .Tuser(meta_t)) i_hdmi_aud_write();
  axis_i #(.DataWidth(1),            .WordWidth(1), .Tuser(meta_t)) i_read_rq_dummy();
  axis_i #(.DataWidth(1),            .WordWidth(1), .UserWidth(1))  i_read_resp_dummy();
  logic write_done;
  logic fifo_error;
  logic [3:0] fifo_data_cnt;
  logic rx_pulse;

  /* Interrupts */
  i2s_irq u_rx_irq (
      .clk   ( clk          ),
      .rst   ( rst          ),
      .pulse ( rx_pulse     ),
      .meta  ( rx_irq_meta  ),
      .irq   ( irq.rx       )
  );

  always_ff @(posedge clk) begin : configuration
    if (rst || soft_reset.rx) begin
      config_const <= '0;
      sampling_freq <= '0;
      error <= '0;
      n <= '0;
      cts <= '0;
      tmds_clk <= '0;
    end else begin
      if (i_hdmi_audio_cdc.de) begin
        config_const.channel_num <= i_hdmi_audio_cdc.infoframe.channel_count + 1;
        sampling_freq.sf <= i_hdmi_audio_cdc.infoframe.sampling_frequency;
        n <= i_hdmi_audio_cdc.n;
        cts <= i_hdmi_audio_cdc.cts;
      end
      if (rx_enable && (!i_hdmi_aud_axis.tready ||
                        i_hdmi_audio_cdc.infoframe.format_type != kLpcm)) begin
        error.overflow <= 1'b1;
      end
      if (tmds_valid) begin
        tmds_clk <= tmds_measure;
      end
    end
  end

  /* TX interrupt is not used in i2s_it */
  assign irq.tx = 1'b0;
  assign tx_irq_const = '0;
  assign rx_irq_const.rsvd = '0;
  assign rx_irq_const.bytes_to_fetch = '0;
  assign rx_irq_const.frame_size = 8;

  i2s_registers #(
      .DataWidth            ( gaxilite_pkg::DataWidth   )
  ) u_i2s_registers (
      .clk                  ( clk                       ),
      .rst                  ( rst                       ),
      .i_axi_lite           ( i_aud_hdmi_csr            ),
      .tx_enable            ( tx_enable                 ),
      .tx_base_addr         ( tx_base_addr              ),
      .tx_buffer_size       ( tx_buffer_size            ),
      .tx_prod_idx          ( tx_prod_idx               ),
      .tx_cons_idx          ( tx_cons_idx               ),
      .rx_enable            ( rx_enable                 ),
      .rx_base_addr         ( rx_base_addr              ),
      .rx_buffer_size       ( rx_buffer_size            ),
      .rx_prod_idx          ( rx_prod_idx               ),
      .rx_cons_idx          ( rx_cons_idx               ),
      .error                ( error                     ),
      .soft_reset           ( soft_reset                ),
      .config_const         ( config_const              ),
      .tx_clk_counter       ( tx_clk_counter            ),
      .tx_ws_counter        ( tx_ws_counter             ),
      .rx_clk_counter       ( rx_clk_counter[0]         ),
      .rx_ws_counter        ( rx_ws_counter[0]          ),
      .tx_irq_meta          ( tx_irq_meta               ),
      .rx_irq_meta          ( rx_irq_meta               ),
      .tx_irq_const         ( tx_irq_const              ),
      .rx_irq_const         ( rx_irq_const              ),
      .sampling_freq        ( sampling_freq             ),
      .n                    ( n                         ),
      .cts                  ( cts                       ),
      .tmds_clk             ( tmds_clk                  )
  );

  typedef struct packed {
    logic [NCTSWidth-1:0] n;
    logic [NCTSWidth-1:0] cts;
    logic [LpcmDataWidth-1:0] data;
    hdmi_audio_infoframe_t infoframe;
  } hdmi_aud_t;

  hdmi_aud_t hdmi_aud_cdc_in;
  hdmi_aud_t hdmi_aud_cdc_out;

  always_comb begin
    hdmi_aud_cdc_in.n         = i_hdmi_audio.n;
    hdmi_aud_cdc_in.cts       = i_hdmi_audio.cts;
    hdmi_aud_cdc_in.data      = i_hdmi_audio.data;
    hdmi_aud_cdc_in.infoframe = i_hdmi_audio.infoframe;
  end

  cdc_synchronizer_data #(
      .Width ( $bits(hdmi_aud_t) )
  ) u_cdc_aud_hdmi (
      .in_clk    ( aud_clk               ),
      .out_clk   ( clk                   ),
      .in_valid  ( i_hdmi_audio.de       ),
      .in_data   ( hdmi_aud_cdc_in       ),
      .out_valid ( i_hdmi_audio_cdc.de   ),
      .out_data  ( hdmi_aud_cdc_out      )
  );

  always_comb begin
    i_hdmi_audio_cdc.n         = hdmi_aud_cdc_out.n;
    i_hdmi_audio_cdc.cts       = hdmi_aud_cdc_out.cts;
    i_hdmi_audio_cdc.data      = hdmi_aud_cdc_out.data;
    i_hdmi_audio_cdc.infoframe = hdmi_aud_cdc_out.infoframe;
  end

  logic [SingleChannelWidth-1:0] shift_and_zero_buf;
  always_comb begin
    i_hdmi_aud_axis.tvalid = i_hdmi_audio_cdc.de;
    i_hdmi_aud_axis.tdata = '0;
    i_hdmi_aud_axis.tdata[31:8] = i_hdmi_audio_cdc.data[23:0];
    i_hdmi_aud_axis.tdata[63:40] = i_hdmi_audio_cdc.data[55:32];
    // HDMI IP process metadata in each channel bits [31:24] which we ignore in software
    // Remove metadata before going further and shift accordingly
    for (int i = 0; i < LpcmDataWidth/SingleChannelWidth; i++) begin : zero_meta_and_shift
      shift_and_zero_buf = i_hdmi_audio_cdc.data[(i+1)*(SingleChannelWidth)-1-:32];
      shift_and_zero_buf <<= 8;
      i_hdmi_aud_axis.tdata[(i+1)*(SingleChannelWidth)-1-:32] = shift_and_zero_buf;
    end
    i_hdmi_aud_axis.tkeep  = '1;
    i_hdmi_aud_axis.tuser  = '0;
    i_hdmi_aud_axis.tlast  = 1'b1;
  end

  axis_fifo #(
      .FifoDepth      ( 8 ),
      .DataCntWidth   ( 4 ),
      .OutputRegType  ( reg_handshake_pkg::kPayload )
  ) u_aud_hdmi_fifo (
      .clk        ( clk                  ),
      .rst        ( rst || soft_reset.rx ),
      .axis_in    ( i_hdmi_aud_axis      ),
      .axis_out   ( i_hdmi_aud_axis_fifo ),
      .error      ( fifo_error           ),
      .data_count ( fifo_data_cnt        )
  );

  axis_data_width_converter u_data_width_conv (
      .clk        ( clk                   ),
      .rst        ( rst || soft_reset.rx  ),
      .i_axis_in  ( i_hdmi_aud_axis_fifo  ),
      .i_axis_out ( i_hdmi_aud_axis_width )
  );

  dma_data_writer #(
      .MaxRingBytes         ( MaxRingBytes               ),
      .AddressWidth         ( gaxilite_pkg::AddrWidth    ),
      .OutputRegType        ( reg_handshake_pkg::kBypass )
  ) u_dma_data_writer (
      .clk                  ( clk                        ),
      .rst                  ( rst || soft_reset.rx       ),
      .i_data_in            ( i_hdmi_aud_axis_width      ),
      .i_data_out           ( i_hdmi_aud_axis_write      ),
      .write_done           ( write_done                 ),
      .ring_enable          ( rx_enable                  ),
      .ring_size            ( rx_buffer_size             ),
      .ring_address         ( rx_base_addr               ),
      .ring_cons_idx        ( rx_cons_idx                ),
      .ring_prod_idx        ( rx_prod_idx                ),
      .ring_prod_idx_rst    ( '0                         ),
      .ring_prod_idx_change ( rx_pulse                   )
  );

  always_comb begin
    i_hdmi_aud_write.tvalid           = i_hdmi_aud_axis_write.tvalid;
    i_hdmi_aud_axis_write.tready      = i_hdmi_aud_write.tready;
    i_hdmi_aud_write.tdata            = i_hdmi_aud_axis_write.tdata;
    i_hdmi_aud_write.tkeep            = i_hdmi_aud_axis_write.tkeep;
    i_hdmi_aud_write.tuser.addr       = i_hdmi_aud_axis_write.tuser;
    i_hdmi_aud_write.tuser.data_size  = DataOutWidth/8;
    i_hdmi_aud_write.tlast            = 1'b1;
  end

  // TX path is unused.
  // Do not set requests, do not accept potential responses.
  assign i_read_rq_dummy.tvalid = 1'b0;
  assign i_read_resp_dummy.tready = 1'b0;
  assign i_read_rq_dummy.tdata = '0;
  assign i_read_rq_dummy.tkeep = '0;
  assign i_read_rq_dummy.tuser = '0;
  assign i_read_rq_dummy.tlast = '0;

  axis_to_aximm #(
      .Id           ( I2sDmaId            ),
      .DataWidth    ( DataOutWidth        )
  ) u_axis_to_aximm (
      .clk          ( clk                 ),
      .rst          ( rst                 ),
      .i_write      ( i_hdmi_aud_write    ),
      .write_done   ( write_done          ),
      .i_read_rq    ( i_read_rq_dummy     ),
      .i_read_resp  ( i_read_resp_dummy   ),
      .i_mm         ( i_aud_hdmi_dma      )
  );

endmodule : hdmi_audio_adapter
