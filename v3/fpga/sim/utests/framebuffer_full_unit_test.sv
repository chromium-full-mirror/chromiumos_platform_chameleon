/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module framebuffer_full_unit_test;

  //Unit test name
  parameter string name = "framebuffer_full_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import svunit_greporter_pkg::*;
  import gvip_axis_item_pkg::bitem;

  import framebuffer_pkg::*;
  import framebuffer_registers_pkg::*;

  //Parameters
  //Clocking
  logic pixel_clk = 1'b0;
  logic avalon_clk = 1'b0;
  logic pixel_reset;
  logic avalon_reset;

  `SVUNIT_CLK_GEN(pixel_clk,  3)
  `SVUNIT_CLK_GEN(avalon_clk, 2)

  localparam int PixelDataWidth = 60;
  localparam int DataWidth = 128;
  localparam int AxiLiteAddrWidth = 12;
  localparam int AxiLiteDataWidth = 32;
  localparam int DmaAddrWidth = 32;

  //Inputs and outputs
  pixel_vip #(.DataWidth(PixelDataWidth), .Name("pixel"))
      pixel(.clk(pixel_clk), .reset(pixel_reset));
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_axi(avalon_clk, avalon_reset);
  gvip_aximm_if #(.N(DataWidth/8), .A(32), .NAME("mm_slv"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) mm_vip(avalon_clk, avalon_reset);

  typedef pixel.axis_item_t axis_item_t;
  typedef mm_vip.item_t mm_item_t;
  typedef drv_axi.item_t axil_item_t;

  `AXIMM_TO_GAXIMM_VIP(mm_vip)
  `GAXIL_VIP_TO_AXIL(drv_axi)

  /**
    extension of axis_item_t for easier maintain raw data
    after randomization of object all data with acctive 'de' will be put
    to 'pattern' member for nice and easy access in analisys port
    (all porch and sync pixel are droped in 'pattern')
  */
  class axis_with_pattern extends axis_item_t;
    typedef axis_with_pattern this_type;

    logic[PixelDataWidth-1:0] pattern[$];

    virtual function this_type clone();
      clone = new();
      clone.copy(this);
    endfunction

    virtual function void copy(bitem rhs);
      this_type _rhs;
      void'($cast(_rhs, rhs));
      super.copy(_rhs);
      pattern = _rhs.pattern;
    endfunction

    function void post_randomize();
      pattern = '{};
      super.post_randomize();
      foreach(tuser[i]) begin
        if (tuser[i].de)
          pattern.push_back(tdata[i]);
      end
    endfunction

  endclass : axis_with_pattern


  typedef frame_pkg::frame_tmds_t #(.Vactive(480), .Hactive(640), .Vbp(13), .Vfp(3), .Vslen(4),
    .Hbp(80), .Hfp(16), .Hslen(64), .T(axis_with_pattern)) frame480p_60;
  typedef frame_pkg::frame_tmds_t #(.Vactive(200), .Hactive(320), .Vbp(6), .Vfp(3), .Vslen(6),
    .Hbp(40), .Hfp(8), .Hslen(32), .T(axis_with_pattern)) frame320x200_60;

  class mm_slv_t implements gvip_aximm_pkg::analysis_port_ic#(mm_item_t);
    axis_with_pattern patterns[$];
    mm_item_t mm_patterns[$];
    axis_with_pattern current_frame;
    int px_idx;

    struct packed {
      logic [7:0] r;
      logic [7:0] g;
      logic [7:0] b;
    } rgb;

    virtual function mm_item_t write (input mm_item_t item);
      mm_patterns.push_back(item.clone());
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AW_W) begin
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::B));
        item.bresp = gaximm_pkg::OKAY;
        item.bid   = item.awid;
        item.buser = item.awuser;
        return item;
      end
    endfunction : write

    task analyzer();
      mm_item_t item;
      forever begin
        @(posedge avalon_clk);
        wait(mm_patterns.size());

        item = mm_patterns.pop_front();

        if (current_frame == null) begin
          `FAIL_IF(patterns.size() == 0)
          current_frame = patterns.pop_front();
          px_idx = 0;
        end

        if (current_frame.pattern.size() == 0) begin
          `FAIL_IF(patterns.size() == 0)
          current_frame = patterns.pop_front();
          px_idx = 0;
        end

        `FAIL_IF(item.awaddr != (4 * px_idx))

        `FAIL_IF(current_frame == null)

        for(int i = 0; i < item.wdata.size(); ++i) begin

          for (int j = 0; j < 4; ++j) begin
            `FAIL_IF(current_frame.pattern.size() == 0)

            rgb.r = current_frame.pattern[0][29:22];
            rgb.g = current_frame.pattern[0][19:12];
            rgb.b = current_frame.pattern[0][9:2];
            void'(current_frame.pattern.pop_front());

            `ifdef DBG $display("px_idx:%0d rgb:%02h%02h%02h", px_idx, rgb.r,rgb.g,rgb.b); `endif

            `FAIL_IF_LOG(item.wdata[i][j*32+31-:32] != rgb, $sformatf("%h!=%h", item.wdata[i][j*32+31-:32], rgb))

            px_idx++;
          end
        end
      end
    endtask : analyzer

  endclass : mm_slv_t

  mm_slv_t mm_slv_ap;

  axis_i #(.DataWidth(128),
           .WordWidth(8),
           .Tuser(framebuffer_pkg::fb_dma_meta_t)) i_axis_fb0_dma();

  framebuffer_pkg::io_map_t pixel_data;
  assign pixel_data.ddio.high = '0;
  assign pixel_data.ddio.low.qd = pixel.qd;
  assign pixel_data.ddio.low.ctrl.de = pixel.de;
  assign pixel_data.ddio.low.ctrl.hsync = pixel.hsync;
  assign pixel_data.ddio.low.ctrl.vsync = pixel.vsync;
  assign pixel_data.ddio.low.ctrl.scdt = pixel.scdt;

  // This is the UUT that we're running the Unit Tests on
  framebuffer_ite_top dut (
      .clk               ( avalon_clk           ),
      .rst               ( avalon_reset         ),
      .pixel_data        ( pixel_data           ),
      .pixel_clk         ( pixel.clk            ),

      .i_fb_dma          ( i_axis_fb0_dma       ),
      .i_fb_csr          ( axil_drv_axi         ),
      .irq               (                      )
  );

  axis_i  #(.DataWidth(128), .WordWidth(8), .Tuser(axis_to_aximm_pkg::meta_t))
                                                                      i_axis_fb0_dma_burst_write();
  axis_i  #(.DataWidth(128), .WordWidth(8), .Tuser(axis_to_aximm_pkg::meta_t))
                                                                      i_axis_fb0_dma_rq_dummy();
  axis_i  #(.DataWidth(128), .WordWidth(8), .Tuser(axis_to_aximm_pkg::meta_t))
                                                                      i_axis_fb0_dma_resp_dummy();

  axis_burst_adapter u_burst_adapter (
      .clk            ( avalon_clk                 ),
      .reset          ( avalon_reset               ),
      .max_burst_size ( 6'd16                      ),
      .i_axis_in      ( i_axis_fb0_dma             ),
      .i_axis_out     ( i_axis_fb0_dma_burst_write )
  );

  axis_to_aximm #(
      .Id           ( axis_to_aximm_pkg::kIdFb0Dma  ),
      .DataWidth    ( 128                           )
  ) u_fb0_axis_to_aximm (
      .clk          ( avalon_clk                    ),
      .rst          ( avalon_reset                  ),
      .i_write      ( i_axis_fb0_dma_burst_write    ),
      .i_read_rq    ( i_axis_fb0_dma_rq_dummy       ),
      .i_read_resp  ( i_axis_fb0_dma_resp_dummy     ),
      .i_mm         ( aximm_mm_vip                  )
  );


  function static void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    pixel.init();
    pixel.run_phase();

    drv_axi.init();
    drv_axi.core.run_phase();

    mm_slv_ap = new();

    mm_vip.init();
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, mm_slv_ap);
    mm_vip.core.run_phase();
  endfunction

  task static setup();
    svunit_ut.setup();
    pixel_reset <= 1'b1;
    avalon_reset <= 1'b1;
    repeat (10) @(posedge pixel_clk);
    pixel_reset <= 1'b0;
    repeat (10) @(posedge avalon_clk);
    avalon_reset <= 1'b0;
    @(posedge avalon_clk);
  endtask

  task static teardown();
    // do nothing
  endtask

  `SVUNIT_TESTS_BEGIN
    `SVTEST(main)
      axil_item_t axil_item = new();
      frame320x200_60 f = new();

      axil_item.wstrb  = '1;
      void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      axil_item.awaddr = AddrBufferSize;
      axil_item.wdata  = f.get_pixels_num() * 4;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrIOColor;
      axil_item.wdata  = k24b;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrIODataRate;
      axil_item.wdata  = kSdr;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrIOPixelMode;
      axil_item.wdata  = kSpm;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrBufferA;
      axil_item.wdata  = 0;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrBufferB;
      axil_item.wdata  = 0;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrEn;
      axil_item.wdata  = 1'b1;
      drv_axi.core.send_item(axil_item.clone());

      fork
        mm_slv_ap.analyzer();
      join_none

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::random_std::create(), 1);

      `FAIL_IF(!f.randomize());
      pixel.send_item(f); // first dummy frame for initialization and align

      // one frame for buffers valid synchonization
      pixel.send_item(f);

      repeat (2) begin
        `FAIL_IF(!f.randomize());
        @(posedge pixel_clk);
        mm_slv_ap.patterns.push_back(f.clone());
        pixel.send_item(f);
        repeat (100) @(posedge pixel_clk);
      end
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : framebuffer_full_unit_test
