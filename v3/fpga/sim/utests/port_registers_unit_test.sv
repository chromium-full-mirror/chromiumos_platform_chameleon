/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for port_registers module.
//
// Using reg_if interface, simulate register behavior
// (gvip_reg_pkg) and read/write those via AXILite VIP.
//

module port_registers_unit_test;

  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;

  import gvip_reg_pkg::*;

  import port_registers_pkg::*;

  string name = "port_registers_unit_test";
  svunit_testcase svunit_ut;

  localparam AxiLiteDataWidth = gaxilite_pkg::DataWidth;
  localparam AxiLiteAddrWidth = port_registers_pkg::AddrWidth;

  logic clk;
  logic rst;

  `SVUNIT_CLK_GEN(clk, 4)

  gclk_if clock (clk, rst);

  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_lite_vip(clk, rst);

  reg_if #($bits(port_id_t)) port_id_i();
  reg_rw #($bits(port_id_t)) port_id;

  reg_if #($bits(vid_status_t)) vid_status_i();
  reg_ro #($bits(vid_status_t)) vid_status;

  `GAXIL_VIP_TO_AXIL(drv_lite_vip)

  typedef drv_lite_vip.item_t lite_item_t;

  port_registers #(
      .DataWidth            ( AxiLiteDataWidth              )
  ) dut (
      .clk                  ( clk                           ),
      .rst                  ( rst                           ),
      .port_id              ( port_id_i.data                ),
      .vid_status           ( vid_status_i.data             ),
      .i_axi_lite           ( axil_drv_lite_vip             )
  );

  class port_reg_msg extends reg_msg #(AxiLiteAddrWidth, AxiLiteDataWidth);
    constraint c_addr {
      addr inside {AddrPortId, AddrVidStatus};
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
      port_reg_msg r_msg;
      port_reg_msg w_msg;
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

  //-----------------------------------------------------------------------------

  mon_reg_if dut_mon;
  int unsigned verify_delay = 1;

  class ro_reg_init;
    rand int unsigned value;
  endclass : ro_reg_init

  ro_reg_init vid_status_init;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    drv_lite_vip.init();

    vid_status_init = new();
    void'(vid_status_init.randomize());
    dut_mon = new(clock, verify_delay);

    port_id = new("port_id", port_id_i, AddrPortId, $bits(port_id_t));
    vid_status = new("vid_status", vid_status_i, AddrVidStatus,
                     $bits(vid_status_t), vid_status_init.value);
    vid_status_i.data = vid_status_init.value;

    dut_mon.add_reg(port_id);
    dut_mon.add_reg(vid_status);

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

  localparam NumOfMessages = 100;

  `SVUNIT_TESTS_BEGIN

    `SVTEST(main)
      lite_item_t lite_item;
      port_reg_msg msg;

      gvip_policy_pkg::policy policy = gvip_policy_pkg::always_active::create();

      drv_lite_vip.core.set_policy(gvip_axil_types_pkg::gvip::B, policy, 1);
      drv_lite_vip.core.set_policy(gvip_axil_types_pkg::gvip::R, policy, 1);

      dut_mon.analyzer();

      for (int i = 0; i < NumOfMessages; i++) begin
        msg = new();
        lite_item = new();

        `FAIL_IF(!msg.randomize());
        if (msg.msg_type == kWrite) begin
          void'(lite_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
          lite_item.awaddr = msg.addr;
          lite_item.wstrb  = msg.strb;
          lite_item.wdata  = msg.data;
        end else if (msg.msg_type == kRead) begin
          void'(lite_item.set_tr_type(gvip_axil_types_pkg::gvip::AR));
          lite_item.araddr = msg.addr;
        end
        dut_mon.add_pattern(lite_item);
        drv_lite_vip.core.send_item(lite_item);
      end

      while(!(dut_mon.done() && dut_mon.is_empty())) @(posedge clk);
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : port_registers_unit_test
