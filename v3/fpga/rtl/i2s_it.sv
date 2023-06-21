/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module i2s_it #(
    parameter int I2sDmaId          = axis_to_aximm_pkg::kIdIt68051Dma,
    parameter int MaxRingBytes      = 524288,
    parameter int AddressWidth      = gaxilite_pkg::AddrWidth,
    parameter int DataOutWidth      = 128,
    parameter int ItChannelNum      = 6,
    // only to ease timing requirements
    parameter reg_handshake_pkg::reg_type_e TimingRegType = reg_handshake_pkg::kBypass
) (
    input  logic                  clk,
    input  logic                  rst,

    axil_i.subordinate                  i_axi_lite,

    i2s_if.receiver               i_i2s_rx[ItChannelNum-1:0],
    aximm_i.manager                i_data_out,

    output i2s_pkg::irq_source_t  irq
);

  import i2s_registers_pkg::*;
  import i2s_pkg::sample_t;
  import axis_to_aximm_pkg::meta_t;

  localparam int DataOutBytes = DataOutWidth/8;
  localparam int DataOutBytesWidth = $clog2(DataOutBytes);

  /* Interface definitions */
  axis_i #(.DataWidth($bits(sample_t)),
           .WordWidth($bits(sample_t))) i_i2s_samples[ItChannelNum]();
  axis_i #(.DataWidth($bits(sample_t)),
           .WordWidth($bits(sample_t))) i_serialized_samples();
  axis_i #(.DataWidth($bits(sample_t)),
           .WordWidth(8),
           .UserWidth(AddressWidth))    i_data_writer_out();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth(8),
           .Tuser(meta_t))             i_write_keep();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth(8),
           .Tuser(meta_t))             i_write_rq_data();
  axis_i #(.DataWidth(1),
           .WordWidth(1),
           .Tuser(meta_t))             i_read_rq_dummy();
  axis_i #(.DataWidth(1),
           .WordWidth(1),
           .UserWidth(1))               i_read_resp_dummy();

  /* Signals */
  logic write_done;
  /* Register definitions */
  rx_enable_t       rx_enable;
  rx_base_addr_t    rx_base_addr;
  rx_buffer_size_t  rx_buffer_size;
  rx_producer_idx_t rx_prod_idx;
  rx_consumer_idx_t rx_cons_idx;
  error_t           error;
  soft_reset_t      soft_reset;
  config_const_t    config_const;
  /* Unused signals for registers */
  tx_enable_t       tx_enable;
  tx_base_addr_t    tx_base_addr;
  tx_buffer_size_t  tx_buffer_size;
  tx_producer_idx_t tx_prod_idx;
  tx_consumer_idx_t tx_cons_idx;
  counter_t                    tx_clk_counter;
  counter_t                    tx_ws_counter;
  counter_t [ItChannelNum-1:0] rx_clk_counter;
  counter_t [ItChannelNum-1:0] rx_ws_counter;
  irq_t             tx_irq_meta;
  irq_t             rx_irq_meta;
  irq_ro_t          tx_irq_const;
  irq_ro_t          rx_irq_const;

  /* Helper signals for integration */
  logic [ItChannelNum-1:0] channel_overflow;

  /* Interrupts */
  logic rx_pulse;

  i2s_irq u_rx_irq (
      .clk   ( clk          ),
      .rst   ( rst          ),
      .pulse ( rx_pulse     ),
      .meta  ( rx_irq_meta  ),
      .irq   ( irq.rx       )
  );

  /* TX interrupt is not used in i2s_it */
  assign irq.tx = 1'b0;

  assign tx_irq_const = '0;
  assign rx_irq_const.rsvd = '0;
  assign rx_irq_const.bytes_to_fetch = '0;
  assign rx_irq_const.frame_size = $bits(sample_t)/8; // value in bytes

  assign config_const.rsvd = '0;
  assign config_const.channel_num = ItChannelNum;
  assign error.rsvd = '0;
  assign error.overflow = |channel_overflow;

  assign tx_cons_idx = '0;
  i2s_registers #(
      .DataWidth            ( gaxilite_pkg::DataWidth   )
  ) u_i2s_registers (
      .clk                  ( clk                       ),
      .rst                  ( rst                       ),
      .i_axi_lite           ( i_axi_lite                ),
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
      .rx_irq_const         ( rx_irq_const              )
  );

  assign tx_clk_counter = '0;
  assign tx_ws_counter = '0;

  for (genvar i = 0; i < ItChannelNum; i++) begin : gen_i2s_it68051_sink
    i2s_rx #(
      .CounterWidth         ( CounterWidth          )
    )  u_i2s_rx (
        .clk                ( clk                   ),
        .rst                ( rst || soft_reset.rx  ),
        .i_i2s_in           ( i_i2s_rx[i]           ),
        .i_axis_samples_out ( i_i2s_samples[i]      ),
        .overflow           ( channel_overflow[i]   ),
        .clk_counter        ( rx_clk_counter[i]     ),
        .ws_counter         ( rx_ws_counter[i]      )
    );
  end

  axis_serializer #(
      .InputNum       ( ItChannelNum                    ),
      .InputRegType   ( reg_handshake_pkg::kPayloadCtrl )
  ) u_i2s_it68051_serializer (
      .clk            ( clk                             ),
      .rst            ( rst || soft_reset.rx            ),
      .i_axis_in      ( i_i2s_samples                   ),
      .i_axis_out     ( i_serialized_samples            )
  );

  dma_data_writer #(
      .MaxRingBytes         ( MaxRingBytes               ),
      .AddressWidth         ( AddressWidth               ),
      .OutputRegType        ( reg_handshake_pkg::kBypass )
  ) u_dma_data_writer (
      .clk                  ( clk                        ),
      .rst                  ( rst || soft_reset.rx       ),
      .i_data_in            ( i_serialized_samples       ),
      .i_data_out           ( i_data_writer_out          ),
      .write_done           ( write_done                 ),
      .ring_enable          ( rx_enable                  ),
      .ring_size            ( rx_buffer_size             ),
      .ring_address         ( rx_base_addr               ),
      .ring_cons_idx        ( rx_cons_idx                ),
      .ring_prod_idx        ( rx_prod_idx                ),
      .ring_prod_idx_rst    ( '0                         ),
      .ring_prod_idx_change ( rx_pulse                   )
  );

  always_comb begin : convert_to_output_width
    i_write_keep.tvalid           = i_data_writer_out.tvalid;
    i_data_writer_out.tready      = i_write_keep.tready;
    i_write_keep.tdata            = {i_data_writer_out.tdata, i_data_writer_out.tdata};

    if (i_data_writer_out.tuser[DataOutBytesWidth-1:0] == 0) begin : mask_valid_data
      i_write_keep.tkeep          = {8'h00, i_data_writer_out.tkeep};
    end else begin
      i_write_keep.tkeep          = {i_data_writer_out.tkeep, 8'h00};
    end

    i_write_keep.tuser.addr       = i_data_writer_out.tuser;
    i_write_keep.tuser.data_size  = $bits(sample_t)/8;
    i_write_keep.tlast            = 1'b1;
  end

  axis_reg_handshake #(
      .RegType  ( TimingRegType         )
  ) u_timing_axis_reg_handshake (
      .clk      ( clk                   ),
      .rst      ( rst || soft_reset.rx  ),
      .axis_in  ( i_write_keep          ),
      .axis_out ( i_write_rq_data       )
  );

  // On IT68051 the TX path is unused.
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
      .i_write      ( i_write_rq_data     ),
      .write_done   ( write_done          ),
      .i_read_rq    ( i_read_rq_dummy     ),
      .i_read_resp  ( i_read_resp_dummy   ),
      .i_mm         ( i_data_out          )
  );

endmodule : i2s_it
