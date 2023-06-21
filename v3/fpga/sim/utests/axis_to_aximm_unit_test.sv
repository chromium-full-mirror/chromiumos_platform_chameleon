/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for axis_to_aximm module.
//
// Provide patterns on axis_vip (according to meta_t structure,
// with addr and data_size), verify proper translation on output
// axim_vip.
module axis_to_aximm_unit_test;

  //Unit test name
  parameter string name = "axis_to_aximm_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  svunit_testcase svunit_ut;

  //Packages and classes import from RTL directories
  import axis_to_aximm_pkg::Value4k;
  import axis_to_aximm_pkg::Boundary4kWidth;
  import axis_to_aximm_pkg::AddrWidth;
  import axis_to_aximm_pkg::meta_t;

  //Test parameters
  parameter int DataWidth = 128;
  parameter int Id = axis_to_aximm_pkg::kIdIt68051Dma;

  //Clocking
  logic clk = 1'b0;
  logic rst;

  localparam int ClkPeriod = 5; // 200MHz
  localparam int N = DataWidth/8;

  default clocking clk_default @(posedge clk); endclocking

  `SVUNIT_CLK_GEN(clk, ClkPeriod)

  //Inputs and outputs
  gvip_aximm_if #(.N(N), .A(AddrWidth), .NAME("mm_slv"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) mm_vip(clk, rst);
  gvip_axis_if #(N, 0, 0, meta_t,
                 "write", gvip_axis_pkg::MASTER) write(clk, rst);
  gvip_axis_if #(N, 0, 0, meta_t,
                 "read_rq", gvip_axis_pkg::MASTER) read_rq(clk, rst);
  gvip_axis_if #(N, 0, 0, meta_t,
                 "read_resp", gvip_axis_pkg::SLAVE) read_resp(clk, rst);

  `AXIMM_TO_GAXIMM_VIP(mm_vip)
  `GAXIS_VIP_TO_AXIS(write, meta_t)
  `GAXIS_VIP_TO_AXIS(read_rq, meta_t)
  `AXIS_TO_GAXIS_VIP(read_resp, meta_t)

  logic write_done;

  axis_to_aximm #(
      .Id           ( Id                  ),
      .DataWidth    ( DataWidth           )
  ) dut (
      .clk          ( clk                 ),
      .rst          ( rst                 ),
      .i_write      ( axis_write          ),
      .write_done   ( write_done          ),
      .i_read_rq    ( axis_read_rq        ),
      .i_read_resp  ( axis_read_resp      ),
      .i_mm         ( aximm_mm_vip        )
  );

  typedef mm_vip.item_t mm_item_t;
  typedef write.item_t write_item_t;
  typedef read_rq.item_t read_rq_item_t;
  typedef read_resp.item_t read_resp_item_t;

  class read_resp_ap implements gvip_axis_pkg::analysis_port_ic#(read_resp_item_t);
    protected read_resp_item_t pattern_queue[$];
    protected read_resp_item_t responses[$];

    function void add_pattern(read_resp_item_t pattern);
      pattern_queue.push_back(pattern.clone());
    endfunction : add_pattern

    function bit is_empty();
      return pattern_queue.size() == 0;
    endfunction : is_empty

    virtual function void write(input read_resp_item_t item);
      responses.push_back(item);
    endfunction : write

    task analyzer();
      read_resp_item_t pattern;
      read_resp_item_t response;

      forever begin
        wait(responses.size());
        response = responses.pop_front();

        `FAIL_IF(is_empty())
        pattern  = pattern_queue.pop_front();

        `FAIL_IF(response.tdata.size() != pattern.tdata.size())
        foreach(response.tdata[i]) begin
          `FAIL_IF_LOG(pattern.tdata[i] != response.tdata[i],
                       $sformatf("Data mismatch id=%0d:\n pattern=0x%0h\n dut=0x%0h",
                                 i, pattern.tdata[i], response.tdata[i]))
        end
      end
    endtask : analyzer

  endclass : read_resp_ap

  class mm_ap implements gvip_aximm_pkg::analysis_port_ic#(mm_item_t);
    protected write_item_t write_pattern_queue[$];
    protected read_rq_item_t read_rq_pattern_queue[$];
    protected read_resp_item_t read_resp_pattern_queue[$];
    protected mm_item_t responses[$];

    function void add_write_pattern(write_item_t pattern);
      write_pattern_queue.push_back(pattern);
    endfunction : add_write_pattern

    function bit is_write_queue_empty();
      return write_pattern_queue.size() == 0;
    endfunction : is_write_queue_empty

    function void add_read_rq_pattern(read_rq_item_t pattern);
      read_rq_pattern_queue.push_back(pattern.clone());
    endfunction : add_read_rq_pattern

    function bit is_read_rq_queue_empty();
      return read_rq_pattern_queue.size() == 0;
    endfunction : is_read_rq_queue_empty

    function void add_read_resp_pattern(read_resp_item_t pattern);
      read_resp_pattern_queue.push_back(pattern.clone());
    endfunction : add_read_resp_pattern

    function bit is_read_resp_queue_empty();
      return read_resp_pattern_queue.size() == 0;
    endfunction : is_read_resp_queue_empty

    function bit is_responses_queue_empty();
      return responses.size() == 0;
    endfunction : is_responses_queue_empty

    function bit is_empty();
      return (is_write_queue_empty() && is_read_rq_queue_empty() &&
              is_read_resp_queue_empty() && is_responses_queue_empty());
    endfunction : is_empty

    virtual function mm_item_t write (input mm_item_t item);
      read_resp_item_t pattern;
      responses.push_back(item.clone());
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AW_W) begin
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::B));
        item.bresp = gaximm_pkg::OKAY;
        item.bid   = item.awid;
        item.buser = item.awuser;
        return item;
      end
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AR) begin
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::R));
        pattern    = read_resp_pattern_queue.pop_front();
        item.rresp = gaximm_pkg::OKAY;
        item.rid   = item.arid;
        item.ruser = '{item.aruser};
        item.rdata = pattern.tdata;
        return item;
      end
      return null;
    endfunction : write

    task analyzer();
      mm_item_t      item;
      read_rq_item_t r_pattern;
      write_item_t   w_pattern;
      forever begin
        @(posedge clk);
        wait(responses.size());
        item = responses.pop_front();
        if (item.tr_type == gvip_aximm_types_pkg::gvip::AW_W) begin
          `FAIL_IF(is_write_queue_empty());
          w_pattern = write_pattern_queue.pop_front();

          `FAIL_IF(item.awburst  != gaxim_pkg::kIncr)
          `FAIL_IF(item.awprot   != '0)
          `FAIL_IF(item.awlock   != '0)
          `FAIL_IF(item.awcache  != '0)
          `FAIL_IF(item.awsize   != gaxim_pkg::kBytes16)
          `FAIL_IF_LOG(item.awaddr   != w_pattern.tuser[0].addr,
                       $sformatf("dut=%0h, pattern=%0h", item.awaddr,
                       w_pattern.tuser[0].addr))
          `FAIL_IF_LOG(item.awlen    != (w_pattern.tuser[0].data_size/(DataWidth/8) - 1 +
                                        ((w_pattern.tuser[0].data_size % (DataWidth/8)) != 0)),
                       $sformatf("dut=%0d, w_pattern=%0d, data_size=%0d", item.awlen,
                                 (w_pattern.tuser[0].data_size/(DataWidth/8) - 1 +
                                 ((w_pattern.tuser[0].data_size % (DataWidth/8)) != 0)),
                                 w_pattern.tuser[0].data_size))
          `FAIL_IF(item.awid     != Id)
          `FAIL_IF(item.awregion != '0)

          for (int i = 0; i < w_pattern.tdata.size(); i++) begin
            `FAIL_IF_LOG(item.wdata[i] != w_pattern.tdata[i],
                         $sformatf("Data mismatch id=%0d:\n w_pattern=0x%0h\n dut=    0x%0h",
                                   i, w_pattern.tdata[i], item.wdata[i]))
            `FAIL_IF_LOG(item.wstrb[i] != w_pattern.tkeep[i],
                         $sformatf("Strb mismatch id=%0d:\n w_pattern=0x%0h\n dut=0x%0h",
                                   i, w_pattern.tkeep[i], item.wstrb[i]))
          end
        end
        if (item.tr_type == gvip_aximm_types_pkg::gvip::AR) begin

          `FAIL_IF(is_read_rq_queue_empty())
          r_pattern = read_rq_pattern_queue.pop_front();

          `FAIL_IF(item.arburst  != gaxim_pkg::kIncr)
          `FAIL_IF(item.arprot   != '0)
          `FAIL_IF(item.arlock   != '0)
          `FAIL_IF(item.arcache  != '0)
          `FAIL_IF(item.arsize   != gaxim_pkg::kBytes16)
          `FAIL_IF_LOG(item.araddr   != r_pattern.tuser[0].addr,
                       $sformatf("dut=%0h, r_pattern=%0h", item.araddr,
                       r_pattern.tuser[0].addr))
          `FAIL_IF_LOG(item.arlen    != (r_pattern.tuser[0].data_size/(DataWidth/8) - 1 +
                                        ((r_pattern.tuser[0].data_size % (DataWidth/8)) != 0)),
                       $sformatf("dut=%0d, r_pattern=%0d, data_size=%0d", item.arlen,
                                 (r_pattern.tuser[0].data_size/(DataWidth/8) - 1 +
                                 ((r_pattern.tuser[0].data_size % (DataWidth/8)) != 0)),
                                 r_pattern.tuser[0].data_size))
          `FAIL_IF(item.arid     != Id)

          `FAIL_IF(item.arregion != '0)
        end
      end
    endtask : analyzer

  endclass : mm_ap

  read_resp_ap u_read_resp_ap;
  mm_ap u_mm_ap;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    mm_vip.init();
    write.init();
    read_rq.init();
    read_resp.init();

    u_read_resp_ap = new();
    read_resp.core.add_ap2pkt(u_read_resp_ap);

    u_mm_ap = new();
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, u_mm_ap);
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AR, u_mm_ap);

    mm_vip.core.run_phase();
    write.core.run_phase();
    read_rq.core.run_phase();
    read_resp.core.run_phase();
  endfunction : build

  task setup();
    svunit_ut.setup();
    rst <= 1'b1;
    repeat (5) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask : setup

  task teardown();
    svunit_ut.teardown();
  endtask : teardown

  localparam DataItems = 50;

  task execute_test(gvip_policy_pkg::policy read_ready,
                    gvip_policy_pkg::policy write_ready);
    mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW, write_ready, 1);
    mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,  write_ready, 1);
    mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR, read_ready,  1);
    read_resp.core.set_policy(gvip_policy_pkg::random::create(), 1);

    fork
      u_mm_ap.analyzer();
      u_read_resp_ap.analyzer();
    join_none

    fork
      begin
        repeat (DataItems) begin
          write_item_t write_data;
          write_data = new();
          `FAIL_IF(!write_data.randomize() with {tuser[0].addr % 4 == 0;
                                                 tuser[0].data_size <= Value4k;
                                                 tuser[0].addr[Boundary4kWidth-1:0] +
                                                 tuser[0].data_size[Boundary4kWidth-1:0] <= Value4k;
                                                 tdata.size()*N == tuser[0].data_size;})

          u_mm_ap.add_write_pattern(write_data);

          write.core.send_item(write_data);
        end
      end
      begin
        repeat (DataItems) begin
          read_rq_item_t read_rq_data;
          read_rq_item_t pattern_item;
          read_resp_item_t resp_item;

          read_rq_data = new();
          resp_item = new();

          `FAIL_IF(!read_rq_data.randomize() with {tdata.size() == 1;
                                                   tuser[0].addr % 4 == 0;
                                                   tuser[0].data_size > 0;
                                                   tuser[0].data_size <= Value4k;})

          if (read_rq_data.tuser[0].addr[Boundary4kWidth-1:0] +
              read_rq_data.tuser[0].data_size[Boundary4kWidth-1:0] > Value4k) begin : split
            pattern_item = read_rq_data.clone();

            pattern_item.tuser[0].addr = read_rq_data.tuser[0].addr;
            pattern_item.tuser[0].data_size = Value4k -
                                              read_rq_data.tuser[0].addr[Boundary4kWidth-1:0];
            u_mm_ap.add_read_rq_pattern(pattern_item.clone());

            `FAIL_IF(!resp_item.randomize() with
              {tdata.size()*N >= pattern_item.tuser[0].data_size;
               tdata.size()*N <= (pattern_item.tuser[0].data_size + N);})
            u_mm_ap.add_read_resp_pattern(resp_item.clone());
            u_read_resp_ap.add_pattern(resp_item.clone());

            pattern_item.tuser[0].addr = (read_rq_data.tuser[0].addr >> Boundary4kWidth)
                                          << Boundary4kWidth;
            pattern_item.tuser[0].data_size = read_rq_data.tuser[0].data_size -
                                               (Value4k -
                                                read_rq_data.tuser[0].addr[Boundary4kWidth-1:0]);
            u_mm_ap.add_read_rq_pattern(pattern_item.clone());

            `FAIL_IF(!resp_item.randomize() with
              {tdata.size()*N >= pattern_item.tuser[0].data_size;
               tdata.size()*N <= (pattern_item.tuser[0].data_size + N);})
            u_mm_ap.add_read_resp_pattern(resp_item);
            u_read_resp_ap.add_pattern(resp_item);
          end
          else begin : do_not_split
            u_mm_ap.add_read_rq_pattern(read_rq_data.clone());
            `FAIL_IF(!resp_item.randomize() with
              {tdata.size()*N >= read_rq_data.tuser[0].data_size;
               tdata.size()*N <= (read_rq_data.tuser[0].data_size + N);})
            u_mm_ap.add_read_resp_pattern(resp_item);
            u_read_resp_ap.add_pattern(resp_item);
          end

          read_rq.core.send_item(read_rq_data);
        end
      end
    join

    while (!(u_mm_ap.is_empty() && u_read_resp_ap.is_empty())) begin
      @(posedge clk);
    end
  endtask : execute_test

  `SVUNIT_TESTS_BEGIN
    `SVTEST(channels_always_ready)
      gvip_policy_pkg::policy read_ready = gvip_policy_pkg::always_active::create();
      gvip_policy_pkg::policy write_ready = gvip_policy_pkg::always_active::create();

      execute_test(read_ready, write_ready);
    `SVTEST_END

    `SVTEST(random_ready)
      gvip_policy_pkg::policy read_ready = gvip_policy_pkg::random::create();
      gvip_policy_pkg::policy write_ready = gvip_policy_pkg::random::create();

      execute_test(read_ready, write_ready);
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : axis_to_aximm_unit_test
