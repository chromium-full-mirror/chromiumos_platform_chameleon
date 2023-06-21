/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module dp_rx_wrapper #(
    parameter int MstSupport = 1,
    parameter int MstCount = MstSupport ? 4 : 1,
    parameter int Lanes = 4,
    parameter int ReverseLaneOrder = 0
) (
    input  logic                clk, // clock for embedded controller, 100 MHz shall be enough, mgmt on it
    input  logic                reset, // Domain: clk
    input  logic                xcvr_reconfig_clk, // 100MHz, to reconfigure transceivers via non-standard
                                                   // interface (xcvr_dp_reconfig_i)
    xcvr_i.agent                i_xcvr, // REQUIRED: std_clkout from XCVR host (PHY wrapper)
    dp_aux_i.host               i_aux, // Domain: aux_clk
    pwr_hpd_i.agent             i_pwr,
    dp_video_i.host             i_dp_video[MstCount-1:0], // REQUIRED: Application clock (at best, be above
                                                  // 202,5 MHz - max clock for DCFIFO
    dp_ss_i.host                i_dp_ss[MstCount-1:0],    // Secondary stream, not used for now
    output dp_rx_pkg::dp_msa_t  dp_msa[MstCount-1:0],   // Const per frame
    dp_audio_i.host             i_dp_audio[MstCount-1:0], // Domain: dp_ss_clk!
    avalon_mm_i.agent           i_mgmt, // interface for DisplayPort DPCD, not for XCVR reconfig.
                                        // Needed to be exposed to software. Domain: clk.
    xcvr_dp_reconfig_i.host     i_xcvr_reconfig, // Domain: xcvr_reconfig_clk
    output logic                mgmt_irq,
    output logic                dev_null
);

  // Helper signals for handling DisplayPort IP
  logic clk_cal;
  logic dp_ss_clk;

  // xcvr_reconfig_clk is 100MHz. Calibration clock must have /2 frequency (50MHz).
  always @(posedge xcvr_reconfig_clk) begin
    clk_cal <= ~clk_cal;
  end

  // Terminated interfaces from DisplayPort IP core
  dp_debug_stream_i   stream_debug[MstCount-1:0]();
  dp_debug_aux_i      i_aux_debug();
  logic [4:0] rx_lane_count;
  logic aux_clk;
  logic aux_reset;
  logic aux_pll_locked;

  generate
    for (genvar i = 0; i < MstCount; i++) begin : secondary_stream_clk
      assign i_dp_ss[i].clk = dp_ss_clk;
      assign i_dp_video[i].clk = dp_ss_clk;
    end
  endgenerate

  assign i_xcvr.polinv = '0;

  clock_crosser u_rst_aux_cdc (
    .in         ( reset     ),
    .in_clk     ( clk       ),
    .in_reset   ( '0        ),
    .out        ( aux_reset ),
    .out_clk    ( aux_clk   ),
    .out_reset  ( '0        )
  );

  pll_aux u_pll_aux (
    .rst      ( reset ),          //   input,  width = 1,   reset.reset
    .refclk   ( clk ),            //   input,  width = 1,  refclk.clk
    .locked   ( aux_pll_locked ), //  output,  width = 1,  locked.export
    .outclk_0 ( aux_clk )         //  output,  width = 1, outclk0.clk
  );

  assign i_mgmt.readdatavalid = i_mgmt.read;

  assign dev_null = '0;

  // DisplayPort IP core
  generate
    if (MstSupport) begin
      dp_rx u_dp_rx (
        .rx_parallel_data       ( i_xcvr.data ),                    //   input,  width = 160,  rx_xcvr_interface.rx_parallel_data
        .rx_std_clkout          ( ReverseLaneOrder ? i_xcvr.std_clkout[Lanes-1] : i_xcvr.std_clkout[0] ),           //   input,    width = 1,                   .rx_std_clkout
        .rx_is_lockedtoref      ( i_xcvr.is_lockedtoref ),          //   input,    width = 4,                   .rx_is_lockedtoref
        .rx_is_lockedtodata     ( i_xcvr.is_lockedtodata ),         //   input,    width = 4,                   .rx_is_lockedtodata
        .rx_restart             ( i_xcvr.restart ),                 //  output,    width = 1,                   .rx_restart
        .rx_bitslip             ( i_xcvr.bitslip ),                 //  output,    width = 4,                   .rx_bitslip
        .rx_cal_busy            ( i_xcvr.cal_busy ),                //   input,    width = 4,                   .rx_cal_busy
        .rx_analogreset         ( i_xcvr.analogreset ),             //  output,    width = 4,                   .rx_analogreset
        .rx_digitalreset        ( i_xcvr.digitalreset ),            //  output,    width = 4,                   .rx_digitalreset
        .rx_set_locktoref       ( i_xcvr.set_locktoref ),           //  output,    width = 4,                   .rx_set_locktoref
        .rx_set_locktodata      ( i_xcvr.set_locktodata ),          //  output,    width = 4,                   .rx_set_locktodata
        .rx_aux_in              ( i_aux.in ),                       //   input,    width = 1,             rx_aux.rx_aux_in
        .rx_aux_out             ( i_aux.out ),                      //  output,    width = 1,                   .rx_aux_out
        .rx_aux_oe              ( i_aux.oe ),                       //  output,    width = 1,                   .rx_aux_oe
        .rx_hpd                 ( i_pwr.hpd ),                      //  output,    width = 1,                   .rx_hpd
        .rx_cable_detect        ( i_pwr.cable_detect ),             //   input,    width = 1,                   .rx_cable_detect
        .rx_pwr_detect          ( i_pwr.pwr_detect ),               //   input,    width = 1,                   .rx_pwr_detect
        .rx_lane_count          ( rx_lane_count ),                  //  output,    width = 5,          rx_params.rx_lane_count
        .rx_vid_sol             ( i_dp_video[0].sol ),              //  output,    width = 1,       rx_video_out.rx_vid_sol
        .rx_vid_eol             ( i_dp_video[0].eol ),              //  output,    width = 1,                   .rx_vid_eol
        .rx_vid_sof             ( i_dp_video[0].sof ),              //  output,    width = 1,                   .rx_vid_sof
        .rx_vid_eof             ( i_dp_video[0].eof ),              //  output,    width = 1,                   .rx_vid_eof
        .rx_vid_locked          ( i_dp_video[0].locked ),           //  output,    width = 1,                   .rx_vid_locked
        .rx_vid_interlace       ( i_dp_video[0].interlace ),        //  output,    width = 1,                   .rx_vid_interlace
        .rx_vid_field           ( i_dp_video[0].field ),            //  output,    width = 1,                   .rx_vid_field
        .rx_vid_overflow        ( i_dp_video[0].overflow ),         //  output,    width = 1,                   .rx_vid_overflow
        .rx_vid_data            ( i_dp_video[0].data ),             //  output,  width = 192,                   .rx_vid_data
        .rx_vid_valid           ( i_dp_video[0].valid ),            //  output,    width = 4,                   .rx_vid_valid
        .rx1_vid_sol            ( i_dp_video[1].sol ),              //  output,    width = 1,      rx1_video_out.rx1_vid_sol
        .rx1_vid_eol            ( i_dp_video[1].eol ),              //  output,    width = 1,                   .rx1_vid_eol
        .rx1_vid_sof            ( i_dp_video[1].sof ),              //  output,    width = 1,                   .rx1_vid_sof
        .rx1_vid_eof            ( i_dp_video[1].eof ),              //  output,    width = 1,                   .rx1_vid_eof
        .rx1_vid_locked         ( i_dp_video[1].locked ),           //  output,    width = 1,                   .rx1_vid_locked
        .rx1_vid_interlace      ( i_dp_video[1].interlace ),        //  output,    width = 1,                   .rx1_vid_interlace
        .rx1_vid_field          ( i_dp_video[1].field ),            //  output,    width = 1,                   .rx1_vid_field
        .rx1_vid_overflow       ( i_dp_video[1].overflow ),         //  output,    width = 1,                   .rx1_vid_overflow
        .rx1_vid_data           ( i_dp_video[1].data ),             //  output,  width = 192,                   .rx1_vid_data
        .rx1_vid_valid          ( i_dp_video[1].valid ),            //  output,    width = 4,                   .rx1_vid_valid
        .rx2_vid_sol            ( i_dp_video[2].sol ),              //  output,    width = 1,      rx2_video_out.rx2_vid_sol
        .rx2_vid_eol            ( i_dp_video[2].eol ),              //  output,    width = 1,                   .rx2_vid_eol
        .rx2_vid_sof            ( i_dp_video[2].sof ),              //  output,    width = 1,                   .rx2_vid_sof
        .rx2_vid_eof            ( i_dp_video[2].eof ),              //  output,    width = 1,                   .rx2_vid_eof
        .rx2_vid_locked         ( i_dp_video[2].locked ),           //  output,    width = 1,                   .rx2_vid_locked
        .rx2_vid_interlace      ( i_dp_video[2].interlace ),        //  output,    width = 1,                   .rx2_vid_interlace
        .rx2_vid_field          ( i_dp_video[2].field ),            //  output,    width = 1,                   .rx2_vid_field
        .rx2_vid_overflow       ( i_dp_video[2].overflow ),         //  output,    width = 1,                   .rx2_vid_overflow
        .rx2_vid_data           ( i_dp_video[2].data ),             //  output,  width = 192,                   .rx2_vid_data
        .rx2_vid_valid          ( i_dp_video[2].valid ),            //  output,    width = 4,                   .rx2_vid_valid
        .rx3_vid_sol            ( i_dp_video[3].sol ),              //  output,    width = 1,      rx3_video_out.rx3_vid_sol
        .rx3_vid_eol            ( i_dp_video[3].eol ),              //  output,    width = 1,                   .rx3_vid_eol
        .rx3_vid_sof            ( i_dp_video[3].sof ),              //  output,    width = 1,                   .rx3_vid_sof
        .rx3_vid_eof            ( i_dp_video[3].eof ),              //  output,    width = 1,                   .rx3_vid_eof
        .rx3_vid_locked         ( i_dp_video[3].locked ),           //  output,    width = 1,                   .rx3_vid_locked
        .rx3_vid_interlace      ( i_dp_video[3].interlace ),        //  output,    width = 1,                   .rx3_vid_interlace
        .rx3_vid_field          ( i_dp_video[3].field ),            //  output,    width = 1,                   .rx3_vid_field
        .rx3_vid_overflow       ( i_dp_video[3].overflow ),         //  output,    width = 1,                   .rx3_vid_overflow
        .rx3_vid_data           ( i_dp_video[3].data ),             //  output,  width = 192,                   .rx3_vid_data
        .rx3_vid_valid          ( i_dp_video[3].valid ),            //  output,    width = 4,                   .rx3_vid_valid
        .rx_vid_clk             ( i_dp_video[0].clk ),              //   input,    width = 1,         rx_vid_clk.clk
        .rx1_vid_clk            ( i_dp_video[1].clk ),              //   input,    width = 1,        rx1_vid_clk.clk
        .rx2_vid_clk            ( i_dp_video[2].clk ),              //   input,    width = 1,        rx2_vid_clk.clk
        .rx3_vid_clk            ( i_dp_video[3].clk ),              //   input,    width = 1,        rx3_vid_clk.clk
        .rx_stream_valid        ( stream_debug[0].valid ),          //  output,    width = 1,          rx_stream.rx_stream_valid
        .rx_stream_clk          ( stream_debug[0].clk ),            //  output,    width = 1,                   .rx_stream_clk
        .rx_stream_data         ( stream_debug[0].data ),           //  output,  width = 128,                   .rx_stream_data
        .rx_stream_ctrl         ( stream_debug[0].ctrl ),           //  output,   width = 16,                   .rx_stream_ctrl
        .rx1_stream_valid       ( stream_debug[1].valid ),          //  output,    width = 1,         rx1_stream.rx1_stream_valid
        .rx1_stream_clk         ( stream_debug[1].clk ),            //  output,    width = 1,                   .rx1_stream_clk
        .rx1_stream_data        ( stream_debug[1].data ),           //  output,  width = 128,                   .rx1_stream_data
        .rx1_stream_ctrl        ( stream_debug[1].ctrl ),           //  output,   width = 16,                   .rx1_stream_ctrl
        .rx2_stream_valid       ( stream_debug[2].valid ),          //  output,    width = 1,         rx2_stream.rx2_stream_valid
        .rx2_stream_clk         ( stream_debug[2].clk ),            //  output,    width = 1,                   .rx2_stream_clk
        .rx2_stream_data        ( stream_debug[2].data ),           //  output,  width = 128,                   .rx2_stream_data
        .rx2_stream_ctrl        ( stream_debug[2].ctrl ),           //  output,   width = 16,                   .rx2_stream_ctrl
        .rx3_stream_valid       ( stream_debug[3].valid ),          //  output,    width = 1,         rx3_stream.rx3_stream_valid
        .rx3_stream_clk         ( stream_debug[3].clk ),            //  output,    width = 1,                   .rx3_stream_clk
        .rx3_stream_data        ( stream_debug[3].data ),           //  output,  width = 128,                   .rx3_stream_data
        .rx3_stream_ctrl        ( stream_debug[3].ctrl ),           //  output,   width = 16,                   .rx3_stream_ctrl
        .rx_aux_debug_data      ( i_aux_debug.data ),               //  output,   width = 32,       rx_aux_debug.data
        .rx_aux_debug_valid     ( i_aux_debug.valid ),              //  output,    width = 1,                   .valid
        .rx_aux_debug_sop       ( i_aux_debug.sop ),                //  output,    width = 1,                   .startofpacket
        .rx_aux_debug_eop       ( i_aux_debug.eop ),                //  output,    width = 1,                   .endofpacket
        .rx_aux_debug_err       ( i_aux_debug.err ),                //  output,    width = 1,                   .error
        .rx_aux_debug_cha       ( i_aux_debug.cha ),                //  output,    width = 1,                   .channel
        .rx_ss_valid            ( i_dp_ss[0].valid ),               //  output,    width = 1,              rx_ss.valid
        .rx_ss_data             ( i_dp_ss[0].data ),                //  output,  width = 160,                   .data
        .rx_ss_sop              ( i_dp_ss[0].sop ),                 //  output,    width = 1,                   .startofpacket
        .rx_ss_eop              ( i_dp_ss[0].eop ),                 //  output,    width = 1,                   .endofpacket
        .rx1_ss_valid           ( i_dp_ss[1].valid ),               //  output,    width = 1,             rx1_ss.valid
        .rx1_ss_data            ( i_dp_ss[1].data ),                //  output,  width = 160,                   .data
        .rx1_ss_sop             ( i_dp_ss[1].sop ),                 //  output,    width = 1,                   .startofpacket
        .rx1_ss_eop             ( i_dp_ss[1].eop ),                 //  output,    width = 1,                   .endofpacket
        .rx2_ss_valid           ( i_dp_ss[2].valid ),               //  output,    width = 1,             rx2_ss.valid
        .rx2_ss_data            ( i_dp_ss[2].data ),                //  output,  width = 160,                   .data
        .rx2_ss_sop             ( i_dp_ss[2].sop ),                 //  output,    width = 1,                   .startofpacket
        .rx2_ss_eop             ( i_dp_ss[2].eop ),                 //  output,    width = 1,                   .endofpacket
        .rx3_ss_valid           ( i_dp_ss[3].valid ),               //  output,    width = 1,             rx3_ss.valid
        .rx3_ss_data            ( i_dp_ss[3].data ),                //  output,  width = 160,                   .data
        .rx3_ss_sop             ( i_dp_ss[3].sop ),                 //  output,    width = 1,                   .startofpacket
        .rx3_ss_eop             ( i_dp_ss[3].eop ),                 //  output,    width = 1,                   .endofpacket
        .rx_ss_clk              ( dp_ss_clk ),                      //  output,    width = 1,          rx_ss_clk.clk
        .rx_msa                 ( dp_msa[0] ),                      //  output,  width = 217,     rx_msa_conduit.rx_msa
        .rx1_msa                ( dp_msa[1] ),                      //  output,  width = 217,    rx1_msa_conduit.rx1_msa
        .rx2_msa                ( dp_msa[2] ),                      //  output,  width = 217,    rx2_msa_conduit.rx2_msa
        .rx3_msa                ( dp_msa[3] ),                      //  output,  width = 217,    rx3_msa_conduit.rx3_msa
        .rx_audio_valid         ( i_dp_audio[0].valid ),            //  output,    width = 1,           rx_audio.rx_audio_valid
        .rx_audio_mute          ( i_dp_audio[0].mute ),             //  output,    width = 1,                   .rx_audio_mute
        .rx_audio_infoframe     ( i_dp_audio[0].infoframe ),        //  output,   width = 40,                   .rx_audio_infoframe
        .rx_audio_lpcm_data     ( i_dp_audio[0].lpcm_data ),        //  output,  width = 256,                   .rx_audio_lpcm_data
        .rx1_audio_valid        ( i_dp_audio[1].valid ),            //  output,    width = 1,          rx1_audio.rx1_audio_valid
        .rx1_audio_mute         ( i_dp_audio[1].mute ),             //  output,    width = 1,                   .rx1_audio_mute
        .rx1_audio_infoframe    ( i_dp_audio[1].infoframe ),        //  output,   width = 40,                   .rx1_audio_infoframe
        .rx1_audio_lpcm_data    ( i_dp_audio[1].lpcm_data ),        //  output,  width = 256,                   .rx1_audio_lpcm_data
        .rx2_audio_valid        ( i_dp_audio[2].valid ),            //  output,    width = 1,          rx2_audio.rx2_audio_valid
        .rx2_audio_mute         ( i_dp_audio[2].mute ),             //  output,    width = 1,                   .rx2_audio_mute
        .rx2_audio_infoframe    ( i_dp_audio[2].infoframe ),        //  output,   width = 40,                   .rx2_audio_infoframe
        .rx2_audio_lpcm_data    ( i_dp_audio[2].lpcm_data ),        //  output,  width = 256,                   .rx2_audio_lpcm_data
        .rx3_audio_valid        ( i_dp_audio[3].valid ),            //  output,    width = 1,          rx3_audio.rx3_audio_valid
        .rx3_audio_mute         ( i_dp_audio[3].mute ),             //  output,    width = 1,                   .rx3_audio_mute
        .rx3_audio_infoframe    ( i_dp_audio[3].infoframe ),        //  output,   width = 40,                   .rx3_audio_infoframe
        .rx3_audio_lpcm_data    ( i_dp_audio[3].lpcm_data ),        //  output,  width = 256,                   .rx3_audio_lpcm_data
        .rx_link_rate           ( i_xcvr_reconfig.link_rate ),      //  output,    width = 2,        rx_reconfig.rx_link_rate
        .rx_link_rate_8bits     ( i_xcvr_reconfig.link_rate_8bits ),//  output,    width = 8,                   .rx_link_rate_8bits
        .rx_reconfig_req        ( i_xcvr_reconfig.d_req ),          //  output,    width = 1,                   .rx_reconfig_req
        .rx_reconfig_ack        ( i_xcvr_reconfig.d_ack ),          //   input,    width = 1,                   .rx_reconfig_ack
        .rx_reconfig_busy       ( i_xcvr_reconfig.d_busy ),         //   input,    width = 1,                   .rx_reconfig_busy
        .rx_analog_reconfig_req ( i_xcvr_reconfig.a_req ),          //  output,    width = 1, rx_analog_reconfig.rx_analog_reconfig_req
        .rx_vod                 ( i_xcvr_reconfig.a_vod ),          //  output,    width = 8,                   .rx_vod
        .rx_emp                 ( i_xcvr_reconfig.a_emp ),          //  output,    width = 8,                   .rx_emp
        .rx_mgmt_chipselect     ( i_mgmt.cs ),                      //   input,    width = 1,            rx_mgmt.chipselect
        .rx_mgmt_read           ( i_mgmt.read ),                    //   input,    width = 1,                   .read
        .rx_mgmt_write          ( i_mgmt.write ),                   //   input,    width = 1,                   .write
        .rx_mgmt_address        ( i_mgmt.address ),                 //   input,    width = 9,                   .address
        .rx_mgmt_writedata      ( i_mgmt.writedata ),               //   input,   width = 32,                   .writedata
        .rx_mgmt_readdata       ( i_mgmt.readdata ),                //  output,   width = 32,                   .readdata
        .rx_mgmt_waitrequest    ( i_mgmt.waitrequest ),             //  output,    width = 1,                   .waitrequest
        .rx_mgmt_irq            ( mgmt_irq ),                       //  output,    width = 1,  rx_mgmt_interrupt.irq
        .clk                    ( clk ),                            //   input,    width = 1,                clk.clk
        .reset                  ( reset ),                          //   input,    width = 1,              reset.reset
        .aux_clk                ( aux_clk ),                        //   input,    width = 1,            aux_clk.clk
        .aux_reset              ( aux_reset ),                      //   input,    width = 1,          aux_reset.reset
        .xcvr_mgmt_clk          ( xcvr_reconfig_clk ),              //   input,    width = 1,      xcvr_mgmt_clk.clk
        .clk_cal                ( clk_cal )                         //   input,    width = 1,            clk_cal.clk
      );
    end else begin /* !MstSupport */
      dp_rx_sst u_dp_rx_sst (
        .rx_parallel_data       ( i_xcvr.data ),                    //   input,  width = 160,  rx_xcvr_interface.rx_parallel_data
        .rx_std_clkout          ( ReverseLaneOrder ? i_xcvr.std_clkout[Lanes-1] : i_xcvr.std_clkout[0] ),          //   input,    width = 1,                   .rx_std_clkout
        .rx_is_lockedtoref      ( i_xcvr.is_lockedtoref ),          //   input,    width = 4,                   .rx_is_lockedtoref
        .rx_is_lockedtodata     ( i_xcvr.is_lockedtodata ),         //   input,    width = 4,                   .rx_is_lockedtodata
        .rx_restart             ( i_xcvr.restart ),                 //  output,    width = 1,                   .rx_restart
        .rx_bitslip             ( i_xcvr.bitslip ),                 //  output,    width = 4,                   .rx_bitslip
        .rx_cal_busy            ( i_xcvr.cal_busy ),                //   input,    width = 4,                   .rx_cal_busy
        .rx_analogreset         ( i_xcvr.analogreset ),             //  output,    width = 4,                   .rx_analogreset
        .rx_digitalreset        ( i_xcvr.digitalreset ),            //  output,    width = 4,                   .rx_digitalreset
        .rx_set_locktoref       ( i_xcvr.set_locktoref ),           //  output,    width = 4,                   .rx_set_locktoref
        .rx_set_locktodata      ( i_xcvr.set_locktodata ),          //  output,    width = 4,                   .rx_set_locktodata
        .rx_aux_in              ( i_aux.in ),                       //   input,    width = 1,             rx_aux.rx_aux_in
        .rx_aux_out             ( i_aux.out ),                      //  output,    width = 1,                   .rx_aux_out
        .rx_aux_oe              ( i_aux.oe ),                       //  output,    width = 1,                   .rx_aux_oe
        .rx_hpd                 ( i_pwr.hpd ),                      //  output,    width = 1,                   .rx_hpd
        .rx_cable_detect        ( i_pwr.cable_detect ),             //   input,    width = 1,                   .rx_cable_detect
        .rx_pwr_detect          ( i_pwr.pwr_detect ),               //   input,    width = 1,                   .rx_pwr_detect
        .rx_lane_count          ( rx_lane_count ),                  //  output,    width = 5,          rx_params.rx_lane_count
        .rx_vid_sol             ( i_dp_video[0].sol ),              //  output,    width = 1,       rx_video_out.rx_vid_sol
        .rx_vid_eol             ( i_dp_video[0].eol ),              //  output,    width = 1,                   .rx_vid_eol
        .rx_vid_sof             ( i_dp_video[0].sof ),              //  output,    width = 1,                   .rx_vid_sof
        .rx_vid_eof             ( i_dp_video[0].eof ),              //  output,    width = 1,                   .rx_vid_eof
        .rx_vid_locked          ( i_dp_video[0].locked ),           //  output,    width = 1,                   .rx_vid_locked
        .rx_vid_interlace       ( i_dp_video[0].interlace ),        //  output,    width = 1,                   .rx_vid_interlace
        .rx_vid_field           ( i_dp_video[0].field ),            //  output,    width = 1,                   .rx_vid_field
        .rx_vid_overflow        ( i_dp_video[0].overflow ),         //  output,    width = 1,                   .rx_vid_overflow
        .rx_vid_data            ( i_dp_video[0].data ),             //  output,  width = 192,                   .rx_vid_data
        .rx_vid_valid           ( i_dp_video[0].valid ),            //  output,    width = 4,                   .rx_vid_valid
        .rx_vid_clk             ( i_dp_video[0].clk ),              //   input,    width = 1,         rx_vid_clk.clk
        .rx_stream_valid        ( stream_debug[0].valid ),          //  output,    width = 1,          rx_stream.rx_stream_valid
        .rx_stream_clk          ( stream_debug[0].clk ),            //  output,    width = 1,                   .rx_stream_clk
        .rx_stream_data         ( stream_debug[0].data ),           //  output,  width = 128,                   .rx_stream_data
        .rx_stream_ctrl         ( stream_debug[0].ctrl ),           //  output,   width = 16,                   .rx_stream_ctrl
        .rx_aux_debug_data      ( i_aux_debug.data ),               //  output,   width = 32,       rx_aux_debug.data
        .rx_aux_debug_valid     ( i_aux_debug.valid ),              //  output,    width = 1,                   .valid
        .rx_aux_debug_sop       ( i_aux_debug.sop ),                //  output,    width = 1,                   .startofpacket
        .rx_aux_debug_eop       ( i_aux_debug.eop ),                //  output,    width = 1,                   .endofpacket
        .rx_aux_debug_err       ( i_aux_debug.err ),                //  output,    width = 1,                   .error
        .rx_aux_debug_cha       ( i_aux_debug.cha ),                //  output,    width = 1,                   .channel
        .rx_ss_valid            ( i_dp_ss[0].valid ),               //  output,    width = 1,              rx_ss.valid
        .rx_ss_data             ( i_dp_ss[0].data ),                //  output,  width = 160,                   .data
        .rx_ss_sop              ( i_dp_ss[0].sop ),                 //  output,    width = 1,                   .startofpacket
        .rx_ss_eop              ( i_dp_ss[0].eop ),                 //  output,    width = 1,                   .endofpacket
        .rx_ss_clk              ( dp_ss_clk ),                      //  output,    width = 1,          rx_ss_clk.clk
        .rx_msa                 ( dp_msa[0] ),                      //  output,  width = 217,     rx_msa_conduit.rx_msa
        .rx_audio_valid         ( i_dp_audio[0].valid ),            //  output,    width = 1,           rx_audio.rx_audio_valid
        .rx_audio_mute          ( i_dp_audio[0].mute ),             //  output,    width = 1,                   .rx_audio_mute
        .rx_audio_infoframe     ( i_dp_audio[0].infoframe ),        //  output,   width = 40,                   .rx_audio_infoframe
        .rx_audio_lpcm_data     ( i_dp_audio[0].lpcm_data ),        //  output,  width = 256,                   .rx_audio_lpcm_data
        .rx_link_rate           ( i_xcvr_reconfig.link_rate ),      //  output,    width = 2,        rx_reconfig.rx_link_rate
        .rx_link_rate_8bits     ( i_xcvr_reconfig.link_rate_8bits ),//  output,    width = 8,                   .rx_link_rate_8bits
        .rx_reconfig_req        ( i_xcvr_reconfig.d_req ),          //  output,    width = 1,                   .rx_reconfig_req
        .rx_reconfig_ack        ( i_xcvr_reconfig.d_ack ),          //   input,    width = 1,                   .rx_reconfig_ack
        .rx_reconfig_busy       ( i_xcvr_reconfig.d_busy ),         //   input,    width = 1,                   .rx_reconfig_busy
        .rx_analog_reconfig_req ( i_xcvr_reconfig.a_req ),          //  output,    width = 1, rx_analog_reconfig.rx_analog_reconfig_req
        .rx_vod                 ( i_xcvr_reconfig.a_vod ),          //  output,    width = 8,                   .rx_vod
        .rx_emp                 ( i_xcvr_reconfig.a_emp ),          //  output,    width = 8,                   .rx_emp
        .rx_mgmt_chipselect     ( i_mgmt.cs ),                      //   input,    width = 1,            rx_mgmt.chipselect
        .rx_mgmt_read           ( i_mgmt.read ),                    //   input,    width = 1,                   .read
        .rx_mgmt_write          ( i_mgmt.write ),                   //   input,    width = 1,                   .write
        .rx_mgmt_address        ( i_mgmt.address ),                 //   input,   width = 11,                   .address
        .rx_mgmt_writedata      ( i_mgmt.writedata ),               //   input,   width = 32,                   .writedata
        .rx_mgmt_readdata       ( i_mgmt.readdata ),                //  output,   width = 32,                   .readdata
        .rx_mgmt_waitrequest    ( i_mgmt.waitrequest ),             //  output,    width = 1,                   .waitrequest
        .rx_mgmt_irq            ( mgmt_irq ),                       //  output,    width = 1,  rx_mgmt_interrupt.irq
        .clk                    ( clk ),                            //   input,    width = 1,                clk.clk
        .reset                  ( reset ),                          //   input,    width = 1,              reset.reset
        .aux_clk                ( aux_clk ),                        //   input,    width = 1,            aux_clk.clk
        .aux_reset              ( aux_reset ),                      //   input,    width = 1,          aux_reset.reset
        .xcvr_mgmt_clk          ( xcvr_reconfig_clk ),              //   input,    width = 1,      xcvr_mgmt_clk.clk
        .clk_cal                ( clk_cal )                         //   input,    width = 1,            clk_cal.clk
      );
    end
  endgenerate

endmodule : dp_rx_wrapper
