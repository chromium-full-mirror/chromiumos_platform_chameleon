/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for axis_serializer module.
//
// Generate patterns on every input (thanks to axis_in VIP interface array),
// pass patterns to ap_impl (via put) in expected order, based on tlast bit
// and verify full bus (data, keep, last, user) in write() method.
//
// Fail in case of any mismatch.

module axis_serializer_unit_test;

  //parameters
  parameter string name = "axis_serializer_unit_test";
  parameter int InputNum = 2;
  localparam int InputNumWidth = $clog2(InputNum);

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  svunit_testcase svunit_ut;

  //Clocking
  logic clk = 1'b0;
  logic rst;

  default clocking clk_default @(posedge clk); endclocking
  `SVUNIT_CLK_GEN(clk, 2)

  localparam int N = 64;
  localparam int I = 0;
  localparam int D = 0;
  localparam type U_T = logic [15:0];

  //Inputs and outputs
  gvip_axis_array_if #(InputNum, N, I, D, U_T, "in", gvip_axis_pkg::MASTER) in(clk, rst);
  gvip_axis_if #(N, I, D, U_T, "out", gvip_axis_pkg::SLAVE) out(clk, rst);

  `GAXIS_VIP_ARRAY_TO_AXIS_ARRAY(in, U_T, InputNum)
  `AXIS_TO_GAXIS_VIP(out, U_T)

  // This is the DUT that we're running the Unit Tests on
  axis_serializer #(
    .InputNum   ( InputNum  )
  )
  dut (
    .clk        ( clk       ),
    .rst        ( rst       ),
    .i_axis_in  ( axis_in   ),
    .i_axis_out ( axis_out  )
  );

  typedef out.item_t item_t;

  //write function implementation <- runs when tlast is asserted on processed data
  class ap_impl implements gvip_axis_pkg::analysis_port_ic#(item_t);
    item_t items_map[int unsigned][$];
    item_t results[$];

    function void put(item_t pat, int unsigned source_id);
      items_map[source_id].push_back(pat.clone);
    endfunction

    virtual function bit is_empty();
      foreach(items_map[i]) begin
        if (items_map[i].size() != 0) begin
          return 0;
        end
      end
      return 1;
    endfunction

    virtual function void write(input item_t item);
      results.push_back(item);
    endfunction : write

    task analyzer();
      forever begin
        item_t pat;
        item_t res;
        int unsigned source_id;

        wait(results.size());
        res = results.pop_front();

        pat = new();
        for (int pat_id=0; pat_id < InputNum; pat_id++) begin
          `FAIL_IF_LOG(is_empty(), "more packets received than sent")
          pat.tdata = {pat.tdata, items_map[pat_id][0].tdata};
          pat.tkeep = {pat.tkeep, items_map[pat_id][0].tkeep};
          pat.tuser = {pat.tuser, items_map[pat_id][0].tuser};
          void'(items_map[pat_id].pop_front());
        end

        `FAIL_IF_LOG(pat.tdata.size() != (res.tdata.size()), $sformatf("Source tlast mismatch: sent: %0d got: %0d",
            pat.tdata.size(), res.tdata.size()))
        foreach(res.tdata[i]) begin
          `FAIL_IF_LOG(pat.tdata[i] != (res.tdata[i]), $sformatf("Source tdata mismatch: sent: %h got: %h",
              pat.tdata[i], res.tdata[i]))
          `FAIL_IF_LOG(pat.tkeep[i] != (res.tkeep[i]), $sformatf("Source tkeep mismatch: sent: %h got: %h",
              pat.tkeep[i], res.tkeep[i]))
          `FAIL_IF_LOG(pat.tuser[i] != (res.tuser[i]), $sformatf("Source tuser mismatch: sent: %h got: %h",
              pat.tuser[i], res.tuser[i]))
        end
      end
    endtask : analyzer

    function void clear();
      foreach(items_map[i]) begin
        items_map[i].delete();
      end
    endfunction : clear

  endclass : ap_impl

  ap_impl axis_out_ap;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    in.init();
    foreach (in.core[i]) begin
      in.core[i].run_phase();
    end

    axis_out_ap = new();
    out.init();
    out.core.add_ap2pkt(axis_out_ap);
    out.core.run_phase();
  endfunction

  task setup();
    svunit_ut.setup();
    rst <= 1'b1;
    repeat(3) @(posedge clk);
    axis_out_ap.clear();
    repeat(10) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask

  task teardown();
    axis_out_ap.clear();
  endtask

  localparam int ITER = `ifdef CI_FAST 10 `else 100 `endif;
  task automatic send_data (int id);
    item_t data;
    repeat(ITER) begin
      data = new();
      `FAIL_IF(!data.randomize() with {tdata.size()*N < 512;})

      axis_out_ap.put(data, id);
      in.core[id].send_item(data);
    end
  endtask : send_data

  `SVUNIT_TESTS_BEGIN

    // Foreach input interface from VIP (in):
    //  - randomize pattern
    //  - submit it for input of DUT (via gvip_axis)
    //  - submit it as pattern to axis_out_ap (axis_serializer sets tlast
    //    which triggers write() task on last beat from the last input id)
    //
    // Do it ITER times.
    // Fail if there's any pattern mismatch.
    //
    // Apply always_ready policy to receive all data on output without pauses.
    `SVTEST(channels_always_ready)
      out.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      foreach(in.core[i]) begin
        automatic int k = i;
        fork
          send_data(k);
        join_none
      end
      wait fork;
      @(posedge clk);

      fork
        begin
          while (!axis_out_ap.is_empty()) @(posedge clk);
        end
        axis_out_ap.analyzer();
      join_any
    `SVTEST_END

    // Foreach input interface from VIP (in):
    //  - randomize pattern
    //  - submit it for input of DUT (via gvip_axis)
    //  - submit it as pattern to axis_out_ap (axis_serializer sets tlast
    //    which triggers write() task on last beat from the last input id)
    //
    // Do it ITER times.
    // Fail if there's any pattern mismatch.
    //
    // Apply random_ready policy to allow receiving side pause given transaction.
    `SVTEST(channels_random_ready)
      out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      foreach(in.core[i]) begin
        automatic int k = i;
        fork
          send_data(k);
        join_none
      end
      wait fork;
      @(posedge clk);

      fork
        begin
          while (!axis_out_ap.is_empty()) @(posedge clk);
        end
        axis_out_ap.analyzer();
      join_any
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : axis_serializer_unit_test
