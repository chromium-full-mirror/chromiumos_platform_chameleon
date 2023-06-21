/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package hdmi_rx_pkg;

  localparam int ColorDepthWidth = 4;
  localparam int BitsPerLane = 10;
  localparam int Symbols = 2;
  localparam int BitSlipBoundarySel = 5;
  localparam int HdmiVidDataWidth = 96;
  localparam int HdmiVidPxPerBeat = Symbols;
  localparam int NCTSWidth = 20;
  localparam int TmdsMeasureWidth = 24;

  localparam int HdmiToDmaAdapterFifoDepth = 64; // TODO(ka): adjust value based on hardware testing

  typedef struct packed {
    logic [HdmiVidPxPerBeat-1:0] de;
    logic [HdmiVidPxPerBeat-1:0] hsync;
    logic [HdmiVidPxPerBeat-1:0] vsync;
    logic                        lock;
    logic [HdmiVidDataWidth-1:0] data;
  } hdmi_data_t;

  /* HDMI FPGA IP User Guide, Table 27 */
  typedef enum logic [3:0] {
    kLpcm = 0,
    k3dAudio = 4,
    kMstLpcm = 6
  } audio_format_t;

  /* HDMI FPGA IP User Guide, Table 28 (HDMI spec 1.4b, section 8.2.2) */
  typedef struct packed {
    logic            down_mix_flag;
    logic [3:0]      lvl_shift_info;
    logic            rsvd2;
    logic [1:0]      lfe_playback_lvl;
    logic [7:0]      speaker_location;
    logic [7:0]      format_type_audio_stream;
    logic [2:0]      rsvd1;
    aud_rx_pkg::sf_e sampling_frequency;
    aud_rx_pkg::ss_e sample_size;
    audio_format_t   format_type;
    logic            rsvd0;
    aud_rx_pkg::cc_e channel_count;
    logic [7:0]      checksum;
  } hdmi_audio_infoframe_t;

endpackage : hdmi_rx_pkg
