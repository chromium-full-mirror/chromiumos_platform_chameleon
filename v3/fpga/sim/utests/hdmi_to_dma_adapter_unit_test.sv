/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module hdmi_to_dma_adapter_unit_test;

  //Unit test name
  parameter string name = "hdmi_to_dma_adapter_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import svunit_greporter_pkg::*;
  import gvip_axis_item_pkg::bitem;
  import gvip_axis_item_pkg::item;
  import hdmi_rx_pkg::*;
  import vid_rx_pkg::*;
  import frame_pkg::ic_picture_t;

  //Clocking
  logic hdmi_clk = 1'b0;
  logic hdmi_rst;
  logic clk = 1'b0;
  logic rst;


  default clocking clk_default @(posedge clk); endclocking

  `SVUNIT_CLK_GEN(clk, 4)
  `SVUNIT_CLK_GEN(hdmi_clk, 3)

  // Inputs and outputs
  hdmi_data_i i_hdmi_vid();
  pixel_vip #(.DataWidth(HdmiVidDataWidth), .Name("pixel"), .ByteAlignment(0))
    pixel(.clk(hdmi_clk), .reset(hdmi_rst));
  gvip_axis_if #(DmaDataWidth/8, 0, 0, vid_meta_t,
                 "dma_data_out", gvip_axis_pkg::SLAVE) v_dma(clk, rst);

  `AXIS_TO_GAXIS_VIP(v_dma, vid_meta_t)

  class vid_conf_t;
    rand static bit alignment;
    rand static vid_dma_format_e vid_format;

    constraint format {
      vid_format inside {k8bpc, k10bpcUpper, k10bpcLower, k12bpcUpper, k12bpcLower, k16bpc};
    };

  endclass : vid_conf_t;

  typedef pixel.axis_item_t axis_item_t;
  typedef v_dma.item_t dma_pattern_t;
  typedef gvip_axis_item_pkg::item #((HdmiVidDataWidth*2)/8, 0, 0, vid_meta_t) axis_conv_t;

  vid_conf_t vid_conf;

  typedef struct packed {
    logic hsync;
    logic vsync;
    logic de;
    logic [HdmiVidDataWidth-1:0] qd;
  } pixel_user_t;
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

  logic overflow;
  hdmi_to_dma_adapter dut (
    .clk           ( clk                  ),
    .rst           ( rst                  ),
    .vid_clk       ( hdmi_clk             ),
    .overflow      ( overflow             ),
    .vid_format    ( vid_conf.vid_format  ),
    .i_hdmi_vid    ( i_hdmi_vid           ),
    .i_hdmi_dma    ( axis_v_dma           )
  );

  class format_conv_t;
    protected vid_dma_format_e format;

    function new(vid_dma_format_e f);
      format = f;
    endfunction : new

    function void convert_to_format(ref vid_input_format_u data[]);
      vid_dma_format_u new_data[];

      case (format)
        k8bpc: begin
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
        k10bpcUpper: begin
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
        k10bpcLower: begin
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
        k12bpcUpper: begin
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
        k12bpcLower: begin
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
        k16bpc: begin
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
        kRaw: begin
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

  class dma_ap implements gvip_axis_pkg::analysis_port_ic#(dma_pattern_t);
    protected dma_pattern_t pattern_queue[$];
    protected dma_pattern_t results_queue[$];
    protected format_conv_t format_conv;
    protected int id = 0;

    function void init(vid_dma_format_e format);
      format_conv = new(format);
    endfunction : init

    function void add_pattern(axis_item_t raw_pat);
      axis_conv_t pat;
      dma_pattern_t new_pat;
      vid_input_format_u data_pat[];
      logic [DmaDataWidth/2-1:0] beat_stream[$];
      int eol_id = 0;
      pat = format_conv.convert_data_size(raw_pat);

      new_pat = new();
      data_pat = new[pat.tdata.size()](pat.tdata);
      format_conv.convert_to_format(data_pat);

      new_pat.tdata = new[pat.tdata.size()*$bits(vid_input_format_u)/DmaDataWidth];
      new_pat.tdata = {<<$bits(vid_input_format_u){{>>{data_pat}}}};

      // Cut half of last beat of data
      if (pat.tdata.size()*$bits(vid_input_format_u)/DmaDataWidth % 2 != 0 &&
          vid_conf.vid_format == k8bpc) begin
        beat_stream = {<<(DmaDataWidth/2){new_pat.tdata}};
        void'(beat_stream.pop_front());
        new_pat.tdata = {>>(DmaDataWidth){beat_stream}};
        foreach(new_pat.tdata[i]) begin
          beat_stream[0] = new_pat.tdata[i][DmaDataWidth/2-1:0];
          new_pat.tdata[i][DmaDataWidth/2-1:0] = new_pat.tdata[i][DmaDataWidth-1:DmaDataWidth/2];
          new_pat.tdata[i][DmaDataWidth-1:DmaDataWidth/2] = beat_stream[0];
        end
      end else begin
        new_pat.tdata = {<<DmaDataWidth{new_pat.tdata}};
      end

      new_pat.tkeep = new[new_pat.tdata.size()];
      foreach (new_pat.tkeep[item]) begin
        new_pat.tkeep[item] = '1; // Continuous keep due to alignment
      end

      // Cut half of last beat of data
      if (pat.tdata.size()*$bits(vid_input_format_u)/DmaDataWidth % 2 != 0 &&
        vid_conf.vid_format == k8bpc) begin
        new_pat.tkeep[new_pat.tkeep.size()-1][DmaKeepWidth-1:DmaKeepWidth/2] = '0;
      end

      new_pat.tuser = new[new_pat.tdata.size()];
      foreach (new_pat.tuser[i]) begin
        new_pat.tuser[i] = '0;
        new_pat.tuser[i].vid.data_valid = 1'b1;
      end

      foreach (pat.tuser[i]) begin
        eol_id++;
        if (pat.tuser[i].vid.eol) begin
          if (vid_conf.vid_format == k8bpc) begin
            new_pat.tuser[eol_id/2*3/2-1].vid.eol = 1'b1;
          end else begin
            new_pat.tuser[eol_id/2*3-1].vid.eol = 1'b1;
          end
        end
      end
      new_pat.tuser[0] = pat.tuser[0];
      new_pat.tuser[new_pat.tuser.size()-1] = pat.tuser[pat.tuser.size()-1];

      pattern_queue.push_back(new_pat);
    endfunction : add_pattern

    function void delete_pattern_queue();
      pattern_queue.delete();
    endfunction : delete_pattern_queue

    function bit is_pattern_queue_empty();
      return (pattern_queue.size() == 0);
    endfunction : is_pattern_queue_empty

    virtual function void write(input dma_pattern_t item);
      results_queue.push_back(item);
    endfunction : write

    task analyzer();
      dma_pattern_t res;
      dma_pattern_t pat;

      forever begin
        @(posedge clk);
        wait(results_queue.size());
        res = results_queue.pop_front();

        `FAIL_IF_LOG(pattern_queue.size() == 0, "More packets received than sent");

        pat = pattern_queue.pop_front();

        `FAIL_IF_LOG(pat.tdata.size() != res.tdata.size(),
                     $sformatf("Size of pattern and result mismatch, id = %d, pat %d != res %d",
                     id, pat.tdata.size(), res.tdata.size()));
        foreach(pat.tdata[i]) begin
          `FAIL_IF_LOG(pat.tdata[i] != res.tdata[i],
                       $sformatf("Data mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tdata[i], res.tdata[i]));
          `FAIL_IF_LOG(pat.tuser[i].vid.data_valid != res.tuser[i].vid.data_valid,
                       $sformatf("User data_valid mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tuser[i].vid.data_valid, res.tuser[i].vid.data_valid));
          `FAIL_IF_LOG(pat.tuser[i].vid.eol != res.tuser[i].vid.eol,
                       $sformatf("User eol mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tuser[i].vid.eol, res.tuser[i].vid.eol));
          `FAIL_IF_LOG(pat.tuser[i].vid.eof != res.tuser[i].vid.eof,
                       $sformatf("User eof mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tuser[i].vid.eof, res.tuser[i].vid.eof));
          `FAIL_IF_LOG(pat.tuser[i].vid != res.tuser[i].vid,
                       $sformatf("User vid mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tuser[i].vid, res.tuser[i].vid));
          `FAIL_IF_LOG(pat.tuser[i].aud != res.tuser[i].aud,
                       $sformatf("User aud mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tuser[i].aud, res.tuser[i].aud));
          `FAIL_IF_LOG(pat.tkeep[i] != res.tkeep[i],
                       $sformatf("Keep mismatch, id = %d, i = %d, pat = %h, res = %h",
                       id, i, pat.tkeep[i], res.tkeep[i]));
        end
        id++;
      end
    endtask : analyzer

  endclass: dma_ap

  dma_ap dma;

  typedef frame_pkg::frame_tmds_t #(.Vactive(8), .Hactive(8), .Vbp(1), .Vfp(0), .Vslen(0),
    .Hbp(1), .Hfp(1), .Hslen(0), .T(axis_item_t)) small_frame;
  typedef frame_pkg::frame_tmds_t #(.Vactive(8), .Hactive(8), .Vbp(8), .Vfp(6), .Vslen(8),
    .Hbp(3), .Hfp(10), .Hslen(8), .T(axis_item_t)) small_frame_porches;
  typedef frame_pkg::frame_tmds_t #(.Vactive(100), .Hactive(320), .Vbp(10), .Vfp(10), .Vslen(8),
    .Hbp(4), .Hfp(2), .Hslen(10), .T(axis_item_t)) frame320x200_60_porches;
  typedef frame_pkg::frame_tmds_t #(.Vactive(100), .Hactive(320), .Vbp(1), .Vfp(0), .Vslen(0),
    .Hbp(1), .Hfp(1), .Hslen(0), .T(axis_item_t)) frame320x200_60;

  task monitor_overflow();
    @(posedge clk);
    `FAIL_IF_LOG(overflow, $sformatf("%t: Error in monitor, FIFO to small\n", $time));
  endtask : monitor_overflow

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    pixel.init();
    v_dma.init();

    vid_conf = new();

    dma = new();

    v_dma.core.add_ap2pkt(dma);

    pixel.run_phase();
    v_dma.core.run_phase();
  endfunction : build

  task setup();
    svunit_ut.setup();

    rst <= 1'b1;
    @(posedge clk);
    rst <= 1'b0;
    `FAIL_IF(!vid_conf.randomize());
  endtask : setup

  task teardown();
    dma.delete_pattern_queue();
  endtask : teardown

  `SVUNIT_TESTS_BEGIN

    repeat (10) begin
    `SVTEST(small_frames)
      small_frame f = new();
      v_dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      dma.init(vid_conf.vid_format);
      fork
        forever begin
          monitor_overflow();
        end
        begin
          dma.analyzer();
        end
      join_none
      repeat(10) begin
        `FAIL_IF(!f.randomize());
        dma.add_pattern(f.clone());
        pixel.send_item(f.clone());
      end

      wait(dma.is_pattern_queue_empty());

    `SVTEST_END
    end

    `SVTEST(small_frames_porches)
      small_frame_porches f = new();
      v_dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      dma.init(vid_conf.vid_format);
      fork
        forever begin
          monitor_overflow();
        end
        begin
          dma.analyzer();
        end
      join_none
      repeat(10) begin
        `FAIL_IF(!f.randomize());
        dma.add_pattern(f.clone());
        pixel.send_item(f.clone());
      end

      wait(dma.is_pattern_queue_empty());

    `SVTEST_END

    `SVTEST(random_valid)
      frame320x200_60 f = new();
      v_dma.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      dma.init(vid_conf.vid_format);
      fork
        forever begin
          monitor_overflow();
        end
        begin
          dma.analyzer();
        end
      join_none
      repeat(2) begin
        `FAIL_IF(!f.randomize());
        dma.add_pattern(f.clone());
        pixel.send_item(f.clone());
      end

      wait(dma.is_pattern_queue_empty());

    `SVTEST_END

    `SVTEST(random_ready)
      frame320x200_60_porches f = new();
      gvip_policy_pkg::random_std rr_schema = gvip_policy_pkg::random_std::create();

      `FAIL_IF(!rr_schema.randomize() with {
        foreach(not_active_interval[i]) not_active_interval[i] < 1;
      })

      v_dma.core.set_policy(rr_schema, 0);

      dma.init(vid_conf.vid_format);
      fork
        forever begin
          monitor_overflow();
        end
        begin
          dma.analyzer();
        end
      join_none
      repeat(2) begin
        `FAIL_IF(!f.randomize());
        dma.add_pattern(f.clone());
        pixel.send_item(f.clone());
      end

      wait(dma.is_pattern_queue_empty());

    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : hdmi_to_dma_adapter_unit_test
