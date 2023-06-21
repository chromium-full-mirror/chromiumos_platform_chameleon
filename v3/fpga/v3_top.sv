/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Top level verilog module representing the v3 fpga

`default_nettype none

module v3_top #(
    parameter int Host2FpgaDataWidth   = 128,
    parameter int Fpga2HostDataWidth   = 128,
    parameter int LwHost2FpgaDataWidth = 32,
    parameter int DpMstPort1SstPort2   = 0, // either parameter must be set
    parameter int DpMstPort2SstPort1   = 1
) (
    input  wire        emif_a10_hps_0_pll_ref_clk_clk, // clk
    input  wire        emif_a10_hps_0_oct_oct_rzqin,   // oct_rzqin
    output wire [0:0]  emif_a10_hps_0_mem_mem_ck,      // mem_ck
    output wire [0:0]  emif_a10_hps_0_mem_mem_ck_n,    // mem_ck_n
    output wire [16:0] emif_a10_hps_0_mem_mem_a,       // mem_a
    output wire [0:0]  emif_a10_hps_0_mem_mem_act_n,   // mem_act_n
    output wire [1:0]  emif_a10_hps_0_mem_mem_ba,      // mem_ba
    output wire [1:0]  emif_a10_hps_0_mem_mem_bg,      // mem_bg
    output wire [0:0]  emif_a10_hps_0_mem_mem_cke,     // mem_cke
    output wire [0:0]  emif_a10_hps_0_mem_mem_cs_n,    // mem_cs_n
    output wire [0:0]  emif_a10_hps_0_mem_mem_odt,     // mem_odt
    output wire [0:0]  emif_a10_hps_0_mem_mem_reset_n, // mem_reset_n
    output wire [0:0]  emif_a10_hps_0_mem_mem_par,     // mem_par
    input  wire [0:0]  emif_a10_hps_0_mem_mem_alert_n, // mem_alert_n
    inout  wire [4:0]  emif_a10_hps_0_mem_mem_dqs,     // mem_dqs
    inout  wire [4:0]  emif_a10_hps_0_mem_mem_dqs_n,   // mem_dqs_n
    inout  wire [39:0] emif_a10_hps_0_mem_mem_dq,      // mem_dq
    inout  wire [4:0]  emif_a10_hps_0_mem_mem_dbi_n,   // mem_dbi_n

    output wire hps_io_hps_io_phery_emac0_TX_CLK, // hps_io_phery_emac0_TX_CLK
    output wire hps_io_hps_io_phery_emac0_TXD0,   // hps_io_phery_emac0_TXD0
    output wire hps_io_hps_io_phery_emac0_TXD1,   // hps_io_phery_emac0_TXD1
    output wire hps_io_hps_io_phery_emac0_TXD2,   // hps_io_phery_emac0_TXD2
    output wire hps_io_hps_io_phery_emac0_TXD3,   // hps_io_phery_emac0_TXD3
    input  wire hps_io_hps_io_phery_emac0_RX_CTL, // hps_io_phery_emac0_RX_CTL
    output wire hps_io_hps_io_phery_emac0_TX_CTL, // hps_io_phery_emac0_TX_CTL
    input  wire hps_io_hps_io_phery_emac0_RX_CLK, // hps_io_phery_emac0_RX_CLK
    input  wire hps_io_hps_io_phery_emac0_RXD0,   // hps_io_phery_emac0_RXD0
    input  wire hps_io_hps_io_phery_emac0_RXD1,   // hps_io_phery_emac0_RXD1
    input  wire hps_io_hps_io_phery_emac0_RXD2,   // hps_io_phery_emac0_RXD2
    input  wire hps_io_hps_io_phery_emac0_RXD3,   // hps_io_phery_emac0_RXD3
    inout  wire hps_io_hps_io_phery_emac0_MDIO,   // hps_io_phery_emac0_MDIO
    output wire hps_io_hps_io_phery_emac0_MDC,    // hps_io_phery_emac0_MDC

    inout  wire hps_io_hps_io_phery_sdmmc_CMD,    // hps_io_phery_sdmmc_CMD
    inout  wire hps_io_hps_io_phery_sdmmc_D0,     // hps_io_phery_sdmmc_D0
    inout  wire hps_io_hps_io_phery_sdmmc_D1,     // hps_io_phery_sdmmc_D1
    inout  wire hps_io_hps_io_phery_sdmmc_D2,     // hps_io_phery_sdmmc_D2
    inout  wire hps_io_hps_io_phery_sdmmc_D3,     // hps_io_phery_sdmmc_D3




    output wire hps_io_hps_io_phery_sdmmc_CCLK,   // hps_io_phery_sdmmc_CCLK

    inout  wire hps_io_hps_io_phery_usb0_DATA0,   // hps_io_phery_usb0_DATA0
    inout  wire hps_io_hps_io_phery_usb0_DATA1,   // hps_io_phery_usb0_DATA1
    inout  wire hps_io_hps_io_phery_usb0_DATA2,   // hps_io_phery_usb0_DATA2
    inout  wire hps_io_hps_io_phery_usb0_DATA3,   // hps_io_phery_usb0_DATA3
    inout  wire hps_io_hps_io_phery_usb0_DATA4,   // hps_io_phery_usb0_DATA4
    inout  wire hps_io_hps_io_phery_usb0_DATA5,   // hps_io_phery_usb0_DATA5
    inout  wire hps_io_hps_io_phery_usb0_DATA6,   // hps_io_phery_usb0_DATA6
    inout  wire hps_io_hps_io_phery_usb0_DATA7,   // hps_io_phery_usb0_DATA7
    input  wire hps_io_hps_io_phery_usb0_CLK,     // hps_io_phery_usb0_CLK
    output wire hps_io_hps_io_phery_usb0_STP,     // hps_io_phery_usb0_STP
    input  wire hps_io_hps_io_phery_usb0_DIR,     // hps_io_phery_usb0_DIR
    input  wire hps_io_hps_io_phery_usb0_NXT,     // hps_io_phery_usb0_NXT

    //UART
    input  wire hps_io_hps_io_phery_uart1_RX,     // hps_io_phery_uart1_RX
    output wire hps_io_hps_io_phery_uart1_TX,     // hps_io_phery_uart1_TX

    inout  wire hps_io_hps_io_phery_i2c1_SDA,     // hps_io_phery_i2c1_SDA
    inout  wire hps_io_hps_io_phery_i2c1_SCL,     // hps_io_phery_i2c1_SCL

    // Boot selection
    inout  wire FLASH_SEL_BS1,
    // shared with LEDs 3
    inout  wire Led3_N_HPS_BS0,

    // LEDs
    // LEDs 0-1 connected to HPS shared pins
    // LEDs 2 connected to FPGA bank 3B
    inout  wire Led0_N,
    inout  wire Led1_N,
    output wire Led2_N,

    // Peripheral interrupts
    // TODO: fix port 2J vref problems
    //input  wire I2cInt,
    //input  wire RtcInt,
    //input  wire EthInt,
    //input  wire Fx3Int,

    //            -- GPIO/SD
    //            hps_io_hps_io_gpio_gpio1_io12           : inout  std_wire                     := 'X';             -- hps_io_gpio_gpio1_io12
    //            hps_io_hps_io_gpio_gpio1_io13           : inout  std_wire                     := 'X';             -- hps_io_gpio_gpio1_io13
    //            hps_io_hps_io_gpio_gpio1_io14           : inout  std_wire                     := 'X';             -- hps_io_gpio_gpio1_io14
    //            hps_io_hps_io_gpio_gpio1_io15           : inout  std_wire                     := 'X';             -- hps_io_gpio_gpio1_io15
    //            hps_io_hps_io_gpio_gpio1_io16           : inout  std_wire                     := 'X';             -- hps_io_gpio_gpio1_io16
    //            hps_io_hps_io_gpio_gpio1_io17           : inout  std_wire                     := 'X';             -- hps_io_gpio_gpio1_io17

    // System pins
    inout wire logic Flash_OE_N,
    // Core and MGT voltage selection
    // TODO: fix port 2K vref problems
    inout wire logic PWR_INT_VSEL,
    //output wire PWR_MGT_VSEL,

    // Bank 3B (by default used for FX3)
    inout wire logic FX3_A0_B3B_L5_U5_N,
    inout wire logic FX3_A1_B3B_L3_T6_P,
    inout wire logic FX3_DQ0_B3B_L8_K4_P,
    inout wire logic FX3_DQ10_B3B_L14_H1_P,
    inout wire logic FX3_DQ11_B3B_L14_G1_N,
    inout wire logic FX3_DQ12_B3B_L10_J3_N,
    inout wire logic FX3_DQ13_B3B_L7_M4_N,
    inout wire logic FX3_DQ14_B3B_L9_N2_P,
    inout wire logic FX3_DQ15_B3B_L1_P3_P,
    inout wire logic FX3_DQ16_B3B_L24_V3_N,
    inout wire logic FX3_DQ17_B3B_L19_U3_P,
    inout wire logic FX3_DQ18_B3B_L23_V2_N,
    inout wire logic FX3_DQ19_B3B_L24_W3_P,
    inout wire logic FX3_DQ1_B3B_L8_L4_N,
    inout wire logic FX3_DQ20_B3B_L19_U4_N,
    inout wire logic FX3_DQ21_B3B_L23_W2_P,
    inout wire logic FX3_DQ22_B3B_L20_U1_N,
    inout wire logic FX3_DQ23_B3B_L20_V1_P,
    inout wire logic FX3_DQ24_B3B_L13_CLK0_M1_N,
    inout wire logic FX3_DQ25_B3B_L22_V5_P,
    inout wire logic FX3_DQ26_B3B_L21_V7_N,
    inout wire logic FX3_DQ27_B3B_L21_U6_P,
    inout wire logic FX3_DQ28_B3B_L12_CLK1_L3_N,
    inout wire logic FX3_DQ29_B3B_L22_V6_N,
    inout wire logic FX3_DQ2_B3B_L4_R5_N,
    inout wire logic FX3_DQ30_B3B_L12_CLK1_L2_P,
    inout wire logic FX3_DQ31_B3B_L13_CLK0_N1_P,
    inout wire logic FX3_DQ3_B3B_L11_RZQ_K2_P,
    inout wire logic FX3_DQ4_B3B_L17_L1_P,
    inout wire logic FX3_DQ5_B3B_L4_R4_P,
    inout wire logic FX3_DQ6_B3B_L11_J2_N,
    inout wire logic FX3_DQ7_B3B_L17_K1_N,
    inout wire logic FX3_DQ8_B3B_L10_H2_P,
    inout wire logic FX3_DQ9_B3B_L7_M3_P,
    inout wire logic FX3_FLAGA_B3B_L15_R2_P,
    inout wire logic FX3_FLAGB_B3B_L18_T1_P,
    inout wire logic FX3_GPIO23_B3B_L16_T3_N,
    inout wire logic FX3_GPIO25_B3B_L5_T4_P,
    inout wire logic FX3_GPIO26_B3B_L18_R1_N,
    inout wire logic FX3_GPIO27_B3B_L3_T7_N,
    inout wire logic FX3_PKTEND_B3B_L1_P4_N_n,
    inout wire logic FX3_SLCS_B3B_L9_N3_N_n,
    inout wire logic FX3_SLRD_B3B_L15_P2_N_n,
    inout wire logic FX3_SLWR_B3B_L16_T2_P_n,
    // Pins used only by the FX3 (not routed to the module connector)
    inout wire logic FX3_SLOE_n,
    inout wire logic FX3_CLK,
    inout wire logic FX3_RESET_PL_n,

    // Chameleon board pins
    // Pasted and massaged from: go/chameleon-v3-fpga-pinout
    output     logic UART_FPGA_TX_AUD_BD_RX_LS,
    output     logic UART_FPGA_RX_AUD_BD_TX_LS,
    inout wire logic AUD_BD_I2C_SCL,
    inout wire logic AUD_BD_I2C_SDA,

    input wire logic DP1_SOM_AUX_IN,
    output     logic DP1_SOM_AUX_OE,
    output     logic DP1_SOM_AUX_OUT,
    input wire logic DP1_SOM_PS8469_HPD,

    output     logic DP1_SOM_PS8469_L0_P,
    output     logic DP1_SOM_PS8469_L1_P,
    output     logic DP1_SOM_PS8469_L2_P,
    output     logic DP1_SOM_PS8469_L3_P,

    inout wire logic DP1_SOM_PS8469_SCL,
    inout wire logic DP1_SOM_PS8469_SDA,

    input wire logic DP2_SOM_AUX_IN,
    output     logic DP2_SOM_AUX_OE,
    output     logic DP2_SOM_AUX_OUT,
    input wire logic DP2_SOM_PS8469_HPD,

    output     logic DP2_SOM_PS8469_L0_P,
    output     logic DP2_SOM_PS8469_L1_P,
    output     logic DP2_SOM_PS8469_L2_P,
    output     logic DP2_SOM_PS8469_L3_P,

    inout wire logic DP2_SOM_PS8469_SCL,
    inout wire logic DP2_SOM_PS8469_SDA,

    input wire logic DP213_SOMP1_AUX_IN,
    output     logic DP213_SOMP1_AUX_OE,
    output     logic DP213_SOMP1_AUX_OUT,
    output     logic DP213_SOMP1_HPD,
    input wire logic DP213_SOMP1_L0_P,
    input wire logic DP213_SOMP1_L1_P,
    input wire logic DP213_SOMP1_L2_P,
    input wire logic DP213_SOMP1_B3_P,
    input wire logic DP213_SOMP1_C3_P,
    inout wire logic SOMP1_IN_DDC_SDA,
    inout wire logic SOMP1_IN_DDC_SCL,

    input wire logic DP213_SOMP2_AUX_IN,
    output     logic DP213_SOMP2_AUX_OE,
    output     logic DP213_SOMP2_AUX_OUT,
    output     logic DP213_SOMP2_HPD,
    input wire logic DP213_SOMP2_L0_P,
    input wire logic DP213_SOMP2_L1_P,
    input wire logic DP213_SOMP2_L2_P,
    input wire logic DP213_SOMP2_B3_P,
    input wire logic DP213_SOMP2_C3_P,

    inout wire logic HDMI_OUT_CEC,
    inout wire logic HDMI_SOM_CEC,

    input wire logic [59:0] IT68051_QD,
    input wire logic IT68051_DE,
    input wire logic IT68051_HSYNC,
    input wire logic IT68051_VSYNC,
    input wire logic IT68051_SCDT,

    input wire logic IT68051_I2S0,
    input wire logic IT68051_I2S1,
    input wire logic IT68051_I2S2,
    input wire logic IT68051_I2S3,
    input wire logic IT68051_I2S4,
    input wire logic IT68051_I2S5,
    input wire logic IT68051_MCLK,
    input wire logic IT68051_MUTE,
    input wire logic IT68051_PCLK,
    input wire logic IT68051_SCK,
    input wire logic IT68051_SPDIF,
    input wire logic IT68051_WS,

    input wire logic PCIE_MB_V3_0_P,
    input wire logic PCIE_MB_V3_1_P,
    input wire logic PCIE_MB_V3_2_P,
    input wire logic PCIE_MB_V3_3_P,
    input wire logic PCIE_HDMI_REFCLKB_P,
    input wire logic DP_REFCLK_P,
    output     logic PCIE_V3_MB_0_P,
    output     logic PCIE_V3_MB_1_P,
    output     logic PCIE_V3_MB_2_P,
    output     logic PCIE_V3_MB_3_P,

    input wire logic SOM_AUD_ADCDAT,
    input wire logic SOM_AUD_ADCLRCK,
    output     logic SOM_AUD_DACDAT,
    input wire logic SOM_AUD_DACLRCK,
    inout wire logic SOM_AUD_I2C_SCL,
    inout wire logic SOM_AUD_I2C_SDA,
    input wire logic SOM_AUD_BCLK,
    output     logic SOM_AUD_MCLK_SEL,

    inout wire logic SOMP2_IN_DDC_SCL,
    inout wire logic SOMP2_IN_DDC_SDA,

    input wire logic SOM_USBH_ID,

    input wire logic SOM_PCIE_PERST_L,
    inout wire logic SOM_A21,
    inout wire logic SOM_A98,
    output wire logic SOM_A104,

    inout wire UART_STM_TX_SOM_RX,
    inout wire UART_STM_RX_SOM_TX,

    inout wire GPIO1_IO1,
    inout wire GPIO1_IO0,
    inout wire GPIO1_IO9,
    inout wire GPIO1_IO8,

    inout wire logic TP66,
    inout wire logic TP67,
    inout wire logic TP70,
    inout wire logic TP76,
    inout wire logic TP77,
    inout wire logic TP78,
    inout wire logic TP79,
    inout wire logic TP80,
    inout wire logic TP81,
    inout wire logic TP82,
    inout wire logic TP83,
    inout wire logic TP84,
    inout wire logic TP85,
    inout wire logic TP86,
    inout wire logic TP87,
    inout wire logic TP106,
    input wire logic HDMI1_IN_PP1800,
    input wire logic HDMI2_IN_PP1800
);

  localparam int Fpga2HostWordWidth = 8;

  localparam int It68051ChannelNum = 4;

  import vid_rx_pkg::MstCount;

  logic clk;
  (* maxfan = 500 *) logic rst;
  logic clk_100;
  (* maxfan = 500 *) logic rst_100;

  logic [3:0]  fb0_irq, fb0_irq_status, fb0_irq_eof;
  logic        fb0_irq_to_hps;
  logic [MstCount-1:0][3:0] fb_dp_irq;
  logic [MstCount-1:0]      fb_dp_irq_to_hps;
  logic [0:0][3:0]          fb_dp_sst_irq;
  logic                     fb_dp_sst_irq_to_hps;

  logic [23:0] led_counter;

  logic [59:0] it68051_qd_remapped;
  logic [3:0]  it68051_from_gpio;

  logic                i2s_it_irq_to_hps;
  logic                i2s_ssm_irq_to_hps;
  logic                dp_mgmt_irq_to_hps;
  logic                dp_sst_mgmt_irq_to_hps;
  logic [MstCount-1:0] i2s_dp_irq_to_hps;
  logic                i2s_dp_sst_irq_to_hps;

  logic [31:0] irq0;

  assign irq0[irq_pkg::kFb0]            = fb0_irq_to_hps;
  assign irq0[irq_pkg::kI2sIt]          = i2s_it_irq_to_hps;
  assign irq0[irq_pkg::kI2sSsm]         = i2s_ssm_irq_to_hps;
  assign irq0[irq_pkg::kFbDpMst0]       = fb_dp_irq_to_hps[0];
  assign irq0[irq_pkg::kFbDpMst1]       = fb_dp_irq_to_hps[1];
  assign irq0[irq_pkg::kFbDpMst2]       = fb_dp_irq_to_hps[2];
  assign irq0[irq_pkg::kFbDpMst3]       = fb_dp_irq_to_hps[3];
  assign irq0[irq_pkg::kFbDpSst]        = fb_dp_sst_irq_to_hps;
  assign irq0[irq_pkg::kDpMstMgmt]      = dp_mgmt_irq_to_hps;
  assign irq0[irq_pkg::kI2sDpMst0]      = i2s_dp_irq_to_hps[0];
  assign irq0[irq_pkg::kI2sDpMst1]      = i2s_dp_irq_to_hps[1];
  assign irq0[irq_pkg::kI2sDpMst2]      = i2s_dp_irq_to_hps[2];
  assign irq0[irq_pkg::kI2sDpMst3]      = i2s_dp_irq_to_hps[3];
  assign irq0[irq_pkg::kI2sDpSst]       = i2s_dp_sst_irq_to_hps;
  assign irq0[irq_pkg::kDpSstMgmt]      = dp_sst_mgmt_irq_to_hps;

  assign irq0[31:(irq_pkg::kDpSstMgmt+1)]  = '0;

  framebuffer_pkg::input_word_t it68051_vid;
  framebuffer_pkg::io_map_t fb_ddio;
  framebuffer_pkg::io_map_t fb_ddio_d;
  framebuffer_pkg::io_map_t fb_ddio_d2;

`ifdef CFG_DP_ENABLED
  dp_video_i i_dp_sst_video[0:0]();
  xcvr_port_i #(.XcvrLaneCount(4)) i_xcvr_port_dp_sst();
  xcvr_i #(.XcvrDataWidth(160), .XcvrLaneCount(4)) i_xcvr_dp_sst();
  xcvr_dp_reconfig_i i_dp_sst_rcfg();
  xcvr_hdmi_config_i i_dp_sst_hdmi_cfg_unused();
  dp_aux_i i_dp_sst_aux();
  pwr_hpd_i i_dp_sst_pwr();
  dp_ss_i i_dp_sst_ss[0:0]();
  dp_rx_pkg::dp_msa_t dp_sst_msa[0:0];
  dp_audio_i i_dp_sst_audio[0:0]();
  avalon_mm_i #(.AddrWidth(11)) i_dp_sst_mgmt();
  logic dp_sst_mgmt_irq;

  dp_video_i i_dp_video[MstCount-1:0]();
  xcvr_port_i #(.XcvrLaneCount(4)) i_xcvr_port_dp();
  xcvr_i #(.XcvrDataWidth(160), .XcvrLaneCount(4)) i_xcvr_dp();
  xcvr_dp_reconfig_i i_dp_rcfg();
  xcvr_hdmi_config_i i_hdmi_cfg_unused();
  dp_aux_i i_dp_aux();
  pwr_hpd_i i_dp_pwr();
  dp_ss_i i_dp_ss[MstCount-1:0]();
  dp_rx_pkg::dp_msa_t dp_msa[MstCount-1:0];
  dp_audio_i i_dp_audio[MstCount-1:0]();
  avalon_mm_i #(.AddrWidth(11)) i_dp_mgmt();
  logic dp_mgmt_irq;
`endif

  always_comb begin
    /*
     * Helper signals to more easily assign the pins that are actually
     * constrained by the HPS.
     */
    it68051_vid.qd         = IT68051_QD;
    it68051_vid.ctrl.de    = IT68051_DE;
    it68051_vid.ctrl.hsync = IT68051_HSYNC;
    it68051_vid.ctrl.vsync = IT68051_VSYNC;
    it68051_vid.ctrl.scdt  = IT68051_SCDT;
  end

  ap_fb_ddio u_ddr (
    .ck     (IT68051_PCLK),  //   input,    width = 1,     ck.export
    .dout   (fb_ddio.ddio),  //  output,  width = 128,   dout.export
    .pad_in (it68051_vid)    //   input,   width = 64, pad_in.export
  );

  always_ff @(posedge IT68051_PCLK) begin
    fb_ddio_d  <= fb_ddio;
    fb_ddio_d2 <= fb_ddio_d;
  end


  /* i2s IT68051 core interface definitions */
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(i2s_registers_pkg::AddrWidth))  i_i2s_it68051_csr();
  aximm_i #(.DataWidth(Fpga2HostDataWidth),
            .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_i2s_it68051_dma();
  i2s_if i_i2s_it68051_rx[It68051ChannelNum-1:0]();
  i2s_pkg::irq_source_t i2s_it_irq_source;

  /* i2s SSM core interface definitions */
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(i2s_registers_pkg::AddrWidth))  i_i2s_ssm2603_csr();
  aximm_i #(.DataWidth(Fpga2HostDataWidth),
            .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_i2s_ssm2603_dma();
  i2s_if i_i2s_ssm2603_rx();
  i2s_if i_i2s_ssm2603_tx();
  i2s_pkg::irq_source_t i2s_ssm_irq_source;

  /* I2S core definitions for DisplayPort MST and SST */
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(framebuffer_registers_pkg::AddrWidth)) i_aud_dp_csr[MstCount-1:0]();
  aximm_i #(.DataWidth(Fpga2HostDataWidth),
            .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_aud_dp_mst_dma();
  i2s_pkg::irq_source_t i2s_dp_irq_source[MstCount-1:0];

  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(framebuffer_registers_pkg::AddrWidth)) i_aud_dp_sst_csr[0:0]();
  aximm_i #(.DataWidth(Fpga2HostDataWidth),
            .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_aud_dp_sst_dma();
  i2s_pkg::irq_source_t i2s_dp_sst_irq_source[0:0];

  assign i_i2s_ssm2603_rx.clk  = SOM_AUD_BCLK;
  assign i_i2s_ssm2603_rx.ws   = SOM_AUD_ADCLRCK;
  assign i_i2s_ssm2603_rx.data = SOM_AUD_ADCDAT;

  assign i_i2s_ssm2603_tx.clk  = SOM_AUD_BCLK;
  assign i_i2s_ssm2603_tx.ws   = SOM_AUD_DACLRCK;
  assign SOM_AUD_DACDAT = i_i2s_ssm2603_tx.data;

  for (genvar i = 0; i < It68051ChannelNum; i++) begin : gen_it68051_i2s_input
    assign i_i2s_it68051_rx[i].clk = IT68051_SCK;
    assign i_i2s_it68051_rx[i].ws  = IT68051_WS;
  end
  assign i_i2s_it68051_rx[0].data  = IT68051_I2S0;
  assign i_i2s_it68051_rx[1].data  = IT68051_I2S1;
  assign i_i2s_it68051_rx[2].data  = IT68051_I2S2;
  assign i_i2s_it68051_rx[3].data  = IT68051_I2S3;

  /* Unused signals from AXI-MM for i_i2s_it68051_csr */
  assign i_i2s_it68051_csr.awuser = '0;
  assign i_i2s_it68051_csr.aruser = '0;

  logic [2:0]  i2s_it68051_csr_awprot;
  logic        i2s_it68051_csr_wlast;
  logic [2:0]  i2s_it68051_csr_arprot;

  /* i2s_it core instance */
  i2s_it #(
      .I2sDmaId       ( axis_to_aximm_pkg::kIdIt68051Dma ),
      .MaxRingBytes   ( 32'h0020_0000                    ),
      .ItChannelNum   ( It68051ChannelNum                ),
      .DataOutWidth   ( Fpga2HostDataWidth               )
  ) u_i2s_it (
      .clk            ( clk                 ),
      .rst            ( rst                 ),
      .i_i2s_rx       ( i_i2s_it68051_rx    ),
      .i_axi_lite     ( i_i2s_it68051_csr   ),
      .i_data_out     ( i_i2s_it68051_dma   ),
      .irq            ( i2s_it_irq_source   )
  );

  /* Framebuffer interfaces */
  axis_i  #(.DataWidth(Fpga2HostDataWidth), .WordWidth(8),
            .Tuser(framebuffer_pkg::fb_dma_meta_t))                 i_axis_fb0_dma();
  axis_i  #(.DataWidth(Fpga2HostDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))                      i_axis_fb0_dma_burst();
  axis_i  #(.DataWidth(Fpga2HostDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))                      i_axis_fb0_dma_rq_dummy();
  axis_i  #(.DataWidth(Fpga2HostDataWidth), .WordWidth(8),
            .Tuser(axis_to_aximm_pkg::meta_t))                      i_axis_fb0_dma_resp_dummy();

  aximm_i #(.DataWidth(Fpga2HostDataWidth), .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_fb0_dma();

  aximm_i #(.DataWidth(Fpga2HostDataWidth), .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_fb_dp_dma[MstCount-1:0]();

  aximm_i #(.DataWidth(Fpga2HostDataWidth), .AddrWidth(axis_to_aximm_pkg::AddrWidth),
            .IdWidth($bits(axis_to_aximm_pkg::ap_id_e))) i_fb_dp_sst_dma[0:0]();

  /* Signals terminated at AP, default assignment */
  assign i_i2s_it68051_dma.bresp = gaxilite_pkg::kOkay;
  assign i_i2s_it68051_dma.rresp = gaxilite_pkg::kOkay;
  assign i_i2s_ssm2603_dma.bresp = gaxilite_pkg::kOkay;
  assign i_i2s_ssm2603_dma.rresp = gaxilite_pkg::kOkay;
  assign i_fb0_dma.bresp = gaxilite_pkg::kOkay;
  assign i_fb0_dma.rresp = gaxilite_pkg::kOkay;

  /* UART0 connections and I/O buffers */
  logic uart0_rx;
  logic uart0_tx;

  ap_gpio_iobuf_0 u_uart0_rx_iobuff (
    .din    ( 1'b0               ),
    .oe     ( 1'b0               ),
    .dout   ( uart0_rx           ),
    .pad_io ( UART_STM_TX_SOM_RX )
  );

  ap_gpio_iobuf_0 u_uart0_tx_iobuff (
    .din    ( uart0_tx           ),
    .oe     ( 1'b1               ),
    .dout   (                    ),
    .pad_io ( UART_STM_RX_SOM_TX )
  );

  /* I2C connections for SOM_AUD and AUD_BD interfaces.
   * SOM_AUD uses I2C0 controller.
   * AUD_BD uses I2C0EMAC controller. */
  i2c_pkg::i2c_buf_t som_aud;
  i2c_pkg::i2c_buf_t aud_bd;

  ap_gpio_iobuf_0 u_som_aud_scl_iobuff (
    .din    ( 1'b0            ),
    .oe     ( som_aud.scl_oe  ),
    .dout   ( som_aud.scl_i   ),
    .pad_io ( SOM_AUD_I2C_SCL )
  );

  ap_gpio_iobuf_0 u_som_aud_sda_iobuff (
    .din    ( 1'b0            ),
    .oe     ( som_aud.sda_oe  ),
    .dout   ( som_aud.sda_i   ),
    .pad_io ( SOM_AUD_I2C_SDA )
  );

  ap_gpio_iobuf_0 u_aud_bd_scl_iobuff (
    .din    ( 1'b0           ),
    .oe     ( aud_bd.scl_oe  ),
    .dout   ( aud_bd.scl_i   ),
    .pad_io ( AUD_BD_I2C_SCL )
  );

  ap_gpio_iobuf_0 u_aud_bd_sda_iobuff (
    .din    ( 1'b0           ),
    .oe     ( aud_bd.sda_oe  ),
    .dout   ( aud_bd.sda_i   ),
    .pad_io ( AUD_BD_I2C_SDA )
  );

  /* i2s_ssm core instance */
  i2s_ssm #(
      .I2sDmaId       ( axis_to_aximm_pkg::kIdSsm2603Dma ),
      .MaxRingBytes   ( 32'h0020_0000                    ),
      .DataOutWidth   ( Fpga2HostDataWidth               )
  ) u_i2s_ssm (
      .clk            ( clk                 ),
      .rst            ( rst                 ),
      .i_i2s_rx       ( i_i2s_ssm2603_rx    ),
      .i_i2s_tx       ( i_i2s_ssm2603_tx    ),
      .i_axi_lite     ( i_i2s_ssm2603_csr   ),
      .i_data_out     ( i_i2s_ssm2603_dma   ),
      .irq            ( i2s_ssm_irq_source  )
  );

  /* Unused signals from i2s_ssm interfaces */
  assign i_i2s_ssm2603_csr.awuser = '0;
  assign i_i2s_ssm2603_csr.aruser = '0;

  /* Configuration interface definition */
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(config_registers_pkg::AddrWidth)) i_config_csr();

  /* Unused signals from config_register interface */
  assign i_config_csr.awuser = '0;
  assign i_config_csr.aruser = '0;

  /* Port interface definition */
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(port_registers_pkg::AddrWidth)) i_port_csr0();
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(port_registers_pkg::AddrWidth)) i_port_csr1();

  /* Framebuffer registers interface definition */
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(framebuffer_registers_pkg::AddrWidth)) i_fb0_csr();
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(framebuffer_registers_pkg::AddrWidth)) i_fb_dp_csr[MstCount-1:0]();
  axil_i #(.DataWidth(gaxilite_pkg::DataWidth),
           .AddrWidth(framebuffer_registers_pkg::AddrWidth)) i_fb_dp_sst_csr[0:0]();

  /* Unused signals from framebuffer_registers interface */
  assign i_fb0_csr.awuser = '0;
  assign i_fb0_csr.aruser = '0;

  /* AP module */
  ap ap0 (
      .emif_a10_hps_0_pll_ref_clk_clk,
      .emif_a10_hps_0_oct_oct_rzqin,
      .emif_a10_hps_0_mem_mem_ck,
      .emif_a10_hps_0_mem_mem_ck_n,
      .emif_a10_hps_0_mem_mem_a,
      .emif_a10_hps_0_mem_mem_act_n,
      .emif_a10_hps_0_mem_mem_ba,
      .emif_a10_hps_0_mem_mem_bg,
      .emif_a10_hps_0_mem_mem_cke,
      .emif_a10_hps_0_mem_mem_cs_n,
      .emif_a10_hps_0_mem_mem_odt,
      .emif_a10_hps_0_mem_mem_reset_n,
      .emif_a10_hps_0_mem_mem_par,
      .emif_a10_hps_0_mem_mem_alert_n,
      .emif_a10_hps_0_mem_mem_dqs,
      .emif_a10_hps_0_mem_mem_dqs_n,
      .emif_a10_hps_0_mem_mem_dq,
      .emif_a10_hps_0_mem_mem_dbi_n,

      .hps_io_hps_io_phery_emac0_TX_CLK,
      .hps_io_hps_io_phery_emac0_TXD0,
      .hps_io_hps_io_phery_emac0_TXD1,
      .hps_io_hps_io_phery_emac0_TXD2,
      .hps_io_hps_io_phery_emac0_TXD3,
      .hps_io_hps_io_phery_emac0_RX_CTL,
      .hps_io_hps_io_phery_emac0_TX_CTL,
      .hps_io_hps_io_phery_emac0_RX_CLK,
      .hps_io_hps_io_phery_emac0_RXD0,
      .hps_io_hps_io_phery_emac0_RXD1,
      .hps_io_hps_io_phery_emac0_RXD2,
      .hps_io_hps_io_phery_emac0_RXD3,
      .hps_io_hps_io_phery_emac0_MDIO,
      .hps_io_hps_io_phery_emac0_MDC,

      .hps_io_hps_io_phery_sdmmc_CMD,
      .hps_io_hps_io_phery_sdmmc_D0,
      .hps_io_hps_io_phery_sdmmc_D1,
      .hps_io_hps_io_phery_sdmmc_D2,
      .hps_io_hps_io_phery_sdmmc_D3,

      .hps_io_hps_io_phery_sdmmc_CCLK,
      .hps_io_hps_io_phery_usb0_DATA0,
      .hps_io_hps_io_phery_usb0_DATA1,
      .hps_io_hps_io_phery_usb0_DATA2,
      .hps_io_hps_io_phery_usb0_DATA3,
      .hps_io_hps_io_phery_usb0_DATA4,
      .hps_io_hps_io_phery_usb0_DATA5,
      .hps_io_hps_io_phery_usb0_DATA6,
      .hps_io_hps_io_phery_usb0_DATA7,
      .hps_io_hps_io_phery_usb0_CLK,
      .hps_io_hps_io_phery_usb0_STP,
      .hps_io_hps_io_phery_usb0_DIR,
      .hps_io_hps_io_phery_usb0_NXT,
      .hps_io_hps_io_phery_i2c1_SDA,
      .hps_io_hps_io_phery_i2c1_SCL,

      .arria10_hps_0_uart0_cts_n  ( ),
      .arria10_hps_0_uart0_dsr_n  ( ),
      .arria10_hps_0_uart0_dcd_n  ( ),
      .arria10_hps_0_uart0_ri_n   ( ),
      .arria10_hps_0_uart0_rx     ( uart0_rx ),

      .arria10_hps_0_uart0_dtr_n  ( ),
      .arria10_hps_0_uart0_rts_n  ( ),
      .arria10_hps_0_uart0_out1_n ( ),
      .arria10_hps_0_uart0_out2_n ( ),
      .arria10_hps_0_uart0_tx     ( uart0_tx ),

      .hps_io_hps_io_phery_uart1_RX,
      .hps_io_hps_io_phery_uart1_TX,

      .arria10_hps_0_i2c0_scl_i_clk  (som_aud.scl_i),
      .arria10_hps_0_i2c0_scl_oe_clk (som_aud.scl_oe),
      .arria10_hps_0_i2c0_sda_i      (som_aud.sda_i),
      .arria10_hps_0_i2c0_sda_oe     (som_aud.sda_oe),

      .arria10_hps_0_i2cemac0_scl_i_clk  (aud_bd.scl_i),
      .arria10_hps_0_i2cemac0_scl_oe_clk (aud_bd.scl_oe),
      .arria10_hps_0_i2cemac0_sda_i      (aud_bd.sda_i),
      .arria10_hps_0_i2cemac0_sda_oe     (aud_bd.sda_oe),

      .hps_io_hps_io_gpio_gpio2_io6(FLASH_SEL_BS1),
      .hps_io_hps_io_gpio_gpio2_io7(Led3_N_HPS_BS0),

      // GPIO/SD
      //.hps_io_hps_io_gpio_gpio1_io12,
      //.hps_io_hps_io_gpio_gpio1_io13,
      //.hps_io_hps_io_gpio_gpio1_io14,
      //.hps_io_hps_io_gpio_gpio1_io15,
      //.hps_io_hps_io_gpio_gpio1_io16,
      //.hps_io_hps_io_gpio_gpio1_io17,

      // TODO(ka): Remove those pins from top design (unused ones)
      .hps_io_hps_io_gpio_gpio1_io1(GPIO1_IO1),
      .hps_io_hps_io_gpio_gpio1_io0(GPIO1_IO0),
      .hps_io_hps_io_gpio_gpio1_io9(GPIO1_IO9),
      .hps_io_hps_io_gpio_gpio1_io8(GPIO1_IO8),

      // HPS LEDs
      .hps_io_hps_io_gpio_gpio1_io2(Led0_N),
      .hps_io_hps_io_gpio_gpio1_io3(Led1_N),

      // System pins
      .hps_io_hps_io_gpio_gpio1_io4(PWR_INT_VSEL),
      .hps_io_hps_io_gpio_gpio1_io5(Flash_OE_N),

      // i2s_it68051_csr ports
      .i2s_it68051_csr_awaddr  ( i_i2s_it68051_csr.awaddr  ),
      .i2s_it68051_csr_awprot  ( i2s_it68051_csr_awprot    ),
      .i2s_it68051_csr_awvalid ( i_i2s_it68051_csr.awvalid ),
      .i2s_it68051_csr_awready ( i_i2s_it68051_csr.awready ),
      .i2s_it68051_csr_wdata   ( i_i2s_it68051_csr.wdata   ),
      .i2s_it68051_csr_wstrb   ( i_i2s_it68051_csr.wstrb   ),
      .i2s_it68051_csr_wlast   ( i2s_it68051_csr_wlast     ),
      .i2s_it68051_csr_wvalid  ( i_i2s_it68051_csr.wvalid  ),
      .i2s_it68051_csr_wready  ( i_i2s_it68051_csr.wready  ),
      .i2s_it68051_csr_bresp   ( i_i2s_it68051_csr.bresp   ),
      .i2s_it68051_csr_bvalid  ( i_i2s_it68051_csr.bvalid  ),
      .i2s_it68051_csr_bready  ( i_i2s_it68051_csr.bready  ),
      .i2s_it68051_csr_araddr  ( i_i2s_it68051_csr.araddr  ),
      .i2s_it68051_csr_arprot  ( i2s_it68051_csr_arprot    ),
      .i2s_it68051_csr_arvalid ( i_i2s_it68051_csr.arvalid ),
      .i2s_it68051_csr_arready ( i_i2s_it68051_csr.arready ),
      .i2s_it68051_csr_rdata   ( i_i2s_it68051_csr.rdata   ),
      .i2s_it68051_csr_rresp   ( i_i2s_it68051_csr.rresp   ),
      .i2s_it68051_csr_rvalid  ( i_i2s_it68051_csr.rvalid  ),
      .i2s_it68051_csr_rready  ( i_i2s_it68051_csr.rready  ),

      // i2s_it68051_dma ports
      .i2s_it68051_dma_awid    ( i_i2s_it68051_dma.awid    ),
      .i2s_it68051_dma_awaddr  ( i_i2s_it68051_dma.awaddr  ),
      .i2s_it68051_dma_awlen   ( i_i2s_it68051_dma.awlen   ),
      .i2s_it68051_dma_awsize  ( i_i2s_it68051_dma.awsize  ),
      .i2s_it68051_dma_awburst ( i_i2s_it68051_dma.awburst ),
      .i2s_it68051_dma_awvalid ( i_i2s_it68051_dma.awvalid ),
      .i2s_it68051_dma_awready ( i_i2s_it68051_dma.awready ),
      .i2s_it68051_dma_wdata   ( i_i2s_it68051_dma.wdata   ),
      .i2s_it68051_dma_wstrb   ( i_i2s_it68051_dma.wstrb   ),
      .i2s_it68051_dma_wlast   ( i_i2s_it68051_dma.wlast   ),
      .i2s_it68051_dma_wvalid  ( i_i2s_it68051_dma.wvalid  ),
      .i2s_it68051_dma_wready  ( i_i2s_it68051_dma.wready  ),
      .i2s_it68051_dma_bid     ( i_i2s_it68051_dma.bid     ),
      .i2s_it68051_dma_bvalid  ( i_i2s_it68051_dma.bvalid  ),
      .i2s_it68051_dma_bready  ( i_i2s_it68051_dma.bready  ),
      .i2s_it68051_dma_arid    ( i_i2s_it68051_dma.arid    ),
      .i2s_it68051_dma_araddr  ( i_i2s_it68051_dma.araddr  ),
      .i2s_it68051_dma_arlen   ( i_i2s_it68051_dma.arlen   ),
      .i2s_it68051_dma_arsize  ( i_i2s_it68051_dma.arsize  ),
      .i2s_it68051_dma_arburst ( i_i2s_it68051_dma.arburst ),
      .i2s_it68051_dma_arvalid ( i_i2s_it68051_dma.arvalid ),
      .i2s_it68051_dma_arready ( i_i2s_it68051_dma.arready ),
      .i2s_it68051_dma_rid     ( i_i2s_it68051_dma.rid     ),
      .i2s_it68051_dma_rdata   ( i_i2s_it68051_dma.rdata   ),
      .i2s_it68051_dma_rlast   ( i_i2s_it68051_dma.rlast   ),
      .i2s_it68051_dma_rvalid  ( i_i2s_it68051_dma.rvalid  ),
      .i2s_it68051_dma_rready  ( i_i2s_it68051_dma.rready  ),

      // i2s_ssm2603_csr ports
      .i2s_ssm2603_csr_awaddr  ( i_i2s_ssm2603_csr.awaddr  ),
      .i2s_ssm2603_csr_awprot  ( /*unused*/                ),
      .i2s_ssm2603_csr_awvalid ( i_i2s_ssm2603_csr.awvalid ),
      .i2s_ssm2603_csr_awready ( i_i2s_ssm2603_csr.awready ),
      .i2s_ssm2603_csr_wdata   ( i_i2s_ssm2603_csr.wdata   ),
      .i2s_ssm2603_csr_wstrb   ( i_i2s_ssm2603_csr.wstrb   ),
      .i2s_ssm2603_csr_wlast   ( /*unused*/                ),
      .i2s_ssm2603_csr_wvalid  ( i_i2s_ssm2603_csr.wvalid  ),
      .i2s_ssm2603_csr_wready  ( i_i2s_ssm2603_csr.wready  ),
      .i2s_ssm2603_csr_bresp   ( i_i2s_ssm2603_csr.bresp   ),
      .i2s_ssm2603_csr_bvalid  ( i_i2s_ssm2603_csr.bvalid  ),
      .i2s_ssm2603_csr_bready  ( i_i2s_ssm2603_csr.bready  ),
      .i2s_ssm2603_csr_araddr  ( i_i2s_ssm2603_csr.araddr  ),
      .i2s_ssm2603_csr_arprot  ( /*unused*/                ),
      .i2s_ssm2603_csr_arvalid ( i_i2s_ssm2603_csr.arvalid ),
      .i2s_ssm2603_csr_arready ( i_i2s_ssm2603_csr.arready ),
      .i2s_ssm2603_csr_rdata   ( i_i2s_ssm2603_csr.rdata   ),
      .i2s_ssm2603_csr_rresp   ( i_i2s_ssm2603_csr.rresp   ),
      .i2s_ssm2603_csr_rvalid  ( i_i2s_ssm2603_csr.rvalid  ),
      .i2s_ssm2603_csr_rready  ( i_i2s_ssm2603_csr.rready  ),

      // i2s_ssm2603_dma ports
      .i2s_ssm2603_dma_awid    ( i_i2s_ssm2603_dma.awid    ),
      .i2s_ssm2603_dma_awaddr  ( i_i2s_ssm2603_dma.awaddr  ),
      .i2s_ssm2603_dma_awlen   ( i_i2s_ssm2603_dma.awlen   ),
      .i2s_ssm2603_dma_awsize  ( i_i2s_ssm2603_dma.awsize  ),
      .i2s_ssm2603_dma_awburst ( i_i2s_ssm2603_dma.awburst ),
      .i2s_ssm2603_dma_awvalid ( i_i2s_ssm2603_dma.awvalid ),
      .i2s_ssm2603_dma_awready ( i_i2s_ssm2603_dma.awready ),
      .i2s_ssm2603_dma_wdata   ( i_i2s_ssm2603_dma.wdata   ),
      .i2s_ssm2603_dma_wstrb   ( i_i2s_ssm2603_dma.wstrb   ),
      .i2s_ssm2603_dma_wlast   ( i_i2s_ssm2603_dma.wlast   ),
      .i2s_ssm2603_dma_wvalid  ( i_i2s_ssm2603_dma.wvalid  ),
      .i2s_ssm2603_dma_wready  ( i_i2s_ssm2603_dma.wready  ),
      .i2s_ssm2603_dma_bid     ( i_i2s_ssm2603_dma.bid     ),
      .i2s_ssm2603_dma_bvalid  ( i_i2s_ssm2603_dma.bvalid  ),
      .i2s_ssm2603_dma_bready  ( i_i2s_ssm2603_dma.bready  ),
      .i2s_ssm2603_dma_arid    ( i_i2s_ssm2603_dma.arid    ),
      .i2s_ssm2603_dma_araddr  ( i_i2s_ssm2603_dma.araddr  ),
      .i2s_ssm2603_dma_arlen   ( i_i2s_ssm2603_dma.arlen   ),
      .i2s_ssm2603_dma_arsize  ( i_i2s_ssm2603_dma.arsize  ),
      .i2s_ssm2603_dma_arburst ( i_i2s_ssm2603_dma.arburst ),
      .i2s_ssm2603_dma_arvalid ( i_i2s_ssm2603_dma.arvalid ),
      .i2s_ssm2603_dma_arready ( i_i2s_ssm2603_dma.arready ),
      .i2s_ssm2603_dma_rid     ( i_i2s_ssm2603_dma.rid     ),
      .i2s_ssm2603_dma_rdata   ( i_i2s_ssm2603_dma.rdata   ),
      .i2s_ssm2603_dma_rlast   ( i_i2s_ssm2603_dma.rlast   ),
      .i2s_ssm2603_dma_rvalid  ( i_i2s_ssm2603_dma.rvalid  ),
      .i2s_ssm2603_dma_rready  ( i_i2s_ssm2603_dma.rready  ),

      // exported user clk (250MHz)
      .clk_clk(clk),

      // exported user clk (100MHz)
      .clk_100_clk(clk_100),

      // exported reset
      .rst_reset(rst),

      // export irq
      .irq0_irq(irq0),

      // framebuffer interrupts
      .fb0_irq_export(fb0_irq),
      .fb0_irq_to_hps_irq(fb0_irq_to_hps),

      // i2s interrupts
      .i2s_it_irq_export(i2s_it_irq_source.rx),
      .i2s_it_irq_to_hps_irq(i2s_it_irq_to_hps),

      .i2s_ssm_irq_export(i2s_ssm_irq_source),
      .i2s_ssm_irq_to_hps_irq(i2s_ssm_irq_to_hps),

      /* Framebuffer CSR */
      .ap_fb0_csr_awaddr                ( i_fb0_csr.awaddr  ),
      .ap_fb0_csr_awprot                ( /*unused*/           ),
      .ap_fb0_csr_awvalid               ( i_fb0_csr.awvalid ),
      .ap_fb0_csr_awready               ( i_fb0_csr.awready ),
      .ap_fb0_csr_wdata                 ( i_fb0_csr.wdata   ),
      .ap_fb0_csr_wstrb                 ( i_fb0_csr.wstrb   ),
      .ap_fb0_csr_wlast                 ( /*unused*/           ),
      .ap_fb0_csr_wvalid                ( i_fb0_csr.wvalid  ),
      .ap_fb0_csr_wready                ( i_fb0_csr.wready  ),
      .ap_fb0_csr_bresp                 ( i_fb0_csr.bresp   ),
      .ap_fb0_csr_bvalid                ( i_fb0_csr.bvalid  ),
      .ap_fb0_csr_bready                ( i_fb0_csr.bready  ),
      .ap_fb0_csr_araddr                ( i_fb0_csr.araddr  ),
      .ap_fb0_csr_arprot                ( /*unused*/           ),
      .ap_fb0_csr_arvalid               ( i_fb0_csr.arvalid ),
      .ap_fb0_csr_arready               ( i_fb0_csr.arready ),
      .ap_fb0_csr_rdata                 ( i_fb0_csr.rdata   ),
      .ap_fb0_csr_rresp                 ( i_fb0_csr.rresp   ),
      .ap_fb0_csr_rvalid                ( i_fb0_csr.rvalid  ),
      .ap_fb0_csr_rready                ( i_fb0_csr.rready  ),

      // AXI connections
      .fb_ite_dma_awid                  (i_fb0_dma.awid),
      .fb_ite_dma_awaddr                (i_fb0_dma.awaddr),
      .fb_ite_dma_awlen                 (i_fb0_dma.awlen),
      .fb_ite_dma_awsize                (i_fb0_dma.awsize),
      .fb_ite_dma_awburst               (i_fb0_dma.awburst),
      .fb_ite_dma_awvalid               (i_fb0_dma.awvalid),
      .fb_ite_dma_awready               (i_fb0_dma.awready),
      .fb_ite_dma_wdata                 (i_fb0_dma.wdata),
      .fb_ite_dma_wstrb                 (i_fb0_dma.wstrb),
      .fb_ite_dma_wlast                 (i_fb0_dma.wlast),
      .fb_ite_dma_wvalid                (i_fb0_dma.wvalid),
      .fb_ite_dma_wready                (i_fb0_dma.wready),
      .fb_ite_dma_bid                   (i_fb0_dma.bid),
      .fb_ite_dma_bvalid                (i_fb0_dma.bvalid),
      .fb_ite_dma_bready                (i_fb0_dma.bready),
      .fb_ite_dma_arid                  (i_fb0_dma.arid),
      .fb_ite_dma_araddr                (i_fb0_dma.araddr),
      .fb_ite_dma_arlen                 (i_fb0_dma.arlen),
      .fb_ite_dma_arsize                (i_fb0_dma.arsize),
      .fb_ite_dma_arburst               (i_fb0_dma.arburst),
      .fb_ite_dma_arvalid               (i_fb0_dma.arvalid),
      .fb_ite_dma_arready               (i_fb0_dma.arready),
      .fb_ite_dma_rid                   (i_fb0_dma.rid),
      .fb_ite_dma_rdata                 (i_fb0_dma.rdata),
      .fb_ite_dma_rlast                 (i_fb0_dma.rlast),
      .fb_ite_dma_rvalid                (i_fb0_dma.rvalid),
      .fb_ite_dma_rready                (i_fb0_dma.rready),

`ifdef CFG_DP_ENABLED
      // dp mgmt interrupts
      .dp_mgmt_irq_export                ( dp_mgmt_irq              ),
      .dp_mgmt_irq_to_hps_irq            ( dp_mgmt_irq_to_hps       ),

      // DisplayPort MST IP management interface
      .dp_mgmt_csr_waitrequest           ( i_dp_mgmt.waitrequest    ),
      .dp_mgmt_csr_readdata              ( i_dp_mgmt.readdata       ),
      .dp_mgmt_csr_readdatavalid         ( i_dp_mgmt.readdatavalid & ~i_dp_mgmt.waitrequest ),
      .dp_mgmt_csr_burstcount            ( i_dp_mgmt.burstcount     ),
      .dp_mgmt_csr_writedata             ( i_dp_mgmt.writedata      ),
      .dp_mgmt_csr_address               ( i_dp_mgmt.address        ),
      .dp_mgmt_csr_write                 ( i_dp_mgmt.write          ),
      .dp_mgmt_csr_read                  ( i_dp_mgmt.read           ),
      .dp_mgmt_csr_byteenable            ( i_dp_mgmt.byteenable     ),

      // dp sst mgmt interrupts
      .dp_sst_mgmt_irq_export            ( dp_sst_mgmt_irq              ),
      .dp_sst_mgmt_irq_to_hps_irq        ( dp_sst_mgmt_irq_to_hps       ),

      // DisplayPort SST IP management interface
      .dp_sst_mgmt_csr_waitrequest       ( i_dp_sst_mgmt.waitrequest    ),
      .dp_sst_mgmt_csr_readdata          ( i_dp_sst_mgmt.readdata       ),
      .dp_sst_mgmt_csr_readdatavalid     ( i_dp_sst_mgmt.readdatavalid & ~i_dp_sst_mgmt.waitrequest ),
      .dp_sst_mgmt_csr_burstcount        ( i_dp_sst_mgmt.burstcount     ),
      .dp_sst_mgmt_csr_writedata         ( i_dp_sst_mgmt.writedata      ),
      .dp_sst_mgmt_csr_address           ( i_dp_sst_mgmt.address        ),
      .dp_sst_mgmt_csr_write             ( i_dp_sst_mgmt.write          ),
      .dp_sst_mgmt_csr_read              ( i_dp_sst_mgmt.read           ),
      .dp_sst_mgmt_csr_byteenable        ( i_dp_sst_mgmt.byteenable     ),

      // Framebuffer IRQs
      .fb_dp_irq0_export                 ( fb_dp_irq[0]         ),
      .fb_dp_irq0_to_hps_irq             ( fb_dp_irq_to_hps[0]  ),
      .fb_dp_irq1_export                 ( fb_dp_irq[1]         ),
      .fb_dp_irq1_to_hps_irq             ( fb_dp_irq_to_hps[1]  ),
      .fb_dp_irq2_export                 ( fb_dp_irq[2]         ),
      .fb_dp_irq2_to_hps_irq             ( fb_dp_irq_to_hps[2]  ),
      .fb_dp_irq3_export                 ( fb_dp_irq[3]         ),
      .fb_dp_irq3_to_hps_irq             ( fb_dp_irq_to_hps[3]  ),

      .fb_dp_sst_irq_export              ( fb_dp_sst_irq[0]     ),
      .fb_dp_sst_irq_to_hps_irq          ( fb_dp_sst_irq_to_hps ),

      // Framebuffer registers and CSRs
      .fb_dp_csr0_awaddr                 ( i_fb_dp_csr[0].awaddr  ),
      .fb_dp_csr0_awprot                 ( /*unused*/             ),
      .fb_dp_csr0_awvalid                ( i_fb_dp_csr[0].awvalid ),
      .fb_dp_csr0_awready                ( i_fb_dp_csr[0].awready ),
      .fb_dp_csr0_wdata                  ( i_fb_dp_csr[0].wdata   ),
      .fb_dp_csr0_wstrb                  ( i_fb_dp_csr[0].wstrb   ),
      .fb_dp_csr0_wlast                  ( /*unused*/             ),
      .fb_dp_csr0_wvalid                 ( i_fb_dp_csr[0].wvalid  ),
      .fb_dp_csr0_wready                 ( i_fb_dp_csr[0].wready  ),
      .fb_dp_csr0_bresp                  ( i_fb_dp_csr[0].bresp   ),
      .fb_dp_csr0_bvalid                 ( i_fb_dp_csr[0].bvalid  ),
      .fb_dp_csr0_bready                 ( i_fb_dp_csr[0].bready  ),
      .fb_dp_csr0_araddr                 ( i_fb_dp_csr[0].araddr  ),
      .fb_dp_csr0_arprot                 ( /*unused*/             ),
      .fb_dp_csr0_arvalid                ( i_fb_dp_csr[0].arvalid ),
      .fb_dp_csr0_arready                ( i_fb_dp_csr[0].arready ),
      .fb_dp_csr0_rdata                  ( i_fb_dp_csr[0].rdata   ),
      .fb_dp_csr0_rresp                  ( i_fb_dp_csr[0].rresp   ),
      .fb_dp_csr0_rvalid                 ( i_fb_dp_csr[0].rvalid  ),
      .fb_dp_csr0_rready                 ( i_fb_dp_csr[0].rready  ),
      .fb_dp_csr1_awaddr                 ( i_fb_dp_csr[1].awaddr  ),
      .fb_dp_csr1_awprot                 ( /*unused*/             ),
      .fb_dp_csr1_awvalid                ( i_fb_dp_csr[1].awvalid ),
      .fb_dp_csr1_awready                ( i_fb_dp_csr[1].awready ),
      .fb_dp_csr1_wdata                  ( i_fb_dp_csr[1].wdata   ),
      .fb_dp_csr1_wstrb                  ( i_fb_dp_csr[1].wstrb   ),
      .fb_dp_csr1_wlast                  ( /*unused*/             ),
      .fb_dp_csr1_wvalid                 ( i_fb_dp_csr[1].wvalid  ),
      .fb_dp_csr1_wready                 ( i_fb_dp_csr[1].wready  ),
      .fb_dp_csr1_bresp                  ( i_fb_dp_csr[1].bresp   ),
      .fb_dp_csr1_bvalid                 ( i_fb_dp_csr[1].bvalid  ),
      .fb_dp_csr1_bready                 ( i_fb_dp_csr[1].bready  ),
      .fb_dp_csr1_araddr                 ( i_fb_dp_csr[1].araddr  ),
      .fb_dp_csr1_arprot                 ( /*unused*/             ),
      .fb_dp_csr1_arvalid                ( i_fb_dp_csr[1].arvalid ),
      .fb_dp_csr1_arready                ( i_fb_dp_csr[1].arready ),
      .fb_dp_csr1_rdata                  ( i_fb_dp_csr[1].rdata   ),
      .fb_dp_csr1_rresp                  ( i_fb_dp_csr[1].rresp   ),
      .fb_dp_csr1_rvalid                 ( i_fb_dp_csr[1].rvalid  ),
      .fb_dp_csr1_rready                 ( i_fb_dp_csr[1].rready  ),
      .fb_dp_csr2_awaddr                 ( i_fb_dp_csr[2].awaddr  ),
      .fb_dp_csr2_awprot                 ( /*unused*/             ),
      .fb_dp_csr2_awvalid                ( i_fb_dp_csr[2].awvalid ),
      .fb_dp_csr2_awready                ( i_fb_dp_csr[2].awready ),
      .fb_dp_csr2_wdata                  ( i_fb_dp_csr[2].wdata   ),
      .fb_dp_csr2_wstrb                  ( i_fb_dp_csr[2].wstrb   ),
      .fb_dp_csr2_wlast                  ( /*unused*/             ),
      .fb_dp_csr2_wvalid                 ( i_fb_dp_csr[2].wvalid  ),
      .fb_dp_csr2_wready                 ( i_fb_dp_csr[2].wready  ),
      .fb_dp_csr2_bresp                  ( i_fb_dp_csr[2].bresp   ),
      .fb_dp_csr2_bvalid                 ( i_fb_dp_csr[2].bvalid  ),
      .fb_dp_csr2_bready                 ( i_fb_dp_csr[2].bready  ),
      .fb_dp_csr2_araddr                 ( i_fb_dp_csr[2].araddr  ),
      .fb_dp_csr2_arprot                 ( /*unused*/             ),
      .fb_dp_csr2_arvalid                ( i_fb_dp_csr[2].arvalid ),
      .fb_dp_csr2_arready                ( i_fb_dp_csr[2].arready ),
      .fb_dp_csr2_rdata                  ( i_fb_dp_csr[2].rdata   ),
      .fb_dp_csr2_rresp                  ( i_fb_dp_csr[2].rresp   ),
      .fb_dp_csr2_rvalid                 ( i_fb_dp_csr[2].rvalid  ),
      .fb_dp_csr2_rready                 ( i_fb_dp_csr[2].rready  ),
      .fb_dp_csr3_awaddr                 ( i_fb_dp_csr[3].awaddr  ),
      .fb_dp_csr3_awprot                 ( /*unused*/             ),
      .fb_dp_csr3_awvalid                ( i_fb_dp_csr[3].awvalid ),
      .fb_dp_csr3_awready                ( i_fb_dp_csr[3].awready ),
      .fb_dp_csr3_wdata                  ( i_fb_dp_csr[3].wdata   ),
      .fb_dp_csr3_wstrb                  ( i_fb_dp_csr[3].wstrb   ),
      .fb_dp_csr3_wlast                  ( /*unused*/             ),
      .fb_dp_csr3_wvalid                 ( i_fb_dp_csr[3].wvalid  ),
      .fb_dp_csr3_wready                 ( i_fb_dp_csr[3].wready  ),
      .fb_dp_csr3_bresp                  ( i_fb_dp_csr[3].bresp   ),
      .fb_dp_csr3_bvalid                 ( i_fb_dp_csr[3].bvalid  ),
      .fb_dp_csr3_bready                 ( i_fb_dp_csr[3].bready  ),
      .fb_dp_csr3_araddr                 ( i_fb_dp_csr[3].araddr  ),
      .fb_dp_csr3_arprot                 ( /*unused*/             ),
      .fb_dp_csr3_arvalid                ( i_fb_dp_csr[3].arvalid ),
      .fb_dp_csr3_arready                ( i_fb_dp_csr[3].arready ),
      .fb_dp_csr3_rdata                  ( i_fb_dp_csr[3].rdata   ),
      .fb_dp_csr3_rresp                  ( i_fb_dp_csr[3].rresp   ),
      .fb_dp_csr3_rvalid                 ( i_fb_dp_csr[3].rvalid  ),
      .fb_dp_csr3_rready                 ( i_fb_dp_csr[3].rready  ),
      .fb_dp_mst_dma02_awid              ( i_fb_dp_dma[0].awid    ),
      .fb_dp_mst_dma02_awaddr            ( i_fb_dp_dma[0].awaddr  ),
      .fb_dp_mst_dma02_awlen             ( i_fb_dp_dma[0].awlen   ),
      .fb_dp_mst_dma02_awsize            ( i_fb_dp_dma[0].awsize  ),
      .fb_dp_mst_dma02_awburst           ( i_fb_dp_dma[0].awburst ),
      .fb_dp_mst_dma02_awvalid           ( i_fb_dp_dma[0].awvalid ),
      .fb_dp_mst_dma02_awready           ( i_fb_dp_dma[0].awready ),
      .fb_dp_mst_dma02_wdata             ( i_fb_dp_dma[0].wdata   ),
      .fb_dp_mst_dma02_wstrb             ( i_fb_dp_dma[0].wstrb   ),
      .fb_dp_mst_dma02_wlast             ( i_fb_dp_dma[0].wlast   ),
      .fb_dp_mst_dma02_wvalid            ( i_fb_dp_dma[0].wvalid  ),
      .fb_dp_mst_dma02_wready            ( i_fb_dp_dma[0].wready  ),
      .fb_dp_mst_dma02_bid               ( i_fb_dp_dma[0].bid     ),
      .fb_dp_mst_dma02_bvalid            ( i_fb_dp_dma[0].bvalid  ),
      .fb_dp_mst_dma02_bready            ( i_fb_dp_dma[0].bready  ),
      .fb_dp_mst_dma02_arid              ( i_fb_dp_dma[0].arid    ),
      .fb_dp_mst_dma02_araddr            ( i_fb_dp_dma[0].araddr  ),
      .fb_dp_mst_dma02_arlen             ( i_fb_dp_dma[0].arlen   ),
      .fb_dp_mst_dma02_arsize            ( i_fb_dp_dma[0].arsize  ),
      .fb_dp_mst_dma02_arburst           ( i_fb_dp_dma[0].arburst ),
      .fb_dp_mst_dma02_arvalid           ( i_fb_dp_dma[0].arvalid ),
      .fb_dp_mst_dma02_arready           ( i_fb_dp_dma[0].arready ),
      .fb_dp_mst_dma02_rid               ( i_fb_dp_dma[0].rid     ),
      .fb_dp_mst_dma02_rdata             ( i_fb_dp_dma[0].rdata   ),
      .fb_dp_mst_dma02_rlast             ( i_fb_dp_dma[0].rlast   ),
      .fb_dp_mst_dma02_rvalid            ( i_fb_dp_dma[0].rvalid  ),
      .fb_dp_mst_dma02_rready            ( i_fb_dp_dma[0].rready  ),
      .fb_dp_mst_dma13_awid              ( i_fb_dp_dma[1].awid    ),
      .fb_dp_mst_dma13_awaddr            ( i_fb_dp_dma[1].awaddr  ),
      .fb_dp_mst_dma13_awlen             ( i_fb_dp_dma[1].awlen   ),
      .fb_dp_mst_dma13_awsize            ( i_fb_dp_dma[1].awsize  ),
      .fb_dp_mst_dma13_awburst           ( i_fb_dp_dma[1].awburst ),
      .fb_dp_mst_dma13_awvalid           ( i_fb_dp_dma[1].awvalid ),
      .fb_dp_mst_dma13_awready           ( i_fb_dp_dma[1].awready ),
      .fb_dp_mst_dma13_wdata             ( i_fb_dp_dma[1].wdata   ),
      .fb_dp_mst_dma13_wstrb             ( i_fb_dp_dma[1].wstrb   ),
      .fb_dp_mst_dma13_wlast             ( i_fb_dp_dma[1].wlast   ),
      .fb_dp_mst_dma13_wvalid            ( i_fb_dp_dma[1].wvalid  ),
      .fb_dp_mst_dma13_wready            ( i_fb_dp_dma[1].wready  ),
      .fb_dp_mst_dma13_bid               ( i_fb_dp_dma[1].bid     ),
      .fb_dp_mst_dma13_bvalid            ( i_fb_dp_dma[1].bvalid  ),
      .fb_dp_mst_dma13_bready            ( i_fb_dp_dma[1].bready  ),
      .fb_dp_mst_dma13_arid              ( i_fb_dp_dma[1].arid    ),
      .fb_dp_mst_dma13_araddr            ( i_fb_dp_dma[1].araddr  ),
      .fb_dp_mst_dma13_arlen             ( i_fb_dp_dma[1].arlen   ),
      .fb_dp_mst_dma13_arsize            ( i_fb_dp_dma[1].arsize  ),
      .fb_dp_mst_dma13_arburst           ( i_fb_dp_dma[1].arburst ),
      .fb_dp_mst_dma13_arvalid           ( i_fb_dp_dma[1].arvalid ),
      .fb_dp_mst_dma13_arready           ( i_fb_dp_dma[1].arready ),
      .fb_dp_mst_dma13_rid               ( i_fb_dp_dma[1].rid     ),
      .fb_dp_mst_dma13_rdata             ( i_fb_dp_dma[1].rdata   ),
      .fb_dp_mst_dma13_rlast             ( i_fb_dp_dma[1].rlast   ),
      .fb_dp_mst_dma13_rvalid            ( i_fb_dp_dma[1].rvalid  ),
      .fb_dp_mst_dma13_rready            ( i_fb_dp_dma[1].rready  ),

      .i2s_dp_csr0_awaddr                ( i_aud_dp_csr[0].awaddr   ),
      .i2s_dp_csr0_awprot                ( /* unused */             ),
      .i2s_dp_csr0_awvalid               ( i_aud_dp_csr[0].awvalid  ),
      .i2s_dp_csr0_awready               ( i_aud_dp_csr[0].awready  ),
      .i2s_dp_csr0_wdata                 ( i_aud_dp_csr[0].wdata    ),
      .i2s_dp_csr0_wstrb                 ( i_aud_dp_csr[0].wstrb    ),
      .i2s_dp_csr0_wlast                 ( /* unused */             ),
      .i2s_dp_csr0_wvalid                ( i_aud_dp_csr[0].wvalid   ),
      .i2s_dp_csr0_wready                ( i_aud_dp_csr[0].wready   ),
      .i2s_dp_csr0_bresp                 ( i_aud_dp_csr[0].bresp    ),
      .i2s_dp_csr0_bvalid                ( i_aud_dp_csr[0].bvalid   ),
      .i2s_dp_csr0_bready                ( i_aud_dp_csr[0].bready   ),
      .i2s_dp_csr0_araddr                ( i_aud_dp_csr[0].araddr   ),
      .i2s_dp_csr0_arprot                ( /* unused */             ),
      .i2s_dp_csr0_arvalid               ( i_aud_dp_csr[0].arvalid  ),
      .i2s_dp_csr0_arready               ( i_aud_dp_csr[0].arready  ),
      .i2s_dp_csr0_rdata                 ( i_aud_dp_csr[0].rdata    ),
      .i2s_dp_csr0_rresp                 ( i_aud_dp_csr[0].rresp    ),
      .i2s_dp_csr0_rvalid                ( i_aud_dp_csr[0].rvalid   ),
      .i2s_dp_csr0_rready                ( i_aud_dp_csr[0].rready   ),
      .i2s_dp_csr1_awaddr                ( i_aud_dp_csr[1].awaddr   ),
      .i2s_dp_csr1_awprot                ( /* unused */             ),
      .i2s_dp_csr1_awvalid               ( i_aud_dp_csr[1].awvalid  ),
      .i2s_dp_csr1_awready               ( i_aud_dp_csr[1].awready  ),
      .i2s_dp_csr1_wdata                 ( i_aud_dp_csr[1].wdata    ),
      .i2s_dp_csr1_wstrb                 ( i_aud_dp_csr[1].wstrb    ),
      .i2s_dp_csr1_wlast                 ( /* unused */             ),
      .i2s_dp_csr1_wvalid                ( i_aud_dp_csr[1].wvalid   ),
      .i2s_dp_csr1_wready                ( i_aud_dp_csr[1].wready   ),
      .i2s_dp_csr1_bresp                 ( i_aud_dp_csr[1].bresp    ),
      .i2s_dp_csr1_bvalid                ( i_aud_dp_csr[1].bvalid   ),
      .i2s_dp_csr1_bready                ( i_aud_dp_csr[1].bready   ),
      .i2s_dp_csr1_araddr                ( i_aud_dp_csr[1].araddr   ),
      .i2s_dp_csr1_arprot                ( /* unused */             ),
      .i2s_dp_csr1_arvalid               ( i_aud_dp_csr[1].arvalid  ),
      .i2s_dp_csr1_arready               ( i_aud_dp_csr[1].arready  ),
      .i2s_dp_csr1_rdata                 ( i_aud_dp_csr[1].rdata    ),
      .i2s_dp_csr1_rresp                 ( i_aud_dp_csr[1].rresp    ),
      .i2s_dp_csr1_rvalid                ( i_aud_dp_csr[1].rvalid   ),
      .i2s_dp_csr1_rready                ( i_aud_dp_csr[1].rready   ),
      .i2s_dp_csr2_awaddr                ( i_aud_dp_csr[2].awaddr   ),
      .i2s_dp_csr2_awprot                ( /* unused */             ),
      .i2s_dp_csr2_awvalid               ( i_aud_dp_csr[2].awvalid  ),
      .i2s_dp_csr2_awready               ( i_aud_dp_csr[2].awready  ),
      .i2s_dp_csr2_wdata                 ( i_aud_dp_csr[2].wdata    ),
      .i2s_dp_csr2_wstrb                 ( i_aud_dp_csr[2].wstrb    ),
      .i2s_dp_csr2_wlast                 ( /* unused */             ),
      .i2s_dp_csr2_wvalid                ( i_aud_dp_csr[2].wvalid   ),
      .i2s_dp_csr2_wready                ( i_aud_dp_csr[2].wready   ),
      .i2s_dp_csr2_bresp                 ( i_aud_dp_csr[2].bresp    ),
      .i2s_dp_csr2_bvalid                ( i_aud_dp_csr[2].bvalid   ),
      .i2s_dp_csr2_bready                ( i_aud_dp_csr[2].bready   ),
      .i2s_dp_csr2_araddr                ( i_aud_dp_csr[2].araddr   ),
      .i2s_dp_csr2_arprot                ( /* unused */             ),
      .i2s_dp_csr2_arvalid               ( i_aud_dp_csr[2].arvalid  ),
      .i2s_dp_csr2_arready               ( i_aud_dp_csr[2].arready  ),
      .i2s_dp_csr2_rdata                 ( i_aud_dp_csr[2].rdata    ),
      .i2s_dp_csr2_rresp                 ( i_aud_dp_csr[2].rresp    ),
      .i2s_dp_csr2_rvalid                ( i_aud_dp_csr[2].rvalid   ),
      .i2s_dp_csr2_rready                ( i_aud_dp_csr[2].rready   ),
      .i2s_dp_csr3_awaddr                ( i_aud_dp_csr[3].awaddr   ),
      .i2s_dp_csr3_awprot                ( /* unused */             ),
      .i2s_dp_csr3_awvalid               ( i_aud_dp_csr[3].awvalid  ),
      .i2s_dp_csr3_awready               ( i_aud_dp_csr[3].awready  ),
      .i2s_dp_csr3_wdata                 ( i_aud_dp_csr[3].wdata    ),
      .i2s_dp_csr3_wstrb                 ( i_aud_dp_csr[3].wstrb    ),
      .i2s_dp_csr3_wlast                 ( /* unused */             ),
      .i2s_dp_csr3_wvalid                ( i_aud_dp_csr[3].wvalid   ),
      .i2s_dp_csr3_wready                ( i_aud_dp_csr[3].wready   ),
      .i2s_dp_csr3_bresp                 ( i_aud_dp_csr[3].bresp    ),
      .i2s_dp_csr3_bvalid                ( i_aud_dp_csr[3].bvalid   ),
      .i2s_dp_csr3_bready                ( i_aud_dp_csr[3].bready   ),
      .i2s_dp_csr3_araddr                ( i_aud_dp_csr[3].araddr   ),
      .i2s_dp_csr3_arprot                ( /* unused */             ),
      .i2s_dp_csr3_arvalid               ( i_aud_dp_csr[3].arvalid  ),
      .i2s_dp_csr3_arready               ( i_aud_dp_csr[3].arready  ),
      .i2s_dp_csr3_rdata                 ( i_aud_dp_csr[3].rdata    ),
      .i2s_dp_csr3_rresp                 ( i_aud_dp_csr[3].rresp    ),
      .i2s_dp_csr3_rvalid                ( i_aud_dp_csr[3].rvalid   ),
      .i2s_dp_csr3_rready                ( i_aud_dp_csr[3].rready   ),
      .i2s_dp_mst_dma_awid               ( i_aud_dp_mst_dma.awid    ),
      .i2s_dp_mst_dma_awaddr             ( i_aud_dp_mst_dma.awaddr  ),
      .i2s_dp_mst_dma_awlen              ( i_aud_dp_mst_dma.awlen   ),
      .i2s_dp_mst_dma_awsize             ( i_aud_dp_mst_dma.awsize  ),
      .i2s_dp_mst_dma_awburst            ( i_aud_dp_mst_dma.awburst ),
      .i2s_dp_mst_dma_awvalid            ( i_aud_dp_mst_dma.awvalid ),
      .i2s_dp_mst_dma_awready            ( i_aud_dp_mst_dma.awready ),
      .i2s_dp_mst_dma_wdata              ( i_aud_dp_mst_dma.wdata   ),
      .i2s_dp_mst_dma_wstrb              ( i_aud_dp_mst_dma.wstrb   ),
      .i2s_dp_mst_dma_wlast              ( i_aud_dp_mst_dma.wlast   ),
      .i2s_dp_mst_dma_wvalid             ( i_aud_dp_mst_dma.wvalid  ),
      .i2s_dp_mst_dma_wready             ( i_aud_dp_mst_dma.wready  ),
      .i2s_dp_mst_dma_bid                ( i_aud_dp_mst_dma.bid     ),
      .i2s_dp_mst_dma_bvalid             ( i_aud_dp_mst_dma.bvalid  ),
      .i2s_dp_mst_dma_bready             ( i_aud_dp_mst_dma.bready  ),
      .i2s_dp_mst_dma_arid               ( i_aud_dp_mst_dma.arid    ),
      .i2s_dp_mst_dma_araddr             ( i_aud_dp_mst_dma.araddr  ),
      .i2s_dp_mst_dma_arlen              ( i_aud_dp_mst_dma.arlen   ),
      .i2s_dp_mst_dma_arsize             ( i_aud_dp_mst_dma.arsize  ),
      .i2s_dp_mst_dma_arburst            ( i_aud_dp_mst_dma.arburst ),
      .i2s_dp_mst_dma_arvalid            ( i_aud_dp_mst_dma.arvalid ),
      .i2s_dp_mst_dma_arready            ( i_aud_dp_mst_dma.arready ),
      .i2s_dp_mst_dma_rid                ( i_aud_dp_mst_dma.rid     ),
      .i2s_dp_mst_dma_rdata              ( i_aud_dp_mst_dma.rdata   ),
      .i2s_dp_mst_dma_rlast              ( i_aud_dp_mst_dma.rlast   ),
      .i2s_dp_mst_dma_rvalid             ( i_aud_dp_mst_dma.rvalid  ),
      .i2s_dp_mst_dma_rready             ( i_aud_dp_mst_dma.rready  ),

      .i2s_dp_irq0_export                ( i2s_dp_irq_source[0].rx  ),
      .i2s_dp_irq0_to_hps_irq            ( i2s_dp_irq_to_hps[0]     ),
      .i2s_dp_irq1_export                ( i2s_dp_irq_source[1].rx  ),
      .i2s_dp_irq1_to_hps_irq            ( i2s_dp_irq_to_hps[1]     ),
      .i2s_dp_irq2_export                ( i2s_dp_irq_source[2].rx  ),
      .i2s_dp_irq2_to_hps_irq            ( i2s_dp_irq_to_hps[2]     ),
      .i2s_dp_irq3_export                ( i2s_dp_irq_source[3].rx  ),
      .i2s_dp_irq3_to_hps_irq            ( i2s_dp_irq_to_hps[3]     ),

      .i2s_dp_sst_irq_export             ( i2s_dp_sst_irq_source[0].rx ),
      .i2s_dp_sst_irq_to_hps_irq         ( i2s_dp_sst_irq_to_hps       ),

      .dp_sst_fb_csr_awaddr              ( i_fb_dp_sst_csr[0].awaddr  ),
      .dp_sst_fb_csr_awprot              ( /*unused*/                 ),
      .dp_sst_fb_csr_awvalid             ( i_fb_dp_sst_csr[0].awvalid ),
      .dp_sst_fb_csr_awready             ( i_fb_dp_sst_csr[0].awready ),
      .dp_sst_fb_csr_wdata               ( i_fb_dp_sst_csr[0].wdata   ),
      .dp_sst_fb_csr_wstrb               ( i_fb_dp_sst_csr[0].wstrb   ),
      .dp_sst_fb_csr_wlast               ( /*unused*/                 ),
      .dp_sst_fb_csr_wvalid              ( i_fb_dp_sst_csr[0].wvalid  ),
      .dp_sst_fb_csr_wready              ( i_fb_dp_sst_csr[0].wready  ),
      .dp_sst_fb_csr_bresp               ( i_fb_dp_sst_csr[0].bresp   ),
      .dp_sst_fb_csr_bvalid              ( i_fb_dp_sst_csr[0].bvalid  ),
      .dp_sst_fb_csr_bready              ( i_fb_dp_sst_csr[0].bready  ),
      .dp_sst_fb_csr_araddr              ( i_fb_dp_sst_csr[0].araddr  ),
      .dp_sst_fb_csr_arprot              ( /*unused*/                 ),
      .dp_sst_fb_csr_arvalid             ( i_fb_dp_sst_csr[0].arvalid ),
      .dp_sst_fb_csr_arready             ( i_fb_dp_sst_csr[0].arready ),
      .dp_sst_fb_csr_rdata               ( i_fb_dp_sst_csr[0].rdata   ),
      .dp_sst_fb_csr_rresp               ( i_fb_dp_sst_csr[0].rresp   ),
      .dp_sst_fb_csr_rvalid              ( i_fb_dp_sst_csr[0].rvalid  ),
      .dp_sst_fb_csr_rready              ( i_fb_dp_sst_csr[0].rready  ),

      .fb_dp_sst_dma_awid                ( i_fb_dp_sst_dma[0].awid    ),
      .fb_dp_sst_dma_awaddr              ( i_fb_dp_sst_dma[0].awaddr  ),
      .fb_dp_sst_dma_awlen               ( i_fb_dp_sst_dma[0].awlen   ),
      .fb_dp_sst_dma_awsize              ( i_fb_dp_sst_dma[0].awsize  ),
      .fb_dp_sst_dma_awburst             ( i_fb_dp_sst_dma[0].awburst ),
      .fb_dp_sst_dma_awvalid             ( i_fb_dp_sst_dma[0].awvalid ),
      .fb_dp_sst_dma_awready             ( i_fb_dp_sst_dma[0].awready ),
      .fb_dp_sst_dma_wdata               ( i_fb_dp_sst_dma[0].wdata   ),
      .fb_dp_sst_dma_wstrb               ( i_fb_dp_sst_dma[0].wstrb   ),
      .fb_dp_sst_dma_wlast               ( i_fb_dp_sst_dma[0].wlast   ),
      .fb_dp_sst_dma_wvalid              ( i_fb_dp_sst_dma[0].wvalid  ),
      .fb_dp_sst_dma_wready              ( i_fb_dp_sst_dma[0].wready  ),
      .fb_dp_sst_dma_bid                 ( i_fb_dp_sst_dma[0].bid     ),
      .fb_dp_sst_dma_bvalid              ( i_fb_dp_sst_dma[0].bvalid  ),
      .fb_dp_sst_dma_bready              ( i_fb_dp_sst_dma[0].bready  ),
      .fb_dp_sst_dma_arid                ( i_fb_dp_sst_dma[0].arid    ),
      .fb_dp_sst_dma_araddr              ( i_fb_dp_sst_dma[0].araddr  ),
      .fb_dp_sst_dma_arlen               ( i_fb_dp_sst_dma[0].arlen   ),
      .fb_dp_sst_dma_arsize              ( i_fb_dp_sst_dma[0].arsize  ),
      .fb_dp_sst_dma_arburst             ( i_fb_dp_sst_dma[0].arburst ),
      .fb_dp_sst_dma_arvalid             ( i_fb_dp_sst_dma[0].arvalid ),
      .fb_dp_sst_dma_arready             ( i_fb_dp_sst_dma[0].arready ),
      .fb_dp_sst_dma_rid                 ( i_fb_dp_sst_dma[0].rid     ),
      .fb_dp_sst_dma_rdata               ( i_fb_dp_sst_dma[0].rdata   ),
      .fb_dp_sst_dma_rlast               ( i_fb_dp_sst_dma[0].rlast   ),
      .fb_dp_sst_dma_rvalid              ( i_fb_dp_sst_dma[0].rvalid  ),
      .fb_dp_sst_dma_rready              ( i_fb_dp_sst_dma[0].rready  ),

      .i2s_dp_sst_csr0_awaddr            ( i_aud_dp_sst_csr[0].awaddr   ),
      .i2s_dp_sst_csr0_awprot            ( /* unused */                 ),
      .i2s_dp_sst_csr0_awvalid           ( i_aud_dp_sst_csr[0].awvalid  ),
      .i2s_dp_sst_csr0_awready           ( i_aud_dp_sst_csr[0].awready  ),
      .i2s_dp_sst_csr0_wdata             ( i_aud_dp_sst_csr[0].wdata    ),
      .i2s_dp_sst_csr0_wstrb             ( i_aud_dp_sst_csr[0].wstrb    ),
      .i2s_dp_sst_csr0_wlast             ( /* unused */                 ),
      .i2s_dp_sst_csr0_wvalid            ( i_aud_dp_sst_csr[0].wvalid   ),
      .i2s_dp_sst_csr0_wready            ( i_aud_dp_sst_csr[0].wready   ),
      .i2s_dp_sst_csr0_bresp             ( i_aud_dp_sst_csr[0].bresp    ),
      .i2s_dp_sst_csr0_bvalid            ( i_aud_dp_sst_csr[0].bvalid   ),
      .i2s_dp_sst_csr0_bready            ( i_aud_dp_sst_csr[0].bready   ),
      .i2s_dp_sst_csr0_araddr            ( i_aud_dp_sst_csr[0].araddr   ),
      .i2s_dp_sst_csr0_arprot            ( /* unused */                 ),
      .i2s_dp_sst_csr0_arvalid           ( i_aud_dp_sst_csr[0].arvalid  ),
      .i2s_dp_sst_csr0_arready           ( i_aud_dp_sst_csr[0].arready  ),
      .i2s_dp_sst_csr0_rdata             ( i_aud_dp_sst_csr[0].rdata    ),
      .i2s_dp_sst_csr0_rresp             ( i_aud_dp_sst_csr[0].rresp    ),
      .i2s_dp_sst_csr0_rvalid            ( i_aud_dp_sst_csr[0].rvalid   ),
      .i2s_dp_sst_csr0_rready            ( i_aud_dp_sst_csr[0].rready   ),
      .i2s_dp_sst_dma_awid               ( i_aud_dp_sst_dma.awid     ),
      .i2s_dp_sst_dma_awaddr             ( i_aud_dp_sst_dma.awaddr   ),
      .i2s_dp_sst_dma_awlen              ( i_aud_dp_sst_dma.awlen    ),
      .i2s_dp_sst_dma_awsize             ( i_aud_dp_sst_dma.awsize   ),
      .i2s_dp_sst_dma_awburst            ( i_aud_dp_sst_dma.awburst  ),
      .i2s_dp_sst_dma_awvalid            ( i_aud_dp_sst_dma.awvalid  ),
      .i2s_dp_sst_dma_awready            ( i_aud_dp_sst_dma.awready  ),
      .i2s_dp_sst_dma_wdata              ( i_aud_dp_sst_dma.wdata    ),
      .i2s_dp_sst_dma_wstrb              ( i_aud_dp_sst_dma.wstrb    ),
      .i2s_dp_sst_dma_wlast              ( i_aud_dp_sst_dma.wlast    ),
      .i2s_dp_sst_dma_wvalid             ( i_aud_dp_sst_dma.wvalid   ),
      .i2s_dp_sst_dma_wready             ( i_aud_dp_sst_dma.wready   ),
      .i2s_dp_sst_dma_bid                ( i_aud_dp_sst_dma.bid      ),
      .i2s_dp_sst_dma_bvalid             ( i_aud_dp_sst_dma.bvalid   ),
      .i2s_dp_sst_dma_bready             ( i_aud_dp_sst_dma.bready   ),
      .i2s_dp_sst_dma_arid               ( i_aud_dp_sst_dma.arid     ),
      .i2s_dp_sst_dma_araddr             ( i_aud_dp_sst_dma.araddr   ),
      .i2s_dp_sst_dma_arlen              ( i_aud_dp_sst_dma.arlen    ),
      .i2s_dp_sst_dma_arsize             ( i_aud_dp_sst_dma.arsize   ),
      .i2s_dp_sst_dma_arburst            ( i_aud_dp_sst_dma.arburst  ),
      .i2s_dp_sst_dma_arvalid            ( i_aud_dp_sst_dma.arvalid  ),
      .i2s_dp_sst_dma_arready            ( i_aud_dp_sst_dma.arready  ),
      .i2s_dp_sst_dma_rid                ( i_aud_dp_sst_dma.rid      ),
      .i2s_dp_sst_dma_rdata              ( i_aud_dp_sst_dma.rdata    ),
      .i2s_dp_sst_dma_rlast              ( i_aud_dp_sst_dma.rlast    ),
      .i2s_dp_sst_dma_rvalid             ( i_aud_dp_sst_dma.rvalid   ),
      .i2s_dp_sst_dma_rready             ( i_aud_dp_sst_dma.rready   ),

      /* Port registers 0 */
      .port0_csr_awaddr               ( i_port_csr0.awaddr  ),
      .port0_csr_awprot               ( /*unused*/          ),
      .port0_csr_awvalid              ( i_port_csr0.awvalid ),
      .port0_csr_awready              ( i_port_csr0.awready ),
      .port0_csr_wdata                ( i_port_csr0.wdata   ),
      .port0_csr_wstrb                ( i_port_csr0.wstrb   ),
      .port0_csr_wlast                ( /*unused*/          ),
      .port0_csr_wvalid               ( i_port_csr0.wvalid  ),
      .port0_csr_wready               ( i_port_csr0.wready  ),
      .port0_csr_bresp                ( i_port_csr0.bresp   ),
      .port0_csr_bvalid               ( i_port_csr0.bvalid  ),
      .port0_csr_bready               ( i_port_csr0.bready  ),
      .port0_csr_araddr               ( i_port_csr0.araddr  ),
      .port0_csr_arprot               ( /*unused*/          ),
      .port0_csr_arvalid              ( i_port_csr0.arvalid ),
      .port0_csr_arready              ( i_port_csr0.arready ),
      .port0_csr_rdata                ( i_port_csr0.rdata   ),
      .port0_csr_rresp                ( i_port_csr0.rresp   ),
      .port0_csr_rvalid               ( i_port_csr0.rvalid  ),
      .port0_csr_rready               ( i_port_csr0.rready  ),

      /* Port registers 1 */
      .port1_csr_awaddr               ( i_port_csr1.awaddr  ),
      .port1_csr_awprot               ( /*unused*/          ),
      .port1_csr_awvalid              ( i_port_csr1.awvalid ),
      .port1_csr_awready              ( i_port_csr1.awready ),
      .port1_csr_wdata                ( i_port_csr1.wdata   ),
      .port1_csr_wstrb                ( i_port_csr1.wstrb   ),
      .port1_csr_wlast                ( /*unused*/          ),
      .port1_csr_wvalid               ( i_port_csr1.wvalid  ),
      .port1_csr_wready               ( i_port_csr1.wready  ),
      .port1_csr_bresp                ( i_port_csr1.bresp   ),
      .port1_csr_bvalid               ( i_port_csr1.bvalid  ),
      .port1_csr_bready               ( i_port_csr1.bready  ),
      .port1_csr_araddr               ( i_port_csr1.araddr  ),
      .port1_csr_arprot               ( /*unused*/          ),
      .port1_csr_arvalid              ( i_port_csr1.arvalid ),
      .port1_csr_arready              ( i_port_csr1.arready ),
      .port1_csr_rdata                ( i_port_csr1.rdata   ),
      .port1_csr_rresp                ( i_port_csr1.rresp   ),
      .port1_csr_rvalid               ( i_port_csr1.rvalid  ),
      .port1_csr_rready               ( i_port_csr1.rready  ),
`endif

      /* Config registers */
      .config_csr_awaddr                ( i_config_csr.awaddr  ),
      .config_csr_awprot                ( /*unused*/           ),
      .config_csr_awvalid               ( i_config_csr.awvalid ),
      .config_csr_awready               ( i_config_csr.awready ),
      .config_csr_wdata                 ( i_config_csr.wdata   ),
      .config_csr_wstrb                 ( i_config_csr.wstrb   ),
      .config_csr_wlast                 ( /*unused*/           ),
      .config_csr_wvalid                ( i_config_csr.wvalid  ),
      .config_csr_wready                ( i_config_csr.wready  ),
      .config_csr_bresp                 ( i_config_csr.bresp   ),
      .config_csr_bvalid                ( i_config_csr.bvalid  ),
      .config_csr_bready                ( i_config_csr.bready  ),
      .config_csr_araddr                ( i_config_csr.araddr  ),
      .config_csr_arprot                ( /*unused*/           ),
      .config_csr_arvalid               ( i_config_csr.arvalid ),
      .config_csr_arready               ( i_config_csr.arready ),
      .config_csr_rdata                 ( i_config_csr.rdata   ),
      .config_csr_rresp                 ( i_config_csr.rresp   ),
      .config_csr_rvalid                ( i_config_csr.rvalid  ),
      .config_csr_rready                ( i_config_csr.rready  )
  );

  // default voltage settings
  //assign PWR_INT_VSEL = 1'bZ;
  //assign PWR_MGT_VSEL = 1'bZ; //TODO: uncomment

  always_ff @(posedge clk) begin
    led_counter++;
  end

  assign Led2_N = ~led_counter[20];

  assign FX3_A0_B3B_L5_U5_N       = 1'bZ;
  assign FX3_A1_B3B_L3_T6_P       = 1'bZ;
  assign FX3_FLAGA_B3B_L15_R2_P   = 1'bZ;
  assign FX3_FLAGB_B3B_L18_T1_P   = 1'bZ;
  assign FX3_GPIO23_B3B_L16_T3_N  = 1'bZ;
  assign FX3_GPIO25_B3B_L5_T4_P   = 1'bZ;
  assign FX3_GPIO26_B3B_L18_R1_N  = 1'bZ;
  assign FX3_GPIO27_B3B_L3_T7_N   = 1'bZ;
  assign FX3_PKTEND_B3B_L1_P4_N_n = 1'bZ;
  assign FX3_SLCS_B3B_L9_N3_N_n   = 1'bZ;
  assign FX3_SLRD_B3B_L15_P2_N_n  = 1'bZ;
  assign FX3_SLWR_B3B_L16_T2_P_n  = 1'bZ;
  assign FX3_SLOE_n               = 1'bZ;
  assign FX3_CLK                  = 1'bZ;
  assign FX3_RESET_PL_n           = 1'b1;
  assign FX3_DQ0_B3B_L8_K4_P      = 1'bZ;
  assign FX3_DQ10_B3B_L14_H1_P    = 1'bZ;
  assign FX3_DQ11_B3B_L14_G1_N    = 1'bZ;
  assign FX3_DQ12_B3B_L10_J3_N    = 1'bZ;
  assign FX3_DQ13_B3B_L7_M4_N     = 1'bZ;
  assign FX3_DQ14_B3B_L9_N2_P     = 1'bZ;
  assign FX3_DQ15_B3B_L1_P3_P     = 1'bZ;
  assign FX3_DQ16_B3B_L24_V3_N    = 1'bZ;
  assign FX3_DQ17_B3B_L19_U3_P    = 1'bZ;
  assign FX3_DQ18_B3B_L23_V2_N    = 1'bZ;
  assign FX3_DQ19_B3B_L24_W3_P    = 1'bZ;
  assign FX3_DQ1_B3B_L8_L4_N      = 1'bZ;
  assign FX3_DQ20_B3B_L19_U4_N    = 1'bZ;
  assign FX3_DQ21_B3B_L23_W2_P    = 1'bZ;
  assign FX3_DQ22_B3B_L20_U1_N    = 1'bZ;
  assign FX3_DQ23_B3B_L20_V1_P    = 1'bZ;
  assign FX3_DQ28_B3B_L12_CLK1_L3_N = 1'bZ;
  assign FX3_DQ29_B3B_L22_V6_N    = 1'bZ;
  assign FX3_DQ2_B3B_L4_R5_N      = 1'bZ;
  assign FX3_DQ30_B3B_L12_CLK1_L2_P = 1'bZ;
  assign FX3_DQ31_B3B_L13_CLK0_N1_P = 1'bZ;
  assign FX3_DQ3_B3B_L11_RZQ_K2_P = 1'bZ;
  assign FX3_DQ4_B3B_L17_L1_P     = 1'bZ;
  assign FX3_DQ5_B3B_L4_R4_P      = 1'bZ;
  assign FX3_DQ6_B3B_L11_J2_N     = 1'bZ;
  assign FX3_DQ7_B3B_L17_K1_N     = 1'bZ;
  assign FX3_DQ8_B3B_L10_H2_P     = 1'bZ;
  assign FX3_DQ9_B3B_L7_M3_P      = 1'bZ;
  assign DP1_SOM_PS8469_SCL       = 1'bZ;
  assign DP1_SOM_PS8469_SDA       = 1'bZ;
  assign DP2_SOM_PS8469_SCL       = 1'bZ;
  assign DP2_SOM_PS8469_SDA       = 1'bZ;
  assign HDMI_OUT_CEC             = 1'bZ;
  assign HDMI_SOM_CEC             = 1'bZ;
  assign SOM_A21                  = 1'bZ;
  assign SOM_A98                  = 1'bZ;
  assign SOM_A104                 = 1'bZ;
  assign TP67                     = 1'bZ;
  assign TP70                     = 1'bZ;
  assign TP76                     = 1'bZ;
  assign TP77                     = 1'bZ;
  assign TP78                     = 1'bZ;
  assign TP79                     = 1'bZ;
  assign TP80                     = 1'bZ;
  assign TP81                     = 1'bZ;
  assign TP82                     = 1'bZ;
  assign TP83                     = 1'bZ;
  assign TP84                     = 1'bZ;
  assign TP85                     = 1'bZ;
  assign TP86                     = 1'bZ;
  assign TP87                     = 1'bZ;
  assign TP106                    = 1'bZ;
  assign UART_FPGA_TX_AUD_BD_RX_LS = 1'bZ;
  assign UART_FPGA_RX_AUD_BD_TX_LS = 1'bZ;
  assign SOMP1_IN_DDC_SDA          = 1'bZ;
  assign SOMP1_IN_DDC_SCL          = 1'bZ;
  assign SOMP2_IN_DDC_SDA          = 1'bZ;
  assign SOMP2_IN_DDC_SCL          = 1'bZ;

  assign i_axis_fb0_dma_rq_dummy.tvalid = 1'b0;
  assign i_axis_fb0_dma_resp_dummy.tready = 1'b0;
  assign i_axis_fb0_dma_rq_dummy.tdata = '0;
  assign i_axis_fb0_dma_rq_dummy.tkeep = '0;
  assign i_axis_fb0_dma_rq_dummy.tuser = '0;
  assign i_axis_fb0_dma_rq_dummy.tlast = '0;

  logic       burst_overflow;
  logic [1:0] burst_eof_hit;

  import framebuffer_pkg::kIrqBuff0;
  import framebuffer_pkg::kIrqBuff1;

  always_comb begin
    fb0_irq_eof = '0;
    fb0_irq_eof[kIrqBuff0] = burst_eof_hit[0];
    fb0_irq_eof[kIrqBuff1] = burst_eof_hit[1];
    fb0_irq = fb0_irq_status | fb0_irq_eof;
  end

  axis_burst_adapter u_burst_adapter (
      .clk            ( clk                  ),
      .reset          ( rst                  ),
      .max_burst_size ( 6'd16                ),
      .overflow       ( burst_overflow       ),
      .eof_hit        ( burst_eof_hit        ),
      .i_axis_in      ( i_axis_fb0_dma       ),
      .i_axis_out     ( i_axis_fb0_dma_burst )
  );

  axis_to_aximm #(
      .Id           ( axis_to_aximm_pkg::kIdFb0Dma  ),
      .DataWidth    ( Fpga2HostDataWidth            )
  ) u_fb0_axis_to_aximm (
      .clk          ( clk                           ),
      .rst          ( rst                           ),
      .i_write      ( i_axis_fb0_dma_burst          ),
      .write_done   (                               ),
      .i_read_rq    ( i_axis_fb0_dma_rq_dummy       ),
      .i_read_resp  ( i_axis_fb0_dma_resp_dummy     ),
      .i_mm         ( i_fb0_dma                     )
  );

  framebuffer_ite_top u_ite_rx (
      .clk        ( clk             ),
      .rst        ( rst             ),
      .pixel_clk  ( IT68051_PCLK    ),
      .pixel_data ( fb_ddio_d2      ),
      .i_fb_dma   ( i_axis_fb0_dma  ),
      .i_fb_csr   ( i_fb0_csr       ),
      .irq        ( fb0_irq_status  )
  );

  config_registers_pkg::spi_t          spi;

  config_registers #(
    .DataWidth  ( gaxilite_pkg::DataWidth )
  ) u_config_registers (
    .clk            ( clk               ),
    .rst            ( rst               ),
    .spi            ( spi               ),
    .i_axi_lite     ( i_config_csr      )
  );

`ifdef CFG_DP_ENABLED
  port_registers_pkg::port_id_t        port_id0;
  port_registers_pkg::port_id_t        port_id1;
  port_registers_pkg::vid_status_t     vid_status_port0;
  port_registers_pkg::vid_status_t     vid_status_port1;

  port_registers #(
    .DataWidth  ( gaxilite_pkg::DataWidth )
  ) u_port_registers0 (
    .clk            ( clk               ),
    .rst            ( rst               ),
    .port_id        ( port_id0          ),
    .vid_status     ( vid_status_port0  ),
    .i_axi_lite     ( i_port_csr0       )
  );

  port_registers #(
    .DataWidth  ( gaxilite_pkg::DataWidth )
  ) u_port_registers1 (
    .clk            ( clk               ),
    .rst            ( rst               ),
    .port_id        ( port_id1          ),
    .vid_status     ( vid_status_port1  ),
    .i_axi_lite     ( i_port_csr1       )
  );

  // synthesis translate_off
  if (DpMstPort1SstPort2 && DpMstPort2SstPort1) begin
    $fatal(1, "Either DpMstPort2SstPort1 or DpMstPort1SstPort2 parameter can be set");
  end
  // synthesis translate_on

  clock_crosser u_rst_100_cdc (
    .in         ( rst     ),
    .in_clk     ( clk     ),
    .in_reset   ( '0      ),
    .out        ( rst_100 ),
    .out_clk    ( clk_100 ),
    .out_reset  ( '0      )
  );
  /* DisplayPort SST IP */
  generate
    assign i_xcvr_port_dp_sst.ref_clk = DP_REFCLK_P; // 135 MHz
    assign i_dp_sst_pwr.cable_detect = 1'b1;
    assign i_dp_sst_pwr.pwr_detect   = 1'b1; // Example reversed logic of this lane, we do not.
    assign i_dp_sst_mgmt.cs = 1'b1;
    if (DpMstPort2SstPort1) begin
      assign i_xcvr_port_dp_sst.serial_data = { DP213_SOMP1_B3_P, DP213_SOMP1_L2_P,
                                                DP213_SOMP1_L1_P, DP213_SOMP1_L0_P };
      assign i_dp_sst_aux.in = DP213_SOMP1_AUX_IN;
      assign DP213_SOMP1_AUX_OUT = i_dp_sst_aux.out;
      assign DP213_SOMP1_AUX_OE  = i_dp_sst_aux.oe;
      assign DP213_SOMP1_HPD = i_dp_sst_pwr.hpd;
    end else if (DpMstPort1SstPort2) begin
      assign i_xcvr_port_dp_sst.serial_data = { DP213_SOMP2_B3_P, DP213_SOMP2_L2_P,
                                                DP213_SOMP2_L1_P, DP213_SOMP2_L0_P };
      assign i_dp_sst_aux.in = DP213_SOMP2_AUX_IN;
      assign DP213_SOMP2_AUX_OUT = i_dp_sst_aux.out;
      assign DP213_SOMP2_AUX_OE  = i_dp_sst_aux.oe;
      assign DP213_SOMP2_HPD = i_dp_sst_pwr.hpd;
    end
  endgenerate

  xcvr_rx_wrapper #(
    .IsHdmi ( 0 )
  ) u_xcvr_dp_sst (
    .clk              ( clk_100 ),
    .reset            ( rst_100 ),
    .i_xcvr_port      ( i_xcvr_port_dp_sst ),
    .i_xcvr           ( i_xcvr_dp_sst ),
    .i_xcvr_dp_rcfg   ( i_dp_sst_rcfg ),
    .i_xcvr_hdmi_cfg  ( i_dp_sst_hdmi_cfg_unused )
  );

  dp_rx_wrapper #(
    .MstSupport ( 0 )
  ) u_dp_sst_rx (
    .clk                ( clk_100         ),
    .reset              ( rst_100         ),
    .xcvr_reconfig_clk  ( clk_100         ),
    .i_xcvr             ( i_xcvr_dp_sst   ),
    .i_aux              ( i_dp_sst_aux    ),
    .i_pwr              ( i_dp_sst_pwr    ),
    .i_dp_video         ( i_dp_sst_video  ),
    .i_dp_ss            ( i_dp_sst_ss     ),
    .dp_msa             ( dp_sst_msa      ),
    .i_dp_audio         ( i_dp_sst_audio  ),
    .i_mgmt             ( i_dp_sst_mgmt   ),
    .i_xcvr_reconfig    ( i_dp_sst_rcfg   ),
    .mgmt_irq           ( dp_sst_mgmt_irq ),
    .dev_null           (  )
  );

  dp_port #(
      .MstSupport   ( 0 ),
      .MstCount     ( 1 )
  ) u_dp_sst_port (
      .clk          ( clk                   ),
      .rst          ( rst                   ),
      .vid_status   ( vid_status_port1      ),
      .fb_irq       ( fb_dp_sst_irq         ),
      .aud_irq      ( i2s_dp_sst_irq_source ),
      .i_dp_vid     ( i_dp_sst_video        ),
      .i_dp_audio   ( i_dp_sst_audio        ),
      .i_fb_csr     ( i_fb_dp_sst_csr       ),
      .i_fb_dp_dma  ( i_fb_dp_sst_dma       ),
      .i_aud_dp_csr ( i_aud_dp_sst_csr      ),
      .i_aud_dp_dma ( i_aud_dp_sst_dma      )
  );

  /* DisplayPort MST IP */
  generate
    assign i_xcvr_port_dp.ref_clk = DP_REFCLK_P; // 135 MHz
    assign i_dp_pwr.cable_detect = 1'b1;
    assign i_dp_pwr.pwr_detect   = 1'b1; // Example reversed logic of this lane, we do not.
    assign i_dp_mgmt.cs = 1'b1;
    if (DpMstPort2SstPort1) begin
      assign i_xcvr_port_dp.serial_data = { DP213_SOMP2_B3_P, DP213_SOMP2_L2_P,
                                            DP213_SOMP2_L1_P, DP213_SOMP2_L0_P };
      assign i_dp_aux.in = DP213_SOMP2_AUX_IN;
      assign DP213_SOMP2_AUX_OUT = i_dp_aux.out;
      assign DP213_SOMP2_AUX_OE  = i_dp_aux.oe;
      assign DP213_SOMP2_HPD = i_dp_pwr.hpd;
    end else if (DpMstPort1SstPort2) begin
      assign i_xcvr_port_dp.serial_data = { DP213_SOMP1_B3_P, DP213_SOMP1_L2_P,
                                            DP213_SOMP1_L1_P, DP213_SOMP1_L0_P };
      assign i_dp_aux.in = DP213_SOMP1_AUX_IN;
      assign DP213_SOMP1_AUX_OUT = i_dp_aux.out;
      assign DP213_SOMP1_AUX_OE  = i_dp_aux.oe;
      assign DP213_SOMP1_HPD = i_dp_pwr.hpd;
    end
  endgenerate

  xcvr_rx_wrapper #(
    .IsHdmi ( 0 )
  ) u_xcvr_dp_mst (
    .clk              ( clk_100 ),
    .reset            ( rst_100 ),
    .i_xcvr_port      ( i_xcvr_port_dp ),
    .i_xcvr           ( i_xcvr_dp ),
    .i_xcvr_dp_rcfg   ( i_dp_rcfg ),
    .i_xcvr_hdmi_cfg  ( i_hdmi_cfg_unused )
  );

  dp_rx_wrapper u_dp_mst_rx (
    .clk                ( clk_100 ),
    .reset              ( rst_100 ),
    .xcvr_reconfig_clk  ( clk_100 ),
    .i_xcvr             ( i_xcvr_dp ),
    .i_aux              ( i_dp_aux ),
    .i_pwr              ( i_dp_pwr ),
    .i_dp_video         ( i_dp_video ),
    .i_dp_ss            ( i_dp_ss ),
    .dp_msa             ( dp_msa ),
    .i_dp_audio         ( i_dp_audio ),
    .i_mgmt             ( i_dp_mgmt ),
    .i_xcvr_reconfig    ( i_dp_rcfg ),
    .mgmt_irq           ( dp_mgmt_irq ),
    .dev_null           (  )
  );

  dp_port #(
      .MstSupport   ( 1 )
  ) u_dp_mst_port (
      .clk          ( clk               ),
      .rst          ( rst               ),
      .vid_status   ( vid_status_port0  ),
      .fb_irq       ( fb_dp_irq         ),
      .aud_irq      ( i2s_dp_irq_source ),
      .i_dp_vid     ( i_dp_video        ),
      .i_dp_audio   ( i_dp_audio        ),
      .i_fb_csr     ( i_fb_dp_csr       ),
      .i_fb_dp_dma  ( i_fb_dp_dma       ),
      .i_aud_dp_csr ( i_aud_dp_csr      ),
      .i_aud_dp_dma ( i_aud_dp_mst_dma  )
  );

`endif

endmodule
