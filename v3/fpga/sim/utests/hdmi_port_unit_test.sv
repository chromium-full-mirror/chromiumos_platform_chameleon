/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module hdmi_port_unit_test;

  //Unit test name
  parameter string name = "hdmi_port_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import svunit_greporter_pkg::*;
  import gvip_axis_item_pkg::bitem;
  import gvip_axis_item_pkg::item;

  import hdmi_rx_pkg::*;
  import vid_rx_pkg::vid_meta_t;
  import vid_rx_pkg::vid_input_format_u;
  import vid_rx_pkg::DmaDataWidth;
  import vid_rx_pkg::DmaKeepWidth;
  import framebuffer_pkg::*;
  import framebuffer_registers_pkg::*;

  //Parameters
  //Clocking
  logic hdmi_clk = 1'b0;
  logic avalon_clk = 1'b0;
  logic hdmi_reset;
  logic avalon_reset;

  `SVUNIT_CLK_GEN(hdmi_clk,  4)
  `SVUNIT_CLK_GEN(avalon_clk, 4)

  localparam int PixelDataWidth = 192;
  localparam int DataWidth = DmaDataWidth;
  localparam int AxiLiteAddrWidth = 12;
  localparam int AxiLiteDataWidth = 32;

  //Inputs and outputs
  hdmi_data_i i_hdmi_vid();
  hdmi_audio_i i_hdmi_audio();
  pixel_vip #(.DataWidth(HdmiVidDataWidth), .Name("pixel"), .ByteAlignment(0))
    pixel(.clk(hdmi_clk), .reset(hdmi_reset));
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_axi(avalon_clk, avalon_reset);
  gvip_aximm_if #(.N(DataWidth/8), .A(32), .NAME("mm_slv"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) mm_vip(avalon_clk, avalon_reset);

  axil_i #(.DataWidth(AxiLiteDataWidth), .AddrWidth(AxiLiteAddrWidth)) i_aud_csr();
  aximm_i #(.DataWidth(DataWidth), .AddrWidth(32)) i_aud_dma();

  typedef pixel.axis_item_t axis_item_t;
  typedef gvip_axis_item_pkg::item #((HdmiVidDataWidth*2)/8, 0, 0, vid_meta_t) axis_conv_t;
  typedef mm_vip.item_t mm_item_t;
  typedef drv_axi.item_t axil_item_t;

  `AXIMM_TO_GAXIMM_VIP(mm_vip)
  `GAXIL_VIP_TO_AXIL(drv_axi)

  class vid_conf_t;
    rand static bit alignment;
  endclass : vid_conf_t;

  typedef struct packed {
    logic hsync;
    logic vsync;
    logic de;
    logic [HdmiVidDataWidth-1:0] qd;
  } pixel_user_t;

  vid_conf_t vid_conf;
  pixel_user_t pixel_d;

 always_ff @(posedge hdmi_clk) begin
    pixel_d.de    <= pixel.de;
    pixel_d.hsync <= pixel.hsync;
    pixel_d.vsync <= pixel.vsync;
    pixel_d.qd    <= pixel.qd;
  end

  always_comb begin
    if (vid_conf.alignment) begin
      i_hdmi_vid.de[0] = pixel_d.de;
      i_hdmi_vid.de[1] = pixel.de;
      i_hdmi_vid.hsync[0] = pixel_d.hsync;
      i_hdmi_vid.hsync[1] = pixel.hsync;
      i_hdmi_vid.vsync[0] = pixel_d.vsync;
      i_hdmi_vid.vsync[1] = pixel.vsync;
      i_hdmi_vid.data[HdmiVidDataWidth/2-1:0] = pixel_d.qd[HdmiVidDataWidth-1-:HdmiVidDataWidth/2];
      i_hdmi_vid.data[HdmiVidDataWidth-1-:HdmiVidDataWidth/2] = pixel.qd[HdmiVidDataWidth/2-1:0];
      i_hdmi_vid.lock = 1'b1;
    end else begin
      for (int i = 0; i < HdmiVidPxPerBeat; i++) begin
        i_hdmi_vid.de[i] = pixel.de;
        i_hdmi_vid.hsync[i] = pixel.hsync;
        i_hdmi_vid.vsync[i] = pixel.vsync;
      end
      i_hdmi_vid.lock = 1'b1;
      i_hdmi_vid.data = pixel.qd;
    end
  end

  class format_conv_t;
    vid_rx_pkg::vid_dma_format_e format;

    function new(vid_rx_pkg::vid_dma_format_e f);
      format = f;
    endfunction : new

    function void convert_to_format(ref vid_rx_pkg::vid_input_format_u data[]);
      vid_rx_pkg::vid_dma_format_u new_data[];

      case (format)
        vid_rx_pkg::k8bpc: begin
          int new_id = 0;
          new_data = new[data.size()/2];
          for (int item = 0; item < data.size(); item = item + 2) begin
            new_data[new_id].raw_data = '0;
            for (int i = 0; i < PixelsInBeat; i++) begin
              new_data[new_id].format8bpc.lower[i].b = data[item].format8bpc_444[i].b;
              new_data[new_id].format8bpc.lower[i].g = data[item].format8bpc_444[i].g;
              new_data[new_id].format8bpc.lower[i].r = data[item].format8bpc_444[i].r;
              new_data[new_id].format8bpc.upper[i].b = data[item+1].format8bpc_444[i].b;
              new_data[new_id].format8bpc.upper[i].g = data[item+1].format8bpc_444[i].g;
              new_data[new_id].format8bpc.upper[i].r = data[item+1].format8bpc_444[i].r;
            end
            new_id++;
          end
          data = new[new_data.size()];
        end
        vid_rx_pkg::k10bpcUpper: begin
          new_data = new[data.size()];
          for (int item = 0; item < data.size(); item++) begin
            new_data[item].raw_data = '0;
            for (int i = 0; i < PixelsInBeat; i++) begin
              new_data[item].format10bpc_upper[i].b = data[item].format10bpc_444[i].b;
              new_data[item].format10bpc_upper[i].g = data[item].format10bpc_444[i].g;
              new_data[item].format10bpc_upper[i].r = data[item].format10bpc_444[i].r;
            end
          end
        end
        vid_rx_pkg::k10bpcLower: begin
          new_data = new[data.size()];
          for (int item = 0; item < data.size(); item++) begin
            new_data[item].raw_data = '0;
            for (int i = 0; i < PixelsInBeat; i++) begin
              new_data[item].format10bpc_lower[i].b = data[item].format10bpc_444[i].b;
              new_data[item].format10bpc_lower[i].g = data[item].format10bpc_444[i].g;
              new_data[item].format10bpc_lower[i].r = data[item].format10bpc_444[i].r;
            end
          end
        end
        vid_rx_pkg::k12bpcUpper: begin
          new_data = new[data.size()];
          for (int item = 0; item < data.size(); item++) begin
            new_data[item].raw_data = '0;
            for (int i = 0; i < PixelsInBeat; i++) begin
              new_data[item].format12bpc_upper[i].b = data[item].format12bpc_444[i].b;
              new_data[item].format12bpc_upper[i].g = data[item].format12bpc_444[i].g;
              new_data[item].format12bpc_upper[i].r = data[item].format12bpc_444[i].r;
            end
          end
        end
        vid_rx_pkg::k12bpcLower: begin
          new_data = new[data.size()];
          for (int item = 0; item < data.size(); item++) begin
            new_data[item].raw_data = '0;
            for (int i = 0; i < PixelsInBeat; i++) begin
              new_data[item].format12bpc_lower[i].b = data[item].format12bpc_444[i].b;
              new_data[item].format12bpc_lower[i].g = data[item].format12bpc_444[i].g;
              new_data[item].format12bpc_lower[i].r = data[item].format12bpc_444[i].r;
            end
          end
        end
        vid_rx_pkg::k16bpc: begin
          new_data = new[data.size()];
          for (int item = 0; item < data.size(); item++) begin
            new_data[item].raw_data = '0;
            for (int i = 0; i < PixelsInBeat; i++) begin
              new_data[item].format16bpc[i].b = data[item].format16bpc_444[i].b;
              new_data[item].format16bpc[i].g = data[item].format16bpc_444[i].g;
              new_data[item].format16bpc[i].r = data[item].format16bpc_444[i].r;
            end
          end
        end
        vid_rx_pkg::kRaw: begin
          new_data = new[data.size()];
          for (int item = 0; item < data.size(); item++) begin
            new_data[item] = data[item];
          end
        end
      endcase

      foreach (new_data[item]) begin
        data[item] = new_data[item];
      end

    endfunction : convert_to_format

    function axis_conv_t convert_data_size(ref axis_item_t pat);
      axis_conv_t new_pattern;
      logic [HdmiVidDataWidth-1:0] data_valid[$];
      int id_eol = 0;
      new_pattern = new();

      foreach(pat.tuser[i]) begin
        if (pat.tuser[i].de) begin
          data_valid.push_back(pat.tdata[i]);
        end
      end

      new_pattern.tdata = new[data_valid.size()/2];
      new_pattern.tkeep = new[data_valid.size()/2];
      new_pattern.tuser = new[data_valid.size()/2];

      foreach(new_pattern.tkeep[i]) begin
        new_pattern.tkeep[i] = '1;
      end

      foreach(new_pattern.tuser[i]) begin
        new_pattern.tuser[i] = '0;
        new_pattern.tuser[i].vid.data_valid = 1'b1;
      end

      new_pattern.tdata = {<<HdmiVidDataWidth{{>>{data_valid}}}};
      new_pattern.tdata.reverse();

      foreach(pat.tuser[i]) begin
        if (pat.tuser[i].de) begin
          id_eol++;
        end
        if (pat.tuser[i].hsync) begin
          new_pattern.tuser[id_eol/2-1].vid.eol = 1'b1;
        end
      end

      new_pattern.tuser[new_pattern.tuser.size()-1].vid.eof = 1'b1;

      return new_pattern;

    endfunction : convert_data_size

  endclass : format_conv_t

  class mm_slv_t implements gvip_aximm_pkg::analysis_port_ic#(mm_item_t);
    mm_item_t mm_results[$];
    mm_item_t mm_patterns[$];
    mm_item_t current_frame;
    format_conv_t format_conv;
    int px_idx;
    int current_frame_idx;

    function void init(vid_rx_pkg::vid_dma_format_e format);
      format_conv = new(format);
    endfunction : init

    function void add_pattern(axis_item_t raw_pat);
      axis_conv_t pat;
      mm_item_t new_pat;
      vid_input_format_u data_pat[];
      logic [DmaDataWidth/2-1:0] beat_stream[$];
      int eol_id = 0;
      pat = format_conv.convert_data_size(raw_pat);

      new_pat = new();
      data_pat = new[pat.tdata.size()](pat.tdata);
      format_conv.convert_to_format(data_pat);

      new_pat.wdata = new[pat.tdata.size()*$bits(vid_input_format_u)/DmaDataWidth];
      new_pat.wdata = {<<$bits(vid_input_format_u){{>>{data_pat}}}};

      // Cut half of last beat of data
      if (pat.tdata.size()*$bits(vid_input_format_u)/DmaDataWidth % 2 != 0 &&
          format_conv.format == vid_rx_pkg::k8bpc) begin
        beat_stream = {<<(DmaDataWidth/2){new_pat.wdata}};
        void'(beat_stream.pop_front());
        new_pat.wdata = {>>(DmaDataWidth){beat_stream}};
        foreach(new_pat.wdata[i]) begin
          beat_stream[0] = new_pat.wdata[i][DmaDataWidth/2-1:0];
          new_pat.wdata[i][DmaDataWidth/2-1:0] = new_pat.wdata[i][DmaDataWidth-1:DmaDataWidth/2];
          new_pat.wdata[i][DmaDataWidth-1:DmaDataWidth/2] = beat_stream[0];
        end
      end else begin
        new_pat.wdata = {<<DmaDataWidth{new_pat.wdata}};
      end

      new_pat.wstrb = new[new_pat.wdata.size()];
      foreach (new_pat.wstrb[item]) begin
        new_pat.wstrb[item] = '1; // Continuous keep due to alignment
      end

      // Cut half of last beat of data
      if (pat.tdata.size()*$bits(vid_input_format_u)/DmaDataWidth % 2 != 0 &&
          format_conv.format == vid_rx_pkg::k8bpc) begin
        new_pat.wstrb[new_pat.wstrb.size()-1][DmaKeepWidth-1:DmaKeepWidth/2] = '0;
      end

      mm_patterns.push_back(new_pat);
    endfunction : add_pattern

    virtual function mm_item_t write (input mm_item_t item);
      mm_results.push_back(item.clone());
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AW_W) begin
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::B));
        item.bresp = gaximm_pkg::OKAY;
        item.bid   = item.awid;
        item.buser = item.awuser;
        return item;
      end
    endfunction : write

    function bit is_empty();
      return (mm_patterns.size() == 0 && mm_results.size() == 0);
    endfunction : is_empty

    task analyzer();
      mm_item_t item;
      forever begin
        @(posedge avalon_clk);
        wait(mm_results.size());

        item = mm_results.pop_front();

        if (current_frame == null) begin
          `FAIL_IF(mm_patterns.size() == 0)
          current_frame = mm_patterns.pop_front();
          current_frame_idx = 0;
          px_idx = 0;
        end

        if (current_frame.wdata.size() == current_frame_idx * item.wdata.size()) begin
          `FAIL_IF(mm_patterns.size() == 0)
          current_frame = mm_patterns.pop_front();
          current_frame_idx = 0;
          px_idx = 0;
        end

        `FAIL_IF_LOG(item.awaddr != (4 * px_idx), $sformatf("item.awaddr = 0x%h, px_idx = 0x%h",
                                                            item.awaddr, px_idx));

        `FAIL_IF(current_frame == null)

        for(int i = 0; i < item.wdata.size(); ++i) begin
          `FAIL_IF(current_frame.wdata.size() == current_frame_idx)
          `FAIL_IF_LOG(item.wdata[i]!= current_frame.wdata[current_frame_idx*item.wdata.size() + i],
                       $sformatf("%h!=%h, id = %d, current_frame_idx = %d", item.wdata[i],
                                 current_frame.wdata[current_frame_idx + i], i, current_frame_idx))
          px_idx = px_idx + 4;
        end

        current_frame_idx++;
      end
    endtask : analyzer

  endclass : mm_slv_t

  mm_slv_t mm_slv_ap;

  port_registers_pkg::vid_status_t vid_status;
  logic [3:0] fb_irq;
  i2s_pkg::irq_source_t aud_irq;
  logic tmds_valid;
  logic [hdmi_rx_pkg::TmdsMeasureWidth-1:0] tmds_measure;

  typedef frame_pkg::frame_tmds_t #(.Vactive(200), .Hactive(160), .Vbp(1), .Vfp(0), .Vslen(0),
    .Hbp(1), .Hfp(1), .Hslen(0), .T(axis_item_t)) frame_320x240;

  // This is the UUT that we're running the Unit Tests on
  hdmi_port dut (
      .clk            ( avalon_clk   ),
      .rst            ( avalon_reset ),
      .vid_clk        ( hdmi_clk     ),
      .aud_clk        ( hdmi_clk     ),
      .vid_status     ( vid_status   ),
      .tmds_valid     ( tmds_valid   ),
      .tmds_measure   ( tmds_measure ),
      .fb_irq         ( fb_irq       ),
      .aud_irq        ( aud_irq      ),
      .i_hdmi_vid     ( i_hdmi_vid   ),
      .i_hdmi_audio   ( i_hdmi_audio ),
      .i_fb_csr       ( axil_drv_axi ),
      .i_fb_hdmi_dma  ( aximm_mm_vip ),
      .i_aud_hdmi_csr ( i_aud_csr    ),
      .i_aud_hdmi_dma ( i_aud_dma    )
    );

  function static void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    pixel.init();
    pixel.run_phase();

    drv_axi.init();
    drv_axi.core.run_phase();

    vid_conf = new();

    mm_slv_ap = new();

    mm_vip.init();
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, mm_slv_ap);
    mm_vip.core.run_phase();
  endfunction

  task static setup();
    svunit_ut.setup();
    hdmi_reset <= 1'b1;
    avalon_reset <= 1'b1;
    repeat (10) @(posedge hdmi_clk);
    hdmi_reset <= 1'b0;
    `FAIL_IF(!vid_conf.randomize());
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
      frame_320x240 f = new();
      gvip_policy_pkg::random_std rr_schema = gvip_policy_pkg::random_std::create();

      axil_item.wstrb  = '1;
      void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      axil_item.awaddr = AddrBufferSize;
      axil_item.wdata  = f.get_pixels_num()*2 * 3; // get_pixels_num returns height divided by two
                                                   // due to two pixels sent in parallel. Multiply
                                                   // size by two to fit whole frame.
                                                   // k8bpc format uses 3 bytes for every pixel
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrBufferA;
      axil_item.wdata  = 0;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrBufferB;
      axil_item.wdata  = 0;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrDmaFormat;
      axil_item.wdata  = vid_rx_pkg::k8bpc;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = AddrEn;
      axil_item.wdata  = 1'b1;
      drv_axi.core.send_item(axil_item.clone());

      mm_slv_ap.init(vid_rx_pkg::k8bpc);

      fork
        mm_slv_ap.analyzer();
      join_none

      `FAIL_IF(!rr_schema.randomize() with {
        foreach(not_active_interval[i]) not_active_interval[i] < 10;
      })

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW, rr_schema, 0);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,  rr_schema, 0);

      `FAIL_IF(!f.randomize());

      // first dummy frame for initialization and align
      pixel.send_item(f);
      // one frame for buffers valid synchonization
      pixel.send_item(f);

      repeat (2) begin
        `FAIL_IF(!f.randomize());
        @(posedge hdmi_clk);
        mm_slv_ap.add_pattern(f);
        pixel.send_item(f);
        repeat (100) @(posedge hdmi_clk);
      end
      while(!mm_slv_ap.is_empty()) begin
        @(posedge hdmi_clk);
      end
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : hdmi_port_unit_test
