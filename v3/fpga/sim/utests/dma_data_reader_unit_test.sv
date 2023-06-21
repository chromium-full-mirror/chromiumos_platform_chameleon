/*
 * Copyright 2022-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for dma_data_reader module.
//
// Simulate ring buffer behavior (updates of producer_idx,
// since dma_data_reader updates consumer_idx).
//
// Provide updates of producer_idx, observe updates of consumer_idx
// and stream of ring requests.

module dma_data_reader_unit_test;

  //Unit test name
  parameter string name = "dma_data_reader_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  svunit_testcase svunit_ut;

  import i2s_pkg::*;
  import axis_to_aximm_pkg::*;

  parameter  int MaxRingBytes            = 32'h0020_0000;
  parameter  int AddressWidth            = 32;
  parameter  int DataOutWidth            = 128;
  parameter  int TxBytesToFetch          = 64;
  localparam int OutputRegType           = 0; // output registers need to turn off to make ut doable
  localparam int MaxRingBytesWidth       = $clog2(MaxRingBytes+1);
  localparam int RingAddrAlignment       = Value4k;
  localparam int RingAddrAlignmentWidth  = $clog2(RingAddrAlignment);
  localparam int MaxPktBeatNum           = 6;

  //Clocking
  logic clk = 1'b0;
  logic rst;

  default clocking clk_default @(posedge clk); endclocking
  `SVUNIT_CLK_GEN(clk, 2)

  //Interfaces

  gvip_axis_if #(DataOutWidth/8, 0, 0, meta_t,
                 "data_out", gvip_axis_pkg::SLAVE) data_out(clk, rst);
  gvip_axis_if #(DataOutWidth/8, 0, 0, logic,
                 "resp_in", gvip_axis_pkg::MASTER) resp_in(clk, rst);
  gvip_axis_if #(DataOutWidth/8, 0, 0, logic,
                 "resp_out", gvip_axis_pkg::SLAVE) resp_out(clk, rst);

  typedef struct packed {
    int unsigned                 num;
    sample_t [MaxPktBeatNum-1:0] sample;
  } samples_t;

  typedef struct packed {
    logic [AddressWidth-1:0] addr;
  } addr_t;

  typedef struct packed {
    logic [MaxRingBytesWidth-1:0] ring;
  } ring_t;

  logic  ring_enable;
  ring_t ring_size;
  addr_t ring_address;
  ring_t ring_prod_idx;
  ring_t ring_cons_idx;
  logic  ring_cons_idx_rst;
  logic  ring_cons_idx_change;

  typedef data_out.item_t item_out_t;
  typedef resp_in.item_t resp_in_t;
  typedef resp_out.item_t resp_out_t;

  `AXIS_TO_GAXIS_VIP(data_out, meta_t)
  `GAXIS_VIP_TO_AXIS(resp_in,  logic)
  `AXIS_TO_GAXIS_VIP(resp_out, logic)

  // TX path
  dma_data_reader #(
    .OutputRegType          ( 0                    ),
    .MaxRingBytes           ( MaxRingBytes         ),
    .AddressWidth           ( AddressWidth         ),
    .BytesToFetch           ( TxBytesToFetch       )
  ) u_dut (
    .clk                    ( clk                  ),
    .rst                    ( rst                  ),
    .i_read_rq              ( axis_data_out        ),
    .i_read_resp_ap         ( axis_resp_in         ),
    .i_read_resp            ( axis_resp_out        ),
    .ring_enable            ( ring_enable          ),
    .ring_size              ( ring_size            ),
    .ring_address           ( ring_address         ),
    .ring_prod_idx          ( ring_prod_idx        ),
    .ring_cons_idx          ( ring_cons_idx        ),
    .ring_cons_idx_rst      ( ring_cons_idx_rst    ),
    .ring_cons_idx_change   ( ring_cons_idx_change )
  );

  class ap_resp_out_impl implements gvip_axis_pkg::analysis_port_ic#(resp_out_t);
    protected resp_out_t responses[$];

    virtual function void write(input resp_out_t item);
      responses.push_back(item);
    endfunction : write

    task analyzer();
      forever begin
        @(posedge clk);
        if (responses.size()) begin
          `FAIL_IF(u_dut.u_data_reader_fifo.full);
        end
      end
    endtask : analyzer

  endclass : ap_resp_out_impl

  class delay_impl;
    rand int unsigned v;

    constraint c {
      soft v < 5;
    }
  endclass : delay_impl

  class ap_beat_impl implements gvip_axis_pkg::analysis_port_ic#(item_out_t);
    protected item_out_t responses[$];
    protected ring_t ring_cons_prev;
    protected process ring_prod_analyzer;
    protected rand delay_impl delay;
    protected rand resp_in_t resp_in_item;

    function new();
      delay = new();
      resp_in_item = new();
      clear();
    endfunction : new

    function void clear();
      ring_cons_prev = '0;
    endfunction : clear

    virtual function void write(input item_out_t item);
      responses.push_back(item);
    endfunction : write

    task analyzer();
      forever begin
        item_out_t   res_item;
        addr_t       res_addr;
        int unsigned ring_cons_res;
        int unsigned data_size;
        logic        consumer_overflow;

        @(posedge clk);
        wait(responses.size());
        res_item = responses.pop_front();
        `FAIL_IF(res_item.tuser.size() != 1)

        res_addr = res_item.tuser[0].addr;
        data_size = res_item.tuser[0].data_size;
        ring_cons_res = ((res_addr + data_size) - ring_address) % ring_size;

        `FAIL_IF_LOG((ring_cons_prev + TxBytesToFetch) % ring_size != ring_cons_res,
                     $sformatf("Hardware have not consumed %0d bytes - prev %0h, current %0h, prod %0h",
                               TxBytesToFetch, ring_cons_prev, ring_cons_res, ring_prod_idx))
        `FAIL_IF_LOG(data_size != TxBytesToFetch,
                     $sformatf("Data size %0d not equal to const fetch %0d",
                               data_size, TxBytesToFetch));

        ring_cons_prev = ring_cons_res;

        `FAIL_IF(!delay.randomize() with {v > 5; v < 15;});
        `FAIL_IF(!resp_in_item.randomize() with {tdata.size()*DataOutWidth/8 == TxBytesToFetch;})
        repeat(delay.v) @(posedge clk);
        resp_in.core.send_item(resp_in_item);
      end
    endtask : analyzer

  endclass : ap_beat_impl

  class prod_impl;
    rand int unsigned value;
    rand int unsigned delay;

    constraint c {
      delay < 200;
    };

  endclass : prod_impl

  class ring_prod_driver;
    prod_impl ring_prod_incr;
    rand int unsigned prod_updates;
    int unsigned space_in_ring;

    constraint updates {
      soft prod_updates > 100;
    };

    task run();
      ring_prod_incr = new();
      forever begin
        @(posedge clk);
        if(prod_updates) begin
          space_in_ring = ring_prod_idx < ring_cons_idx
                        ? ring_cons_idx - ring_prod_idx - 1
                        : ring_size - ring_prod_idx + ring_cons_idx - 1;
          if (space_in_ring >= TxBytesToFetch) begin
            `FAIL_IF(!ring_prod_incr.randomize() with {value <= space_in_ring;})
            repeat(ring_prod_incr.delay) @(posedge clk);
            ring_prod_idx <= (ring_prod_idx + ring_prod_incr.value) % ring_size;
            prod_updates--;
          end
          else begin
            @(posedge clk);
          end
          // Send last aligned request
          @(posedge clk);
          ring_prod_idx <= (ring_prod_idx +
                            (TxBytesToFetch - (ring_prod_idx % TxBytesToFetch))) % ring_size;
        end
      end
    endtask : run

    function bit done();
      return (prod_updates == 0);
    endfunction : done

  endclass : ring_prod_driver

  ap_beat_impl ap_beat;
  ap_resp_out_impl resp_beat_analyzer;
  ring_prod_driver ring_prod_drv;

  class cfg_impl;
    rand int unsigned delay;
    rand int unsigned delay_before;
    rand int unsigned delay_after;
    rand addr_t addr;
    rand ring_t size;

    constraint c {
      addr[RingAddrAlignmentWidth-1:0] == '0;
      delay_before < 10;
      delay_after < 50;
      $countones(size) == 1;
      size > TxBytesToFetch;
      size < MaxRingBytes;
      delay > 500;
      delay < 1000;
    }
  endclass : cfg_impl

  task randomize_cfg();
    cfg_impl cfg;
    cfg = new();

    `FAIL_IF(!cfg.randomize())

    repeat (cfg.delay) @(posedge clk);

    ring_cons_idx_rst <= 1'b0;
    ring_enable <= 1'b0;

    repeat (cfg.delay_before) begin
      while (!data_out.axis.tready) @(posedge clk);
      @(posedge clk);
    end

    ring_address <= cfg.addr;
    ring_prod_idx <= '0;
    ring_size <= cfg.size;
    @(posedge clk);
    ring_cons_idx_rst <= 1'b1;
    @(posedge clk);
    ring_cons_idx_rst <= 1'b0;
    repeat (cfg.delay_after) @(posedge clk);

    ap_beat.clear();

    ring_enable <= 1'b1;
  endtask : randomize_cfg;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    data_out.init();
    resp_in.init();
    resp_out.init();

    ap_beat = new();
    resp_beat_analyzer = new();
    ring_prod_drv = new();

    data_out.core.add_ap2transfer(ap_beat);
    resp_out.core.add_ap2transfer(resp_beat_analyzer);

    data_out.core.run_phase();
    resp_in.core.run_phase();
    resp_out.core.run_phase();
  endfunction

  task setup();
    svunit_ut.setup();
    //data_out.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
    rst <= 1'b1;
    repeat(10) @(posedge clk);
    rst <= 1'b0;
    ring_enable <= 1'b0;
    randomize_cfg();
    repeat(10) @(posedge clk);
  endtask

  task teardown();
    ap_beat.clear();
  endtask

  localparam ITER = 1000;

  `SVUNIT_TESTS_BEGIN
    `SVTEST(output_always_ready)
      `FAIL_IF(!ring_prod_drv.randomize() with {prod_updates == ITER;});
      data_out.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      resp_out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      fork
        ap_beat.analyzer();
        resp_beat_analyzer.analyzer();
        ring_prod_drv.run();
      join_none

      while (!ring_prod_drv.done()) @(posedge clk);
      // drain test
      while ((ring_prod_idx != ring_cons_idx) ||
             (u_dut.in_flight_requested_data != 0)) @(posedge clk);
    `SVTEST_END

    `SVTEST(output_ready_randomized)
      `FAIL_IF(!ring_prod_drv.randomize() with {prod_updates == ITER;});
      data_out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      resp_out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      fork
        ap_beat.analyzer();
        resp_beat_analyzer.analyzer();
        ring_prod_drv.run();
      join_none

      while (!ring_prod_drv.done()) @(posedge clk);
      // drain test
      while ((ring_prod_idx != ring_cons_idx) ||
             (u_dut.in_flight_requested_data != 0)) @(posedge clk);
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : dma_data_reader_unit_test
