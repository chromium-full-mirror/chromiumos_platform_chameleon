/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

//`define DBG 1

module framebuffer_ite_top_unit_test;

  //Unit test name
  parameter string name = "framebuffer_ite_top_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import svunit_greporter_pkg::*;
  import gvip_axis_item_pkg::bitem;
  import gvip_reg_pkg::*;

  import frame_pkg::ic_picture_t;
  import framebuffer_registers_pkg::*;

  //Parameters
  //Clocking
  logic pixel_clk = 1'b0;
  logic pixel_ddr_clk = 1'b0;
  logic avalon_clk = 1'b0;
  logic pixel_reset;
  logic avalon_reset;

  `SVUNIT_CLK_GEN(pixel_clk, 6)
  `SVUNIT_CLK_GEN(pixel_ddr_clk, 3)
  `SVUNIT_CLK_GEN(avalon_clk, 4)

  localparam int PixelDataWidth = 60;
  localparam int DataWidth = 128;
  localparam int AxiLiteAddrWidth = 12;
  localparam int AxiLiteDataWidth = 32;
  localparam int DmaAddrWidth = 32;

  import framebuffer_pkg::fb_dma_meta_t;

  //Inputs and outputs
  pixel_vip #(.DataWidth(PixelDataWidth), .Name("pixel"))
    pixel(.clk(pixel_ddr_clk), .reset(pixel_reset));
  gvip_axis_if #(DataWidth/8, 0, 0, fb_dma_meta_t, "dma", gvip_axis_pkg::SLAVE)
    dma(avalon_clk, avalon_reset);
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_axi(avalon_clk, avalon_reset);

  typedef dma.item_t dma_item_t;
  typedef pixel.axis_item_t axis_item_t;
  typedef drv_axi.item_t axil_item_t;

  `AXIS_TO_GAXIS_VIP(dma, fb_dma_meta_t)
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

  typedef frame_pkg::frame_dpm_t #(.Vactive(2), .Hactive(2), .Vbp(1), .Vfp(1), .Vslen(1),
    .Hbp(1), .Hfp(1), .Hslen(1), .T(axis_with_pattern)) small_frame_dpm;
  typedef frame_pkg::frame_dpm_t #(.Vactive(480), .Hactive(640), .Vbp(13), .Vfp(3), .Vslen(4),
    .Hbp(80), .Hfp(16), .Hslen(64), .T(axis_with_pattern)) frame480p_60_dpm;
  typedef frame_pkg::frame_dpm_t #(.Vactive(200), .Hactive(320), .Vbp(6), .Vfp(3), .Vslen(6),
    .Hbp(40), .Hfp(8), .Hslen(32), .T(axis_with_pattern)) frame320x200_60_dpm;

  typedef frame_pkg::frame_tmds_t #(.Vactive(2), .Hactive(2), .Vbp(1), .Vfp(1), .Vslen(1),
    .Hbp(1), .Hfp(1), .Hslen(1), .T(axis_with_pattern)) small_frame;
  typedef frame_pkg::frame_tmds_t #(.Vactive(480), .Hactive(640), .Vbp(13), .Vfp(3), .Vslen(4),
    .Hbp(80), .Hfp(16), .Hslen(64), .T(axis_with_pattern)) frame480p_60;
  typedef frame_pkg::frame_tmds_t #(.Vactive(200), .Hactive(320), .Vbp(6), .Vfp(3), .Vslen(6),
    .Hbp(40), .Hfp(8), .Hslen(32), .T(axis_with_pattern)) frame320x200_60;

  typedef frame_pkg::frame_tmds_t #(.Vactive(200), .Hactive(320), .Vbp(6), .Vfp(3), .Vslen(6),
    .Hbp(40), .Hfp(8), .Hslen(32),
    .T(axis_with_pattern), .InvPolarity(1)) frame320x200_60_inv_polarity;
  //---------------------------------------------------------------------------

  virtual class ap_t implements gvip_axis_pkg::analysis_port_ic#(dma_item_t);
    axis_with_pattern patterns[$];
    axis_with_pattern current_frame;
    dma_item_t dma_patterns[$];
    int px_idx;
    bit skip = 0; // do not analyze incoming transactions

    typedef struct packed {
      logic [7:0] r;
      logic [7:0] g;
      logic [7:0] b;
    } rgb_t;

    pure virtual task chk_data(dma_item_t item);

    virtual function void write(input dma_item_t item);
      if (skip) return;

      // skip eof
      if (item.tuser[0].eof) begin
        current_frame = patterns.pop_front();
        px_idx = 0;
        return;
      end

      dma_patterns.push_back(item);

    endfunction : write

    task analyzer();
      dma_item_t item;

      forever begin
        @(posedge avalon_clk);
        wait(dma_patterns.size());

        item = dma_patterns.pop_front();
        `ifdef DBG $display(item.convert2string()); `endif

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

        `FAIL_IF(current_frame == null)

        chk_data(item);
      end

    endtask : analyzer

  endclass : ap_t

  //---------------------------------------------------------------------------

  class ap_dpm_t extends ap_t;
    virtual task chk_data(dma_item_t item);
      rgb_t rgb;
      for (int i = 0; i < item.tdata.size(); ++i) begin
        int pidx = item.tuser[i].addr / 4 / 2;

        for (int j = 0; j < 2; ++j) begin
          `FAIL_IF(current_frame.pattern.size() == 0)

          rgb.r = current_frame.pattern[pidx+j][20+2+:8];
          rgb.g = current_frame.pattern[pidx+j][10+2+:8];
          rgb.b = current_frame.pattern[pidx+j][0+2+:8];

          `ifdef DBG $display("px_idx:%0d rgb:%02h%02h%02h", px_idx, rgb.r,rgb.g,rgb.b); `endif

          `FAIL_IF_LOG(item.tdata[i][j*64+31-:32] != rgb,
              $sformatf("%h != %h", item.tdata[i][j*64+31-:32], rgb))

          rgb.r = current_frame.pattern[pidx+j][30+20+2+:8];
          rgb.g = current_frame.pattern[pidx+j][30+10+2+:8];
          rgb.b = current_frame.pattern[pidx+j][30+0+2+:8];

          `FAIL_IF_LOG(item.tdata[i][j*64+32+31-:32] != rgb,
              $sformatf("%h != %h (%h != %h)", item.tdata[i][j*64+32+31-:32], rgb, item.tdata[i],
                                               current_frame.pattern[pidx+j]))

          px_idx += 2;
        end
      end
    endtask
  endclass : ap_dpm_t

  //---------------------------------------------------------------------------

  class ap_spm_t extends ap_t;
    virtual task chk_data(dma_item_t item);
      rgb_t rgb;
      for (int i = 0; i < item.tdata.size(); ++i) begin

        `FAIL_IF_LOG(item.tuser[i].addr/4 != px_idx,
              $sformatf("%0d != %0d", item.tuser[i].addr/4, px_idx))

        for (int j = 0; j < 4; ++j) begin
          `FAIL_IF(current_frame.pattern.size() == 0)

          rgb.r = current_frame.pattern[0][22+:8];
          rgb.g = current_frame.pattern[0][12+:8];
          rgb.b = current_frame.pattern[0][2+:8];

          `ifdef DBG $display("px_idx:%0d rgb:%02h%02h%02h", px_idx, rgb.r,rgb.g,rgb.b); `endif

          `FAIL_IF_LOG(item.tdata[i][j*32+31-:32] != rgb,
              $sformatf("%h != %h, i = %d, j = %d", item.tdata[i][j*32+31-:32], rgb, i, j))

          void'(current_frame.pattern.pop_front());
          px_idx += 1;
        end
      end
    endtask
  endclass : ap_spm_t

  //---------------------------------------------------------------------------

  framebuffer_pkg::io_map_t pixel_data;
  framebuffer_pkg::input_word_t pixel_data_ddr;

  assign pixel_data_ddr.qd = pixel.qd;
  assign pixel_data_ddr.ctrl.de = pixel.de;
  assign pixel_data_ddr.ctrl.hsync = pixel.hsync;
  assign pixel_data_ddr.ctrl.vsync = pixel.vsync;
  assign pixel_data_ddr.ctrl.scdt = pixel.scdt;

  altddio_in #(
    .width (64)
  ) ddio_pixel (
    .datain    ( pixel_data_ddr             ), // required port, DDR input data
    .inclock   ( pixel_clk                  ), // required port, input reference clock to sample data by
    .inclocken ( 1'b1                       ), // enable data clock
    .aset      ( 1'b0                       ), // asynchronous set
    .aclr      ( 1'b0                       ), // asynchronous clear
    .sset      ( 1'b0                       ), // synchronous set
    .sclr      ( 1'b0                       ), // synchronous clear
    .dataout_h ( pixel_data.ddio.high       ), // data sampled at the rising edge of inclock
    .dataout_l ( pixel_data.ddio.low        )  // data sampled at the falling edge of inclock
  );

  ap_spm_t ap_spm;
  ap_dpm_t ap_dpm;
  ap_t ap;

  // This is the UUT that we're running the Unit Tests on
  framebuffer_ite_top dut (
      .clk               ( avalon_clk        ),
      .rst               ( avalon_reset      ),
      .pixel_data        ( pixel_data        ),
      .pixel_clk         ( pixel_clk         ),

      .i_fb_dma          ( axis_dma          ),
      .i_fb_csr          ( axil_drv_axi      ),
      .irq               (                   )
  );

  function static void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    pixel.init();
    pixel.run_phase();

    drv_axi.init();
    drv_axi.core.run_phase();

    ap_spm = new();
    ap_dpm = new();

    dma.init();
    dma.core.add_ap2pkt(ap_spm);
    dma.core.add_ap2pkt(ap_dpm);
    dma.core.run_phase();

    // we don't want to wait to first vsync (end of first frame)
    // in simulation we can skip this alignment
    force dut.u_fb_dma.first_frame_skipped = 1'b1;
  endfunction

  task static setup();
      svunit_ut.setup();
      pixel_reset <= 1'b1;
      avalon_reset <= 1'b1;
      repeat (10) @(posedge pixel_clk);
      @(posedge pixel_ddr_clk);
      pixel_reset <= 1'b0;
      repeat (10) @(posedge avalon_clk);
      avalon_reset <= 1'b0;
      @(posedge avalon_clk);

      ap_spm.skip = 1; // skip checking in AP
      ap_dpm.skip = 1; // skip checking in AP
  endtask

  task static teardown();
    while (ap.patterns.size()) begin
      void'(ap.patterns.pop_front());
    end
  endtask

  import framebuffer_registers_pkg::data_rate_e;
  import framebuffer_registers_pkg::pixel_mode_e;
  import framebuffer_registers_pkg::kSdr;
  import framebuffer_registers_pkg::kDdr;
  import framebuffer_registers_pkg::kSpm;
  import framebuffer_registers_pkg::kDpm;

  // for testing dual data rate, please change default of data_rate to kDdr and
  // change clock in pixel_vip instance (pixel) to pixel_ddr_clk
  task configure_fb(ic_picture_t pic, ap_t current_ap = ap_spm, bit skip = 0,
                    data_rate_e data_rate = kDdr,
                    pixel_mode_e pixel_mode = kSpm);
    axil_item_t axil_item;

    ap = current_ap;
    ap.skip = skip;
    axil_item = new();

    axil_item.wstrb  = '1;

    void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
    axil_item.awaddr = AddrBufferSize;
    axil_item.wdata  = pic.get_pixels_num() * 4; // 4 bytes per pixel
    drv_axi.core.send_item(axil_item.clone());
    axil_item.awaddr = AddrIODataRate;
    axil_item.wdata  = data_rate;
    drv_axi.core.send_item(axil_item.clone());
    axil_item.awaddr = AddrIOPixelMode;
    axil_item.wdata  = pixel_mode;
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
      ap.analyzer();
    join_none

  endtask

  `SVUNIT_TESTS_BEGIN
    // dummy 3 startup frames
    // allows frame buffer to initialize counters etc. at vsync and hsync events
    `SVTEST(startup_frames)
      int frames;
      small_frame f = new();
      configure_fb(f, .skip(1));
      dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      repeat (3) begin
        `FAIL_IF(!f.randomize());
        @(posedge pixel_clk);
        @(posedge pixel_ddr_clk);
        pixel.send_item(f.clone());
      end
      repeat (100) @(posedge pixel_clk);
    `SVTEST_END

    repeat(2)
    `SVTEST(main_320)
      int frames;
      frame320x200_60 f = new();
      configure_fb(f);
      dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      // one frame for buffers valid synchonization
      `FAIL_IF(!f.randomize());
      @(posedge pixel_clk);
      pixel.send_item(f.clone());

      repeat (2) begin
        `FAIL_IF(!f.randomize());
        @(posedge pixel_clk);
        @(posedge pixel_ddr_clk);
        ap.patterns.push_back(f.clone());
        pixel.send_item(f.clone());
      end
      wait (ap.px_idx == (320*200));
      repeat (20) @(posedge pixel_clk);
    `SVTEST_END

    `SVTEST(inv_polarity_320)
      int frames;
      frame320x200_60_inv_polarity f = new();
      configure_fb(f);
      dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      // one frame for buffers valid synchonization
      `FAIL_IF(!f.randomize());
      @(posedge pixel_clk);
      pixel.send_item(f.clone());

      `FAIL_IF(!f.randomize());
      @(posedge pixel_ddr_clk);
      ap.patterns.push_back(f.clone());
      pixel.send_item(f.clone());

      wait (ap.px_idx == (320*200));
      repeat (20) @(posedge pixel_clk);
    `SVTEST_END

    `SVTEST(main_480p_dpm)
      int frames;
      frame480p_60_dpm f = new();
      configure_fb(f, .current_ap(ap_dpm), .pixel_mode(kDpm));
      dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      // one frame for buffers valid synchonization
      `FAIL_IF(!f.randomize());
      @(posedge pixel_clk);
      pixel.send_item(f.clone());

      // and one for test
      `FAIL_IF(!f.randomize());
      @(posedge pixel_clk);
      @(posedge pixel_ddr_clk);
      ap.patterns.push_back(f.clone());
      pixel.send_item(f.clone());

      wait (ap.px_idx == (480*640));
      repeat (20) @(posedge pixel_clk);
    `SVTEST_END

    `SVTEST(main_320_dpm)
      int frames;
      frame320x200_60_dpm f = new();
      configure_fb(f, .current_ap(ap_dpm), .pixel_mode(kDpm));
      dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      // one frame for buffers valid synchonization
      `FAIL_IF(!f.randomize());
      @(posedge pixel_clk);
      pixel.send_item(f.clone());

      repeat (2) begin
        `FAIL_IF(!f.randomize());
        @(posedge pixel_clk);
        @(posedge pixel_ddr_clk);
        ap.patterns.push_back(f.clone());
        pixel.send_item(f.clone());
      end
      wait (ap.px_idx == (320*200));
      repeat (20) @(posedge pixel_clk);
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : framebuffer_ite_top_unit_test
