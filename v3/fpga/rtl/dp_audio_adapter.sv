/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module dp_audio_adapter #(
    parameter int MaxRingBytes  = 524228,
    parameter int MaxChannelNum = 8,
    parameter int LpcmDataWidth = 256,
    parameter int DataOutWidth  = 128
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  aud_clk,
    input  logic                  write_done,
    dp_audio_i.agent              i_dp_audio,
    output i2s_pkg::irq_source_t  irq,
    axil_i.subordinate            i_aud_dp_csr,
    axis_i.host                   i_aud_dp_write
);

  import i2s_registers_pkg::*;
  import axis_to_aximm_pkg::meta_t;
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
  dp_audio_i i_dp_audio_cdc();
  axis_i  #(.DataWidth(LpcmDataWidth), .WordWidth(8))   i_dp_aud_axis();
  axis_i  #(.DataWidth(LpcmDataWidth), .WordWidth(8))   i_dp_aud_axis_fifo();
  axis_i  #(.DataWidth(DataOutWidth),  .WordWidth(8))   i_dp_aud_axis_width();
  axis_i #(.DataWidth(DataOutWidth), .WordWidth(8),
           .UserWidth(gaxilite_pkg::AddrWidth)) i_dp_aud_axis_write();
  axis_i #(.DataWidth(DataOutWidth), .WordWidth(8), .Tuser(meta_t)) i_dp_aud_write();
  axis_i #(.DataWidth(1),            .WordWidth(1), .Tuser(meta_t)) i_read_rq_dummy();
  axis_i #(.DataWidth(1),            .WordWidth(1), .UserWidth(1))  i_read_resp_dummy();
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
      error = '0;
    end else begin
      if (i_dp_audio_cdc.valid) begin
        config_const.channel_num <= i_dp_audio_cdc.infoframe.channel_count + 1;
        sampling_freq.sf <= i_dp_audio_cdc.infoframe.sampling_frequency;
      end
      if (!i_dp_aud_axis.tready) begin
        error.overflow <= 1'b1;
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
      .i_axi_lite           ( i_aud_dp_csr              ),
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
      .sampling_freq        ( sampling_freq             )
  );

  typedef struct packed {
    logic mute;
    logic [LpcmDataWidth-1:0] lpcm_data;
    dp_rx_pkg::dp_infoframe_t infoframe;
  } dp_aud_t;

  dp_aud_t dp_aud_cdc_in;
  dp_aud_t dp_aud_cdc_out;

  always_comb begin
    dp_aud_cdc_in.mute      = i_dp_audio.mute;
    dp_aud_cdc_in.infoframe = i_dp_audio.infoframe;
    dp_aud_cdc_in.lpcm_data = i_dp_audio.lpcm_data;
  end

  cdc_synchronizer_data #(
      .Width ( $bits(dp_aud_t) )
  ) u_cdc_aud_dp (
      .in_clk    ( aud_clk               ),
      .out_clk   ( clk                   ),
      .in_valid  ( i_dp_audio.valid      ),
      .in_data   ( dp_aud_cdc_in         ),
      .out_valid ( i_dp_audio_cdc.valid  ),
      .out_data  ( dp_aud_cdc_out        )
  );

  always_comb begin
    i_dp_audio_cdc.mute      = dp_aud_cdc_out.mute;
    i_dp_audio_cdc.infoframe = dp_aud_cdc_out.infoframe;
    i_dp_audio_cdc.lpcm_data = dp_aud_cdc_out.lpcm_data;
  end

  logic [SingleChannelWidth-1:0] shift_and_zero_buf;
  always_comb begin
    i_dp_aud_axis.tvalid = i_dp_audio_cdc.valid && ~i_dp_audio_cdc.mute;
    i_dp_aud_axis.tdata  = i_dp_audio_cdc.lpcm_data;
    // DisplayPort IP process metadata in each channel bits [31:24] which we ignore in software
    // Remove metadata before going further and shift accordingly
    for (int i = 0; i < LpcmDataWidth/SingleChannelWidth; i++) begin : zero_meta_and_shift
      shift_and_zero_buf = i_dp_audio_cdc.lpcm_data[(i+1)*(SingleChannelWidth)-1-:32];
      shift_and_zero_buf <<= 8;
      i_dp_aud_axis.tdata[(i+1)*(SingleChannelWidth)-1-:32] = shift_and_zero_buf;
    end
    i_dp_aud_axis.tkeep  = '1;
    i_dp_aud_axis.tuser  = '0;
    i_dp_aud_axis.tlast  = 1'b1;
  end

  axis_fifo #(
      .FifoDepth      ( 8 ),
      .DataCntWidth   ( 4 ),
      .OutputRegType  ( reg_handshake_pkg::kBypass )
  ) u_aud_dp_fifo (
      .clk        ( clk                  ),
      .rst        ( rst || soft_reset.rx ),
      .axis_in    ( i_dp_aud_axis        ),
      .axis_out   ( i_dp_aud_axis_fifo   ),
      .error      ( fifo_error           ),
      .data_count ( fifo_data_cnt        )
  );

  axis_data_width_converter #(
    .OutputRegType ( reg_handshake_pkg::kPayloadCtrl )
  ) u_data_width_conv (
      .clk        ( clk                  ),
      .rst        ( rst || soft_reset.rx ),
      .i_axis_in  ( i_dp_aud_axis_fifo   ),
      .i_axis_out ( i_dp_aud_axis_width  )
  );

  dma_data_writer #(
      .MaxRingBytes         ( MaxRingBytes               ),
      .AddressWidth         ( gaxilite_pkg::AddrWidth    ),
      .OutputRegType        ( reg_handshake_pkg::kBypass )
  ) u_dma_data_writer (
      .clk                  ( clk                        ),
      .rst                  ( rst || soft_reset.rx       ),
      .i_data_in            ( i_dp_aud_axis_width        ),
      .i_data_out           ( i_dp_aud_axis_write        ),
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
    i_aud_dp_write.tvalid           = i_dp_aud_axis_write.tvalid;
    i_dp_aud_axis_write.tready      = i_aud_dp_write.tready;
    i_aud_dp_write.tdata            = i_dp_aud_axis_write.tdata;
    i_aud_dp_write.tkeep            = i_dp_aud_axis_write.tkeep;
    i_aud_dp_write.tuser.addr       = i_dp_aud_axis_write.tuser;
    i_aud_dp_write.tuser.data_size  = DataOutWidth/8;
    i_aud_dp_write.tlast            = 1'b1;
  end

endmodule : dp_audio_adapter
