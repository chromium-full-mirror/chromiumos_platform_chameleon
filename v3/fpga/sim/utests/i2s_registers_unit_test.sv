/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for i2s_registers module.
//
// Using reg_if interface, register behavior
// (gvip_reg_pkg) and read/write those via AXILite VIP.
//

module i2s_registers_unit_test;

  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  import gvip_reg_pkg::*;

  import i2s_registers_pkg::*;
  import i2s_pkg::*;

  string name = "i2s_registers_unit_test";
  svunit_testcase svunit_ut;

  localparam AxiLiteDataWidth = gaxilite_pkg::DataWidth;
  localparam AxiLiteAddrWidth = i2s_registers_pkg::AddrWidth;

  logic clk;
  logic rst;

  `SVUNIT_CLK_GEN(clk, 4)

  gclk_if clock (clk, rst);
  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_lite_vip(clk, rst);

  reg_if #($bits(tx_enable_t))        tx_enable_i();
  reg_if #($bits(tx_base_addr_t))     tx_base_addr_i();
  reg_if #($bits(tx_buffer_size_t))   tx_buffer_size_i();
  reg_if #($bits(tx_producer_idx_t))  tx_prod_idx_i();
  reg_if #($bits(tx_consumer_idx_t))  tx_cons_idx_i();
  reg_if #($bits(rx_enable_t))        rx_enable_i();
  reg_if #($bits(rx_base_addr_t))     rx_base_addr_i();
  reg_if #($bits(rx_buffer_size_t))   rx_buffer_size_i();
  reg_if #($bits(rx_producer_idx_t))  rx_prod_idx_i();
  reg_if #($bits(rx_consumer_idx_t))  rx_cons_idx_i();
  reg_if #($bits(error_t))            error_i();
  reg_if #($bits(soft_reset_t))       soft_reset_i();
  reg_if #($bits(config_const_t))     config_const_i();
  reg_if #(32)                        counter_width_i();
  reg_if #(32)                        clk_frequency_i();
  reg_if #(CounterWidth)              tx_clk_counter_i();
  reg_if #(CounterWidth)              tx_ws_counter_i();
  reg_if #(CounterWidth)              rx_clk_counter_i();
  reg_if #(CounterWidth)              rx_ws_counter_i();
  reg_if #($bits(irq_t))              rx_irq_i();
  reg_if #($bits(irq_ro_t))           rx_irq_const_i();
  reg_if #($bits(irq_t))              tx_irq_i();
  reg_if #($bits(irq_ro_t))           tx_irq_const_i();
  reg_if #($bits(sampling_freq_t))    sampling_freq_i();

  reg_rw #($bits(tx_enable_t))        tx_enable;
  reg_rw #($bits(tx_base_addr_t))     tx_base_addr;
  reg_rw #($bits(tx_buffer_size_t))   tx_buffer_size;
  reg_rw #($bits(tx_producer_idx_t))  tx_prod_idx;
  reg_ro #($bits(tx_consumer_idx_t))  tx_cons_idx;
  reg_rw #($bits(rx_enable_t))        rx_enable;
  reg_rw #($bits(rx_base_addr_t))     rx_base_addr;
  reg_rw #($bits(rx_buffer_size_t))   rx_buffer_size;
  reg_ro #($bits(rx_producer_idx_t))  rx_prod_idx;
  reg_rw #($bits(rx_consumer_idx_t))  rx_cons_idx;
  reg_ro #($bits(error_t))            error;
  reg_wo #($bits(soft_reset_t))       soft_reset;
  reg_ro #($bits(config_const_t))     config_const;
  reg_ro_const #(32)                  counter_width;
  reg_ro_const #(32)                  clk_frequency;
  reg_ro #(CounterWidth)              tx_clk_counter;
  reg_ro #(CounterWidth)              tx_ws_counter;
  reg_ro #(CounterWidth)              rx_clk_counter;
  reg_ro #(CounterWidth)              rx_ws_counter;
  reg_rw #($bits(irq_t))              rx_irq;
  reg_ro_const #($bits(irq_ro_t))     rx_irq_const;
  reg_rw #($bits(irq_t))              tx_irq;
  reg_ro_const #($bits(irq_ro_t))     tx_irq_const;
  reg_ro #($bits(sampling_freq_t))    sampling_freq;

  `GAXIL_VIP_TO_AXIL(drv_lite_vip)

  typedef drv_lite_vip.item_t lite_item_t;

  i2s_registers #(
      .DataWidth            ( AxiLiteDataWidth              )
  ) dut (
      .clk                  ( clk                           ),
      .rst                  ( rst                           ),
      .i_axi_lite           ( axil_drv_lite_vip             ),
      .tx_enable            ( tx_enable_i.data              ),
      .tx_base_addr         ( tx_base_addr_i.data           ),
      .tx_buffer_size       ( tx_buffer_size_i.data         ),
      .tx_prod_idx          ( tx_prod_idx_i.data            ),
      .tx_cons_idx          ( tx_cons_idx_i.data            ),
      .rx_enable            ( rx_enable_i.data              ),
      .rx_base_addr         ( rx_base_addr_i.data           ),
      .rx_buffer_size       ( rx_buffer_size_i.data         ),
      .rx_prod_idx          ( rx_prod_idx_i.data            ),
      .rx_cons_idx          ( rx_cons_idx_i.data            ),
      .error                ( error_i.data                  ),
      .soft_reset           ( soft_reset_i.data             ),
      .config_const         ( config_const_i.data           ),
      .tx_clk_counter       ( tx_clk_counter_i.data         ),
      .tx_ws_counter        ( tx_ws_counter_i.data          ),
      .rx_clk_counter       ( rx_clk_counter_i.data         ),
      .rx_ws_counter        ( rx_ws_counter_i.data          ),
      .rx_irq_meta          ( rx_irq_i.data                 ),
      .rx_irq_const         ( rx_irq_const_i.data           ),
      .tx_irq_meta          ( tx_irq_i.data                 ),
      .tx_irq_const         ( tx_irq_const_i.data           ),
      .sampling_freq        ( sampling_freq_i.data          )
  );

  class i2s_reg_msg extends reg_msg #(AxiLiteAddrWidth, AxiLiteDataWidth);

      constraint c_addr {
          addr inside {AddrTxEnable, AddrTxBaseAddr,
                       AddrTxBufferSize, AddrTxProducerIdx, AddrTxConsumerIdx,
                       AddrRxEnable, AddrRxBaseAddr,
                       AddrRxBufferSize, AddrRxProducerIdx, AddrRxConsumerIdx,
                       AddrError, AddrConfigConst, AddrClkFrequencyMhz, AddrCounterWidth,
                       AddrTxClkCounter, AddrTxWsCounter, AddrRxClkCounter, AddrRxWsCounter,
                       AddrRxIrq, AddrRxIrqConst, AddrTxIrq, AddrTxIrqConst, AddrSamplingFreq};
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
      i2s_reg_msg r_msg;
      i2s_reg_msg w_msg;
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

  ro_reg_init tx_cons_idx_init;
  ro_reg_init rx_prod_idx_init;
  ro_reg_init errors_init;
  ro_reg_init config_const_init;
  ro_reg_init tx_clk_counter_init;
  ro_reg_init tx_ws_counter_init;
  ro_reg_init rx_clk_counter_init;
  ro_reg_init rx_ws_counter_init;
  ro_reg_init tx_irq_const_init;
  ro_reg_init rx_irq_const_init;
  ro_reg_init sampling_freq_init;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    drv_lite_vip.init();

    dut_mon = new(clock, verify_delay);

    tx_cons_idx_init = new();
    rx_prod_idx_init = new();
    errors_init = new();
    config_const_init = new();
    tx_clk_counter_init = new();
    tx_ws_counter_init = new();
    rx_clk_counter_init = new();
    rx_ws_counter_init = new();
    tx_irq_const_init = new();
    rx_irq_const_init = new();
    sampling_freq_init = new();
    void'(tx_cons_idx_init.randomize());
    void'(rx_prod_idx_init.randomize());
    void'(errors_init.randomize());
    void'(config_const_init.randomize());
    void'(tx_clk_counter_init.randomize());
    void'(tx_ws_counter_init.randomize());
    void'(rx_clk_counter_init.randomize());
    void'(rx_ws_counter_init.randomize());
    void'(tx_irq_const_init.randomize());
    void'(rx_irq_const_init.randomize());
    void'(sampling_freq_init.randomize());

    tx_enable = new("tx_enable", tx_enable_i, AddrTxEnable, $bits(tx_enable_t));
    tx_base_addr = new("tx_base_addr", tx_base_addr_i, AddrTxBaseAddr,  $bits(tx_base_addr_t),
                       0, axis_to_aximm_pkg::Boundary4kWidth);
    tx_buffer_size = new("tx_buffer_size", tx_buffer_size_i,
                         AddrTxBufferSize, $bits(tx_buffer_size_t),
                         0, axis_to_aximm_pkg::Boundary4kWidth);
    tx_prod_idx = new("tx_prod_idx", tx_prod_idx_i, AddrTxProducerIdx,  $bits(tx_producer_idx_t));
    tx_cons_idx = new("tx_cons_idx", tx_cons_idx_i,
                      AddrTxConsumerIdx,  $bits(tx_consumer_idx_t), tx_cons_idx_init.value);
    rx_enable = new("rx_enable", rx_enable_i, AddrRxEnable, $bits(rx_enable_t));
    rx_base_addr = new("rx_base_addr", rx_base_addr_i, AddrRxBaseAddr,  $bits(rx_base_addr_t),
                       0, axis_to_aximm_pkg::Boundary4kWidth);
    rx_buffer_size = new("rx_buffer_size", rx_buffer_size_i,
                         AddrRxBufferSize, $bits(rx_buffer_size_t),
                         0, axis_to_aximm_pkg::Boundary4kWidth);
    rx_prod_idx = new("rx_prod_idx", rx_prod_idx_i,
                      AddrRxProducerIdx,  $bits(rx_producer_idx_t), rx_prod_idx_init.value);
    rx_cons_idx = new("rx_cons_idx", rx_cons_idx_i, AddrRxConsumerIdx, $bits(rx_consumer_idx_t));
    error = new("error", error_i, AddrError, $bits(error_t), errors_init.value);
    soft_reset = new("soft_reset", soft_reset_i, AddrSoftReset, $bits(soft_reset_t));
    config_const = new("config_const", config_const_i,
                       AddrConfigConst, $bits(config_const_t), config_const_init.value);
    counter_width = new("counter_width", counter_width_i, AddrCounterWidth, 32, CounterWidth);
    clk_frequency = new("clk_frequency", clk_frequency_i, AddrClkFrequencyMhz, 32, ClkFrequencyMhz);
    tx_clk_counter = new("tx_clk_counter", tx_clk_counter_i,
                         AddrTxClkCounter, CounterWidth, tx_clk_counter_init.value);
    tx_ws_counter = new("tx_ws_counter", tx_ws_counter_i,
                        AddrTxWsCounter, CounterWidth, tx_ws_counter_init.value);
    rx_clk_counter = new("rx_clk_counter", rx_clk_counter_i,
                         AddrRxClkCounter, CounterWidth, rx_clk_counter_init.value);
    rx_ws_counter = new("rx_ws_counter", rx_ws_counter_i,
                        AddrRxWsCounter, CounterWidth, rx_ws_counter_init.value);
    tx_irq = new("tx_irq", tx_irq_i, AddrTxIrq, $bits(irq_t));
    tx_irq_const = new("tx_irq_const", tx_irq_const_i,
                       AddrTxIrqConst, $bits(irq_ro_t), tx_irq_const_init.value);
    rx_irq = new("rx_irq", rx_irq_i, AddrRxIrq, $bits(irq_t));
    rx_irq_const = new("rx_irq_const", rx_irq_const_i,
                       AddrRxIrqConst, $bits(irq_ro_t), rx_irq_const_init.value);
    sampling_freq = new("sampling_freq", sampling_freq_i,
                        AddrSamplingFreq, $bits(sampling_freq_t), sampling_freq_init.value);

    tx_cons_idx_i.data = tx_cons_idx_init.value;
    rx_prod_idx_i.data = rx_prod_idx_init.value;
    error_i.data = errors_init.value;
    config_const_i.data = config_const_init.value;
    counter_width_i.data = CounterWidth;
    clk_frequency_i.data = ClkFrequencyMhz;
    tx_clk_counter_i.data = tx_clk_counter_init.value;
    tx_ws_counter_i.data = tx_ws_counter_init.value;
    rx_clk_counter_i.data = rx_clk_counter_init.value;
    rx_ws_counter_i.data = rx_ws_counter_init.value;
    tx_irq_const_i.data = tx_irq_const_init.value;
    rx_irq_const_i.data = rx_irq_const_init.value;
    sampling_freq_i.data = sampling_freq_init.value;

    dut_mon.add_reg(tx_enable);
    dut_mon.add_reg(tx_base_addr);
    dut_mon.add_reg(tx_buffer_size);
    dut_mon.add_reg(tx_prod_idx);
    dut_mon.add_reg(tx_cons_idx);
    dut_mon.add_reg(rx_enable);
    dut_mon.add_reg(rx_base_addr);
    dut_mon.add_reg(rx_buffer_size);
    dut_mon.add_reg(rx_prod_idx);
    dut_mon.add_reg(rx_cons_idx);
    dut_mon.add_reg(error);
    dut_mon.add_reg(config_const);
    dut_mon.add_reg(counter_width);
    dut_mon.add_reg(clk_frequency);
    dut_mon.add_reg(tx_clk_counter);
    dut_mon.add_reg(tx_ws_counter);
    dut_mon.add_reg(rx_clk_counter);
    dut_mon.add_reg(rx_ws_counter);
    dut_mon.add_reg(tx_irq);
    dut_mon.add_reg(tx_irq_const);
    dut_mon.add_reg(rx_irq);
    dut_mon.add_reg(rx_irq_const);
    dut_mon.add_reg(sampling_freq);

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
      i2s_reg_msg msg;

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

endmodule : i2s_registers_unit_test
