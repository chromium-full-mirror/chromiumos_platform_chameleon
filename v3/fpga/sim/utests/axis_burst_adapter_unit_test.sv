/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module axis_burst_adapter_unit_test;

  //Unit test name
  parameter string name = "axis_burst_adapter_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  svunit_testcase svunit_ut;

  //Parameters
  //Clocking
  logic clk = 1'b0;
  logic rst;
  `SVUNIT_CLK_GEN(clk, 3)

  localparam int DataWidth = 128;
  localparam int BurstLenWidth = 8;

  localparam int N = DataWidth/8;
  localparam int I = 0;
  localparam int D = 0;

  //Inputs and outputs
  gvip_axis_if #(N, I, D, framebuffer_pkg::fb_dma_meta_t,
                 "single", gvip_axis_pkg::MASTER) single(clk, rst);
  gvip_axis_if #(N, I, D, axis_to_aximm_pkg::meta_t,
                 "burst", gvip_axis_pkg::SLAVE)   burst(clk, rst);

  axis_i     #(.Tuser(framebuffer_pkg::fb_dma_meta_t), .DataWidth(DataWidth),
               .WordWidth(8)) always_last();

  `GAXIS_VIP_TO_AXIS(single, framebuffer_pkg::fb_dma_meta_t)
  `AXIS_TO_GAXIS_VIP(burst, axis_to_aximm_pkg::meta_t)

  logic [BurstLenWidth-1:0] burst_size;

  typedef single.item_t s_item_t;
  typedef burst.item_t b_item_t;

  class single_item extends s_item_t;
    localparam int AddrWidth = axis_to_aximm_pkg::AddrWidth;
    constraint c_addr {
      foreach (tkeep[i]) {
        tkeep[i] == '1;
      }

      foreach (tuser[i]) {
        // Because of some internal error in QuestaSim we need to index address field with
        // bit range select instead of field select (.addr)
        // ** Fatal: (vsim-7177) Internal Error - Invalid variable address.
        if (i > 0) {
          tuser[i][AddrWidth-1:0] == tuser[i-1][AddrWidth-1:0] + N;
        }
        tuser[i][33:32] == 0;
      }
    }
    function void post_randomize();
      super.post_randomize();
      // address four pixels 4 bytes each
      // this is faster then random solver
      foreach(tuser[i]) tuser[i][3:0] = '0;
    endfunction
  endclass : single_item


  class ap implements gvip_axis_pkg::analysis_port_ic#(b_item_t);
    localparam int Boundary4k = 4096;
    localparam int BytesInBeat = 16;
    protected s_item_t patterns[$];
    protected b_item_t results[$];
    int burst_size;

    // In tests we use axis_vip item which generates burst transaction on bus (burst is converted
    // to single beats transaction with below burst_to_single always_comb)
    // With this function we split test item to number of smaller bursts with size of desired
    // burst_size or smaller if we hit 4K boundary
    function void put_pattern(s_item_t pattern);
      // extract patterns fields to SV queue, we queue we can operate on data ranges
      framebuffer_pkg::fb_dma_meta_t             user[$] = pattern.tuser;
      logic [DataWidth-1:0]                      data[$] = pattern.tdata;
      logic [DataWidth/8-1:0]                    keep[$] = pattern.tkeep;

      // size of each queue is the same (nature of axis_vip item) so we can use one of them
      while (user.size()) begin
        int beats_to_squash = burst_size; // we want to squash desired numbers of beats unless...
        int last_idx = (burst_size < user.size()-1) ? burst_size : user.size()-1;
        s_item_t sub_item = new();

        // ...unless we crossing 4K boundary with address (if first address is one 4K space and
        // the second in another)
        if ((user[0].addr / Boundary4k) != (user[last_idx].addr / Boundary4k)) begin
          int boundary_4k_which_we_hit = $ceil(real'(user[0].addr) / Boundary4k) * Boundary4k;
          int available_bytes_to_4k = boundary_4k_which_we_hit - user[0].addr;
          beats_to_squash = available_bytes_to_4k / BytesInBeat;
        end

        // ranges cut
        sub_item.tdata = data[0:beats_to_squash-1];
        sub_item.tuser = user[0:beats_to_squash-1];
        sub_item.tkeep = keep[0:beats_to_squash-1];
        data = data[beats_to_squash:$];
        user = user[beats_to_squash:$];
        keep = keep[beats_to_squash:$];

        patterns.push_back(sub_item);
      end
    endfunction : put_pattern

    function bit is_empty();
      // there is always one beat of data in apdapter (at axis_reg_slice)
      return (patterns.size() == 1);
    endfunction : is_empty

    function void clear();
      results.delete();
      patterns.delete();
    endfunction : clear

    // analysis callback with received axis transaction
    virtual function void write (input b_item_t item);
      results.push_back(item);
    endfunction : write

    task analyzer();
      forever begin
        b_item_t incoming;
        s_item_t patt;

        wait(results.size());
        incoming = results.pop_front();

        `FAIL_IF(patterns.size() == 0)

        `ifdef DBG  $display(incoming.convert2string()); `endif
        patt = patterns.pop_front();

        // fail if incoming transaction is bigger then desired
        `FAIL_IF(incoming.tuser.size() > burst_size)
        // fail if number of beats in incoming transaction is unexpected
        `FAIL_IF_LOG(incoming.tuser.size() != patt.tuser.size(),
                     $sformatf("%0d != %0d %p", incoming.tuser.size(),
                                                patt.tuser.size(), patt.tuser))
        // fail if field with size of incoming transaction is wrong
        `FAIL_IF_LOG(incoming.tuser[0].data_size != patt.tdata.size()*DataWidth/8,
                     $sformatf("%0d != %0d", incoming.tuser[0].data_size,
                                             patt.tdata.size()*DataWidth/8))
        // compare each beats field with pattern
        foreach (incoming.tdata[i]) begin
          `FAIL_IF_LOG(incoming.tdata[i] != patt.tdata[i],
            $sformatf("incoming[%0d]: %0h != patt[%0d]: %0h", i, incoming.tdata[i], i, patt.tdata[i]));
          `FAIL_IF(incoming.tuser[i].addr != patt.tuser[i].addr);
          `FAIL_IF(incoming.tkeep[i] != patt.tkeep[i]);
        end
      end
    endtask : analyzer

  endclass : ap


  // This process just override tlast signal in interface
  // in this way we create numberous single beat transaction form single burst item
  always_comb begin : burst_to_single
    axis_single.tready = always_last.tready;
    always_last.tvalid = axis_single.tvalid;
    always_last.tdata  = axis_single.tdata;
    always_last.tkeep  = axis_single.tkeep;
    always_last.tuser  = axis_single.tuser;
    always_last.tlast  = '1;
  end

  axis_burst_adapter #(
      .BurstLenWidth ( BurstLenWidth )
  ) u_dut (
      .clk            ( clk         ),
      .reset          ( rst         ),
      .max_burst_size ( burst_size  ),
      .overflow       (             ),
      .i_axis_in      ( always_last ),
      .i_axis_out     ( axis_burst  )
  );

  ap ap_inst;

  function static void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    single.init();
    single.core.run_phase();

    ap_inst = new();

    burst.init();
    burst.core.add_ap2pkt(ap_inst);
    burst.core.run_phase();
  endfunction

  task static setup();
    svunit_ut.setup();
    rst <= 1'b1;
    repeat(10) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask

  task static teardown();
    ap_inst.clear();
  endtask

  `SVUNIT_TESTS_BEGIN

    `SVTEST(random_valid_ready)
      single_item item;
      burst_size = 16;
      ap_inst.burst_size = burst_size;

      single.core.set_policy(gvip_policy_pkg::random::create(), 1);
      burst.core.set_policy(gvip_policy_pkg::random::create(), 1);

      repeat (10) begin
        item = new();
        `FAIL_IF(!item.randomize())
        ap_inst.put_pattern(item);
        single.core.send_item(item);
      end
      @(posedge clk);

      fork
        begin
          while (!ap_inst.is_empty()) @(posedge clk);
        end
        ap_inst.analyzer();
      join_any

      repeat (10) @(posedge clk);
    `SVTEST_END

    `SVTEST(always_valid_ready)
      single_item item;
      burst_size = 16;
      ap_inst.burst_size = burst_size;

      single.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      burst.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      repeat (10) begin
        item = new();
        `FAIL_IF(!item.randomize())
        ap_inst.put_pattern(item);
        single.core.send_item(item);
      end
      @(posedge clk);

      fork
        begin
          while (!ap_inst.is_empty()) @(posedge clk);
        end
        ap_inst.analyzer();
      join_any

      repeat (10) @(posedge clk);
    `SVTEST_END

    `SVTEST(slow_ready)
      gvip_policy_pkg::random rr_schema = gvip_policy_pkg::random::create();
      single_item item;
      burst_size = 16;
      ap_inst.burst_size = burst_size;

      `FAIL_IF(!rr_schema.randomize() with {
        foreach(active_interval[i])     active_interval[i] < 8;
        foreach(not_active_interval[i]) not_active_interval[i] > 20;
      })
      burst.core.set_policy(rr_schema);

      repeat (10) begin
        item = new();
        `FAIL_IF(!item.randomize())
        ap_inst.put_pattern(item);
        single.core.send_item(item);
      end
      @(posedge clk);

      fork
        begin
          while (!ap_inst.is_empty()) @(posedge clk);
        end
        ap_inst.analyzer();
      join_any

      repeat (10) @(posedge clk);
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : axis_burst_adapter_unit_test
