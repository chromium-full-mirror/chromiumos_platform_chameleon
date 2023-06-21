/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Module receives i2s data. Serialize it and transmits to axi stream interface

module i2s_rx_deserializer #(
  parameter int CounterWidth = 28
) (
    input logic                     clk,
    input logic                     rst,
    i2s_if.receiver                 i_i2s_in,
    axis_i.host                     i_axis_samples_out,
    output logic                    overflow,
    output logic [CounterWidth-1:0] clk_counter,
    output logic [CounterWidth-1:0] ws_counter
);
  // parameters and typedefs
  import i2s_pkg::sample_t;
  import i2s_pkg::I2sMaxSampleWidth;
  import i2s_registers_pkg::counter_t;

  localparam int SampleCntWidth = $clog2(I2sMaxSampleWidth + 1);

  i2s_if i_i2s_d();
  i2s_if i_i2s_d2();
  i2s_if i_i2s_d3();

  typedef enum logic[1:0] {
    kIdle   = 2'd0,
    kLeft   = 2'd1,
    kRight  = 2'd2,
    kOutput = 2'd3
  } state_e;

  // signal declarations
  state_e                    state;
  state_e                    state_next;
  logic                      i2s_valid;
  logic                      ws_rising;
  logic                      ws_falling;
  logic                      ws_d;
  sample_t                   samples_data;
  sample_t                   samples_data_next;
  sample_t                   samples_out_next;
  logic [SampleCntWidth-1:0] bit_cnt;
  logic [SampleCntWidth-1:0] bit_cnt_next;
  logic                      overflow_next;
  logic                      samples_valid_next;
  logic [CounterWidth-1:0]   system_clock_counter;
  logic [CounterWidth-1:0]   clk_counter_i;
  logic [CounterWidth-1:0]   ws_counter_i;

  // probe i2s bus with clk
  always_ff @(posedge clk) begin
    i_i2s_d.clk  <= i_i2s_in.clk;
    i_i2s_d.ws   <= i_i2s_in.ws;
    i_i2s_d.data <= i_i2s_in.data;
  end

  // 2-flop synchronizer stage
  always_ff @(posedge clk) begin : sync_flops_i2s
    i_i2s_d2.clk  <= i_i2s_d.clk;
    i_i2s_d3.clk  <= i_i2s_d2.clk;
    i_i2s_d2.ws   <= i_i2s_d.ws;
    i_i2s_d3.ws   <= i_i2s_d2.ws;
    i_i2s_d2.data <= i_i2s_d.data;
    i_i2s_d3.data <= i_i2s_d2.data;
  end

  // helper signals
  assign i2s_valid  = !i_i2s_d3.clk && i_i2s_d2.clk;
  assign ws_rising  = !ws_d &&  i_i2s_d3.ws;
  assign ws_falling =  ws_d && !i_i2s_d3.ws;

  // unused out signals
  assign i_axis_samples_out.tuser = '0;
  assign i_axis_samples_out.tkeep = 1'b1;
  assign i_axis_samples_out.tlast = 1'b1;

  // detect WS signal edge (synchronous to i2s.clk)
  always_ff @(posedge clk) begin : detect_ws_edge
    if (i2s_valid) begin
      ws_d <= i_i2s_d3.ws;
    end
  end

  always_ff @(posedge clk) begin : fsm_state_ff
    if (rst) begin
      state <= kIdle;
    end else begin
      state <= state_next;
    end
  end

  always_ff @(posedge clk) begin : fsm_regs_ff
    if (rst) begin
      i_axis_samples_out.tvalid <= '0;
      i_axis_samples_out.tdata  <= '0;
      samples_data              <= '0;
      overflow                  <= '0;
      bit_cnt                   <= '0;
    end else begin
      i_axis_samples_out.tvalid <= samples_valid_next;
      i_axis_samples_out.tdata  <= samples_out_next;
      samples_data              <= samples_data_next;
      overflow                  <= overflow_next;
      bit_cnt                   <= bit_cnt_next;
    end
  end

  // main fsm
  // I2S bus spec is available at https://www.sparkfun.com/datasheets/BreakoutBoards/I2SBUS.pdf
  // Implement standard i2s handling mode (not left/right justified one).
  always_comb begin : fsm
    state_next         = state;
    samples_valid_next = i_axis_samples_out.tvalid;
    samples_out_next   = i_axis_samples_out.tdata;
    samples_data_next  = samples_data;
    bit_cnt_next       = bit_cnt;
    overflow_next      = overflow;
    unique case (state)
      // kIdle - wait for i2s_valid and ws_falling to start sampling left channel
      kIdle: begin
        samples_data_next = '0;
        if (i_axis_samples_out.tready) begin
          samples_valid_next = 1'b0;
        end
        if (i2s_valid) begin
          if (ws_falling) begin
            state_next = kLeft;
          end
        end
      end
      // kLeft: read bit from i2s bus when valid and store it (starting from msb)\
      // in samples_data.left at proper bit position.
      // If ws_rising occurs, zero counter and switch to kRight.
      kLeft: begin
        if (i_axis_samples_out.tready) begin
          samples_valid_next = 1'b0;
        end
        if (i2s_valid) begin
          if (bit_cnt != I2sMaxSampleWidth) begin
            samples_data_next.left[I2sMaxSampleWidth - 1 - bit_cnt] = i_i2s_d3.data;
            bit_cnt_next = bit_cnt + 1;
          end
          if (ws_rising) begin
            state_next = kRight;
            bit_cnt_next = '0;
          end
        end
      end
      // kRight: read bit from i2s bus when valid and store it (starting from msb)
      // in samples_data.right at proper bit position.
      // If ws_falling occurs, zero counter and switch to kOutput.
      kRight: begin
        if (i_axis_samples_out.tready) begin
          samples_valid_next = 1'b0;
        end
        if (i2s_valid) begin
          if (bit_cnt != I2sMaxSampleWidth) begin
            samples_data_next.right[I2sMaxSampleWidth - 1 - bit_cnt] = i_i2s_d3.data;
            bit_cnt_next = bit_cnt + 1;
          end
          if (ws_falling) begin
            state_next = kOutput;
            bit_cnt_next = '0;
          end
        end
      end
      // kOutput: Set output valid, check overflow and switch to kLeft.
      kOutput: begin
        state_next = kLeft;
        if (i_axis_samples_out.tready) begin
          samples_valid_next = 1'b0;
        end
        if (i_axis_samples_out.tvalid) begin
          overflow_next = 1'b1;
        end

        samples_valid_next = 1'b1;
        samples_out_next   = samples_data;
      end
      default: begin
        state_next = kIdle;
      end
    endcase // state
  end

  // counters to check i2s clk and ws frequency
  always_ff @(posedge clk) begin
    if (rst) begin
      system_clock_counter <= '0;
      clk_counter_i <= '0;
      ws_counter_i <= '0;
    end else begin
      system_clock_counter <= system_clock_counter + 1;

      if (i2s_valid) begin
        clk_counter_i <= clk_counter_i + 1;
        if (ws_falling) begin
          ws_counter_i <= ws_counter_i + 1;
        end
      end

      if (system_clock_counter == 0) begin
        clk_counter_i <= '0;
        ws_counter_i <= '0;
        clk_counter <= clk_counter_i;
        ws_counter <= ws_counter_i;
      end
    end
  end

endmodule : i2s_rx_deserializer
