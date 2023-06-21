/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module vid_to_dma_data_width_conv_unit_test;

  //Unit test name
  parameter string name = "vid_to_dma_data_width_conv_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  import vid_rx_pkg::*;

  svunit_testcase svunit_ut;

  //Parameters
  //Clocking
  logic clk = 1'b0;
  logic rst;
  `SVUNIT_CLK_GEN(clk, 4)

  //Inputs and outputs
  gvip_axis_if #(PixelDataWidth/8, 0, 0, vid_meta_t,
                 "input", gvip_axis_pkg::MASTER) v_in(clk, rst);
  gvip_axis_if #(DmaDataWidth/8, 0, 0, vid_meta_t,
                 "output", gvip_axis_pkg::SLAVE) v_out(clk, rst);

  `GAXIS_VIP_TO_AXIS(v_in, vid_meta_t)
  `AXIS_TO_GAXIS_VIP(v_out, vid_meta_t)

  typedef v_in.item_t in_item_t;
  typedef v_out.item_t out_item_t;

  vid_to_dma_data_width_conv dut (
      .clk        ( clk        ),
      .rst        ( rst        ),
      .i_axis_in  ( axis_v_in  ),
      .i_axis_out ( axis_v_out )
  );

  class ap implements gvip_axis_pkg::analysis_port_ic#(out_item_t);
    out_item_t results[$];
    out_item_t patterns[$];

    function void add_pattern(in_item_t input_item);
      out_item_t pat;
      logic [PixelDataWidth-1:0] data_pat[];

      pat = new();
      data_pat = new[input_item.tdata.size()](input_item.tdata);

      pat.tdata = new[input_item.tdata.size()*PixelDataWidth/DmaDataWidth];
      pat.tdata = {<<DmaDataWidth{{<<PixelDataWidth{{>>{data_pat}}}}}};

      pat.tkeep = new[input_item.tkeep.size()*PixelDataWidth/DmaDataWidth];
      foreach (pat.tkeep[i]) begin
        pat.tkeep[i] = '1;
      end

      patterns.push_back(pat);
    endfunction : add_pattern

    virtual function void write (input out_item_t item);
      results.push_back(item);
    endfunction : write

    function void clear();
      results.delete();
      patterns.delete();
    endfunction : clear

    function bit is_empty();
      return (results.size() == 0 && patterns.size() == 0);
    endfunction : is_empty

    task analyzer();
      forever begin
        out_item_t res;
        out_item_t pat;

        wait(results.size());

        res = results.pop_front();
        pat = patterns.pop_front();

        `FAIL_IF_LOG(pat.tdata.size() != res.tdata.size(),
                     $sformatf("%0d != %0d", pat.tdata.size(), res.tdata.size()));

        foreach (pat.tdata[i]) begin
          `FAIL_IF_LOG(pat.tdata[i] != res.tdata[i],
            $sformatf("pat[%0d]: %0h != res[%0d]: %0h", i, pat.tdata[i], i, res.tdata[i]));
          `FAIL_IF_LOG(pat.tkeep[i] != res.tkeep[i],
            $sformatf("pat[%0d]: %0h != res[%0d]: %0h", i, pat.tkeep[i], i, res.tkeep[i]));
        end

      end
    endtask : analyzer

  endclass : ap

  ap ap_inst;

  function static void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    v_in.init();
    v_in.core.run_phase();

    ap_inst = new();

    v_out.init();
    v_out.core.add_ap2pkt(ap_inst);
    v_out.core.run_phase();
  endfunction : build

  task static setup();
    svunit_ut.setup();
    rst <= 1'b1;
    repeat(10) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask : setup

  task static teardown();
    ap_inst.clear();
  endtask

  `SVUNIT_TESTS_BEGIN

    `SVTEST(always_valid_ready)
      in_item_t item;

      v_in.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      v_out.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      repeat (10) begin
        item = new();
        `FAIL_IF(!item.randomize() with {tdata.size()*PixelDataWidth/8 % 48 == 0;
                                         tdata.size()*PixelDataWidth/8 > 192;
                                         foreach (tkeep[i]) tkeep[i] == '1;});
        ap_inst.add_pattern(item);
        v_in.core.send_item(item);
      end
      @(posedge clk);

      fork
        begin
          while (!ap_inst.is_empty()) @(posedge clk);
        end
        ap_inst.analyzer();
      join_any
    `SVTEST_END

    `SVTEST(random_ready)
      in_item_t item;

      v_in.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      v_out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);

      repeat (10) begin
        item = new();
        `FAIL_IF(!item.randomize() with {tdata.size()*PixelDataWidth/8 % 48 == 0;
                                         tdata.size()*PixelDataWidth/8 > 192;
                                         foreach (tkeep[i]) tkeep[i] == '1;});
        ap_inst.add_pattern(item);
        v_in.core.send_item(item);
      end
      @(posedge clk);

      fork
        begin
          while (!ap_inst.is_empty()) @(posedge clk);
        end
        ap_inst.analyzer();
      join_any
    `SVTEST_END

    `SVTEST(random_valid_ready)
      in_item_t item;

      v_in.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      v_out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);

      repeat (10) begin
        item = new();
        `FAIL_IF(!item.randomize() with {tdata.size()*PixelDataWidth/8 % 48 == 0;
                                         tdata.size()*PixelDataWidth/8 > 192;
                                         foreach (tkeep[i]) tkeep[i] == '1;});
        ap_inst.add_pattern(item);
        v_in.core.send_item(item);
      end
      @(posedge clk);

      fork
        begin
          while (!ap_inst.is_empty()) @(posedge clk);
        end
        ap_inst.analyzer();
      join_any
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : vid_to_dma_data_width_conv_unit_test

