/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////
// Vip interface definition //
//////////////////////////////


// Interface: gvip_axis_if
//
// It could be used in testbench to simplify vip instantiation
// With axis instantion in it, it could be connected
// to dut's gaxis_if interface
// N - number of bytes
// I - tid width
// D - tdest width
// U_T - tuser type
// NAME - string with vip name
// CORE_TYPE - one of VIPs type (MASTER/SLAVE/MONITOR)
// item - item type definition that matches interface -
//        for some simulators is requied to have single point of type definition
//        so in such case type can by pass to VIP
// clk - clock on which gaxis_if interface works
// rst - reset of gaxis_if interface
interface gvip_axis_if #(
    parameter int N = 1,
    parameter int I = 1,
    parameter int D = 1,
    parameter type U_T = logic[0:0], // tuser type
    parameter string NAME = "unnamed gvip_axis_if",
    parameter gvip_axis_pkg::gvip_type_e CORE_TYPE = gvip_axis_pkg::MASTER,
    parameter type item = gvip_axis_item_pkg::item #(N, I, D, U_T)
) (
    input logic clk,
    input logic rst
);

  // Item which match type with vip
  // in XILINX_SIMULATOR there need to be single place to
  // typdef item so it cannot be in the vip interface,
  // because test would need to recreate same item
`ifndef XILINX_SIMULATOR
  typedef gvip_axis_item_pkg::item #(N, I, D, U_T) item_t;
`endif

  gaxis_if #(N, I, D, U_T) axis();

  gclk_if clk_i(.clk(clk), .rst(rst));

  gvip_axis_pkg::core #(N, I, D, U_T, item) core;

  // Function: init
  //
  // Calls core class constructor. Use it to initialize vip.
  // vip_cfg  - optional configuration object (please check: gvip_config at gvip_axis_pkg.sv)
  function automatic void init(gvip_axis_pkg::gvip_config vip_cfg = null);
    core = new(NAME, axis, clk_i, CORE_TYPE, vip_cfg);
  endfunction : init

endinterface : gvip_axis_if
