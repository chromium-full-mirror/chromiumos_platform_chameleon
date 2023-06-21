/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package dp_rx_pkg;

  localparam int MsaWidth = 217;
  localparam int Symbols = 4;

  localparam DpToDmaAdapterFifoDepth = 64; // TODO(ka): adjust value based on hardware testing

  typedef struct packed {
    logic [MsaWidth-1:0] msa;
  } dp_msa_t;

  typedef struct packed {
    logic            down_mix_flag;
    logic [3:0]      lvl_shift_info;
    logic [2:0]      rsvd2;
    logic [1:0]      lfe_playback_lvl;
    logic [7:0]      speaker_location;
    logic [10:0]     rsvd1;
    aud_rx_pkg::sf_e sampling_frequency;
    aud_rx_pkg::ss_e sample_size;
    logic [3:0]      format_type;
    logic            rsvd0;
    aud_rx_pkg::cc_e channel_count;
  } dp_infoframe_t;

endpackage : dp_rx_pkg
