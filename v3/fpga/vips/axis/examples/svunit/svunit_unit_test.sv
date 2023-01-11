/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

///////////////////////////////////
// gaxis vip example with SVUnit //
///////////////////////////////////

`include "svunit_defines.svh"

module svunit_unit_test;
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  string name = "svunit_ut";
  svunit_testcase svunit_ut;

  parameter int iterations = 10;
  parameter int N = 8;
  parameter int I = 4;
  parameter int D = 3;
  parameter type U_T = logic[31:0];

  logic clk;
  logic rst;

  // vips declaration
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_in", gvip_axis_pkg::MASTER) gaxis_vip_in(clk, rst);
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_out", gvip_axis_pkg::SLAVE) gaxis_vip_out(clk, rst);

  // get item type from vip's interface
  typedef gaxis_vip_in.item_t item_t;
  item_t item;

  dut dut(
    .clk       ( clk                ),
    .rst       ( rst                ),
    .i_axis_in ( gaxis_vip_in.axis  ),
    .i_axis_out( gaxis_vip_out.axis )
  );

  // class which is analyzing incomming packets from i_axis_out
  class ap_impl implements gvip_axis_pkg::analysis_port_ic #(item_t);
    item_t pat_queue[$];
    item_t res_queue[$];

    virtual function void write (input item_t item);
      res_queue.push_back(item);
    endfunction : write

    task analyzer;
      item_t pat;
      item_t res;

      forever begin
        wait (res_queue.size());
        res = res_queue.pop_front();

        `FAIL_IF(pat_queue.size() == 0)
        if (pat_queue.size() == 0) return;

        pat = pat_queue.pop_front();

        `FAIL_IF_LOG(!res.compare(pat), $sformatf("%t Packet missmatch\n%s\n%s", $time,
            gvip_axis_item_pkg::printer #()::add_prefix(pat.convert2string(), "pattern"),
            gvip_axis_item_pkg::printer #()::add_prefix(res.convert2string(), "result")))
      end

    endtask : analyzer

    function void add_pat(item_t arg);
      pat_queue.push_back(arg);
    endfunction : add_pat

    function bit is_empty();
      return (pat_queue.size() == 0);
    endfunction : is_empty

    function void clear();
      pat_queue.delete();
      res_queue.delete();
    endfunction : clear

  endclass : ap_impl

  ap_impl ap;

  initial begin
    clk = 0;
    forever begin
      #2;
      clk <= !clk;
    end
  end

  function void build();
    svunit_ut = new(name);
    gaxis_vip_in.init();
    gaxis_vip_out.init();
    ap = new();

    gaxis_vip_out.core.add_ap2pkt(ap);
  endfunction : build

  task setup();
    svunit_ut.setup();
    rst <= 1;
    gaxis_vip_in.core.run_phase();
    gaxis_vip_out.core.run_phase();
    repeat(4) @(posedge clk);
    rst <= 0;
  endtask : setup

  int file;
  string result_file_name;
  task teardown();
    if (!$value$plusargs("RESULT_PREFIX=%s",result_file_name)) begin
      result_file_name="test_result";
    end

    if (svunit_ut.get_error_count()) begin
      file = $fopen($sformatf("%s-ko",result_file_name),"a+");
    end
    else begin
      file = $fopen($sformatf("%s-ok",result_file_name),"a+");
    end
    $fwrite(file, "Test ended");
    $fclose(file);

    svunit_ut.teardown();
  endtask : teardown

  `SVUNIT_TESTS_BEGIN

    `SVTEST(main)
      repeat (iterations) begin
        item = new();
        `FAIL_IF(!(item.randomize() with {tdata.size() < 5; tlast == 1;}))
        ap.add_pat(item);
        // send packet
        gaxis_vip_in.core.send_item(item);
      end
      fork
        begin
          while (!ap.is_empty) @(posedge clk);
        end
        ap.analyzer();
      join_any
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : svunit_unit_test
