/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/* Wrapper for HDMI IP core */
module hdmi_rx_wrapper #(
    parameter int SymbolsPerClock = hdmi_rx_pkg::Symbols
) (
    input  logic            clk, // expected 100MHz
    input  logic            reset,
    xcvr_i.agent            i_xcvr,
    xcvr_hdmi_config_i.host i_xcvr_hdmi_cfg,
    hdmi_pwr_i.agent        i_pwr,
    hdmi_aux_i.host         i_aux, // aux_clk = ls_clk (without FRL, this case)
    hdmi_audio_i.host       i_audio, // Domain: aux_clk (ls_clk)
    hdmi_data_i.host        i_video, // Domain: vid_clk (up to 300MHz)
    i2c_i.host              i_i2c,
    avalon_mm_i.agent       i_edid_ram,
    input logic             edid_ram_access
);

  import hdmi_rx_pkg::*;

  localparam int GcpWidth = 6;
  localparam int InfoAviWidth = 112;
  localparam int InfoVsiWidth = 61;

  logic [SymbolsPerClock*BitsPerLane-1:0] r, g, b;
  logic [GcpWidth-1:0] gcp;

  /* Unused signals */
  logic [InfoAviWidth-1:0] info_avi;
  logic [InfoVsiWidth-1:0] info_vsi;
  logic mode;
  logic ctrl;
  logic tmds_config_trans_det;

  clock_crosser #(
    .W ( ColorDepthWidth )
  ) u_cdc_color_sync (
    .in_clk     ( i_xcvr_hdmi_cfg.ls_clk ),
    .in_reset   ( 1'b0 ),
    .out_clk    ( clk ),
    .out_reset  ( 1'b0 ),
    .in         ( gcp[ColorDepthWidth-1:0] ),
    .out        ( i_xcvr_hdmi_cfg.color_depth_sync )
  );

  assign {r, g, b} = i_xcvr.data;

  logic [7:0] edid_ram_readdata;

  always_comb begin
    if (edid_ram_access) begin
      i_edid_ram.readdata = edid_ram_readdata;
      i_edid_ram.readdatavalid = i_edid_ram.read & ~i_edid_ram.waitrequest;
    end else begin
      i_edid_ram.readdata = 8'hff;
      i_edid_ram.readdatavalid = i_edid_ram.read;
    end
  end

  hdmi_rx u_hdmi_rx (
    .reset                 ( reset ),
    .reset_vid             ( i_xcvr_hdmi_cfg.reset_vid ),
    .clk_b                 ( i_xcvr.std_clkout[0] ),
    .clk_g                 ( i_xcvr.std_clkout[1] ),
    .clk_r                 ( i_xcvr.std_clkout[2] ),
    .ls_clk                ( i_xcvr_hdmi_cfg.ls_clk ),
    .vid_clk               ( i_xcvr_hdmi_cfg.vid_clk ),
    .os                    ( &i_xcvr.set_locktoref ),
    .in_b                  ( b ),
    .in_g                  ( g ),
    .in_r                  ( r ),
    .in_lock               ( i_xcvr_hdmi_cfg.hdmi_lock ),
    .aux_data              ( i_aux.data ),
    .aux_valid             ( i_aux.valid ),
    .aux_sop               ( i_aux.sop ),
    .aux_eop               ( i_aux.eop ),
    .aux_error             ( i_aux.error ),
    .gcp                   ( gcp ),
    .info_avi              ( info_avi ),
    .info_vsi              ( info_vsi ),
    .aux_pkt_addr          ( i_aux.pkt_addr ),
    .aux_pkt_data          ( i_aux.pkt_data ),
    .aux_pkt_wr            ( i_aux.pkt_wr ),
    .audio_CTS             ( i_audio.cts ),
    .audio_N               ( i_audio.n ),
    .audio_data            ( i_audio.data ),
    .audio_de              ( i_audio.de ),
    .audio_metadata        ( i_audio.metadata ),
    .audio_format          ( i_audio.format ),
    .audio_info_ai         ( i_audio.infoframe ),
    .locked                ( i_xcvr_hdmi_cfg.color_locked ),
    .vid_data              ( i_video.data ),
    .vid_de                ( i_video.de ),
    .vid_hsync             ( i_video.hsync ),
    .vid_vsync             ( i_video.vsync ),
    .vid_lock              ( i_video.lock ),
    .in_5v_power           ( i_pwr.pwr & ~edid_ram_access),
    .rx_hpd_req            ( i_pwr.hpd ),
    .mode                  ( mode ),
    .ctrl                  ( ctrl ),
    .i2c_clk               ( clk ),
    .i2c_scl               ( i_i2c.scl ),
    .i2c_sda               ( i_i2c.sda ),
    .edid_ram_access       ( edid_ram_access ),
    .edid_ram_address      ( i_edid_ram.address ),
    .edid_ram_read         ( i_edid_ram.read ),
    .edid_ram_write        ( i_edid_ram.write ),
    .edid_ram_writedata    ( i_edid_ram.writedata ),
    .edid_ram_waitrequest  ( i_edid_ram.waitrequest ),
    .edid_ram_readdata     ( edid_ram_readdata ),
    .tmds_config_trans_det ( tmds_config_trans_det ),
    .tmds_bit_clock_ratio  ( i_xcvr_hdmi_cfg.bit_clock_ratio )
  );

endmodule : hdmi_rx_wrapper
