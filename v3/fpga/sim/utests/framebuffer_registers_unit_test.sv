/*
 * Copyright 2022-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for framebuffer_registers module.
//
// Using reg_if interface, simulate register behavior
// (gvip_reg_pkg) and read/write those via AXILite VIP.
//

module framebuffer_registers_unit_test;

  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  import gvip_reg_pkg::*;

  import framebuffer_registers_pkg::*;

  string name = "framebuffer_registers_unit_test";
  svunit_testcase svunit_ut;

  localparam AxiLiteDataWidth = gaxilite_pkg::DataWidth;
  localparam AxiLiteAddrWidth = AddrWidth;

  logic clk;
  logic rst;

  `SVUNIT_CLK_GEN(clk, 4)

  gclk_if clock (clk, rst);
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_lite_vip(clk, rst);

  reg_if #($bits(dim_t))             height_i();
  reg_if #($bits(dim_t))             width_i();
  reg_if #($bits(enable_t))          en_i();
  reg_if #($bits(buffer_addr_t))     buffer_addr_a_i();
  reg_if #($bits(buffer_addr_t))     buffer_addr_b_i();
  reg_if #($bits(buffer_size_t))     buffer_size_i();
  reg_if #($bits(rst_t))             reset_from_register_i();
  reg_if #($bits(errors_t))          errors_i();
  reg_if #($bits(color_depth_e))     io_color_i();
  reg_if #($bits(data_rate_e))       data_rate_i();
  reg_if #($bits(pixel_mode_e))      pixel_mode_i();
  reg_if #($bits(sync_polarity_t))   sync_polarity_i();
  reg_if #($bits(dma_format_t))      dma_format_i();
  reg_if #(32)                       version_i();

  reg_ro #($bits(dim_t))             height;
  reg_ro #($bits(dim_t))             width;
  reg_rw #($bits(enable_t))          en;
  reg_rw #($bits(buffer_addr_t))     buffer_addr_a;
  reg_rw #($bits(buffer_addr_t))     buffer_addr_b;
  reg_rw #($bits(buffer_size_t))     buffer_size;
  reg_rw #($bits(rst_t))             reset_from_register;
  reg_ro #($bits(errors_t))          errors;
  reg_rw #($bits(color_depth_e))     io_color;
  reg_rw #($bits(data_rate_e))       data_rate;
  reg_rw #($bits(pixel_mode_e))      pixel_mode;
  reg_rw #($bits(sync_polarity_t))   sync_polarity;
  reg_rw #($bits(dma_format_t))      dma_format;
  reg_ro_const #(32)                 version;

  logic [framebuffer_pkg::BufferCount-1:0]  buffer_write;

  `GAXIL_VIP_TO_AXIL(drv_lite_vip)

  typedef drv_lite_vip.item_t lite_item_t;

  framebuffer_registers #(
      .AddrWidth            ( AxiLiteAddrWidth              ),
      .DataWidth            ( AxiLiteDataWidth              )
  ) dut (
      .clk                  ( clk                           ),
      .rst                  ( rst                           ),
      .height               ( height_i.data                 ),
      .width                ( width_i.data                  ),
      .en                   ( en_i.data                     ),
      .buffer_addr_a        ( buffer_addr_a_i.data          ),
      .buffer_addr_b        ( buffer_addr_b_i.data          ),
      .buffer_write         ( buffer_write                  ),
      .buffer_size          ( buffer_size_i.data            ),
      .reset_from_register  ( reset_from_register_i.data    ),
      .errors               ( errors_i.data                 ),
      .io_color             ( io_color_i.data               ),
      .data_rate            ( data_rate_i.data              ),
      .pixel_mode           ( pixel_mode_i.data             ),
      .sync_polarity        ( sync_polarity_i.data          ),
      .dma_format           ( dma_format_i.data             ),
      .i_axi_lite           ( axil_drv_lite_vip             )
  );

  //-----------------------------------------------------------------------------

  class framebuffer_reg_msg extends reg_msg #(AxiLiteAddrWidth, AxiLiteDataWidth);

    constraint c_addr {
      addr inside {AddrDimHeight, AddrDimWidth, AddrEn, AddrBufferA, AddrBufferB,
                   AddrBufferSize, AddrErrorStatus, AddrIOColor,
                   AddrIODataRate, AddrIOPixelMode, AddrSyncPolarity,
                   AddrDmaFormat, AddrVersion};
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
      framebuffer_reg_msg r_msg;
      framebuffer_reg_msg w_msg;
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

  class ro_reg_init;
    rand int unsigned value;
  endclass : ro_reg_init

  ro_reg_init height_init;
  ro_reg_init width_init;
  ro_reg_init errors_init;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    drv_lite_vip.init();

    dut_mon = new(clock, verify_delay);

    height_init = new();
    width_init = new();
    errors_init = new();
    void'(height_init.randomize());
    void'(width_init.randomize());
    void'(errors_init.randomize());
    height = new("height", height_i, AddrDimHeight, $bits(dim_t), height_init.value);
    width = new("width", width_i, AddrDimWidth,  $bits(dim_t), width_init.value);
    en = new("en", en_i, AddrEn, $bits(enable_t));
    buffer_addr_a = new("buffer_addr_a", buffer_addr_a_i, AddrBufferA, $bits(buffer_addr_t), 32'hdeadbeef);
    buffer_addr_b = new("buffer_addr_b", buffer_addr_b_i, AddrBufferB, $bits(buffer_addr_t), 32'hdeadbeef);
    buffer_size = new("buffer_size", buffer_size_i, AddrBufferSize, $bits(buffer_size_t));
    reset_from_register = new("reset_reg", reset_from_register_i, AddrReset, $bits(rst_t));
    errors = new("errors", errors_i, AddrErrorStatus, $bits(errors_t), errors_init.value);
    io_color = new("io_color", io_color_i, AddrIOColor, $bits(color_depth_e));
    data_rate = new("data_rate", data_rate_i, AddrIODataRate, $bits(data_rate_e));
    pixel_mode = new("pixel_mode", pixel_mode_i, AddrIOPixelMode, $bits(pixel_mode_e));
    sync_polarity = new("sync_polarity", sync_polarity_i, AddrSyncPolarity, $bits(sync_polarity_t));
    dma_format = new("dma_format", dma_format_i, AddrDmaFormat, $bits(dma_format_t));
    version = new("version", version_i, AddrVersion, 32, FramebufferVersion);

    height_i.data = height_init.value;
    width_i.data = width_init.value;
    errors_i.data = errors_init.value;
    version_i.data = FramebufferVersion;

    dut_mon.add_reg(height);
    dut_mon.add_reg(width);
    dut_mon.add_reg(en);
    dut_mon.add_reg(buffer_addr_a);
    dut_mon.add_reg(buffer_addr_b);
    dut_mon.add_reg(buffer_size);
    dut_mon.add_reg(errors);
    dut_mon.add_reg(io_color);
    dut_mon.add_reg(data_rate);
    dut_mon.add_reg(pixel_mode);
    dut_mon.add_reg(sync_polarity);
    dut_mon.add_reg(dma_format);
    dut_mon.add_reg(version);

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

  localparam NumOfMessages = 1000;

  `SVUNIT_TESTS_BEGIN

    `SVTEST(main)
      lite_item_t lite_item;
      framebuffer_reg_msg msg;

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

endmodule : framebuffer_registers_unit_test
