/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Macros to handy convert VIP AXIL interface to/from AXIL RTL interface

`define GAXIL_VIP_TO_AXIL(INF) \
    \
    axil_i #(.DataWidth(INF.N*8), .AddrWidth(INF.A)) axil_``INF(); \
    assign axil_``INF.awvalid  = INF.axil.awvalid;   \
    assign INF.axil.awready    = axil_``INF.awready; \
    assign axil_``INF.awaddr   = INF.axil.awaddr;    \
    \
    assign axil_``INF.wvalid   = INF.axil.wvalid;    \
    assign INF.axil.wready     = axil_``INF.wready;  \
    assign axil_``INF.wdata    = INF.axil.wdata;     \
    assign axil_``INF.wstrb    = INF.axil.wstrb;     \
    \
    assign INF.axil.bvalid     = axil_``INF.bvalid;  \
    assign axil_``INF.bready   = INF.axil.bready;    \
    assign INF.axil.bresp      = gaxil_pkg::resp_e'(axil_``INF.bresp);   \
    \
    assign axil_``INF.arvalid  = INF.axil.arvalid;   \
    assign INF.axil.arready    = axil_``INF.arready; \
    assign axil_``INF.araddr   = INF.axil.araddr;    \
    \
    assign INF.axil.rvalid     = axil_``INF.rvalid;  \
    assign axil_``INF.rready   = INF.axil.rready;    \
    assign INF.axil.rdata      = axil_``INF.rdata;   \
    assign INF.axil.rresp      = gaxil_pkg::resp_e'(axil_``INF.rresp);

`define AXIL_TO_GAXIL_VIP(INF) \
    \
    axil_i #(.DataWidth(INF.N*8), .AddrWidth(INF.A)) axil_``INF(); \
    assign INF.axil.awvalid    = axil_``INF.awvalid;   \
    assign axil_``INF.awready  = INF.axil.awready;     \
    assign INF.axil.awaddr     = axil_``INF.awaddr;    \
    \
    assign INF.axil.wvalid     = axil_``INF.wvalid;    \
    assign axil_``INF.wready   = INF.axil.wready;      \
    assign INF.axil.wdata      = axil_``INF.wdata;     \
    assign INF.axil.wstrb      = axil_``INF.wstrb;     \
    \
    assign axil_``INF.bvalid   = INF.axil.bvalid;      \
    assign INF.axil.bready     = axil_``INF.bready;    \
    assign axil_``INF.bresp    = gaxilite_pkg::resp_t'(INF.axil.bresp);       \
    \
    assign INF.axil.arvalid    = axil_``INF.arvalid;   \
    assign axil_``INF.arready  = INF.axil.arready;     \
    assign INF.axil.araddr     = axil_``INF.araddr;    \
    \
    assign axil_``INF.rvalid   = INF.axil.rvalid;      \
    assign INF.axil.rready     = axil_``INF.rready;    \
    assign axil_``INF.rdata    = INF.axil.rdata;       \
    assign axil_``INF.rresp    = gaxilite_pkg::resp_t'(INF.axil.rresp);

