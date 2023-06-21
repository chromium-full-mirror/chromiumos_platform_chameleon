/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package vid_rx_pkg;
  localparam int PixelDataWidth = 192;
  localparam int PixelsInBeat = 4;
  localparam int PixelKeepWidth = PixelsInBeat;
  localparam int DmaDataWidth = 128;
  localparam int DmaKeepWidth = DmaDataWidth/8;
  localparam int VidFormatWidth = 3;
  localparam int MstCount = 4;

  typedef enum logic [1:0] {
    kSinkDpMst = 0,
    kSinkHdmi  = 1,
    kSinkDpSst = 2
  } vid_sink_e;

  typedef enum logic [VidFormatWidth-1:0] {
    k8bpc       = 0,
    k10bpcUpper = 1,
    k10bpcLower = 2,
    k12bpcUpper = 3,
    k12bpcLower = 4,
    k16bpc      = 5,
    kRaw        = 6,
    k8bpcPad    = 7 // ITE old format
  } vid_dma_format_e;

  typedef struct packed {
    logic [PixelDataWidth-1:0] raw;
  } vid_dma_raw_t;

  typedef struct packed {
    logic [23:16] b;
    logic [15:8]  g;
    logic [7:0]   r;
  } vid_dma_format_8bpc_single_t;

  typedef struct packed {
    vid_dma_format_8bpc_single_t [PixelsInBeat-1:0] upper;
    vid_dma_format_8bpc_single_t [PixelsInBeat-1:0] lower;
  } vid_dma_format_8bpc_t;

  typedef struct packed {
    logic [47:38] b;
    logic [37:32] _padding_b;
    logic [31:22] g;
    logic [21:16] _padding_g;
    logic [15:6]  r;
    logic [5:0]   _padding_r;
  } vid_dma_format_10bpc_lower_padding_t;

  typedef struct packed {
    logic [47:42] _padding_b;
    logic [41:32] b;
    logic [31:26] _padding_g;
    logic [25:16] g;
    logic [15:10] _padding_r;
    logic [9:0]   r;
  } vid_dma_format_10bpc_upper_padding_t;

  typedef struct packed {
    logic [47:36] b;
    logic [35:32] _padding_b;
    logic [31:20] g;
    logic [19:16] _padding_g;
    logic [15:4]  r;
    logic [3:0]   _padding_r;
  } vid_dma_format_12bpc_lower_padding_t;

  typedef struct packed {
    logic [47:44] _padding_b;
    logic [43:32] b;
    logic [31:28] _padding_g;
    logic [27:16] g;
    logic [15:12] _padding_r;
    logic [11:0]  r;
  } vid_dma_format_12bpc_upper_padding_t;

  typedef struct packed {
    logic [47:32] b;
    logic [31:16] g;
    logic [15:0]  r;
  } vid_dma_format_16bpc_t;

  typedef union packed {
    vid_dma_format_8bpc_t                                   format8bpc;
    vid_dma_format_10bpc_upper_padding_t [PixelsInBeat-1:0] format10bpc_upper;
    vid_dma_format_10bpc_lower_padding_t [PixelsInBeat-1:0] format10bpc_lower;
    vid_dma_format_12bpc_upper_padding_t [PixelsInBeat-1:0] format12bpc_upper;
    vid_dma_format_12bpc_lower_padding_t [PixelsInBeat-1:0] format12bpc_lower;
    vid_dma_format_16bpc_t               [PixelsInBeat-1:0] format16bpc;
    vid_dma_raw_t                                           raw_data;
  } vid_dma_format_u;

  // Format common for DP and HDMI IP cores
  typedef struct packed {
    logic [PixelDataWidth-1:0] raw;
  } vid_input_word_t;

  // 4:4:4 format
  typedef struct packed {
    logic [47:40] r;
    logic [39:32] _unused_r;
    logic [31:24] g;
    logic [23:16] _unused_g;
    logic [15:8]  b;
    logic [7:0]   _unused_b;
  } vid_444_8bpc_format_t;

  typedef struct packed {
    logic [47:38] r;
    logic [37:32] _unused_r;
    logic [31:22] g;
    logic [21:16] _unused_g;
    logic [15:6]  b;
    logic [5:0]   _unused_b;
  } vid_444_10bpc_format_t;

  typedef struct packed {
    logic [47:36] r;
    logic [35:32] _unused_r;
    logic [31:20] g;
    logic [19:16] _unused_g;
    logic [15:4]  b;
    logic [3:0]   _unused_b;
  } vid_444_12bpc_format_t;

  typedef struct packed {
    logic [47:32] r;
    logic [31:16] g;
    logic [15:0]  b;
  } vid_444_16bpc_format_t;

  // 4:2:2 format
  typedef struct packed {
    logic [47:32] _unused;
    logic [31:24] y;
    logic [23:16] _unused_y;
    logic [15:8]  cbcr;
    logic [7:0]   _unused_cbcr;
  } vid_422_8bpc_format_t;

  typedef struct packed {
    logic [47:32] _unused;
    logic [31:22] y;
    logic [21:16] _unused_y;
    logic [15:6]  cbcr;
    logic [5:0]   _unused_cbcr;
  } vid_422_10bpc_format_t;

  typedef struct packed {
    logic [47:32] _unused;
    logic [31:20] y;
    logic [19:16] _unused_y;
    logic [15:4]  cbcr;
    logic [3:0]   _unused_cbcr;
  } vid_422_12bpc_format_t;

  typedef struct packed {
    logic [47:32] _unused;
    logic [31:16] y;
    logic [15:0]  cbcr;
  } vid_422_16bpc_format_t;

  // 4:2:0 format
  typedef struct packed {
    logic [47:40] y_n1;
    logic [39:32] _unused_y_n1;
    logic [31:24] y_n0;
    logic [23:16] _unused_y_n0;
    logic [15:8]  cbcr;
    logic [7:0]   _unused_cbcr;
  } vid_420_8bpc_format_t;

  typedef struct packed {
    logic [47:38] y_n1;
    logic [37:32] _unused_y_n1;
    logic [31:22] y_n0;
    logic [21:16] _unused_y_n0;
    logic [15:6]  cbcr;
    logic [5:0]   _unused_cbcr;
  } vid_420_10bpc_format_t;

  typedef struct packed {
    logic [47:36] y_n1;
    logic [35:32] _unused_y_n1;
    logic [31:20] y_n0;
    logic [19:16] _unused_y_n0;
    logic [15:4]  cbcr;
    logic [3:0]   _unused_cbcr;
  } vid_420_12bpc_format_t;

  typedef struct packed {
    logic [47:32] y_n1;
    logic [31:16] y_n0;
    logic [15:0]  cbcr;
  } vid_420_16bpc_format_t;

  typedef union packed {
    vid_444_8bpc_format_t  [PixelsInBeat-1:0] format8bpc_444;
    vid_444_10bpc_format_t [PixelsInBeat-1:0] format10bpc_444;
    vid_444_12bpc_format_t [PixelsInBeat-1:0] format12bpc_444;
    vid_444_16bpc_format_t [PixelsInBeat-1:0] format16bpc_444;

    vid_422_8bpc_format_t  [PixelsInBeat-1:0] format8bpc_422;
    vid_422_10bpc_format_t [PixelsInBeat-1:0] format10bpc_422;
    vid_422_12bpc_format_t [PixelsInBeat-1:0] format12bpc_422;
    vid_422_16bpc_format_t [PixelsInBeat-1:0] format16bpc_422;

    vid_420_8bpc_format_t  [PixelsInBeat-1:0] format8bpc_420;
    vid_420_10bpc_format_t [PixelsInBeat-1:0] format10bpc_420;
    vid_420_12bpc_format_t [PixelsInBeat-1:0] format12bpc_420;
    vid_420_16bpc_format_t [PixelsInBeat-1:0] format16bpc_420;

    vid_input_word_t                          raw_video;
  } vid_input_format_u;

  typedef struct packed {
    logic sof;
    logic sol;
    logic eof;
    logic eol;
    logic data_valid;
    logic interlace;
    logic error;
  } vid_meta_vid_t;

  typedef struct packed {
    logic dev_null;   // TODO
  } vid_meta_aud_t;

  typedef struct packed {
    vid_meta_vid_t vid;
    vid_meta_aud_t aud;
  } vid_meta_t;

endpackage : vid_rx_pkg
