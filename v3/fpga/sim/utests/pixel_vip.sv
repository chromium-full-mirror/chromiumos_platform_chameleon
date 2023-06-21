/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/**
  Verification IP for pixel interface build on axis_vip_i
  with the same API and item object
 */
interface pixel_vip #(
  parameter int DataWidth = 60,
  parameter string Name = "unnamed interface",
  parameter int ByteAlignment = 1
)(
  input logic clk,
  input logic reset
);

  localparam AlignDataWidth = ByteAlignment ? DataWidth + (DataWidth % 8) : DataWidth;

  // all control signals will be put in axis tuser member
  typedef struct packed {
    logic hsync;
    logic vsync;
    logic scdt;
    logic de;
    int dbg_idx;
  } pixel_user_t;

  // interface signals
  logic [DataWidth-1:0] qd;
  logic                 de;
  logic                 hsync;
  logic                 vsync;
  logic                 scdt;


  gvip_axis_if #((AlignDataWidth)/8, 0, 0, pixel_user_t,
                 ({Name,".axis"}), gvip_axis_pkg::MASTER) axis(clk, reset);

  typedef gvip_axis_item_pkg::item #((AlignDataWidth)/8, 0, 0, pixel_user_t) axis_item_t;

  assign hsync = axis.axis.tuser.hsync;
  assign vsync = axis.axis.tuser.vsync;
  assign scdt = axis.axis.tuser.scdt;
  assign de = axis.axis.tvalid & axis.axis.tuser.de;
  assign qd = axis.axis.tdata;
  assign axis.axis.tready = 1'b1;

  function static void init();
    axis.init();
  endfunction : init

  function static void run_phase();
    axis.core.run_phase();
  endfunction : run_phase

  function static void clear();
    axis.core.clean();
  endfunction : clear

  task static send_item(axis_item_t data);
    axis.core.send_item(data);
  endtask : send_item

endinterface : pixel_vip
