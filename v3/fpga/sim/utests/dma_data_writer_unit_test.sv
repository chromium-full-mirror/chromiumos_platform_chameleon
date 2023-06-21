/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for dma_data_writer module.
//
// Simulate ring buffer behavior (updates of consumer_idx,
// since dma_data_writer updates producer_idx).
//
// Provide stream of patterns on input axis, check output data
// based on space_in_ring calculation, verify producer_idx updates.

module dma_data_writer_unit_test;

  //Unit test name
  parameter string name = "dma_data_writer_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  svunit_testcase svunit_ut;
  import i2s_pkg::*;

  localparam int WordWidth = $bits(sample_t);
  localparam int WordBytesWidth = WordWidth/8;

  parameter  int MaxRingBytes            = 1024;
  parameter  int AddressWidth            = 32;
  localparam int OutputRegType           = 0; // output registers need to be turn off to make ut doable
  localparam int MaxRingBytesWidth       = $clog2(MaxRingBytes);
  localparam int RingAddrAlignment       = axis_to_aximm_pkg::Value4k;
  localparam int RingAddrAlignmentWidth  = $clog2(RingAddrAlignment);
  localparam int MaxPktBeatNum           = 6;

  //Clocking
  logic clk = 1'b0;
  logic rst;

  default clocking clk_default @(posedge clk); endclocking
  `SVUNIT_CLK_GEN(clk, 2)

  //Inputs and outputs
  gvip_axis_if #($bits(sample_t)/8, 0, 0, logic,
                 "data_in", gvip_axis_pkg::MASTER) data_in(clk, rst);
  gvip_axis_if #($bits(sample_t)/8, 0, 0, logic [AddressWidth-1:0],
                 "data_out", gvip_axis_pkg::SLAVE) data_out(clk, rst);

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


  logic  write_done;
  logic  ring_enable;
  ring_t ring_size;
  addr_t ring_address;
  ring_t ring_cons_idx;
  ring_t ring_prod_idx;
  logic  ring_prod_idx_rst;
  logic  ring_prod_idx_change;

  typedef data_in.item_t item_in_t;
  typedef data_out.item_t item_out_t;

  class sample_item extends item_in_t;

    constraint c {
      tdata.size()*$bits(sample_t)/8 > 0;
      tdata.size()*$bits(sample_t)/8 <= WordBytesWidth*MaxPktBeatNum;
      tdata.size()*$bits(sample_t)/8 % WordBytesWidth == 0;
    }

  endclass : sample_item

  `GAXIS_VIP_TO_AXIS(data_in,  logic)
  `AXIS_TO_GAXIS_VIP(data_out, logic [AddressWidth-1:0])

  dma_data_writer #(
    .MaxRingBytes ( MaxRingBytes  ),
    .AddressWidth ( AddressWidth  ),
    .OutputRegType( OutputRegType )
  )
  dut (
    .clk                  ( clk                  ),
    .rst                  ( rst                  ),
    .i_data_in            ( axis_data_in         ),
    .i_data_out           ( axis_data_out        ),
    .write_done           ( write_done           ),
    .ring_enable          ( ring_enable          ),
    .ring_size            ( ring_size            ),
    .ring_address         ( ring_address         ),
    .ring_cons_idx        ( ring_cons_idx        ),
    .ring_prod_idx        ( ring_prod_idx        ),
    .ring_prod_idx_rst    ( ring_prod_idx_rst    ),
    .ring_prod_idx_change ( ring_prod_idx_change )
  );

  int unsigned ring_prod_pat;
  int was_ring_disable;

  always @(posedge clk) begin
    if (!ring_enable) begin
      was_ring_disable = 2;
    end
  end

  class ap_impl implements gvip_axis_pkg::analysis_port_ic#(item_out_t);
    samples_t pat_queue[$];
    item_out_t results[$];

    function new();
      clear();
    endfunction : new

    task add_pat(item_in_t item);
      samples_t pat;
      pat = '0;
      pat.num = item.tdata.size();
      `FAIL_IF(pat.num > MaxRingBytesWidth)

      foreach (item.tdata[i]) begin
        pat.sample[i] = item.tdata[i];
      end
      pat_queue.push_back(pat);
    endtask : add_pat

    function void clear();
      was_ring_disable = 2;
      pat_queue.delete();
      ring_disable();
    endfunction : clear

    function void ring_disable();
      pat_queue.delete();
    endfunction : ring_disable

    virtual function void write(input item_out_t item);
      results.push_back(item);
    endfunction : write

    task analyzer();
      samples_t                 pat_sample;
      samples_t                 res_sample;
      item_out_t                res_item;
      int                       sample_index[$];

      forever begin
        @(posedge clk);
        wait(results.size());

        `FAIL_IF_LOG(pat_queue.size() == 0, "more packets received than sent")
        if (was_ring_disable == 2) begin
          was_ring_disable = 1;
          void'(results.pop_front());
          continue;
        end

        res_item = results.pop_front();
        `FAIL_IF_LOG(res_item.tdata.size() > MaxPktBeatNum,
            $sformatf("item size mismatch: res: %0d should not be greater than %0d",
                      res_item.tdata.size(), MaxPktBeatNum))
        res_sample = '0;
        res_sample.num = res_item.tdata.size();
        foreach (res_item.tdata[i]) begin
          res_sample.sample[i] = res_item.tdata[i];
        end

        if (was_ring_disable) begin
          sample_index = pat_queue.find_first_index(x) with (x == res_sample);
          `FAIL_IF_LOG(sample_index.size() == 0,
              $sformatf("Failed to find pattern(%h)", res_sample))

          pat_queue = pat_queue[sample_index[0]:$];
        end
        pat_sample = pat_queue.pop_front();
        was_ring_disable = 0;

        `FAIL_IF_LOG(res_sample != pat_sample,
            $sformatf("Sample mismatch. Res: %h Pat: %h was_ring_disable: %0d",
                      res_sample, pat_sample, was_ring_disable))
      end
    endtask : analyzer

    function bit is_empty();
      return (pat_queue.size() == 0 || results.size() == 0);
    endfunction : is_empty

  endclass : ap_impl

  class delay_impl;
    rand int unsigned v;

    constraint c {
      v < 5;
    }
  endclass : delay_impl

  class ap_beat_impl implements gvip_axis_pkg::analysis_port_ic#(item_out_t);
    protected process ring_prod_analyzer;
    int unsigned ring_prod_updates;
    int unsigned ring_prod_pat_internal;
    rand delay_impl delay;
    item_out_t results[$];

    function new();
      clear();
    endfunction : new

    function void clear();
      ring_disable();
      ring_prod_updates = 0;
      write_done <= 1'b0;
    endfunction : clear

    function void ring_disable();
      ring_prod_pat = '0;
      ring_prod_pat_internal = '0;
    endfunction : ring_disable

    virtual function void write(input item_out_t item);
      results.push_back(item);
    endfunction : write

    task analyzer();
      item_out_t                res_item;
      addr_t                    res_addr;
      int unsigned              ring_prod_res;
      int unsigned              space_in_ring;

      forever begin
        wait(results.size());
        res_item = results.pop_front();
        `FAIL_IF(res_item.tuser.size() != 1)

        res_addr = res_item.tuser[0];
        ring_prod_res = res_addr - ring_address;

        `FAIL_IF_LOG(ring_prod_res != ring_prod_pat_internal,
            $sformatf("Ring prod mismatch. Res: %0d Pat: %0d Full addr: %h",
                       ring_prod_res, ring_prod_pat_internal, res_addr))
        space_in_ring = ring_prod_pat_internal < ring_cons_idx
                            ? ring_cons_idx - ring_prod_pat_internal - 1
                            : ring_size - ring_prod_pat_internal + ring_cons_idx - 1;
        `FAIL_IF_LOG(space_in_ring < WordBytesWidth,
          $sformatf({"Msg does not fit in ring. space_in_ring: %0d ring_prod_pat: %0d",
                     "ring_cons_idx: %0d ring_size: %0d WordBytesWidth: %0d"},
                space_in_ring, ring_prod_pat_internal, ring_cons_idx, ring_size, WordBytesWidth))

        ring_prod_updates++;
        ring_prod_pat_internal <= (ring_prod_pat_internal + WordBytesWidth) % ring_size;
      end
    endtask : analyzer

    function void run_ring_prod_analyzer;
      fork
        delay = new();
        ring_prod_analyzer = process::self();
        forever begin
          `FAIL_IF(!delay.randomize() with {v < 5;})
          repeat (delay.v) @(posedge clk);
          if (ring_prod_updates) begin
            ack_write();
            ring_prod_updates--;
          end else begin
            @(posedge clk);
          end
        end
      join_none
    endfunction : run_ring_prod_analyzer

    function void stop_ring_prod_analyzer();
      if (ring_prod_analyzer != null) begin
        ring_prod_analyzer.kill();
      end
    endfunction : stop_ring_prod_analyzer

    task ack_write;
      write_done <= 1'b1;
      @(posedge clk);
      ring_prod_pat <= (ring_prod_pat + WordBytesWidth) % ring_size;
      write_done <= 1'b0;
    endtask : ack_write

  endclass : ap_beat_impl


  class cons_impl;
    rand int unsigned value;
    rand int unsigned delay;

    constraint c {
      delay < 200;
      value % WordBytesWidth == 0;
    }
  endclass : cons_impl

  class ring_cons_driver;
    protected process main;
    cons_impl ring_cons_incr;
    int unsigned to_consume;

    function void run();
      fork
        begin
          ring_cons_incr = new();
          main = process::self();
          forever begin
            to_consume = ring_prod_pat >= ring_cons_idx
                         ? ring_prod_pat - ring_cons_idx
                         : ring_size - ring_cons_idx + ring_prod_pat;
            `FAIL_IF_LOG(to_consume % WordBytesWidth != 0,
              $sformatf("To consume: %0d Ring prod(%0d) and cons(%0d) should change with %0d step",
                          to_consume, ring_prod_pat, ring_cons_idx, WordBytesWidth))

            if (to_consume > 0) begin
              `FAIL_IF(!ring_cons_incr.randomize() with {value <= to_consume;})
              repeat(ring_cons_incr.delay) @(posedge clk);
              ring_cons_idx <= (ring_cons_idx + ring_cons_incr.value) % ring_size;
            end
            else begin
              @(posedge clk);
            end
          end
        end
      join_none
    endfunction : run

    function void stop();
      if(main != null) begin
        main.kill();
      end
    endfunction : stop

  endclass : ring_cons_driver

  ap_impl ap;
  ap_beat_impl ap_beat;
  ring_cons_driver ring_cons_drv;

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
      size > WordWidth;
      delay > 500;
      delay < 1000;
    }
  endclass : cfg_impl

  task randomize_cfg();
    cfg_impl cfg;
    cfg = new();
    `FAIL_IF(!cfg.randomize())
    repeat (cfg.delay) @(posedge clk);
    ring_prod_idx_rst <= 1'b0;
    ring_enable <= 1'b0;
    ring_cons_drv.stop();
    repeat (cfg.delay_before) begin
      while (!axis_data_out.tready) @(posedge clk);
      @(posedge clk);
    end
    ring_address <= cfg.addr;
    ring_cons_idx <= '0;
    ring_size <= cfg.size;
    @(posedge clk);
    ring_prod_idx_rst <= 1'b1;
    @(posedge clk);
    ring_prod_idx_rst <= 1'b0;
    repeat (cfg.delay_after) @(posedge clk);
    ap_beat.ring_disable();
    ring_cons_drv.run();
    ring_enable <= 1'b1;
  endtask : randomize_cfg;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    data_in.init();
    data_out.init();

    ap = new();
    ap_beat = new();
    ring_cons_drv = new();
    data_out.core.add_ap2pkt(ap);
    data_out.core.add_ap2transfer(ap_beat);
    data_in.core.run_phase();
    data_out.core.run_phase();
  endfunction

  task setup();
    svunit_ut.setup();
    rst <= 1'b1;
    repeat(10) @(posedge clk);
    rst <= 1'b0;
    ring_enable <= 1'b0;
    ap_beat.run_ring_prod_analyzer();
    randomize_cfg();
    repeat(10) @(posedge clk);
  endtask

  task teardown();
    ap_beat.stop_ring_prod_analyzer();
    ap.clear();
    ap_beat.clear();
  endtask

  localparam ITER = 10000;

  task run_test;
    sample_item data;
    static int id = 0;

    fork
      ap_beat.analyzer();
      ap.analyzer();
    join_none

    repeat(ITER) begin
      data = new();
      `FAIL_IF(!data.randomize())
      ap.add_pat(data);
      data.is_posted = 0;
      data_in.core.send_item(data);
    end
    while (!ap.is_empty()) @(posedge clk);
  endtask : run_test

  `SVUNIT_TESTS_BEGIN
    `SVTEST(output_always_ready)
      data_in.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      data_out.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      fork
        run_test();
        forever begin
          randomize_cfg();
        end
      join_any
    `SVTEST_END

    `SVTEST(output_ready_randomized)
      data_in.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      data_out.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      fork
        run_test();
        forever begin
          randomize_cfg();
        end
      join_any
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : dma_data_writer_unit_test
