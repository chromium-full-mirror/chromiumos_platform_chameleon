/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Test for i2s_tx_serializer module.
//
// SVUnit along with VIPs operate on the transaction level
// using constrained random verification.
//
// This means that unit test generates some pattern
// of data `axis_data`, which is submitted at:
// - `in_vip` (via `send_item` method)
// - `i2s_stream` (via `add_pattern` method).
//
// `axis_data` pattern for `in_vip` will allow the VIP to supply
// the `axis_data` pattern on input of the DUT (i2s_tx_serializer).
// `in_vip` is used here to drive the inputs to the DUT.
//
// `axis_data` pattern in `i2s_stream` will allow `i2s_stream` to verify
// (compare) data comming from DUT output (thanks to implemented
// `i2s_analysis_port_ic`) with the pattern.
// `i2s_stream` monitors output from the DUT (i2s bus) and triggers
// `write` task everytime the transaction on the i2s bus will finish.
//
// Basically the `write` task is responsible for verifying
// if the provided pattern on input to DUT matches expected
// output from it (and it contains `FAIL_IF macros).
//
// `axis_data` is just a pure data pattern (provided on `tdata` of AXI4Stream).
// All other signals on AXIS interface (for instance, `valid`/`ready`) logic
// are handled by the VIP (in this case, `in_vip`)

`include "svunit_defines.svh"

module i2s_tx_serializer_unit_test;

  //Unit test name
  parameter string name = "i2s_tx_serializer_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  svunit_testcase svunit_ut;
  import i2s_vip_pkg::*;

  //Package helper from RTL directory
  import i2s_pkg::sample_t;

  //Clocking
  logic clk = 1'b0;
  logic rst;
  logic clk_i2s = 1'b0;

  localparam int ClkPeriod = 5;       //200MHz
  localparam int I2sClkPeriod = 354;  //11.2896 MHz (MCLK) / 4, table 30, row 15

  localparam real ClkRatio = real'(I2sClkPeriod)/real'(ClkPeriod);

  // the value should not be too big - test would be too long
  // and it should not be too small - there would be rouning error
  // in counter verification
  localparam int CounterWidth = 18;
  localparam int CounterTolerance = 1;

  default clocking clk_default @(posedge clk); endclocking

  `SVUNIT_CLK_GEN(clk,     ClkPeriod)
  `SVUNIT_CLK_GEN(clk_i2s, I2sClkPeriod)

  //Inputs and outputs
  gvip_axis_if #(.N($bits(sample_t)/8), .I(0), .D(0), .NAME("axis_tx")) in_vip(clk, rst);
  i2s_vip_if #(.Name("i2s_tx"),  .IsTransmitter(0), .IsMaster(1)) i2s_vip(clk_i2s, rst);

  logic [CounterWidth-1:0] clk_counter;
  logic [CounterWidth-1:0] ws_counter;

  `GAXIS_VIP_TO_AXIS(in_vip, logic)

  // This is the DUT that we're running the Unit Tests on
  i2s_tx_serializer #(
    .CounterWidth ( CounterWidth  )
  ) dut (
      .clk        ( clk           ),
      .rst        ( rst           ),
      .i_axis_in  ( axis_in_vip   ),
      .i_i2s_out  ( i2s_vip.inf   ),
      .clk_counter( clk_counter   ),
      .ws_counter ( ws_counter    )
  );

  // Helper typedefs for given unit test AP implementation
  typedef in_vip.item_t axis_item_t;
  typedef i2s_vip.item_t i2s_item_t;

  class i2s_stream_ap implements i2s_analysis_port_ic;
    protected axis_item_t pattern_queue[$];

    function void add_pattern(axis_item_t pattern);
      pattern_queue.push_back(pattern.clone());
    endfunction : add_pattern

    function void delete_pattern_queue();
      pattern_queue.delete();
    endfunction : delete_pattern_queue

    function bit is_pattern_queue_empty();
      return (pattern_queue.size() == 0);
    endfunction : is_pattern_queue_empty

    virtual task write(i2s_item item);
      axis_item_t pattern;
      sample_t pattern_sample;

      `FAIL_IF(is_pattern_queue_empty())
      pattern = pattern_queue.pop_front();
      pattern_sample = {>>{pattern.tdata}};

      foreach (pattern_sample.left[i]) begin
        `FAIL_IF_LOG(pattern_sample.left[i] != item.left[i],
                     $sformatf("Mismatch in bit %d in left: pattern = 0x%0h, dut = 0x%0h",
                               i, pattern_sample.left, item.left))
      end

      foreach (pattern_sample.right[i]) begin
        `FAIL_IF_LOG(pattern_sample.right[i] != item.right[i],
                     $sformatf("Mismatch in bit %d in right: pattern = 0x%0h, dut = 0x%0h",
                               i, pattern_sample.right, item.right))
      end

    endtask : write

  endclass : i2s_stream_ap

  class cycles_to_reset;
      rand int unsigned to_reset;

    constraint c_to_reset {
      to_reset dist {
        [1:10] := 10,
        [990:1000] := 10
      };
    }
  endclass : cycles_to_reset

  i2s_stream_ap i2s_stream;
  i2s_item_t i2s_data;
  cycles_to_reset c_to_reset;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    in_vip.init();
    i2s_vip.init();

    i2s_data = new();
    i2s_data.repeat_this = -1;   // repeat until the end of test
    i2s_data.ws_bclk_ratio = 64; // for 44,1 kHz

    i2s_stream = new();
    i2s_vip.add_ap2mon(i2s_stream);

    c_to_reset = new();

    in_vip.core.run_phase();
    i2s_vip.run_phase();
  endfunction : build

  task setup();
    svunit_ut.setup();

    rst <= 1'b1;

    // Only for utest purposes, force at least two cycles
    // of BCLK (slow) reset.
    //
    // The reason behind it is that WS signal is set on negedge
    // of BCLK and probed by RTL on posedge of BCLK,
    // according to SSM2603 specification.
    //
    // So in hardware it's fine to have the first sample
    // from axis delayed by single i2s transaction period.
    //
    // In unit test it isn't, so there's a need to keep reset longer
    // (to make sure that first WS falling edge will be correctly probed
    // by RTL.
    repeat(2) @(posedge clk_i2s);
    rst <= 1'b0;
    @(posedge clk);

    // force i2s_vip to set ws
    i2s_vip.write_item(i2s_data);
  endtask : setup

  task teardown();
    i2s_stream.delete_pattern_queue();
  endtask : teardown

  localparam int ITER = `ifdef CI_FAST 10 `else 100 `endif;

  `SVUNIT_TESTS_BEGIN

    // Apply always_valid policy to have continuous data on input.
    // Randomize pattern, submit it for input of DUT (via in_vip)
    // and as pattern to compare with DUT output.
    //
    // Do it ITER times.
    // Fail if any sample bit on i2s does not match corresponding pattern.
    `SVTEST(always_valid)
      axis_item_t axis_data;
      in_vip.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      repeat(ITER) begin
          axis_data = new();
          `FAIL_IF(!axis_data.randomize() with {tdata.size()*N == 8;});
          i2s_stream.add_pattern(axis_data);
          in_vip.core.send_item(axis_data);
      end

      wait(i2s_stream.is_pattern_queue_empty());

    `SVTEST_END

    // Similar test to always_valid, but input data is randomly valid (not always).
    `SVTEST(random_valid)
      axis_item_t axis_data;
      in_vip.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      repeat(ITER) begin
          axis_data = new();
          `FAIL_IF(!axis_data.randomize() with {tdata.size()*N == 8;});
          i2s_stream.add_pattern(axis_data);
          in_vip.core.send_item(axis_data);
      end

      wait(i2s_stream.is_pattern_queue_empty());

    `SVTEST_END

    // Similar to random_valid test, but do not wait for all patterns
    // on output, just randomly end test (which will trigger reset for module).
    //
    // Repeat this test multiple (5) times to make sure that if reset
    // is triggered at some random time (in some random FSM state),
    // the next incomming data is verified and correct.
    repeat(5)
      `SVTEST(reset)
        axis_item_t axis_data;
        `FAIL_IF(!c_to_reset.randomize());

        in_vip.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
        repeat(ITER) begin
            axis_data = new();
            `FAIL_IF(!axis_data.randomize() with {tdata.size()*N == 8;});
            i2s_stream.add_pattern(axis_data);
            in_vip.core.send_item(axis_data);
        end

        repeat(c_to_reset.to_reset) @(posedge clk);

      `SVTEST_END

    // Check counters.
    //
    // Submit ITER number of data with same ws_bclk_ratio. Check if counter values are correct
    `SVTEST(counters_check)
      int unsigned clk_counter_pattern;
      int unsigned ws_counter_pattern;
      axis_item_t axis_data;

      in_vip.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      repeat(400) begin
          axis_data = new();
          `FAIL_IF(!axis_data.randomize() with {tdata.size()*N == 8;});
          i2s_stream.add_pattern(axis_data);
          in_vip.core.send_item(axis_data);
      end

      wait(i2s_stream.is_pattern_queue_empty());
      clk_counter_pattern = 2**CounterWidth/ClkRatio;
      ws_counter_pattern = clk_counter_pattern/i2s_data.ws_bclk_ratio;
      `FAIL_IF_LOG(clk_counter == 0 || ws_counter == 0,
                   "Too low test iterations or CounterWidth too big")

      // There is need to add small to do not report rounding errors
      `FAIL_IF(clk_counter < clk_counter_pattern - CounterTolerance)
      `FAIL_IF(clk_counter > clk_counter_pattern + CounterTolerance)
      `FAIL_IF(ws_counter < ws_counter_pattern - CounterTolerance)
      `FAIL_IF(ws_counter > ws_counter_pattern + CounterTolerance)
    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : i2s_tx_serializer_unit_test

