/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module dp_to_dma_adapter_unit_test;

  //Unit test name
  parameter string name = "dp_to_dma_adapter_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import svunit_greporter_pkg::*;
  import dp_rx_pkg::*;
  import vid_rx_pkg::*;

  //Clocking
  logic dp_clk = 1'b0;
  logic dp_rst;
  logic clk = 1'b0;
  logic rst;


  default clocking clk_default @(posedge clk); endclocking

  `SVUNIT_CLK_GEN(clk, 4)
  `SVUNIT_CLK_GEN(dp_clk, 6) // simulate 166MHz clock on input.
                             // Maximum possible clock is 202,5MHz,
                             // but the input transceiver can generate up to 32,4Gbpc,
                             // which translates to 166,6 MHz clock @ 192b wide bus.

  // Inputs and outputs
  // Use GVIP_AXIS to generate DP interface
  gvip_axis_if #(PixelDataWidth/8, 0, 0, vid_meta_t,
                 "dp_vid_in", gvip_axis_pkg::MASTER)   v_vid_dp(dp_clk, dp_rst);
  gvip_axis_if #(DmaDataWidth/8, 0, 0, vid_meta_t,
                 "dma_data_out", gvip_axis_pkg::SLAVE) v_dma(clk, rst);

  `AXIS_TO_GAXIS_VIP(v_dma, vid_meta_t)

  class vid_conf_t;
    rand static vid_dma_format_e vid_format;

    constraint format {
      vid_format inside {k8bpc, k10bpcUpper, k10bpcLower, k12bpcUpper, k12bpcLower, k16bpc};
    };

  endclass : vid_conf_t;

  dp_video_i i_dp_vid();

  assign i_dp_vid.clk = dp_clk;
  assign v_vid_dp.axis.tready = 1'b1;

  always @(posedge dp_clk) begin
    for (int i = 0; i < PixelsInBeat; i++) begin
      i_dp_vid.valid[i] <= v_vid_dp.axis.tvalid; // valid comes always on four lanes.
    end
    i_dp_vid.data      <= v_vid_dp.axis.tdata;
    i_dp_vid.sol       <= v_vid_dp.axis.tuser.vid.sol;
    i_dp_vid.eol       <= v_vid_dp.axis.tuser.vid.eol;
    i_dp_vid.sof       <= v_vid_dp.axis.tuser.vid.sof;
    i_dp_vid.eof       <= v_vid_dp.axis.tuser.vid.eof;
    i_dp_vid.locked    <= 1'b1;
    i_dp_vid.interlace <= v_vid_dp.axis.tuser.vid.interlace;
    i_dp_vid.field     <= 1'b1;
    i_dp_vid.overflow  <= v_vid_dp.axis.tuser.vid.error;
  end

  typedef v_vid_dp.item_t dp_vid_t;
  typedef v_dma.item_t dma_pattern_t;

  vid_conf_t vid_conf;
  logic overflow;

  dp_to_dma_adapter dut (
    .clk           ( clk                  ),
    .rst           ( rst                  ),
    .vid_format    ( vid_conf.vid_format  ),
    .overflow      ( overflow             ),
    .i_dp_vid      ( i_dp_vid             ),
    .i_dp_dma      ( axis_v_dma           )
  );

  class dp_vid_pattern extends dp_vid_t;
    function void post_randomize();
      foreach(tuser[i]) begin
        tuser[i] = '0;
        tuser[i].vid.data_valid = 1'b1;
      end

      tuser[0].vid.sof = 1;
      tuser[0].vid.sol = 1;
      tuser[tuser.size()-1].vid.eol = 1;
      tuser[tuser.size()-1].vid.eof = 1;
    endfunction : post_randomize
  endclass : dp_vid_pattern

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

  endclass : format_conv_t

  class dma_ap implements gvip_axis_pkg::analysis_port_ic#(dma_pattern_t);
    protected dma_pattern_t pattern_queue[$];
    protected dma_pattern_t results_queue[$];
    protected format_conv_t format_conv;
    protected int id = 0;

    function void init(vid_dma_format_e format);
      format_conv = new(format);
    endfunction : init

    function void add_pattern(dp_vid_t pat);
      dma_pattern_t new_pat;
      vid_input_format_u data_pat[];
      logic [DmaDataWidth/2-1:0] beat_stream[$];
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

  task monitor_overflow();
    @(posedge clk);
    `FAIL_IF_LOG(overflow, $sformatf("%t: Error in monitor, FIFO to small\n", $time));
  endtask : monitor_overflow

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    v_vid_dp.init();
    v_dma.init();

    vid_conf = new();

    dma = new();

    v_dma.core.add_ap2pkt(dma);

    v_vid_dp.core.run_phase();
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

  localparam int ITER = `ifdef CI_FAST 50 `else 1000 `endif;

  `SVUNIT_TESTS_BEGIN

    repeat(5) begin
    `SVTEST(random_valid)
      dp_vid_pattern vid_data;

      v_vid_dp.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
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
      repeat(ITER) begin
        vid_data = new();
        `FAIL_IF(!vid_data.randomize() with {tdata.size()*PixelDataWidth/8 % 48 == 0;
                                             tdata.size()*PixelDataWidth/8 < 2000;
                                             tdata.size()*PixelDataWidth/8 > 192;});
        dma.add_pattern(vid_data);
        v_vid_dp.core.send_item(vid_data);
      end

      wait(dma.is_pattern_queue_empty());

    `SVTEST_END
    end

    repeat(5) begin
    `SVTEST(random_ready)
      dp_vid_pattern vid_data;
      gvip_policy_pkg::random_std rr_schema = gvip_policy_pkg::random_std::create();

      `FAIL_IF(!rr_schema.randomize() with {
        foreach(not_active_interval[i]) not_active_interval[i] < 10;
      })

      v_vid_dp.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
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
      repeat(ITER) begin
        vid_data = new();
        `FAIL_IF(!vid_data.randomize() with {tdata.size()*PixelDataWidth/8 % 48 == 0;
                                             tdata.size()*PixelDataWidth/8 < 2000;
                                             tdata.size()*PixelDataWidth/8 > 192;});
        dma.add_pattern(vid_data);
        v_vid_dp.core.send_item(vid_data);
      end

      wait(dma.is_pattern_queue_empty());

    `SVTEST_END
    end

  `SVUNIT_TESTS_END

endmodule : dp_to_dma_adapter_unit_test
