/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// I2S serializer
// Translates data incomming on axis_i to i2s interface.
//
// Module uses oversampling strategy to interact
// with i2s interface - synchronizes the i2s.clk
// and whole i2s interface to fast clock frequency
// (clk input port).

module i2s_tx_serializer #(
  parameter int CounterWidth = 28
) (
    input  logic        clk,
    input  logic        rst,
    axis_i.agent        i_axis_in,
    i2s_if.transmitter  i_i2s_out,
    output logic [CounterWidth-1:0] clk_counter,
    output logic [CounterWidth-1:0] ws_counter
);
  // parameters and typedefs
  import i2s_pkg::I2sMaxSampleWidth;
  import i2s_pkg::sample_t;

  typedef enum logic [1:0] {
    kIdle               = 2'd0,
    kDelay              = 2'd1,
    kSendLeftChannel    = 2'd2,
    kSendRightChannel   = 2'd3
  } i2s_tx_state_e;

  // signal and helper interfaces declaration
  i2s_if                   i_i2s_d1();
  i2s_if                   i_i2s_d2();
  i2s_if                   i_i2s_d3();
  i2s_if                   i_i2s_out_next();
  i2s_tx_state_e           state;
  i2s_tx_state_e           state_next;
  sample_t                 data_to_send;
  sample_t                 data_to_send_next;
  logic                    i2s_clk_rising;
  logic                    i2s_clk_falling;
  logic                    ws_d;
  logic                    ws_falling;
  logic                    ws_change;
  logic [CounterWidth-1:0] system_clock_counter;
  logic [CounterWidth-1:0] clk_counter_i;
  logic [CounterWidth-1:0] ws_counter_i;

  // probe control of i2s (clk and ws) on clk
  always_ff @(posedge clk) begin : probe_i2s
    i_i2s_d1.clk <= i_i2s_out.clk;
    i_i2s_d1.ws  <= i_i2s_out.ws;
  end

  // 2-flop synchronizer stage
  always_ff @(posedge clk) begin : sync_flops_i2s
    i_i2s_d2.clk <= i_i2s_d1.clk;
    i_i2s_d3.clk <= i_i2s_d2.clk;
    i_i2s_d2.ws  <= i_i2s_d1.ws;
    i_i2s_d3.ws  <= i_i2s_d2.ws;
  end

  // detect WS signal edge (synchronous to i2s.clk)
  always_ff @(posedge clk) begin : detect_ws_edge
    if (i2s_clk_rising) begin
      ws_d <= i_i2s_d3.ws;
    end
  end

  // helper signals assignment
  assign i2s_clk_rising   = !i_i2s_d3.clk &&  i_i2s_d2.clk;
  assign i2s_clk_falling  =  i_i2s_d3.clk && !i_i2s_d2.clk;
  assign ws_change        =  ws_d  ^  i_i2s_d3.ws;
  assign ws_falling       =  ws_d && !i_i2s_d3.ws;

  // control tready asynchronously based on state machine
  assign i_axis_in.tready = (state == kIdle) ||
      (state == kSendRightChannel && i2s_clk_rising && ws_change);

  always_ff @(posedge clk) begin : fsm_state_ff
    if (rst) begin
      state <= kIdle;
    end else begin
      state <= state_next;
    end
  end

  always_ff @(posedge clk) begin : fsm_regs_ff
    if (rst) begin
      data_to_send   <= '0;
      i_i2s_out.data <= '0;
    end else begin
      data_to_send   <= data_to_send_next;
      i_i2s_out.data <= i_i2s_out_next.data;
    end
  end

  // main FSM to drive i2s data
  always_comb begin : fsm
    state_next          = state;
    data_to_send_next   = data_to_send;
    i_i2s_out_next.data = i_i2s_out.data;
    unique case (state)
      kIdle: begin
        if (i_axis_in.tvalid) begin
          data_to_send_next = i_axis_in.tdata;
          state_next        = kDelay;
        end
      end
      kDelay: begin
        if (i2s_clk_rising) begin
          if (ws_falling) begin
            state_next = kSendLeftChannel;
          end
        end
      end
      kSendLeftChannel: begin
        if (i2s_clk_falling) begin
          i_i2s_out_next.data    = data_to_send.left[I2sMaxSampleWidth-1];
          data_to_send_next.left = data_to_send.left << 1;
        end

        if (i2s_clk_rising) begin
          if (ws_change) begin
            state_next = kSendRightChannel;
          end
        end
      end
      kSendRightChannel: begin
        if (i2s_clk_falling) begin
          i_i2s_out_next.data     = data_to_send.right[I2sMaxSampleWidth-1];
          data_to_send_next.right = data_to_send.right << 1;
        end

        if (i2s_clk_rising) begin
          if (ws_change) begin
            if (i_axis_in.tvalid) begin
              data_to_send_next = i_axis_in.tdata;
              state_next        = kSendLeftChannel;
            end else begin
              state_next   = kIdle;
            end
          end
        end
      end
      default: begin
        state_next = kIdle;
      end
    endcase
  end

  // counters to check i2s clk and ws frequency
  always_ff @(posedge clk) begin
    if (rst) begin
      system_clock_counter <= '0;
      clk_counter_i <= '0;
      ws_counter_i <= '0;
    end else begin
      system_clock_counter <= system_clock_counter + 1;

      if (i2s_clk_rising) begin
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

endmodule : i2s_tx_serializer
