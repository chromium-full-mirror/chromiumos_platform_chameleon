/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module dp_port_unit_test;

  //Unit test name
  parameter string name = "dp_port_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import svunit_greporter_pkg::*;
  import gvip_axis_item_pkg::bitem;

  import vid_rx_pkg::vid_meta_t;
  import vid_rx_pkg::vid_input_format_u;
  import vid_rx_pkg::DmaDataWidth;
  import vid_rx_pkg::DmaKeepWidth;
  import framebuffer_pkg::*;
  import framebuffer_registers_pkg::*;

  //Parameters
  //Clocking
  logic dp_clk = 1'b0;
  logic avalon_clk = 1'b0;
  logic dp_reset;
  logic avalon_reset;

  `SVUNIT_CLK_GEN(dp_clk,  6)
  `SVUNIT_CLK_GEN(avalon_clk, 4)

  localparam int PixelDataWidth = 192;
  localparam int DataWidth = DmaDataWidth;
  localparam int AxiLiteAddrWidth = 12;
  localparam int AxiLiteDataWidth = 32;

  //Inputs and outputs
  gvip_axis_if #(PixelDataWidth/8, 0, 0, vid_meta_t,
                 "dp_vid_in", gvip_axis_pkg::MASTER)   v_vid_dp(dp_clk, dp_reset);
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_axi(avalon_clk, avalon_reset);
  gvip_aximm_if #(.N(DataWidth/8), .A(32), .NAME("mm_slv"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) mm_vip(avalon_clk, avalon_reset);

  dp_video_i i_dp_vid[0:0]();

  assign i_dp_vid[0].clk = dp_clk;
  assign v_vid_dp.axis.tready = 1'b1;

  always @(posedge dp_clk) begin
    for (int i = 0; i < vid_rx_pkg::PixelsInBeat; i++) begin
      i_dp_vid[0].valid[i] <= v_vid_dp.axis.tvalid; // valid comes always on four lanes.
    end
    i_dp_vid[0].data      <= v_vid_dp.axis.tdata;
    i_dp_vid[0].sol       <= v_vid_dp.axis.tuser.vid.sol;
    i_dp_vid[0].eol       <= v_vid_dp.axis.tuser.vid.eol;
    i_dp_vid[0].sof       <= v_vid_dp.axis.tuser.vid.sof;
    i_dp_vid[0].eof       <= v_vid_dp.axis.tuser.vid.eof;
    i_dp_vid[0].locked    <= 1'b1;
    i_dp_vid[0].interlace <= v_vid_dp.axis.tuser.vid.interlace;
    i_dp_vid[0].field     <= 1'b1;
    i_dp_vid[0].overflow  <= v_vid_dp.axis.tuser.vid.error;
  end

  typedef v_vid_dp.item_t dp_vid_pattern;
  typedef mm_vip.item_t mm_item_t;
  typedef drv_axi.item_t axil_item_t;

  aximm_i #(.DataWidth(DataWidth), .AddrWidth(32)) aximm_mm_vip[0:0]();
  axil_i #(.DataWidth(AxiLiteDataWidth), .AddrWidth(AxiLiteAddrWidth))
    axil_drv_axi[0:0]();

  dp_audio_i i_dp_audio[0:0]();
  aximm_i #(.DataWidth(DataWidth), .AddrWidth(32)) aximm_mm_aud_vip();
  axil_i #(.DataWidth(AxiLiteDataWidth), .AddrWidth(AxiLiteAddrWidth))
    axil_drv_aud_axi[0:0]();

  always_comb begin
    mm_vip.aximm.awvalid    = aximm_mm_vip[0].awvalid;
    aximm_mm_vip[0].awready = mm_vip.aximm.awready;
    mm_vip.aximm.awid       = aximm_mm_vip[0].awid;
    mm_vip.aximm.awaddr     = aximm_mm_vip[0].awaddr;
    mm_vip.aximm.awlen      = aximm_mm_vip[0].awlen;
    mm_vip.aximm.awsize     = aximm_mm_vip[0].awsize;
    mm_vip.aximm.awburst    = gaximm_pkg::burst_type_e'(aximm_mm_vip[0].awburst);
    mm_vip.aximm.awprot     = aximm_mm_vip[0].awprot;
    mm_vip.aximm.awlock     = aximm_mm_vip[0].awlock;
    mm_vip.aximm.awcache    = aximm_mm_vip[0].awcache;
    mm_vip.aximm.awregion   = aximm_mm_vip[0].awregion;

    mm_vip.aximm.wvalid     = aximm_mm_vip[0].wvalid;
    aximm_mm_vip[0].wready  = mm_vip.aximm.wready;
    mm_vip.aximm.wdata      = aximm_mm_vip[0].wdata;
    mm_vip.aximm.wstrb      = aximm_mm_vip[0].wstrb;
    mm_vip.aximm.wlast      = aximm_mm_vip[0].wlast;

    aximm_mm_vip[0].bvalid  = mm_vip.aximm.bvalid;
    mm_vip.aximm.bready     = aximm_mm_vip[0].bready;
    aximm_mm_vip[0].bid     = mm_vip.aximm.bid;
    aximm_mm_vip[0].bresp   = gaxilite_pkg::resp_t'(mm_vip.aximm.bresp);

    mm_vip.aximm.arvalid    = aximm_mm_vip[0].arvalid;
    aximm_mm_vip[0].arready = mm_vip.aximm.arready;
    mm_vip.aximm.arid       = aximm_mm_vip[0].arid;
    mm_vip.aximm.araddr     = aximm_mm_vip[0].araddr;
    mm_vip.aximm.arlen      = aximm_mm_vip[0].arlen;
    mm_vip.aximm.arsize     = aximm_mm_vip[0].arsize;
    mm_vip.aximm.arburst    = gaximm_pkg::burst_type_e'(aximm_mm_vip[0].arburst);
    mm_vip.aximm.arprot     = aximm_mm_vip[0].arprot;
    mm_vip.aximm.arlock     = aximm_mm_vip[0].arlock;
    mm_vip.aximm.arcache    = aximm_mm_vip[0].arcache;
    mm_vip.aximm.arregion   = aximm_mm_vip[0].arregion;

    aximm_mm_vip[0].rvalid  = mm_vip.aximm.rvalid;
    mm_vip.aximm.rready     = aximm_mm_vip[0].rready;
    aximm_mm_vip[0].rid     = mm_vip.aximm.rid;
    aximm_mm_vip[0].rdata   = mm_vip.aximm.rdata;
    aximm_mm_vip[0].rresp   = gaxilite_pkg::resp_t'(mm_vip.aximm.rresp);
    aximm_mm_vip[0].rlast   = mm_vip.aximm.rlast;

    axil_drv_axi[0].awvalid  = drv_axi.axil.awvalid;
    drv_axi.axil.awready     = axil_drv_axi[0].awready;
    axil_drv_axi[0].awaddr   = drv_axi.axil.awaddr;

    axil_drv_axi[0].wvalid   = drv_axi.axil.wvalid;
    drv_axi.axil.wready      = axil_drv_axi[0].wready;
    axil_drv_axi[0].wdata    = drv_axi.axil.wdata;
    axil_drv_axi[0].wstrb    = drv_axi.axil.wstrb;

    drv_axi.axil.bvalid      = axil_drv_axi[0].bvalid;
    axil_drv_axi[0].bready   = drv_axi.axil.bready;
    drv_axi.axil.bresp       = gaxil_pkg::resp_e'(axil_drv_axi[0].bresp);

    axil_drv_axi[0].arvalid  = drv_axi.axil.arvalid;
    drv_axi.axil.arready     = axil_drv_axi[0].arready;
    axil_drv_axi[0].araddr   = drv_axi.axil.araddr;

    drv_axi.axil.rvalid      = axil_drv_axi[0].rvalid;
    axil_drv_axi[0].rready   = drv_axi.axil.rready;
    drv_axi.axil.rdata       = axil_drv_axi[0].rdata;
    drv_axi.axil.rresp       = gaxil_pkg::resp_e'(axil_drv_axi[0].rresp);
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

    function void add_pattern(dp_vid_pattern pat);
      mm_item_t new_pat;
      vid_input_format_u data_pat[];
      logic [DmaDataWidth/2-1:0] beat_stream[$];
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
                                                            item.awaddr, px_idx))

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
  logic [0:0][3:0] fb_irq;
  i2s_pkg::irq_source_t aud_irq[0:0];

  typedef frame_pkg::frame_axis_t #(.Vactive(240), .Hactive(320), .T(dp_vid_pattern)) frame_320x240;
  typedef frame_pkg::frame_axis_t #(.Vactive(1080), .Hactive(1920), .T(dp_vid_pattern)) frame_1080p;

  // This is the UUT that we're running the Unit Tests on
  dp_port #(
      .MstSupport   ( 0 )
  ) dut (
      .clk          ( avalon_clk        ),
      .rst          ( avalon_reset      ),
      .vid_status   ( vid_status        ),
      .fb_irq       ( fb_irq            ),
      .aud_irq      ( aud_irq           ),
      .i_dp_vid     ( i_dp_vid          ),
      .i_dp_audio   ( i_dp_audio        ),
      .i_fb_csr     ( axil_drv_axi      ),
      .i_fb_dp_dma  ( aximm_mm_vip      ),
      .i_aud_dp_csr ( axil_drv_aud_axi  ),
      .i_aud_dp_dma ( aximm_mm_aud_vip  )
    );

  function static void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    v_vid_dp.init();
    v_vid_dp.core.run_phase();

    drv_axi.init();
    drv_axi.core.run_phase();

    mm_slv_ap = new();

    mm_vip.init();
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, mm_slv_ap);
    mm_vip.core.run_phase();
  endfunction

  task static setup();
    svunit_ut.setup();
    dp_reset <= 1'b1;
    avalon_reset <= 1'b1;
    repeat (10) @(posedge dp_clk);
    dp_reset <= 1'b0;
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
      axil_item.wdata  = f.get_pixels_num() * 3; //k8bpc format uses 3 bytes for every pixel
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

      v_vid_dp.core.set_policy(rr_schema, 1);

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW, rr_schema, 0);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,  rr_schema, 0);

      `FAIL_IF(!f.randomize());

      // first dummy frame for initialization and align
      v_vid_dp.core.send_item(f);
      // one frame for buffers valid synchonization
      v_vid_dp.core.send_item(f);

      repeat (2) begin
        `FAIL_IF(!f.randomize());
        @(posedge dp_clk);
        mm_slv_ap.add_pattern(f);
        v_vid_dp.core.send_item(f);
        repeat (100) @(posedge dp_clk);
      end
      while(!mm_slv_ap.is_empty()) begin
        @(posedge dp_clk);
      end
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : dp_port_unit_test
