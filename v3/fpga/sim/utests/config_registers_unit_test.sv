/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for config_registers module.
//
// Using reg_if interface, simulate register behavior
// (gvip_reg_pkg) and read/write those via AXILite VIP.
//

module config_registers_unit_test;

  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  import gvip_reg_pkg::*;

  import config_registers_pkg::*;

  string name = "config_registers_unit_test";
  svunit_testcase svunit_ut;

  localparam int AxiLiteDataWidth = gaxilite_pkg::DataWidth;
  localparam int AxiLiteAddrWidth = config_registers_pkg::AddrWidth;

  logic clk;
  logic rst;

  `SVUNIT_CLK_GEN(clk, 4)

  gclk_if clock (clk, rst);
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_lite_vip(clk, rst);

  reg_if #(AxiLiteDataWidth) guid_i();
  reg_if #(AxiLiteDataWidth) chip_id_i();
  reg_ro_const #(AxiLiteDataWidth) guid;
  reg_ro_const #(AxiLiteDataWidth) chip_id;

  `GAXIL_VIP_TO_AXIL(drv_lite_vip)

  typedef drv_lite_vip.item_t lite_item_t;

  assign guid_i.data = GUID;
  assign chip_id_i.data = CHIP_ID;

  config_registers #(
      .DataWidth            ( AxiLiteDataWidth              )
  ) dut (
      .clk                  ( clk                           ),
      .rst                  ( rst                           ),
      .i_axi_lite           ( axil_drv_lite_vip             )
  );

  class config_reg_msg_t extends reg_msg #(AxiLiteAddrWidth, AxiLiteDataWidth);

      constraint c_araddr {
        addr inside {AddrGitHash, AddrChipId};
        addr % 4 == 0;
      };

  endclass

  class mon_reg_if extends reg_mon implements gvip_axil_pkg::analysis_port_ic#(lite_item_t);
    protected lite_item_t pattern_q[$];

    function new(virtual gclk_if clk, int unsigned verify_delay = 0);
      super.new(clk, verify_delay);
    endfunction : new

    function void add_pattern(lite_item_t pattern);
      pattern_q.push_back(pattern);
    endfunction : add_pattern

    function bit is_empty();
      return !pattern_q.size();
    endfunction : is_empty

    virtual function lite_item_t write (input lite_item_t item);
      config_reg_msg_t r_msg;
      config_reg_msg_t w_msg;
      reg_meta rg[$];
      if (item.tr_type == gvip_axil_types_pkg::gvip::AW_W) begin
        w_msg = new();
        w_msg.msg_type = kWrite;
        w_msg.addr     = item.awaddr;
        w_msg.strb     = item.wstrb;
        w_msg.data     = item.wdata;
        add_msg_update(w_msg.clone());
        add_msg_response(w_msg.clone());
      end
      if (item.tr_type == gvip_axil_types_pkg::gvip::AR) begin
        r_msg = new();
        r_msg.msg_type = kRead;
        r_msg.addr     = item.araddr;
        rg             = regs.find(r) with (r.reg_addr == item.araddr);
        r_msg.data     = rg[0].get();
        add_msg_response(r_msg.clone());
      end
      void'(pattern_q.pop_front());
      return null; // monitor only
    endfunction : write

    task analyzer();
      fork
        reg_update();
        reg_monitor();
      join_none
    endtask : analyzer

  endclass : mon_reg_if

  mon_reg_if dut_mon;
  int unsigned verify_delay = 1;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    drv_lite_vip.init();

    dut_mon = new(clock, verify_delay);

    guid = new("guid", guid_i, AddrGitHash, AxiLiteDataWidth, GUID);
    dut_mon.add_reg(guid);
    chip_id = new("chip_id", chip_id_i, AddrChipId, AxiLiteDataWidth, CHIP_ID);
    dut_mon.add_reg(chip_id);

    drv_lite_vip.core.add_ap(gvip_axil_types_pkg::gvip::AW_W, dut_mon);
    drv_lite_vip.core.add_ap(gvip_axil_types_pkg::gvip::AR,   dut_mon);

    drv_lite_vip.core.run_phase();
  endfunction

  task setup();
    svunit_ut.setup();
    rst <= 1'b1;
    repeat(10) @(posedge clk);
    rst <= 1'b0;
  endtask

  task teardown();
  endtask

  localparam int NumOfMessages = 100;

  `SVUNIT_TESTS_BEGIN

    `SVTEST(main)
      lite_item_t lite_item;
      config_reg_msg_t msg;

      gvip_policy_pkg::policy policy = gvip_policy_pkg::always_active::create();

      drv_lite_vip.core.set_policy(gvip_axil_types_pkg::gvip::B, policy, 1);
      drv_lite_vip.core.set_policy(gvip_axil_types_pkg::gvip::R, policy, 1);

      dut_mon.analyzer();

      for (int i = 0; i < NumOfMessages; i++) begin
        msg = new();
        lite_item = new();

        `FAIL_IF(!msg.randomize() with {msg_type == kRead;});
        void'(lite_item.set_tr_type(gvip_axil_types_pkg::gvip::AR));
        lite_item.araddr = msg.addr;

        dut_mon.add_pattern(lite_item);
        drv_lite_vip.core.send_item(lite_item);
      end

      while(!(dut_mon.done() && dut_mon.is_empty())) @(posedge clk);
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : config_registers_unit_test
