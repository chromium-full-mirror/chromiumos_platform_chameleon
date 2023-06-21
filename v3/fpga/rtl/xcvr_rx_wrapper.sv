/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module xcvr_rx_wrapper #(
    parameter bit IsHdmi           = 0, // TODO: Remove this parameter once both HDMI and DP
                                        //       paths will be proven to work
                                        //       and one GXB will be generated.
    parameter int Lanes            = IsHdmi ? 3 : 4,
    parameter int ReverseLaneOrder = 0
) (
    input  logic               clk, // reconfiguration clock, 100MHz
    input  logic               reset,

    xcvr_port_i.agent          i_xcvr_port,
    xcvr_i.host                i_xcvr,
    xcvr_dp_reconfig_i.agent   i_xcvr_dp_rcfg,
    xcvr_hdmi_config_i.agent   i_xcvr_hdmi_cfg
);

  /* Local parameters */
  localparam bit IsDp = !IsHdmi;

  /* Do not use reset signals from external interface -
   * this module has dedicated transceiver reset */
  logic [Lanes-1:0] xcvr_analogreset;
  logic [Lanes-1:0] xcvr_digitalreset;
  logic [Lanes-1:0] xcvr_rx_ready;

  /* Reconfiguration interface, driven by reconfiguration modules */
  avalon_mm_i #(.AddrWidth(12)) i_xcvr_rcfg();

  generate
  if (IsHdmi) begin
    import hdmi_rx_pkg::*;

    /* Helper signals to connect dependent modules */
    avalon_mm_i #(.AddrWidth(12)) i_xcvr_rcfg_mr();
    avalon_mm_i #(.AddrWidth(12)) i_xcvr_rcfg_ext();
    logic [Lanes-1:0] xcvrs_lockedtodata;
    logic [Lanes*BitSlipBoundarySel-1:0] xcvr_bitslipboundarysel;
    logic [Lanes*BitsPerLane*Symbols-1:0] xcvr_data_not_aligned;
    logic iopll_locked;
    logic reset_core;
    logic reset_xcvr;
    logic reset_pll;
    logic reset_pll_reconfig;
    logic token_detected;
    logic reconfig_pcs_in_progress;
    logic [63:0] reconfig_to_pll;
    logic [63:0] reconfig_from_pll;
    logic iopll_cdr_refclk;
    logic cdr_refclk;
    logic rx_reconfig_en;
    logic gxb_reset;
    logic gxb_reset_sync;
    logic [32*Lanes-1:0] xcvr_rcfg_readdata;
    logic [Lanes-1:0] xcvr_rcfg_waitrequest;
    logic [$clog2(Lanes-1):0] rx_ch_num;
    logic xcvr_rcfg_en;

    xcvr_switch_refclk u_xcvr_switch_refclk (
      .clk          ( clk             ),
      .rst          ( reset           ),
      .i_xcvr_rcfg  ( i_xcvr_rcfg_ext ),
      .cal_busy     ( i_xcvr.cal_busy ),
      .reconfig_en  ( xcvr_rcfg_en    )
    );

    assign rx_ch_num = i_xcvr_rcfg.address[11:10];
    assign i_xcvr_rcfg.readdata = xcvr_rcfg_readdata[32*rx_ch_num+:32];
    assign i_xcvr_rcfg.waitrequest = xcvr_rcfg_waitrequest[rx_ch_num];

    always_comb begin
      i_xcvr_rcfg.cs = '0;
      i_xcvr_rcfg.address = '0;
      i_xcvr_rcfg.byteenable = '0;
      i_xcvr_rcfg.read = '0;
      i_xcvr_rcfg.write = '0;
      i_xcvr_rcfg.writedata = '0;
      i_xcvr_rcfg.burstcount = '0;
      i_xcvr_rcfg_ext.readdata = '0;
      i_xcvr_rcfg_ext.waitrequest = '0;
      i_xcvr_rcfg_mr.readdata = '0;
      i_xcvr_rcfg_mr.waitrequest = '0;
      if (xcvr_rcfg_en) begin
        i_xcvr_rcfg.cs = i_xcvr_rcfg_ext.cs;
        i_xcvr_rcfg.address = i_xcvr_rcfg_ext.address;
        i_xcvr_rcfg.byteenable = i_xcvr_rcfg_ext.byteenable;
        i_xcvr_rcfg.read = i_xcvr_rcfg_ext.read;
        i_xcvr_rcfg_ext.readdata = i_xcvr_rcfg.readdata;
        i_xcvr_rcfg.write = i_xcvr_rcfg_ext.write;
        i_xcvr_rcfg_ext.waitrequest = i_xcvr_rcfg.waitrequest;
        i_xcvr_rcfg.writedata = i_xcvr_rcfg_ext.writedata;
        i_xcvr_rcfg.burstcount = i_xcvr_rcfg_ext.burstcount;
      end else begin
        i_xcvr_rcfg.cs = i_xcvr_rcfg_mr.cs;
        i_xcvr_rcfg.address = i_xcvr_rcfg_mr.address;
        i_xcvr_rcfg.byteenable = i_xcvr_rcfg_mr.byteenable;
        i_xcvr_rcfg.read = i_xcvr_rcfg_mr.read;
        i_xcvr_rcfg_mr.readdata = i_xcvr_rcfg.readdata;
        i_xcvr_rcfg.write = i_xcvr_rcfg_mr.write;
        i_xcvr_rcfg_mr.waitrequest = i_xcvr_rcfg.waitrequest;
        i_xcvr_rcfg.writedata = i_xcvr_rcfg_mr.writedata;
        i_xcvr_rcfg.burstcount = i_xcvr_rcfg_mr.burstcount;
      end
    end

    avalon_mm_i #(.AddrWidth(9)) i_xcvr_pll_reconfig();

    /* HDMI does not utilize set_lockedtodata, just looks for frequency locking. */
    assign xcvrs_lockedtodata = &i_xcvr.set_locktoref ?
                                i_xcvr.is_lockedtoref :
                                i_xcvr.is_lockedtodata;

    gxb_hdmi_rx u_gxb_rx (
      /* I */ .reconfig_write             ( {3{i_xcvr_rcfg.write}} ),
      /* I */ .reconfig_read              ( {3{i_xcvr_rcfg.read}} ),
      /* I */ .reconfig_address           ( {3{i_xcvr_rcfg.address[9:0]}} ),
      /* I */ .reconfig_writedata         ( {3{i_xcvr_rcfg.writedata}} ),
      /* O */ .reconfig_readdata          ( xcvr_rcfg_readdata ),
      /* O */ .reconfig_waitrequest       ( xcvr_rcfg_waitrequest ),
      /* I */ .reconfig_clk               ( {3{clk}} ),
      /* I */ .reconfig_reset             ( {3{reset}} ),
      /* I */ .rx_analogreset             ( xcvr_analogreset ),
      /* O */ .rx_cal_busy                ( i_xcvr.cal_busy ),
      /* I */ .rx_cdr_refclk0             ( i_xcvr_port.ref_clk ),
      /* I */ .rx_cdr_refclk1             ( cdr_refclk ),
      /* O */ .rx_clkout                  ( i_xcvr.std_clkout ),
      /* I */ .rx_coreclkin               ( i_xcvr.std_clkout ),
      /* I */ .rx_digitalreset            ( xcvr_digitalreset | {3{reconfig_pcs_in_progress}}),
      /* O */ .rx_is_lockedtodata         ( i_xcvr.is_lockedtodata ),
      /* O */ .rx_is_lockedtoref          ( i_xcvr.is_lockedtoref ),
      /* O */ .rx_parallel_data           ( xcvr_data_not_aligned ),
      /* I */ .rx_serial_data             ( i_xcvr_port.serial_data[Lanes-1:0] ), // Last port is
                                                                                  // TMDS clk
      /* I */ .rx_set_locktodata          ( 3'd0 ),
      /* I */ .rx_set_locktoref           ( i_xcvr.set_locktoref ),
      /* O */ .unused_rx_parallel_data    ( ),
      /* O */ .rx_patterndetect           ( ),
      /* O */ .rx_syncstatus              ( ),
      /* I */ .rx_std_wa_patternalign     ( 3'b000 ),
      /* O */ .rx_std_bitslipboundarysel  ( xcvr_bitslipboundarysel )
    );

    symbol_aligner #(
      .SYMBOLS_PER_CLOCK ( Symbols )
    ) u_symbol_aligner (
      /* I */ .mgmt_clk                     ( clk ),
      /* I */ .reset                        ( reset ),
      /* I */ .rx_clk                       ( i_xcvr.std_clkout ),
      /* I */ .rx_parallel_data             ( xcvr_data_not_aligned ),
      /* I */ .rx_std_bitslipboundarysel    ( xcvr_bitslipboundarysel ),
      /* I */ .rx_ready                     ( xcvr_rx_ready ),
      /* I */ .rx_reconfig_pcs_in_progress  ( reconfig_pcs_in_progress ),
      /* O */ .token_detected               ( token_detected ),
      /* O */ .rx_parallel_data_aligned     ( i_xcvr.data )
    );

    assign gxb_reset = reset || reset_xcvr || ~iopll_locked || xcvr_rcfg_en;
    altera_std_synchronizer #(
      .depth ( 3 )
    ) u_gxb_reset_sync (
      .clk      ( clk ),
      .reset_n  ( 1'b1 ),
      .din      ( gxb_reset ),
      .dout     ( gxb_reset_sync )
    );

    gxb_hdmi_rx_reset u_gxb_rx_reset (
      /* I */ .clock              ( clk ),
      /* I */ .reset              ( gxb_reset_sync ),
      /* O */ .rx_analogreset     ( xcvr_analogreset ),
      /* I */ .rx_cal_busy        ( i_xcvr.cal_busy ),
      /* O */ .rx_digitalreset    ( xcvr_digitalreset ),
      /* I */ .rx_is_lockedtodata ( xcvrs_lockedtodata ),
      /* O */ .rx_ready           ( xcvr_rx_ready )
    );

    mr_reconfig_mgmt #(
       .FAST_SIMULATION (0)
    ) u_mr_reconfig_mgmt (
      /* I */ .clock                    ( clk ),
      /* I */ .reset                    ( reset ),
      /* I */ .refclock                 ( i_xcvr_port.serial_data[Lanes] ),
      /* I */ .rx_is_20                 ( i_xcvr_hdmi_cfg.bit_clock_ratio ),
      /* I */ .rx_hdmi_locked           ( i_xcvr_hdmi_cfg.color_locked ),
      /* I */ .rx_color_depth           ( i_xcvr_hdmi_cfg.color_depth_sync ),
      /* I */ .rx_ready                 ( &xcvr_rx_ready ),
      /* I */ .pll_locked               ( iopll_locked ),
      /* O */ .reset_core               ( reset_core ),
      /* O */ .reset_vid                ( i_xcvr_hdmi_cfg.reset_vid ),
      /* O */ .reset_xcvr               ( reset_xcvr ),
      /* O */ .reset_pll                ( reset_pll ),
      /* O */ .reset_pll_reconfig       ( reset_pll_reconfig ),
      /* O */ .rx_set_locktoref         ( i_xcvr.set_locktoref ),
      /* O */ .measure                  ( i_xcvr_hdmi_cfg.tmds_measure ),
      /* O */ .measure_valid            ( i_xcvr_hdmi_cfg.tmds_measure_valid ),
      /* I */ .rx_cal_busy              ( i_xcvr.cal_busy ),
      /* I */ .rx_reconfig_waitrequest  ( i_xcvr_rcfg_mr.waitrequest ),
      /* I */ .rx_reconfig_readdata     ( i_xcvr_rcfg_mr.readdata ),
      /* O */ .rx_reconfig_write        ( i_xcvr_rcfg_mr.write ),
      /* O */ .rx_reconfig_read         ( i_xcvr_rcfg_mr.read ),
      /* O */ .rx_reconfig_address      ( i_xcvr_rcfg_mr.address ),
      /* O */ .rx_reconfig_writedata    ( i_xcvr_rcfg_mr.writedata ),
      /* I */ .pll_reconfig_waitrequest ( i_xcvr_pll_reconfig.waitrequest ),
      /* O */ .pll_reconfig_write       ( i_xcvr_pll_reconfig.write),
      /* O */ .pll_reconfig_address     ( i_xcvr_pll_reconfig.address),
      /* O */ .pll_reconfig_writedata   ( i_xcvr_pll_reconfig.writedata),
      /* O */ .rx_reconfig_en           ( rx_reconfig_en ),
      /* I */ .tkn_detected             ( token_detected ),
      /* O */ .reconfig_pcs_in_progress ( reconfig_pcs_in_progress )
    );

    // GPLL to generate HDMI clocks
    clock_control u_clock_control1 (
       /* I */ .inclk  ( iopll_cdr_refclk ),
       /* O */ .outclk ( cdr_refclk )
    );

    // The IO PLL is defaulted to the following settings to ease timing constraint/analysis
    // The default setting is not optimum for real time run, reconfig to the right value per incoming
    // stream rate will be performed (taken care by state machine in multi-rate operation) upon power-up.
    // refclk = 300MHz (for rate detect 24-bit counter)
    // outclk_0 = 600MHz (for GXB to generate output clock of 300MHz in 2-symbol mode)
    // outclk_1 = 300MHz (ls clk)
    // outclk_2 = 300MHz (vid clk)
    //wire pll_locked;

    pll_hdmi u_iopll (
       /* I */ .refclk            ( i_xcvr_port.serial_data[Lanes] ),
       /* I */ .rst               ( reset_pll ),
       /* O */ .outclk_0          ( iopll_cdr_refclk ),
       /* O */ .outclk_1          ( i_xcvr_hdmi_cfg.ls_clk ),
       /* O */ .outclk_2          ( i_xcvr_hdmi_cfg.vid_clk ),
       /* O */ .locked            ( iopll_locked ),
       /* I */ .reconfig_to_pll   ( reconfig_to_pll ),
       /* O */ .reconfig_from_pll ( reconfig_from_pll )
    );

    pll_hdmi_reconfig u_iopll_reconfig (
       /* I */ .mgmt_clk          ( clk ),
       /* I */ .mgmt_reset        ( reset_pll_reconfig ),
       /* O */ .mgmt_waitrequest  ( i_xcvr_pll_reconfig.waitrequest ),
       /* I */ .mgmt_read         ( /* unused */),
       /* I */ .mgmt_write        ( i_xcvr_pll_reconfig.write ),
       /* O */ .mgmt_readdata     ( /* unused */ ),
       /* I */ .mgmt_address      ( i_xcvr_pll_reconfig.address ),
       /* I */ .mgmt_writedata    ( i_xcvr_pll_reconfig.writedata ),
       /* O */ .reconfig_to_pll   ( reconfig_to_pll ),
       /* I */ .reconfig_from_pll ( reconfig_from_pll )
    );

    assign i_xcvr_hdmi_cfg.hdmi_lock = &xcvr_rx_ready & ~reset_core;

    /* Terminate unused interface */
    assign i_xcvr_dp_rcfg.d_ack  = 1'b0;
    assign i_xcvr_dp_rcfg.d_busy = 1'b1;

  end else begin /* IsDp */
    import dp_rx_pkg::*;
    /* Do not use reset signals from external interface -
     * this module has dedicated transceiver reset */
    logic [Lanes-1:0] xcvr_analogreset_ack;
    logic bitec_rcfg_reset;

    reg [2:0] restart_d;
    wire restart = restart_d[2];
    always @ (posedge clk)
      restart_d <= {restart_d[1:0],i_xcvr.restart};

    logic [Lanes-1:0] xcvr_is_lockedtodata;
    logic [Lanes-1:0] xcvr_is_lockedtoref;
    logic [Lanes-1:0] xcvr_set_locktodata;
    logic [Lanes-1:0] xcvr_set_locktoref;
    logic [Lanes*Symbols*10-1:0] xcvr_data;
    logic xcvr_coreclkin;

    gxb_dp_rx_reset gxb_rx_reset_i
    (
      .clock                ( clk ),
      .reset                ( reset | bitec_rcfg_reset | restart ),
      .rx_analogreset       ( xcvr_analogreset ),
      .rx_cal_busy          ( i_xcvr.cal_busy ),
      .rx_digitalreset      ( xcvr_digitalreset ),
      .rx_is_lockedtodata   ( i_xcvr.is_lockedtodata ),
      .rx_ready             ( xcvr_rx_ready )
    );

    gxb_dp_rx gxb_rx_i (
      .rx_cdr_refclk0             ( i_xcvr_port.ref_clk ),
      .reconfig_clk               ( clk ),
      .reconfig_reset             ( reset ),
      .reconfig_write             ( i_xcvr_rcfg.write ),
      .reconfig_read              ( i_xcvr_rcfg.read ),
      .reconfig_address           ( i_xcvr_rcfg.address ),
      .reconfig_writedata         ( i_xcvr_rcfg.writedata ),
      .reconfig_readdata          ( i_xcvr_rcfg.readdata ),
      .reconfig_waitrequest       ( i_xcvr_rcfg.waitrequest ),
      .rx_cal_busy                ( i_xcvr.cal_busy ),
      .rx_serial_data             ( i_xcvr_port.serial_data ),
      .rx_clkout                  ( i_xcvr.std_clkout ),

      .rx_analogreset             ( xcvr_analogreset ),
      .rx_analogreset_ack         ( xcvr_analogreset_ack ),
      .rx_digitalreset            ( xcvr_digitalreset ),
      .rx_set_locktodata          ( xcvr_set_locktodata ),
      .rx_set_locktoref           ( xcvr_set_locktoref ),
      .rx_bitslip                 ( i_xcvr.bitslip ),
      .rx_coreclkin               ( {Lanes{xcvr_coreclkin}} ),
      .rx_polinv                  ( i_xcvr.polinv ),
      .rx_is_lockedtodata         ( xcvr_is_lockedtodata ),
      .rx_is_lockedtoref          ( xcvr_is_lockedtoref ),
      .rx_parallel_data           ( xcvr_data ),

      .unused_rx_parallel_data    ()
    );

    if (ReverseLaneOrder) begin
      assign xcvr_coreclkin = i_xcvr.std_clkout[Lanes-1];
      assign xcvr_set_locktodata = { i_xcvr.set_locktodata[0], i_xcvr.set_locktodata[1],
                                     i_xcvr.set_locktodata[2], i_xcvr.set_locktodata[3] };
      assign xcvr_set_locktoref = { i_xcvr.set_locktoref[0], i_xcvr.set_locktoref[1],
                                    i_xcvr.set_locktoref[2], i_xcvr.set_locktoref[3] };
      assign i_xcvr.is_lockedtodata = { xcvr_is_lockedtodata[0], xcvr_is_lockedtodata[1],
                                        xcvr_is_lockedtodata[2], xcvr_is_lockedtodata[3]};
      assign i_xcvr.is_lockedtoref = { xcvr_is_lockedtoref[0], xcvr_is_lockedtoref[1],
                                       xcvr_is_lockedtoref[2], xcvr_is_lockedtoref[3]};
      assign i_xcvr.data = { xcvr_data[0+:(Symbols*10)],
                             xcvr_data[(1*Symbols*10)+:(Symbols*10)],
                             xcvr_data[(2*Symbols*10)+:(Symbols*10)],
                             xcvr_data[(3*Symbols*10)+:(Symbols*10)]};
    end else begin /* !ReverseLaneOrder */
      assign xcvr_coreclkin = i_xcvr.std_clkout[0];
      assign xcvr_set_locktodata = i_xcvr.set_locktodata;
      assign xcvr_set_locktoref = i_xcvr.set_locktoref;
      assign i_xcvr.is_lockedtodata = xcvr_is_lockedtodata;
      assign i_xcvr.is_lockedtoref = xcvr_is_lockedtoref;
      assign i_xcvr.data = xcvr_data;
    end

    assign i_xcvr_dp_rcfg.d_ack = 1'b1;

    bitec_reconfig_alt_a10 #(
      .RX_LANES ( Lanes ),
      .RX_RATES_NUM ( 4 )
    ) bitec_reconfig_alt_a10_i (
      .clk                      ( clk ),
      .reset                    ( reset ),
      .rx_analogreset_ack       ( &xcvr_analogreset_ack ),

      .rx_link_rate             ( i_xcvr_dp_rcfg.link_rate_8bits ),
      .rx_link_rate_strobe      ( i_xcvr_dp_rcfg.d_req ),
      .rx_xcvr_busy             ( i_xcvr_dp_rcfg.d_busy ),
      .rx_xcvr_reset            ( bitec_rcfg_reset ),
      .rx_vodemp_strobe         ( i_xcvr_dp_rcfg.a_req ),
      .rx_vod                   ( i_xcvr_dp_rcfg.a_vod ),
      .rx_emp                   ( i_xcvr_dp_rcfg.a_emp ),

        // TX Reconfig (Not Used)
      .tx_analogreset_ack       (1'b0),
      .tx_link_rate             (8'd0),
      .tx_vod                   (8'd0),
      .tx_emp                   (8'd0),
      .tx_link_rate_strobe      (1'b0),
      .tx_vodemp_strobe         (1'b0),
      .tx_mgmt_readdata         (32'd0),
      .tx_mgmt_waitrequest      (1'b0),
      .txpll_mgmt_readdata      (32'd0),
      .txpll_mgmt_waitrequest   (1'b0),
      .tx_xcvr_cal_busy         (1'b0),
      .tx_pll_cal_busy          (1'b0),
      // Management interface
      .rx_mgmt_chnum            ( i_xcvr_rcfg.address[11:10]),
      .rx_mgmt_address          ( i_xcvr_rcfg.address[9:0]),
      .rx_mgmt_writedata        ( i_xcvr_rcfg.writedata),
      .rx_mgmt_readdata         ( i_xcvr_rcfg.readdata),
      .rx_mgmt_write            ( i_xcvr_rcfg.write),
      .rx_mgmt_read             ( i_xcvr_rcfg.read),
      .rx_mgmt_waitrequest      ( i_xcvr_rcfg.waitrequest),
      .rx_xcvr_cal_busy         ( |i_xcvr.cal_busy )
    );
  end
  endgenerate

endmodule : xcvr_rx_wrapper
