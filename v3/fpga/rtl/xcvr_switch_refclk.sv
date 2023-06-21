/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Module to reconfigure refclk for GXB from rx_cdr_refclk0 to rx_cdr_refclk1

module xcvr_switch_refclk #(
    parameter int Lanes = 3
) (
    input  logic             clk,
    input  logic             rst,

    avalon_mm_i.host         i_xcvr_rcfg,
    input  logic [Lanes-1:0] cal_busy,
    output logic             reconfig_en
);

  localparam int CdrLookupRefclk1Addr = 12'h16b;
  localparam int CdrMuxAddr           = 12'h141;
  localparam int AvalonAddrWidth      = 12;
  localparam int AvalonDataWidth      = 32;

  logic switch_ref_clk_request;
  logic switch_ref_clk_done;
  logic [Lanes-1:0] cal_busy_d;
  logic [Lanes-1:0] cal_busy_done;
  logic last_channel;
  logic [1:0] channel;
  logic [AvalonDataWidth-1:0] readdata;
  logic [AvalonAddrWidth-3:0] addr;

  typedef enum logic [2:0] {
    kIdle         = 0,
    kRead         = 1,
    kMod          = 2,
    kWrite        = 3,
    kNext         = 4,
    kWaitForCalib = 5,
    kDone         = 6
  } reconfig_state_e;

  reconfig_state_e state;
  reconfig_state_e state_next;

  always_comb begin : next_state
    state_next = state;

    case(state)
      kIdle: begin
        if (reconfig_en) begin
          state_next = kRead;
        end else begin
          state_next = kIdle;
        end
      end

      kRead: begin
        if (i_xcvr_rcfg.waitrequest) begin
          state_next = kRead;
        end else begin
          state_next = kMod;
        end
      end

      kMod: begin
        state_next = kWrite;
      end

      kWrite: begin
        if (i_xcvr_rcfg.waitrequest) begin
          state_next = kWrite;
        end else begin
          if (last_channel) begin
            state_next = kWaitForCalib;
          end else begin
            state_next = kNext;
          end
        end
      end

      kNext: begin
        state_next = kRead;
      end

      kWaitForCalib: begin
        if (&cal_busy_done) begin
          state_next = kDone;
        end else begin
          state_next = kWaitForCalib;
        end
      end

      kDone: begin
        state_next = kIdle;
      end

    endcase
  end

  always_ff @(posedge clk) begin : state_machine_avalon
    if (rst) begin
      state <= kIdle;
    end else begin
      state <= state_next;
    end
  end

  always_ff @(posedge clk) begin : save_readdata
    if (rst) begin
      readdata <= '0;
    end else begin
      if (state_next == kMod) begin
        readdata <= i_xcvr_rcfg.readdata;
      end
    end
  end

  always_ff @(posedge clk) begin : read
    if (rst) begin
      i_xcvr_rcfg.read = '0;
    end else begin
      if (state_next == kRead) begin
        i_xcvr_rcfg.read <= 1'b1;
      end else begin
        i_xcvr_rcfg.read <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin : write
    if (rst) begin
      i_xcvr_rcfg.write = '0;
    end else begin
      if (state_next == kWrite) begin
        i_xcvr_rcfg.write <= 1'b1;
      end else begin
        i_xcvr_rcfg.write <= 1'b0;
      end
    end
  end

  always_comb begin : address
    if (state == kRead) begin
      addr = CdrLookupRefclk1Addr;
    end else if (state == kWrite) begin
      addr = CdrMuxAddr;
    end else begin
      addr = '0;
    end
  end

  assign i_xcvr_rcfg.cs = 1'b1;
  assign i_xcvr_rcfg.byteenable = 4'hf;
  assign i_xcvr_rcfg.address = {channel, addr};
  assign i_xcvr_rcfg.writedata = readdata;
  assign i_xcvr_rcfg.burstcount = 1;

  always_ff @(posedge clk) begin : last_channel_idx
    if (rst) begin
      channel <= '0;
      last_channel <= '0;
    end else begin
      if (state == kIdle) begin
        channel <= '0;
      end else if (state == kNext && ~last_channel) begin
        channel <= channel + 1;
      end
      last_channel <= channel == (Lanes-1);
    end
  end

  always_ff @(posedge clk) begin : switch_ref_clk_flags
    if (rst) begin
      switch_ref_clk_done    <= 1'b0;
      switch_ref_clk_request <= 1'b1;
    end else begin
      if (state_next == kWaitForCalib) begin
        switch_ref_clk_request <= 1'b0;
      end
      if (state_next == kDone) begin
        switch_ref_clk_done    <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin : trigger_reconfig
    if (rst) begin
      reconfig_en <= 1'b0;
    end else begin
      if (&cal_busy_done && switch_ref_clk_request) begin : trigger_start
        reconfig_en <= 1'b1;
      end
      if (switch_ref_clk_done) begin
        reconfig_en <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin
    cal_busy_d <= cal_busy;
  end

  always_ff @(posedge clk) begin : calibration_done
    if (rst) begin
      cal_busy_done <= '0;
    end else begin
      if (~cal_busy_done[0]) begin
        cal_busy_done[0] <= ~cal_busy[0] & cal_busy_d[0];
      end else if (state_next == kWaitForCalib && cal_busy[0]) begin
        cal_busy_done[0] <= 1'b0;
      end
      if (~cal_busy_done[1]) begin
        cal_busy_done[1] <= ~cal_busy[1] & cal_busy_d[1];
      end else if (state_next == kWaitForCalib && cal_busy[1]) begin
        cal_busy_done[1] <= 1'b0;
      end
      if (~cal_busy_done[2]) begin
        cal_busy_done[2] <= ~cal_busy[2] & cal_busy_d[2];
      end else if (state_next == kWaitForCalib && cal_busy[2]) begin
        cal_busy_done[2] <= 1'b0;
      end
    end
  end

endmodule : xcvr_switch_refclk
