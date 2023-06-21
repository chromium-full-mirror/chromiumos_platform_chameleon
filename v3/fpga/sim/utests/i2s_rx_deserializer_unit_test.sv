/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

// Unit test for i2s_rx_deserializer module.
//
// Generate data in i2s_vip_if, translate it in unit test
// to pattern comparable to output data on axis_samples interface.
//
// Fail test in case of any bit mismatch between pattern and output data.
module i2s_rx_deserializer_unit_test;

  //Unit test name
  parameter string name = "i2s_rx_deserializer_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  svunit_testcase svunit_ut;
  import i2s_pkg::sample_t;

  //Clocking
  logic clk = 1'b0;
  logic rst;
  logic clk_i2s = 1'b0;

  localparam int ClkPeriod = 2;
  localparam int I2sClkPeriod = 20;

  localparam int ClkRatio = I2sClkPeriod/ClkPeriod;

  // the value should not be too big - test would be too long
  // and it should not be too small - there would be rouning error
  // in counter verification
  localparam int CounterWidth = 18;
  localparam int CounterTolerance = 1;

  default clocking clk_default @(posedge clk); endclocking
  `SVUNIT_CLK_GEN(clk, ClkPeriod)
  `SVUNIT_CLK_GEN(clk_i2s, I2sClkPeriod)

  //Inputs and outputs
  gvip_axis_if #(.N($bits(sample_t)/8), .I(0), .D(0), .NAME("samples"),
                 .CORE_TYPE(gvip_axis_pkg::SLAVE)) samples(clk, rst);
  i2s_vip_if #(.Name("i2s"), .IsTransmitter(1)) i2s(clk_i2s, rst);

  logic overflow;
  logic [CounterWidth-1:0] clk_counter;
  logic [CounterWidth-1:0] ws_counter;

  `AXIS_TO_GAXIS_VIP(samples, logic)

  // This is the UUT that we're running the Unit Tests on
  i2s_rx_deserializer #(
    .CounterWidth      ( CounterWidth )
  ) dut (
    .clk               ( clk          ),
    .rst               ( rst          ),
    .i_i2s_in          ( i2s.inf      ),
    .i_axis_samples_out( axis_samples ),
    .overflow          ( overflow     ),
    .clk_counter       ( clk_counter  ),
    .ws_counter        ( ws_counter   )
  );

  typedef samples.item_t axis_item_t;
  typedef i2s.item_t i2s_item_t;
  i2s_item_t i2s_data;

  //write task implementation <- runs when tlast is asserted on processed data
  class samples_ap_impl implements gvip_axis_pkg::analysis_port_ic#(axis_item_t);
    i2s_item_t pat_queue[$];
    axis_item_t results[$];

    virtual function void write(input axis_item_t item);
      results.push_back(item);
    endfunction : write

    task analyzer();
      forever begin
        i2s_item_t pat;
        axis_item_t res;
        sample_t pat_sample;
        sample_t res_sample;

        wait(results.size());
        res = results.pop_front();

        `FAIL_IF_LOG(pat_queue.size() == 0, "more packets received than sent")
        pat = pat_queue.pop_front();

        pat_sample.left = pat.left;
        pat_sample.right = pat.right;
        `FAIL_IF_LOG(res.tdata.size() != 1,
                     $sformatf("item size mismatch: res: %0d should be always 1", res.tdata.size()))
        res_sample = res.tdata[0];
        `FAIL_IF_LOG(res_sample != pat_sample,
                     $sformatf("Sample mismatch. Res: %h Pat: %h", res_sample, pat_sample))
      end
    endtask : analyzer

    function void add_pat(i2s_item_t pat);
      sample_t pat_sample;
      pat_sample.left = pat.left;
      pat_sample.right = pat.right;
      pat_queue.push_back(pat.clone());
    endfunction : add_pat

    function void clean();
      pat_queue.delete();
      results.delete();
    endfunction : clean

    function bit is_empty();
      return pat_queue.size() == 0;
    endfunction : is_empty

  endclass : samples_ap_impl

  class cycles_to_reset;
    rand int unsigned to_reset;

    constraint c_to_reset {
      to_reset dist {
        [1:10] := 10,
        [990:1000] := 10
      };
    }
  endclass : cycles_to_reset

  samples_ap_impl samples_ap;
  cycles_to_reset c_to_reset;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);
    i2s.init();
    samples.init();
    samples_ap = new();
    samples.core.add_ap2pkt(samples_ap);
    i2s.run_phase();
    samples.core.run_phase();
    c_to_reset = new();
  endfunction

  task setup();
    int after_reset;
    rst <= 1'b1;
    repeat(10) @(posedge clk);
    rst <= 1'b0;
    `FAIL_IF(!std::randomize(after_reset) with {after_reset < 100;})
    repeat(after_reset) @(posedge clk);
  endtask

  task teardown();
    i2s.clear();
    samples_ap.clean();
  endtask

  localparam int ITER = `ifdef CI_FAST 10 `else 100 `endif;

  `SVUNIT_TESTS_BEGIN

    // Randomize i2s_data, put it to:
    // - i2s (via write_item), which will serialize it properly and
    //   put on the i2s input bus of DUT,
    // - samples_ap (via add_pat), which, thanks to axis_proxy_analysis_port_ic
    //   implementation, will collect the output data from i_axis_samples_out
    //   and compare it with pattern submitted via add_pat.
    //
    // Do it ITER times.
    //
    // In case of any bit mismatch at samples_ap, test fails.
    //
    // Check if overflow occurs (in parallel), fail if it does.
    //
    // Test finishes when all patterns are processed in samples_ap.
    // Output of this test (axis bus) is always ready to receive data.
    `SVTEST(output_always_ready)
      samples.core.set_policy(gvip_policy_pkg::always_active::create(), 1);
      fork
        forever begin
          @(posedge clk);
          `FAIL_IF(overflow)
        end
      join_none
      repeat(ITER) begin
        i2s_data = new();
        `FAIL_IF(!i2s_data.randomize())
        samples_ap.add_pat(i2s_data);
        i2s.write_item(i2s_data);
      end

      disable fork;

      fork
        begin
          while (!samples_ap.is_empty()) @(posedge clk);
        end
        samples_ap.analyzer();
      join_any

    `SVTEST_END


    // Check overflow.
    //
    // Output from axis is not ready to receive data.
    //
    // Submit single pattern (as per output_always_ready test),
    // wait 2*i2s_data.ws_bclk_ratio*ClkRatio cycles (time of processing single i2s sample)
    // and verify lack of overflow (since there's first valid on output, waiting for tready).
    //
    // Submit second pattern, wait for processing, fail if there's no overflow
    // (should be, since there's not_ready on output and there's data to be processed)
    `SVTEST(overflow_check)
      samples.core.set_policy(gvip_policy_pkg::always_inactive::create(), 1);

      i2s_data = new();
      `FAIL_IF(!i2s_data.randomize())
      samples_ap.add_pat(i2s_data);
      i2s.write_item(i2s_data);
      repeat(2*i2s_data.ws_bclk_ratio*ClkRatio) @(posedge clk);
      `FAIL_IF(overflow)

      i2s_data = new();
      `FAIL_IF(!i2s_data.randomize())
      samples_ap.add_pat(i2s_data);
      i2s.write_item(i2s_data);
      repeat(2*i2s_data.ws_bclk_ratio*ClkRatio) @(posedge clk);
      `FAIL_IF(!overflow)
    `SVTEST_END

    // Similar to output_ready_randomized test, but do not wait for all patterns
    // on output, just randomly end test (which will trigger reset for module).
    //
    // Repeat this test multiple (5) times to make sure that if reset
    // is triggered at some random time (in some random FSM state),
    // the next incomming data is verified and correct.
    //
    // Check if overflow occurs (in parallel), fail if it does.
    repeat(10)
      `SVTEST(reset)
        samples.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
        `FAIL_IF(!c_to_reset.randomize());

        fork
          forever begin
            @(posedge clk);
            `FAIL_IF(overflow)
          end
        join_none
        repeat(5) begin
          i2s_data = new();
          `FAIL_IF(!i2s_data.randomize())
          samples_ap.add_pat(i2s_data);
          i2s.write_item(i2s_data);
        end

        fork
          begin
            while (!samples_ap.is_empty()) @(posedge clk);
          end
          samples_ap.analyzer();
        join_any

        repeat(c_to_reset.to_reset) @(posedge clk);
        disable fork;
      `SVTEST_END

    // Similar to reset test, but verify the state of the dut internal variables.
    `SVTEST(reset_koutput)
      samples.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      `FAIL_IF(!c_to_reset.randomize());

      fork
        forever begin
          @(posedge clk);
          `FAIL_IF(overflow)
        end
      join_none
      repeat(5) begin
        i2s_data = new();
        `FAIL_IF(!i2s_data.randomize())
        samples_ap.add_pat(i2s_data);
        i2s.write_item(i2s_data);
      end

      fork
        begin
          while (dut.state != dut.kRight || !dut.ws_falling || !dut.i2s_valid) @(posedge clk);
        end
        samples_ap.analyzer();
      join_any

      disable fork;
    `SVTEST_END

    // Similar test to output_always_ready, but output ready is randomly ready (not always).
    `SVTEST(output_ready_randomized)
      samples.core.set_policy(gvip_policy_pkg::random_std::create(), 1);
      fork
        forever begin
          @(posedge clk);
          `FAIL_IF(overflow)
        end
      join_none
      repeat(ITER) begin
        i2s_data = new();
        `FAIL_IF(!i2s_data.randomize())
        samples_ap.add_pat(i2s_data);
        i2s.write_item(i2s_data);
      end

      fork
        begin
          while (!samples_ap.is_empty()) @(posedge clk);
        end
        samples_ap.analyzer();
      join_any

      disable fork;
    `SVTEST_END

    // Check counters.
    //
    // Submit ITER number of data with same ws_bclk_ratio. Check if counter values are correct
    `SVTEST(counters_check)
      int unsigned clk_counter_pattern;
      int unsigned ws_counter_pattern;

      samples.core.set_policy(gvip_policy_pkg::always_active::create(), 1);

      fork
        forever begin
          @(posedge clk);
          `FAIL_IF(overflow)
        end
      join_none
      i2s_data = new();
      `FAIL_IF(!i2s_data.randomize())
      repeat(400) begin
        samples_ap.add_pat(i2s_data);
        i2s.write_item(i2s_data);
      end

      fork
        begin
          while (!samples_ap.is_empty()) @(posedge clk);
        end
        samples_ap.analyzer();
      join_any

      disable fork;

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

endmodule : i2s_rx_deserializer_unit_test
