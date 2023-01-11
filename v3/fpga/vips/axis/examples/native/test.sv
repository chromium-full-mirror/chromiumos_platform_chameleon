/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

///////////////////////
// gaxis vip example //
///////////////////////

`include "assert.svh"

module test;
  // ACK_TIME is set in Makefiles to run different versions of the test
  parameter int ACK_TIME = 1;

  parameter int iterations = 100;
  parameter int N = 8;
  parameter int I = 4;
  parameter int D = 3;
  parameter type U_T = logic[31:0];


  logic clk;
  logic rst;
  // vips declaration
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_in", gvip_axis_pkg::MASTER) gaxis_vip_in(clk, rst);

`ifdef XILINX_SIMULATOR
  typedef gvip_axis_item_pkg::item #(N, I, D, U_T) item_t;
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_out", gvip_axis_pkg::SLAVE, item_t) gaxis_vip_out(clk, rst);
`else
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_out", gvip_axis_pkg::SLAVE) gaxis_vip_out(clk, rst);
  typedef gaxis_vip_out.item_t item_t;
`endif

  // get item type from vip's interface
  item_t item_obj;
  bit test_passed;

  dut #(
    .ACK_TIME  ( ACK_TIME           )
  )
  dut(
    .clk       ( clk                ),
    .rst       ( rst                ),
    .i_axis_in ( gaxis_vip_in.axis  ),
    .i_axis_out( gaxis_vip_out.axis )
  );

  `ASSERT_AXIS_INF(clk, rst, gaxis_vip_in.axis, in)
  `ASSERT_AXIS_INF(clk, rst, gaxis_vip_out.axis, out);

  // class which is analyzing incomming packets from i_axis_out
  class ap_impl implements gvip_axis_pkg::analysis_port_ic #(item_t);
    item_t pat_queue[$];

    virtual function void write (input item_t item);
      item_t pat;

      if (pat_queue.size() == 0) begin
        test_passed = 1'b0;
        $error ("pattern queue is empty");
      end

      pat = pat_queue.pop_front();

      if (!item.compare(pat)) begin
        test_passed = 1'b0;
        $error("%t Packet missmatch\n%s\n%s", $time,
          gvip_axis_item_pkg::printer #()::add_prefix(pat.convert2string(), "pattern"),
          gvip_axis_item_pkg::printer #()::add_prefix(item.convert2string(), "result"));
      end
    endfunction : write

    function void add_pat(item_t arg);
      pat_queue.push_back(arg);
    endfunction : add_pat

    function bit is_empty();
      return (pat_queue.size() == 0);
    endfunction : is_empty

    function void clear();
      pat_queue.delete();
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

  class my_policy extends gvip_axis_pkg::active_to_last;
    function new(string name = "inst_of_my_policy", string type_name = $typename(this));
      super.new(name, type_name);
    endfunction
    static function my_policy create();
      create = new();
    endfunction
  endclass : my_policy

  initial begin
    rst <= 1;
    test_passed = 1'b1;
    repeat(4) @(posedge clk);
    rst <= 0;
  end
  int file;
  string result_file_name;
  gvip_axis_pkg::gvip_config vip_out_cfg = new();
  initial begin
    vip_out_cfg.coverage = 1;

    gaxis_vip_in.init();
    gaxis_vip_out.init(vip_out_cfg);

    // It could be used to disable info about policy which is set
    // greporter_pkg::greporter::set_verbosity("AXIS-VIP[gaxis_vip_in]", greporter_pkg::LOW);
    // greporter_pkg::greporter::set_verbosity(gaxis_vip_out.core.get_config.report_id, greporter_pkg::LOW);

    ap = new();

    gaxis_vip_out.core.add_ap2pkt(ap);

    gaxis_vip_in.core.run_phase();
    gaxis_vip_out.core.run_phase();

    // just to show possiblities
    gaxis_vip_out.core.set_policy(gvip_axis_pkg::active_to_last::create("to_last"), 1);
    gaxis_vip_out.core.set_policy(my_policy::create(), 1);

    gaxis_vip_in.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
    gaxis_vip_out.core.set_policy(gvip_policy_pkg::random::create(), 1);
    fork
      forever begin
        int delay;
        if (!(std::randomize(delay) with {delay < 100; delay > 50;})) begin
          test_passed = 1'b0;
          $error("Can't randomize delay");
        end
        repeat(delay) @(posedge clk);
        gaxis_vip_in.core.set_policy(gvip_policy_pkg::policy_after_partner_active::create(), 1);
        if (!(std::randomize(delay) with {delay < 300; delay > 200;})) begin
          test_passed = 1'b0;
          $error("Can't randomize delay");
        end
        repeat(delay) @(posedge clk);
        gaxis_vip_in.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      end
    join_none

    repeat (iterations) begin
      item_obj = new();
      if (!(item_obj.randomize() with {tdata.size() < 5; tlast == 1;})) begin
        test_passed = 1'b0;
        $error("Can't randomize item");
      end
      ap.add_pat(item_obj);
      // send packet
      gaxis_vip_in.core.send_item(item_obj);
    end

    while (!ap.is_empty) @(posedge clk);

    if (!$value$plusargs("RESULT_PREFIX=%s",result_file_name)) begin
      result_file_name="test_result";
    end

    if (test_passed) begin
      file = $fopen($sformatf("%s-ok",result_file_name),"a+");
    end
    else begin
      file = $fopen($sformatf("%s-ko",result_file_name),"a+");
    end
    $fwrite(file, "Test ended");
    $fclose(file);
    $finish;
  end

endmodule : test
