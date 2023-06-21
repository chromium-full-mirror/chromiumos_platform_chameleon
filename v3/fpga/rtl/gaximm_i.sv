/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

interface aximm_i #(
    parameter int DataWidth = 512,
    parameter int AddrWidth = 64,
    parameter int IdWidth   = 4,
    parameter int LenWidth  = 8,
    parameter int SizeWidth = 3
);
    logic                                awvalid;
    logic                                awready;
    logic [               IdWidth-1 : 0] awid;
    logic [             AddrWidth-1 : 0] awaddr;
    logic [              LenWidth-1 : 0] awlen;
    logic [             SizeWidth-1 : 0] awsize;
    logic [ gaxim_pkg::BurstWidth-1 : 0]  awburst;
    logic [ gaxim_pkg::ProtWidth-1 : 0]  awprot;
    logic                                awlock;
    logic [gaxim_pkg::CacheWidth-1  : 0] awcache;
    logic [gaxim_pkg::RegionWidth-1 : 0] awregion;

    logic                                wvalid;
    logic                                wready;
    logic [ DataWidth-1 : 0]             wdata;
    logic [DataWidth/8-1 : 0]            wstrb;
    logic [0:0]                          wlast;

    logic                                bvalid;
    logic                                bready;
    logic [IdWidth-1 : 0]                bid;
    gaxilite_pkg::resp_t                 bresp;

    logic                                arvalid;
    logic                                arready;
    logic [               IdWidth-1 : 0] arid;
    logic [             AddrWidth-1 : 0] araddr;
    logic [              LenWidth-1 : 0] arlen;
    logic [             SizeWidth-1 : 0] arsize;
    logic [gaxim_pkg::BurstWidth-1 : 0]  arburst;
    logic [ gaxim_pkg::ProtWidth-1 : 0]  arprot;
    logic                                arlock;
    logic [gaxim_pkg::CacheWidth-1  : 0] arcache;
    logic [gaxim_pkg::RegionWidth-1 : 0] arregion;

    logic                                rvalid;
    logic                                rready;
    logic [  IdWidth-1 : 0]              rid;
    logic [DataWidth-1 : 0]              rdata;
    gaxilite_pkg::resp_t                 rresp;
    logic [0:0]                          rlast;

    modport manager (
            output awvalid,
            input  awready,
            output awid,
            output awaddr,
            output awlen,
            output awsize,
            output awburst,
            output awprot,
            output awlock,
            output awcache,
            output awregion,

            output wvalid,
            input  wready,
            output wdata,
            output wstrb,
            output wlast,

            input  bvalid,
            output bready,
            input  bid,
            input  bresp,

            output arvalid,
            input  arready,
            output arid,
            output araddr,
            output arlen,
            output arsize,
            output arburst,
            output arprot,
            output arlock,
            output arcache,
            output arregion,

            input  rvalid,
            output rready,
            input  rid,
            input  rdata,
            input  rresp,
            input  rlast
        );

    modport subordinate (
            input  awvalid,
            output awready,
            input  awid,
            input  awaddr,
            input  awlen,
            input  awsize,
            input  awburst,
            input  awprot,
            input  awlock,
            input  awcache,
            input  awregion,

            input  wvalid,
            output wready,
            input  wdata,
            input  wstrb,
            input  wlast,

            output bvalid,
            input  bready,
            output bid,
            output bresp,

            input  arvalid,
            output arready,
            input  arid,
            input  araddr,
            input  arlen,
            input  arsize,
            input  arburst,
            input  arprot,
            input  arlock,
            input  arcache,
            input  arregion,

            output rvalid,
            input  rready,
            output rid,
            output rdata,
            output rresp,
            output rlast
        );

endinterface : aximm_i

