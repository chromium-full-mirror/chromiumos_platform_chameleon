/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module i2s_irq #(
    parameter int CounterWidth = i2s_registers_pkg::CounterWidth
) (
    input  logic                       clk,
    input  logic                       rst,

    input  logic                       pulse,
    input  i2s_registers_pkg::irq_t    meta,
    output logic                       irq
);
  logic [CounterWidth-1:0] pulse_cnt;

  always_ff @(posedge clk) begin : pulse_counter
    if (rst) begin
      pulse_cnt <= '0;
    end else begin
      if (pulse_cnt == meta.frames_cnt) begin
        pulse_cnt <= '0;
      end else begin
        if (pulse) begin
          pulse_cnt <= pulse_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin : irq_generator
    if (rst) begin
      irq <= '0;
    end else begin
      irq <= (meta.enable && |meta.frames_cnt && pulse_cnt == meta.frames_cnt);
    end
  end

endmodule : i2s_irq
