/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

////////////////////////////////////
// Vip array interface definition //
////////////////////////////////////

// Interface: gvip_axis_array_if
//
// It could be used in testbench to simplify vip instantiation
// With axis array instantion in it, it could be connected
// to dut's gaxis_if interface array
// NUM - number of gaxis_if interfaces
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
// rst - clock on which gaxis_if interface works
 interface gvip_axis_array_if #(
    parameter int NUM = 1,
    parameter int N = 1,
    parameter int I = 1,
    parameter int D = 1,
    parameter type U_T = logic[0:0],
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

  gaxis_if #(N, I, D, U_T) axis[NUM-1:0]();

  gclk_if clk_i(.clk(clk), .rst(rst));

  gvip_axis_pkg::core #(N, I, D, U_T, item) core[NUM-1:0];

  // Base class used to register axis interfaces in classes
  virtual class register_init_base;
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif;
  endclass : register_init_base

  // Array of classes with axis interfaces registered in it
  register_init_base inits_queue[int];

  // Class used to register axis interfaces in classes
  class register_init extends register_init_base;
    function new (
        virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
        int i,
        ref register_init_base init_map[int]);
      this.vif = vif;
      init_map[i] = this;
    endfunction : new
  endclass : register_init


  // Function: init_single
  //
  // Call core class constructor for single vip. Use it to initialize specific vip.
  // i  - sets vip to initialize
  // vip_cfg  - optional configuration object (please check: gvip_config)
  function automatic void init_single(
      int i,
      gvip_axis_pkg::gvip_config vip_cfg = null);
    core[i] = new($sformatf("%s_%0d", NAME, i), inits_queue[i].vif, clk_i, CORE_TYPE, vip_cfg);
  endfunction : init_single


  // Function: init
  //
  // Call core class constructor for all vips. Use it to initialize all vips.
  // vip_cfg  - optional configuration object (please check: gvip_config)
  // call core class constructor for all vips. Use it to initialize all vips
  function automatic void init(gvip_axis_pkg::gvip_config vip_cfg = null);
    foreach (core[i]) begin
      init_single(i, vip_cfg);
    end
  endfunction : init

  // Register all axis interfaces in classes
  for (genvar i = 0; i < NUM; i++) begin : ARRAY
    register_init init_obj = new(axis[i], i, inits_queue);
  end

endinterface : gvip_axis_array_if
