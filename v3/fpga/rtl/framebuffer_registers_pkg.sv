/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package framebuffer_registers_pkg;

  localparam int AddrWidth = 'h8;
  localparam int DimWidth = 14;
  localparam int BufferAddrWidth = framebuffer_pkg::BufferAddrWidth;
  localparam int BufferSizeWidth = framebuffer_pkg::BufferSizeWidth;
  localparam int FramebufferVersion = 32'hc0fb0001;

  // CSR addresses
  localparam int AddrEn              = 8'h00;
  localparam int AddrDimHeight       = 8'h04;
  localparam int AddrDimWidth        = 8'h08;
  localparam int AddrBufferA         = 8'h0c;
  localparam int AddrBufferB         = 8'h10;
  localparam int AddrBufferSize      = 8'h14;
  localparam int AddrReset           = 8'h18;
  localparam int AddrErrorStatus     = 8'h1c;
  localparam int AddrIOColor         = 8'h20;
  localparam int AddrIODataRate      = 8'h24;
  localparam int AddrIOPixelMode     = 8'h28;
  localparam int AddrSyncPolarity    = 8'h2c;
  localparam int AddrDmaFormat       = 8'h30;
  localparam int AddrVersion         = 8'h34;
  localparam int WrongAddrReadValue  = 32'hdeadbeef;

  typedef struct packed {
    logic [DimWidth-1:0] dim;
  } dim_t;

  typedef struct packed {
    logic en;
  } enable_t;

  typedef struct packed {
    logic [BufferSizeWidth-1:0] size;
  } buffer_size_t;

  typedef struct packed {
    logic [BufferAddrWidth-1:0] addr;
  } buffer_addr_t;

  typedef struct packed {
    logic rst;
  } rst_t;

  typedef struct packed {
    logic adapter_error;
    logic dma_fifo_overflow;
  } errors_t;

  typedef enum logic[1:0] {
    k24b = 0,
    k30b,
    k36b
  } color_depth_e;

  typedef enum logic {
    kSdr = 0,
    kDdr = 1
  } data_rate_e;

  typedef enum logic {
    kDetect = 0,
    kForce = 1
  } polarity_state_e;

  typedef struct packed {
    polarity_state_e state;
    logic vsync_inv;
    logic hsync_inv;
  } sync_polarity_t;

  typedef struct packed {
    vid_rx_pkg::vid_dma_format_e format;
  } dma_format_t;

  typedef enum logic {
    kSpm = 0,
    kDpm = 1
  } pixel_mode_e;

  typedef enum logic {
    kBufferA = 0,
    kBufferB = 1
  } buffer_id_e;

endpackage : framebuffer_registers_pkg
