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
  parameter int NUM = 4;

  parameter int iterations = NUM*100;
  parameter int N = 8;
  parameter int I = 4;
  parameter int D = $clog2(NUM);
  parameter type U_T = logic[31:0];

  import greporter_pkg::greporter;

  logic clk;
  logic rst;
  // vips declaration
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_in", gvip_axis_pkg::MASTER) gaxis_vip_in(clk, rst);

`ifdef XILINX_SIMULATOR
  typedef gvip_axis_item_pkg::item #(N, I, D, U_T) item_t;
  gvip_axis_array_if #(NUM, N, I, D, U_T, "gaxis_vip_out", gvip_axis_pkg::SLAVE, item_t) gaxis_vip_out(clk, rst);
`else
  gvip_axis_array_if #(NUM, N, I, D, U_T, "gaxis_vip_out", gvip_axis_pkg::SLAVE) gaxis_vip_out(clk, rst);
  typedef gaxis_vip_in.item_t item_t;
`endif

  // get item type from vip's interface
  item_t item_obj;

  dut #(
    .NUM       ( NUM                )
  ) dut (
    .clk       ( clk                ),
    .rst       ( rst                ),
    .i_axis_in ( gaxis_vip_in.axis  ),
    .i_axis_out( gaxis_vip_out.axis )
  );

  `ASSERT_AXIS_INF(clk, rst, gaxis_vip_in.axis, in)
  generate
    for (genvar i=0; i<NUM; i++) begin : OUT_ASSERTIONS
      `ASSERT_AXIS_INF(clk, rst, gaxis_vip_out.axis[i], out);
    end
  endgenerate

  // class which is analyzing incomming packets from all i_axis_out interfaces
  class ap_impl implements gvip_axis_pkg::analysis_port_ic #(item_t);
    item_t pat_queue[NUM][$];

    virtual function void write (input item_t item);
      item_t pat;
      int item_dest = item.tdest;

      if (pat_queue[item_dest].size() == 0) begin
        greporter::error("TEST", "Pattern queue is empty");
      end

      pat = pat_queue[item_dest].pop_front();

      if (!item.compare(pat)) begin
        greporter::error("TEST", $sformatf("%t Packet mismatch\n%s\n%s", $time,
          gvip_axis_item_pkg::printer #()::add_prefix(pat.convert2string(), "pattern"),
          gvip_axis_item_pkg::printer #()::add_prefix(item.convert2string(), "result")));
      end
    endfunction : write

    function void add_pat(item_t arg, int dest);
      pat_queue[dest].push_back(arg);
    endfunction : add_pat

    function bit is_empty();
      foreach(pat_queue[i]) begin
        if (pat_queue[i].size() != 0)
          return 0;
        end
      return 1;
    endfunction : is_empty

    function void clear();
      foreach(pat_queue[i]) begin
        pat_queue[i].delete();
      end
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

  initial begin
    rst <= 1;
    repeat(4) @(posedge clk);
    rst <= 0;
  end

  int file;
  int dest;
  string result_file_name;
  gvip_axis_pkg::gvip_config vip_out_cfg = new();
  initial begin
    gaxis_vip_in.init();
    gaxis_vip_in.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
    gaxis_vip_in.core.run_phase();

    vip_out_cfg.coverage = 1;
    // gaxis_vip_out vip handles interface's array
    // there could be used init to initialize core for all vips
    // or init_single to initialize specyfic core
    gaxis_vip_out.init(vip_out_cfg);
    ap = new();
    for (int i=0; i<NUM; i++) begin : OUT_INIT
      // each core in gaxis_vip_out needs its analysys port, run_phase call and policy
      gaxis_vip_out.core[i].add_ap2pkt(ap);
      gaxis_vip_out.core[i].run_phase();
      gaxis_vip_out.core[i].set_policy(gvip_policy_pkg::random_std::create(), 1);
    end

    repeat (iterations) begin
      item_obj = new();
      if (!(item_obj.randomize() with {tdata.size() < 5; tdest < NUM;})) begin
        greporter::error("TEST", "Can't randomize item");
      end
      dest = item_obj.tdest;
      ap.add_pat(item_obj, dest);
      // send packet
      gaxis_vip_in.core.send_item(item_obj);
    end

    while (!ap.is_empty) @(posedge clk);

    if (!$value$plusargs("RESULT_PREFIX=%s",result_file_name)) begin
      result_file_name="test_result";
    end

    if (greporter::get_counter_error() || greporter::get_counter_fatal()) begin
      file = $fopen($sformatf("%s-ko",result_file_name),"a+");
    end
    else begin
      file = $fopen($sformatf("%s-ok",result_file_name),"a+");
    end
    $fwrite(file, "Test ended");
    $fclose(file);
    $finish;
  end

endmodule : test
