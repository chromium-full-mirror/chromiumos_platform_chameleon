/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`ifndef __HDMI_RX_I_SV__
`define __HDMI_RX_I_SV__

/* Interfaces for HDMI IP core */
interface hdmi_data_i #(
    parameter int DataWidth = hdmi_rx_pkg::HdmiVidDataWidth,
    parameter int PixelsPerBeat = hdmi_rx_pkg::HdmiVidPxPerBeat
) ();
  logic [PixelsPerBeat-1:0] de;
  logic [PixelsPerBeat-1:0] hsync;
  logic [PixelsPerBeat-1:0] vsync;
  logic lock;
  logic [DataWidth-1:0] data;

  modport host (
    output de,
    output hsync,
    output vsync,
    output lock,
    output data
  );

  modport agent (
    input  de,
    input  hsync,
    input  vsync,
    input  lock,
    input  data
  );

endinterface : hdmi_data_i

interface hdmi_aux_i #(
    parameter int DataWidth = 72,
    parameter int PktAddrWidth = 7
) ();
  logic valid;
  logic [DataWidth-1:0] data;
  logic sop;
  logic eop;
  logic error;
  logic pkt_addr;
  logic pkt_data;
  logic pkt_wr;

  modport host (
    output valid,
    output data,
    output sop,
    output eop,
    output error,
    output pkt_addr,
    output pkt_data,
    output pkt_wr
  );

  modport agent (
    input  valid,
    input  data,
    input  sop,
    input  eop,
    input  error,
    input  pkt_addr,
    input  pkt_data,
    input  pkt_wr
  );

endinterface : hdmi_aux_i

interface hdmi_audio_i #(
    parameter int NCTSWidth = hdmi_rx_pkg::NCTSWidth,
    parameter int DataWidth = 256, // TODO: Consider structure (Table 39) if needed
    parameter int MetadataWidth = 165, // TODO: Consider structure for it if needed (Table 29, HDMI User Guide)
    parameter int FormatWidth = 5
) ();

  logic [NCTSWidth-1:0] cts;
  logic [NCTSWidth-1:0] n;
  logic [DataWidth-1:0] data;
  logic de;
  logic [MetadataWidth-1:0] metadata;
  logic [FormatWidth-1:0] format;
  hdmi_rx_pkg::hdmi_audio_infoframe_t infoframe;

  modport host (
    output cts,
    output n,
    output data,
    output de,
    output metadata,
    output format,
    output infoframe
  );

  modport agent (
    input  cts,
    input  n,
    input  data,
    input  de,
    input  metadata,
    input  format,
    input  infoframe
  );

endinterface : hdmi_audio_i

interface hdmi_pwr_i ();

  logic hpd;
  logic pwr;

  modport host (
    input  hpd,
    output pwr
  );

  modport agent (
    output hpd,
    input  pwr
  );

endinterface : hdmi_pwr_i

interface xcvr_hdmi_config_i #(
    parameter int ColorDepthWidth = 4,
    parameter int TmdsMeasureWidth = hdmi_rx_pkg::TmdsMeasureWidth
) ();

  logic vid_clk;
  logic ls_clk;
  logic reset_vid;
  logic bit_clock_ratio;
  logic color_locked;
  logic [ColorDepthWidth-1:0] color_depth_sync;
  logic hdmi_lock;
  logic [TmdsMeasureWidth-1:0] tmds_measure;
  logic tmds_measure_valid;

  modport host (
    input  vid_clk,
    input  ls_clk,
    input  reset_vid,
    output bit_clock_ratio,
    output color_locked,
    output color_depth_sync,
    input  hdmi_lock,
    input  tmds_measure,
    input  tmds_measure_valid
  );

  modport agent (
    output vid_clk,
    output ls_clk,
    output reset_vid,
    input  bit_clock_ratio,
    input  color_locked,
    input  color_depth_sync,
    output hdmi_lock,
    output tmds_measure,
    output tmds_measure_valid
  );

endinterface : xcvr_hdmi_config_i

`endif // __HDMI_RX_I_SV__
