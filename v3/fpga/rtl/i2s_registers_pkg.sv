/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Register offset definitions and helper types for i2s_registers module
 */

package i2s_registers_pkg;

  parameter int AddrWidth          = 'h8;
  parameter int CounterWidth       = 'd28;

  typedef logic       tx_enable_t;
  typedef logic[31:0] tx_base_addr_t;
  typedef logic[31:0] tx_buffer_size_t;
  typedef logic[31:0] tx_producer_idx_t;
  typedef logic[31:0] tx_consumer_idx_t;
  typedef logic       rx_enable_t;
  typedef logic[31:0] rx_base_addr_t;
  typedef logic[31:0] rx_buffer_size_t;
  typedef logic[31:0] rx_producer_idx_t;
  typedef logic[31:0] rx_consumer_idx_t;
  typedef logic[CounterWidth-1:0] counter_t;
  typedef struct packed {
    logic [30:0] rsvd;
    logic overflow;
  } error_t;
  typedef struct packed {
    logic tx;
    logic rx;
  } soft_reset_t;
  typedef struct packed {
    logic [23:0] rsvd;
    logic [7:0]  channel_num;
  } config_const_t;
  typedef struct packed {
    logic [23:0] frames_cnt;
    logic [6:0]  rsvd;
    logic        enable;
  } irq_t;
  typedef struct packed {
    logic [7:0]  rsvd;
    logic [15:0] bytes_to_fetch;
    logic [7:0]  frame_size;
  } irq_ro_t;
  typedef struct packed {
    aud_rx_pkg::sf_e sf;
  } sampling_freq_t;
  typedef logic[31:0] hdmi_n_t;
  typedef logic[31:0] hdmi_cts_t;
  typedef logic[31:0] hdmi_tmds_clk_t;

  localparam int AddrTxEnable        = 'h0;
  localparam int AddrTxBaseAddr      = 'h4;
  localparam int AddrTxBufferSize    = 'h8;
  localparam int AddrTxProducerIdx   = 'hc;
  localparam int AddrTxConsumerIdx   = 'h10;
  localparam int AddrRxEnable        = 'h14;
  localparam int AddrRxBaseAddr      = 'h18;
  localparam int AddrRxBufferSize    = 'h1c;
  localparam int AddrRxProducerIdx   = 'h20;
  localparam int AddrRxConsumerIdx   = 'h24;
  localparam int AddrError           = 'h28;
  localparam int AddrSoftReset       = 'h2c;
  localparam int AddrConfigConst     = 'h30;
  localparam int AddrTxClkCounter    = 'h34;
  localparam int AddrTxWsCounter     = 'h38;
  localparam int AddrRxClkCounter    = 'h3C;
  localparam int AddrRxWsCounter     = 'h40;
  localparam int AddrCounterWidth    = 'h44;
  localparam int AddrClkFrequencyMhz = 'h48;
  localparam int AddrRxIrq           = 'h4C;
  localparam int AddrRxIrqConst      = 'h50;
  localparam int AddrTxIrq           = 'h54;
  localparam int AddrTxIrqConst      = 'h58;
  localparam int AddrSamplingFreq    = 'h5c;
  localparam int AddrHdmiN           = 'h60;
  localparam int AddrHdmiCts         = 'h64;
  localparam int AddrTmdsClk         = 'h68;

endpackage : i2s_registers_pkg
