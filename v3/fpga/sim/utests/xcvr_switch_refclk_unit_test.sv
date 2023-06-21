/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for axis_to_aximm module.
//
// Provide patterns on axis_vip (according to meta_t structure,
// with addr and data_size), verify proper translation on output
// axim_vip.
module xcvr_switch_refclk_unit_test;

  //Unit test name
  parameter string name = "axis_to_aximm_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  svunit_testcase svunit_ut;

  localparam int Lanes = 3;

  //Clocking
  logic clk = 1'b0;
  logic rst;
  logic [Lanes-1:0] cal_busy;
  logic reconfig_en;

  default clocking clk_default @(posedge clk); endclocking

  `SVUNIT_CLK_GEN(clk, 4)
  avalon_mm_i #(.AddrWidth(12)) i_xcvr_rcfg();

  xcvr_switch_refclk dut (
      .clk          ( clk         ),
      .rst          ( rst         ),
      .i_xcvr_rcfg  ( i_xcvr_rcfg ),
      .cal_busy     ( cal_busy    ),
      .reconfig_en  ( reconfig_en )
  );

  class cal_busy_wait;
    rand int wait_for_cal_busy;
    constraint c {
      wait_for_cal_busy < 200;
      wait_for_cal_busy > 50;
    };
  endclass : cal_busy_wait

  class avalon_tr;
    rand int readdata;
    rand int waitrequest_cycles;

    constraint wr_cycles {
      waitrequest_cycles < 6;
      waitrequest_cycles > 3;
    };

    task wait_for_ready();
      i_xcvr_rcfg.waitrequest <= 1'b1;
      repeat (waitrequest_cycles) @(posedge clk);
      i_xcvr_rcfg.waitrequest <= 1'b0;
    endtask : wait_for_ready

    task handle_write_tr();
      forever begin
        @(posedge clk);
        #1;
        if (i_xcvr_rcfg.write) begin
          wait_for_ready();
        end
      end
    endtask : handle_write_tr

    task handle_read_tr();
      forever begin
        @(posedge clk);
        #1;
        if (i_xcvr_rcfg.read) begin
          wait_for_ready();
          i_xcvr_rcfg.readdata = readdata;
        end
      end
    endtask : handle_read_tr

    task handle_cal_busy();
      forever begin
        @(posedge clk);
        #1;
        if (dut.state_next == 5) begin
          cal_busy = 3'h7;
          repeat(cb_wait.wait_for_cal_busy) @(posedge clk);
          cal_busy = '0;
        end
      end
    endtask : handle_cal_busy
  endclass : avalon_tr

  cal_busy_wait cb_wait;
  avalon_tr av_tr;
  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    cb_wait = new();
    av_tr = new();
  endfunction : build

  task setup();
    svunit_ut.setup();
    `FAIL_IF(!cb_wait.randomize())
    `FAIL_IF(!av_tr.randomize())
    cal_busy <= 3'h7;
    rst <= 1'b1;
    repeat (5) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
    repeat(cb_wait.wait_for_cal_busy) @(posedge clk);
    cal_busy <= '0;
  endtask : setup

  task teardown();
    svunit_ut.teardown();
  endtask : teardown

  `SVUNIT_TESTS_BEGIN
    `SVTEST(main)
      wait(cal_busy == '0);
      fork
        av_tr.handle_read_tr();
        av_tr.handle_write_tr();
        av_tr.handle_cal_busy();
      join_none
      wait(dut.state == 6);
      wait(reconfig_en == 0);
    `SVTEST_END

  `SVUNIT_TESTS_END


endmodule : xcvr_switch_refclk_unit_test
