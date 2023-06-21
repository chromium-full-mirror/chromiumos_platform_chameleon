/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`ifndef __GXB_I__
`define __GXB_I__

/* Interfaces for GXB modules */
interface xcvr_i #(
    parameter int XcvrDataWidth = 160,
    parameter int XcvrLaneCount = 4
);

  logic [XcvrDataWidth-1:0] data;
  logic [XcvrLaneCount-1:0] std_clkout;
  logic [XcvrLaneCount-1:0] is_lockedtoref;
  logic [XcvrLaneCount-1:0] is_lockedtodata;
  logic restart;
  logic [XcvrLaneCount-1:0] bitslip;
  logic [XcvrLaneCount-1:0] polinv;
  logic [XcvrLaneCount-1:0] cal_busy;
  logic [XcvrLaneCount-1:0] analogreset;
  logic [XcvrLaneCount-1:0] digitalreset;
  logic [XcvrLaneCount-1:0] set_locktoref;
  logic [XcvrLaneCount-1:0] set_locktodata;

  modport host (
    output data,
    output std_clkout,
    output is_lockedtoref,
    output is_lockedtodata,
    input  restart,
    input  bitslip,
    input  polinv,
    output cal_busy,
    input  analogreset,
    input  digitalreset,
    input  set_locktoref,
    input  set_locktodata
  );

  modport agent (
    input  data,
    input  std_clkout,
    input  is_lockedtoref,
    input  is_lockedtodata,
    output restart,
    output bitslip,
    output polinv,
    input  cal_busy,
    output analogreset,
    output digitalreset,
    inout  set_locktoref,
    output set_locktodata
  );

endinterface : xcvr_i

interface xcvr_port_i #(
    parameter int XcvrLaneCount = 4
);
  logic ref_clk;
  logic [XcvrLaneCount-1:0] serial_data;

  modport host (
    output  ref_clk,
    output serial_data
  );

  modport agent (
    input  ref_clk,
    input  serial_data
  );

endinterface : xcvr_port_i

`endif // __GXB_I__
