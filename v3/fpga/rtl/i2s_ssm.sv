/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module i2s_ssm #(
    parameter int I2sDmaId          = axis_to_aximm_pkg::kIdSsm2603Dma,
    parameter int MaxRingBytes      = 524288,
    parameter int AddressWidth      = gaxilite_pkg::AddrWidth,
    parameter int DataOutWidth      = 128,
    parameter int TxBytesToFetch    = 64,
    // only to ease timing requirements
    parameter reg_handshake_pkg::reg_type_e RxTimingRegType = reg_handshake_pkg::kBypass
) (
    input  logic                  clk,
    input  logic                  rst,

    axil_i.subordinate                  i_axi_lite,

    i2s_if.receiver               i_i2s_rx,
    i2s_if.transmitter            i_i2s_tx,
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
           .WordWidth($bits(sample_t))) i_i2s_rx_samples();
  axis_i #(.DataWidth($bits(sample_t)),
           .WordWidth(8),
           .UserWidth(AddressWidth))    i_data_writer_out();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth(8),
           .Tuser(meta_t))             i_write_keep();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth(8),
           .Tuser(meta_t))             i_write_rq_data();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth(8),
           .Tuser(meta_t))             i_read_rq();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth($bits(sample_t))) i_read_resp();
  axis_i #(.DataWidth(DataOutWidth),
           .WordWidth($bits(sample_t))) i_read_resp_fifo();
  axis_i #(.DataWidth($bits(sample_t)),
           .WordWidth($bits(sample_t))) i_read_resp_data();

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
  counter_t         tx_clk_counter;
  counter_t         tx_ws_counter;
  counter_t         rx_clk_counter;
  counter_t         rx_ws_counter;
  irq_t             tx_irq_meta;
  irq_t             rx_irq_meta;
  irq_ro_t          tx_irq_const;
  irq_ro_t          rx_irq_const;

  /* Helper signals for integration */
  logic rx_channel_overflow;

  /* Interrupts */
  logic rx_pulse, tx_pulse;

  i2s_irq u_rx_irq (
      .clk   ( clk                  ),
      .rst   ( rst || soft_reset.rx ),
      .pulse ( rx_pulse             ),
      .meta  ( rx_irq_meta          ),
      .irq   ( irq.rx               )
  );

  i2s_irq u_tx_irq (
      .clk   ( clk                  ),
      .rst   ( rst || soft_reset.tx ),
      .pulse ( tx_pulse             ),
      .meta  ( tx_irq_meta          ),
      .irq   ( irq.tx               )
  );

  assign tx_irq_const.rsvd = '0;
  assign tx_irq_const.frame_size = $bits(sample_t)/8; // value in bytes
  assign tx_irq_const.bytes_to_fetch = TxBytesToFetch;
  assign rx_irq_const.rsvd = '0;
  assign rx_irq_const.frame_size = $bits(sample_t)/8; // value in bytes
  assign rx_irq_const.bytes_to_fetch = '0;

  assign config_const.rsvd = '0;
  assign config_const.channel_num = 1;
  assign error.rsvd = '0;
  assign error.overflow = rx_channel_overflow;

  // Registers
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
      .rx_clk_counter       ( rx_clk_counter            ),
      .rx_ws_counter        ( rx_ws_counter             ),
      .tx_irq_meta          ( tx_irq_meta               ),
      .rx_irq_meta          ( rx_irq_meta               ),
      .tx_irq_const         ( tx_irq_const              ),
      .rx_irq_const         ( rx_irq_const              )
  );

  // RX path
  i2s_rx u_i2s_rx (
      .clk                ( clk                   ),
      .rst                ( rst || soft_reset.rx  ),
      .i_i2s_in           ( i_i2s_rx              ),
      .i_axis_samples_out ( i_i2s_rx_samples      ),
      .overflow           ( rx_channel_overflow   ),
      .clk_counter        ( rx_clk_counter        ),
      .ws_counter         ( rx_ws_counter         )
  );

  dma_data_writer #(
      .MaxRingBytes         ( MaxRingBytes               ),
      .AddressWidth         ( AddressWidth               ),
      .OutputRegType        ( reg_handshake_pkg::kBypass )
  ) u_dma_data_writer (
      .clk                  ( clk                        ),
      .rst                  ( rst || soft_reset.rx       ),
      .i_data_in            ( i_i2s_rx_samples           ),
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
      .RegType  ( RxTimingRegType       )
  ) u_rx_timing_axis_reg_handshake (
      .clk      ( clk                   ),
      .rst      ( rst || soft_reset.rx  ),
      .axis_in  ( i_write_keep          ),
      .axis_out ( i_write_rq_data       )
  );

  // Interface converter for TX and RX
  axis_to_aximm #(
      .Id           ( I2sDmaId            ),
      .DataWidth    ( DataOutWidth        )
  ) u_axis_to_aximm (
      .clk          ( clk                 ),
      .rst          ( rst                 ),
      .i_write      ( i_write_rq_data     ),
      .write_done   ( write_done          ),
      .i_read_rq    ( i_read_rq           ),
      .i_read_resp  ( i_read_resp         ),
      .i_mm         ( i_data_out          )
  );

  // TX path
  dma_data_reader #(
      .OutputRegType          ( reg_handshake_pkg::kPayload ),
      .MaxRingBytes           ( MaxRingBytes                ),
      .AddressWidth           ( AddressWidth                ),
      .BytesToFetch           ( TxBytesToFetch              )
  ) u_dma_data_reader (
      .clk                    ( clk                         ),
      .rst                    ( rst || soft_reset.tx        ),
      .i_read_rq              ( i_read_rq                   ),
      .i_read_resp_ap         ( i_read_resp                 ),
      .i_read_resp            ( i_read_resp_fifo            ),
      .ring_enable            ( tx_enable                   ),
      .ring_size              ( tx_buffer_size              ),
      .ring_address           ( tx_base_addr                ),
      .ring_prod_idx          ( tx_prod_idx                 ),
      .ring_cons_idx          ( tx_cons_idx                 ),
      .ring_cons_idx_rst      ( '0                          ),
      .ring_cons_idx_change   ( tx_pulse                    )
  );

  axis_data_width_converter u_tx_resp_converter (
      .clk        ( clk                   ),
      .rst        ( rst || soft_reset.tx  ),
      .i_axis_in  ( i_read_resp_fifo      ),
      .i_axis_out ( i_read_resp_data      )
  );

  i2s_tx u_i2s_tx (
      .clk            ( clk                   ),
      .rst            ( rst || soft_reset.tx  ),
      .i_axis_in      ( i_read_resp_data      ),
      .i_i2s_out      ( i_i2s_tx              ),
      .clk_counter    ( tx_clk_counter        ),
      .ws_counter     ( tx_ws_counter         )
  );

endmodule : i2s_ssm
