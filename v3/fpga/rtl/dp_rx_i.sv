/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`ifndef __DP_RX_I_SV__
`define __DP_RX_I_SV__

interface dp_aux_i ();
  logic in;
  logic out;
  logic oe;

  modport host (
    input  in,
    output out,
    output oe
  );

  modport agent (
    output in,
    input out,
    input oe
  );

endinterface : dp_aux_i

interface pwr_hpd_i ();
  logic hpd;
  logic cable_detect;
  logic pwr_detect;

  modport host (
    input  hpd,
    output cable_detect,
    output pwr_detect
  );

  modport agent (
    output hpd,
    input  cable_detect,
    input  pwr_detect
  );

endinterface : pwr_hpd_i

interface dp_video_i #(
    parameter int DataWidth = 192,
    parameter int PixelsInBeat = 4
) ();
  logic clk;
  logic [PixelsInBeat-1:0] valid;
  logic [DataWidth-1:0] data;
  logic sol;
  logic eol;
  logic sof;
  logic eof;
  logic locked;
  logic interlace;
  logic field;
  logic overflow;

  modport host (
    output clk,
    output data,
    output valid,
    output sol,
    output eol,
    output sof,
    output eof,
    output locked,
    output interlace,
    output field,
    output overflow
  );

  modport agent (
    input clk,
    input data,
    input valid,
    input sol,
    input eol,
    input sof,
    input eof,
    input locked,
    input interlace,
    input field,
    input overflow
  );
endinterface : dp_video_i

interface dp_debug_stream_i #(
    parameter int DataWidth = 128,
    parameter int CtrlWidth = 16
) ();

  logic clk;
  logic valid;
  logic [DataWidth-1:0] data;
  logic [CtrlWidth-1:0] ctrl;

  modport host (
    output clk,
    output valid,
    output data,
    output ctrl
  );

  modport agent (
    input  clk,
    input  valid,
    input  data,
    input  ctrl
  );

endinterface : dp_debug_stream_i

interface dp_debug_aux_i #(
    parameter int DataWidth = 32
) ();

  logic valid;
  logic [DataWidth-1:0] data;
  logic sop;
  logic eop;
  logic err;
  logic cha;

  modport host (
    output valid,
    output data,
    output sop,
    output eop,
    output err,
    output cha
  );

  modport agent (
    input  valid,
    input  data,
    input  sop,
    input  eop,
    input  err,
    input  cha
  );

endinterface : dp_debug_aux_i

interface dp_ss_i #(
    parameter int DataWidth = 160
) ();

  logic clk;
  logic valid;
  logic [DataWidth-1:0] data;
  logic sop;
  logic eop;

  modport host (
    output clk,
    output valid,
    output data,
    output sop,
    output eop
  );

  modport agent (
    input  clk,
    input  valid,
    input  data,
    input  sop,
    input  eop
  );

endinterface : dp_ss_i

interface dp_audio_i #(
    parameter int DataWidth = 256
) ();

  logic valid;
  logic mute;
  dp_rx_pkg::dp_infoframe_t infoframe;
  logic [DataWidth-1:0] lpcm_data;

  modport host (
    output valid,
    output mute,
    output infoframe,
    output lpcm_data
  );

  modport agent (
    input  valid,
    input  mute,
    input  infoframe,
    input  lpcm_data
  );

endinterface : dp_audio_i

interface xcvr_dp_reconfig_i #(
    parameter int LinkRateWidth = 2,
    parameter int AVodEmpWidth = 8
) ();

  logic [LinkRateWidth-1:0] link_rate;
  logic [7:0] link_rate_8bits;
  logic d_req;
  logic d_ack;
  logic d_busy;
  logic [AVodEmpWidth-1:0] a_vod;
  logic [AVodEmpWidth-1:0] a_emp;
  logic a_req;

  modport host (
    output link_rate,
    output link_rate_8bits,
    output d_req,
    input  d_ack,
    input  d_busy,
    output a_vod,
    output a_emp,
    output a_req
  );

  modport agent (
    input  link_rate,
    input  link_rate_8bits,
    input  d_req,
    output d_ack,
    output d_busy,
    input  a_vod,
    input  a_emp,
    input  a_req
  );

endinterface : xcvr_dp_reconfig_i

`endif // __DP_RX_I_SV__
