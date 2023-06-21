/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package framebuffer_pkg;

  localparam int PixelBurstSize = 16;
  localparam int PixelsInBeat = 4;
  localparam int PixelDataWidth = 32;
  localparam int BufferAddrWidth = 32;
  localparam int BufferSizeWidth = 32;
  localparam int BufferCount = 2;
  localparam int AddrMaskAlignment = 4'hf;

  // TODO: since we have fifo in burst adapter in future we can decrease size
  localparam int PixelToMemFifoDepth = 512;

  typedef struct packed {
    logic [PixelsInBeat-1:0][PixelDataWidth-1:0] pixel;
  } pixel_word_t;

  typedef struct packed {
    logic [BufferCount-1:0]     eof;
    logic [BufferAddrWidth-1:0] addr;
  } fb_dma_meta_t;

  typedef struct packed {
    logic sof;
    logic sol;
    logic eof;
    logic eol;
    logic data_valid;
  } fb_adapter_meta_t;

  typedef enum logic[1:0] {
    kIrqBuff0      = 0,
    kIrqBuff1      = 1,
    kIrqResolution = 2,
    kIrqError      = 3
  } irq_e;

  typedef struct packed {
    logic de;
    logic scdt;
    logic vsync;
    logic hsync;
  } pixel_ctrl_t;

  typedef struct packed {
    pixel_ctrl_t ctrl;
    logic [59:0] qd;
  } input_word_t;

  typedef struct packed {
    input_word_t high;
    input_word_t low;
  } input_word_ddr_t;

  typedef struct packed {
    pixel_ctrl_t unused_ctrl;
    logic [59:0] unsued_qd;
  } unused_ddr_bits_t;

  //-----------------------------------------------------------------------------------------------

  typedef struct packed {
    pixel_ctrl_t ctrl;
    logic [59:30] _unused;
    logic [29:22] r;
    logic [21:20] _unused0;
    logic [19:12] g;
    logic [11:10] _unused1;
    logic [ 9: 2] b;
    logic [ 1: 0] _unused2;
  } spm_sdr_io_map_24b_t; // 64 bits

  typedef struct packed {
    pixel_ctrl_t ctrl;
    logic [59:30] _unused;
    logic [29:20] r;
    logic [19:10] g;
    logic [ 9: 0] b;
  } spm_sdr_io_map_30b_t; // 64 bits

  typedef struct packed {
    pixel_ctrl_t ctrl;
    logic [59:36] _unused;
    logic [35:34] r_0_1;
    logic [33:32] g_0_1;
    logic [31:30] b_0_1;
    logic [29:20] r_11_2;
    logic [19:10] g_11_2;
    logic [ 9: 0] b_11_2;
  } spm_sdr_io_map_36b_t; // 64 bits

  typedef struct packed {
    pixel_ctrl_t ctrl;

    logic [59:52] r_b;
    logic [51:50] _unused_r_b;
    logic [49:42] g_b;
    logic [41:40] _unused_g_b;
    logic [39:32] b_b;
    logic [31:30] _unused_b_b;

    logic [29:22] r_a;
    logic [21:20] _unused_r_a;
    logic [19:12] g_a;
    logic [11:10] _unused_g_a;
    logic [ 9: 2] b_a;
    logic [ 1: 0] _unused_b_a;
  } dpm_sdr_io_map_24b_t; // 64 bits

  typedef struct packed {
    pixel_ctrl_t ctrl;

    logic [59:50] r_b;
    logic [49:40] g_b;
    logic [39:30] b_b;

    logic [29:20] r_a;
    logic [19:10] g_a;
    logic [ 9: 0] b_a;
  } dpm_sdr_io_map_30b_t; // 64 bits

  //-----------------------------------------------------------------------------------------------

  typedef struct packed {
    unused_ddr_bits_t _unused_ddr_bits;
    spm_sdr_io_map_36b_t bits;
  } spm_sdr_io_map_36b_padded_t;

  typedef struct packed {
    spm_sdr_io_map_36b_t edge_2;
    spm_sdr_io_map_36b_t edge_1;
  } spm_ddr_io_map_36b_t;

  typedef struct packed {
    unused_ddr_bits_t _unused_ddr_bits;
    spm_sdr_io_map_30b_t bits;
  } spm_sdr_io_map_30b_padded_t;

  typedef struct packed {
    spm_sdr_io_map_30b_t edge_2;
    spm_sdr_io_map_30b_t edge_1;
  } spm_ddr_io_map_30b_t;

  typedef struct packed {
    unused_ddr_bits_t _unused_ddr_bits;
    spm_sdr_io_map_24b_t bits;
  } spm_sdr_io_map_24b_padded_t;

  typedef struct packed {
    spm_sdr_io_map_24b_t edge_2;
    spm_sdr_io_map_24b_t edge_1;
  } spm_ddr_io_map_24b_t;

  typedef struct packed {
    unused_ddr_bits_t _unused_ddr_bits;
    dpm_sdr_io_map_24b_t bits;
  } dpm_sdr_io_map_24b_padded_t;

  typedef struct packed {
    unused_ddr_bits_t _unused_ddr_bits;
    dpm_sdr_io_map_30b_t bits;
  } dpm_sdr_io_map_30b_padded_t;

  typedef struct packed {
    dpm_sdr_io_map_30b_t edge_2;
    dpm_sdr_io_map_30b_t edge_1;
  } dpm_ddr_io_map_30b_t;

  typedef struct packed {
    dpm_sdr_io_map_24b_t edge_2;
    dpm_sdr_io_map_24b_t edge_1;
  } dpm_ddr_io_map_24b_t;

  //-----------------------------------------------------------------------------------------------

  typedef union packed {
    spm_sdr_io_map_36b_padded_t spm_sdr_36b; // 1px in word
    spm_sdr_io_map_30b_padded_t spm_sdr_30b; // 1px in word
    spm_sdr_io_map_24b_padded_t spm_sdr_24b; // 1px in word

    spm_ddr_io_map_36b_t        spm_ddr_36b; // 2px in word
    spm_ddr_io_map_30b_t        spm_ddr_30b; // 2px in word
    spm_ddr_io_map_24b_t        spm_ddr_24b; // 2px in word

    dpm_sdr_io_map_24b_padded_t dpm_sdr_24b; // 2px in word
    dpm_sdr_io_map_30b_padded_t dpm_sdr_30b; // 2px in word
    dpm_ddr_io_map_24b_t        dpm_ddr_24b; // 4px in word
    dpm_ddr_io_map_30b_t        dpm_ddr_30b; // 4px in word

    input_word_ddr_t            ddio;
  } io_map_t;

endpackage : framebuffer_pkg
