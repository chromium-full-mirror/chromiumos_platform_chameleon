/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////
// Vip interface definition //
//////////////////////////////


// Interface: gvip_aximm_if
//
// It could be used in testbench to simplify vip instantion
// With aximm instantion in it, it could be connected
// to dut's gaximm_if interface
//   N         - number of bytes of tdata
//   I         - id signal width
//   A         - address signal width
//   U_REQ     - awuser and aruser type
//   U_DATA    - wuser and ruser type
//   U_RESP    - buser type
//   CORE_TYPE - one of VIPs type (gvip::MASTER/gvip::SLAVE/gvip::MONITOR)
//   item_t    - item type definition that matches interface -
//               for some simulators is requied to have single point of
//               type definition so in such case type can by passed to VIP
// clk - clock on which gaximm_if interface works
// rst - reset of gaximm_if interface
 //
interface gvip_aximm_if #(
    parameter int N=1,
    parameter int I=1,
    parameter int A=1,
    parameter type U_REQ=logic[0:0],
    parameter type U_DATA=logic[0:0],
    parameter type U_RESP=logic[0:0],
    parameter string NAME = "unnamed gvip_aximm_if",
    parameter gvip_aximm_types_pkg::gvip::type_e CORE_TYPE = gvip_aximm_types_pkg::gvip::MASTER,
    parameter type item = gvip_aximm_item_pkg::item #(N, I, A, U_REQ, U_DATA, U_RESP)
) (
    input logic clk,
    input logic rst
);

  // Item which match type with vip
  // in XILINX_SIMULATOR there need to be single place to
  // typdef item so it cannot be in the vip interface,
  // because test would need to recreate same item
`ifndef XILINX_SIMULATOR
  typedef gvip_aximm_item_pkg::item #(N, I, A, U_REQ, U_DATA, U_RESP) item_t;
`endif

  gaximm_if #(N, I, A, U_REQ, U_DATA, U_RESP) aximm();

  gclk_if clk_i(.clk(clk), .rst(rst));

  gvip_aximm_pkg::core #(N, I, A, U_REQ, U_DATA, U_RESP, item) core;

  // Function: init
  //
  // Calls core class constructor. Use it to initialize vip.
  // vip_cfg  - optional configuration object (please check: gvip_config at gvip_aximm_pkg.sv)
  function automatic void init(gvip_aximm_pkg::gvip_config vip_cfg = null);
    core = new(NAME, aximm, clk_i, CORE_TYPE, vip_cfg);
  endfunction : init

endinterface : gvip_aximm_if
