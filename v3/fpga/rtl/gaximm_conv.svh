/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Macros to handy convert VIP AXIMM interface to/from AXIMM RTL interface

`define GAXIMM_VIP_TO_AXIMM(INF) \
    \
    aximm_i #(.DataWidth(INF.N*8), .AddrWidth(INF.A)) aximm_``INF(); \
    assign aximm_``INF.awvalid  = INF.aximm.awvalid;   \
    assign INF.aximm.awready    = aximm_``INF.awready; \
    assign aximm_``INF.awid     = INF.aximm.awid;      \
    assign aximm_``INF.awaddr   = INF.aximm.awaddr;    \
    assign aximm_``INF.awlen    = INF.aximm.awlen;     \
    assign aximm_``INF.awsize   = INF.aximm.awsize;    \
    assign aximm_``INF.awburst  = INF.aximm.awburst;   \
    assign aximm_``INF.awprot   = INF.aximm.awprot;    \
    assign aximm_``INF.awlock   = INF.aximm.awlock;    \
    assign aximm_``INF.awcache  = INF.aximm.awcache;   \
    assign aximm_``INF.awregion = INF.aximm.awregion;  \
    \
    assign aximm_``INF.wvalid   = INF.aximm.wvalid;    \
    assign INF.aximm.wready     = aximm_``INF.wready;  \
    assign aximm_``INF.wdata    = INF.aximm.wdata;     \
    assign aximm_``INF.wstrb    = INF.aximm.wstrb;     \
    assign aximm_``INF.wlast    = INF.aximm.wlast;     \
    \
    assign INF.aximm.bvalid     = aximm_``INF.bvalid;  \
    assign aximm_``INF.bready   = INF.aximm.bready;    \
    assign INF.aximm.bid        = aximm_``INF.bid;     \
    assign INF.aximm.bresp      = gaximm_pkg::resp_e'(aximm_``INF.bresp);   \
    \
    assign aximm_``INF.arvalid  = INF.aximm.arvalid;   \
    assign INF.aximm.arready    = aximm_``INF.arready; \
    assign aximm_``INF.arid     = INF.aximm.arid;      \
    assign aximm_``INF.araddr   = INF.aximm.araddr;    \
    assign aximm_``INF.arlen    = INF.aximm.arlen;     \
    assign aximm_``INF.arsize   = INF.aximm.arsize;    \
    assign aximm_``INF.arburst  = INF.aximm.arburst;   \
    assign aximm_``INF.arprot   = INF.aximm.arprot;    \
    assign aximm_``INF.arlock   = INF.aximm.arlock;    \
    assign aximm_``INF.arcache  = INF.aximm.arcache;   \
    assign aximm_``INF.arregion = INF.aximm.arregion;  \
    \
    assign INF.aximm.rvalid     = aximm_``INF.rvalid;  \
    assign aximm_``INF.rready   = INF.aximm.rready;    \
    assign INF.aximm.rid        = aximm_``INF.rid;     \
    assign INF.aximm.rdata      = aximm_``INF.rdata;   \
    assign INF.aximm.rresp      = gaximm_pkg::resp_e'(aximm_``INF.rresp);   \
    assign INF.aximm.rlast      = aximm_``INF.rlast;

`define AXIMM_TO_GAXIMM_VIP(INF) \
    \
    aximm_i #(.DataWidth(INF.N*8), .AddrWidth(INF.A)) aximm_``INF(); \
    assign INF.aximm.awvalid    = aximm_``INF.awvalid;   \
    assign aximm_``INF.awready  = INF.aximm.awready;     \
    assign INF.aximm.awid       = aximm_``INF.awid;      \
    assign INF.aximm.awaddr     = aximm_``INF.awaddr;    \
    assign INF.aximm.awlen      = aximm_``INF.awlen;     \
    assign INF.aximm.awsize     = aximm_``INF.awsize;    \
    assign INF.aximm.awburst    = gaximm_pkg::burst_type_e'(aximm_``INF.awburst);   \
    assign INF.aximm.awprot     = aximm_``INF.awprot;    \
    assign INF.aximm.awlock     = aximm_``INF.awlock;    \
    assign INF.aximm.awcache    = aximm_``INF.awcache;   \
    assign INF.aximm.awregion   = aximm_``INF.awregion;  \
    \
    assign INF.aximm.wvalid     = aximm_``INF.wvalid;    \
    assign aximm_``INF.wready   = INF.aximm.wready;      \
    assign INF.aximm.wdata      = aximm_``INF.wdata;     \
    assign INF.aximm.wstrb      = aximm_``INF.wstrb;     \
    assign INF.aximm.wlast      = aximm_``INF.wlast;     \
    \
    assign aximm_``INF.bvalid   = INF.aximm.bvalid;      \
    assign INF.aximm.bready     = aximm_``INF.bready;    \
    assign aximm_``INF.bid      = INF.aximm.bid;         \
    assign aximm_``INF.bresp    = gaxilite_pkg::resp_t'(INF.aximm.bresp);       \
    \
    assign INF.aximm.arvalid    = aximm_``INF.arvalid;   \
    assign aximm_``INF.arready  = INF.aximm.arready;     \
    assign INF.aximm.arid       = aximm_``INF.arid;      \
    assign INF.aximm.araddr     = aximm_``INF.araddr;    \
    assign INF.aximm.arlen      = aximm_``INF.arlen;     \
    assign INF.aximm.arsize     = aximm_``INF.arsize;    \
    assign INF.aximm.arburst    = gaximm_pkg::burst_type_e'(aximm_``INF.arburst);   \
    assign INF.aximm.arprot     = aximm_``INF.arprot;    \
    assign INF.aximm.arlock     = aximm_``INF.arlock;    \
    assign INF.aximm.arcache    = aximm_``INF.arcache;   \
    assign INF.aximm.arregion   = aximm_``INF.arregion;  \
    \
    assign aximm_``INF.rvalid   = INF.aximm.rvalid;      \
    assign INF.aximm.rready     = aximm_``INF.rready;    \
    assign aximm_``INF.rid      = INF.aximm.rid;         \
    assign aximm_``INF.rdata    = INF.aximm.rdata;       \
    assign aximm_``INF.rresp    = gaxilite_pkg::resp_t'(INF.aximm.rresp);       \
    assign aximm_``INF.rlast    = INF.aximm.rlast;

