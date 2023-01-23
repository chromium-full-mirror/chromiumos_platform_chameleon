/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////
// Vip interface definition //
//////////////////////////////


// Interface: gvip_axil_if
//
// It could be used in testbench to simplify vip instantion
// With axil instantion in it, it could be connected
// to dut's gaxil_if interface
//   N         - number of bytes of tdata
//   A         - address signal width
//   CORE_TYPE - one of VIPs type (gvip::MASTER/gvip::SLAVE/gvip::MONITOR)
//   item_t    - item type definition that matches interface -
//               for some simulators is requied to have single point of
//               type definition so in such case type can by pass to VIP
// clk - clock on which gaxil_if interface works
// rst - reset of gaxil_if interface
 //
interface gvip_axil_if #(
    parameter int N=1,
    parameter int A=1,
    parameter string NAME = "unnamed gvip_axil_if",
    parameter gvip_axil_types_pkg::gvip::type_e CORE_TYPE = gvip_axil_types_pkg::gvip::MASTER,
    parameter type item = gvip_axil_item_pkg::item #(N, A)
) (
    input logic clk,
    input logic rst
);

  // Item which match type with vip
  // in XILINX_SIMULATOR there need to be single place to
  // typdef item so it cannot be in the vip interface,
  // because test would need to recreate same item
`ifndef XILINX_SIMULATOR
  typedef gvip_axil_item_pkg::item #(N, A) item_t;
`endif

  gaxil_if #(N, A) axil();

  gclk_if clk_i(.clk(clk), .rst(rst));

  gvip_axil_pkg::core #(N, A, item) core;

  // Function: init
  //
  // Calls core class constructor. Use it to initialize vip.
  // vip_cfg  - optional configuration object (please check: gvip_config at gvip_axil_pkg.sv)
  function automatic void init(gvip_axil_pkg::gvip_config vip_cfg = null);
    core = new(NAME, axil, clk_i, CORE_TYPE, vip_cfg);
  endfunction : init

endinterface : gvip_axil_if
