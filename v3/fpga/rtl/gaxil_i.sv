/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

interface axil_i #(
    parameter int DataWidth = 32,
    parameter int AddrWidth = 32,
    parameter int UserWidth = 1,
    type Taddr = logic [AddrWidth-1:0],
    type Tuser = logic [UserWidth-1:0],
    type Tdata = logic [DataWidth-1:0],
    // add this parameters as workaround for Quartus bug
    // if use construct such a $bits(Tdata) outside interface
    // Quartus return 1 width of Tdata
    parameter int TdataWidth = $bits(Tdata),
    parameter int TuserWidth = $bits(Tuser),
    parameter int TaddrWidth = $bits(Taddr)
);

    logic                    awvalid;
    logic                    awready;
    Taddr                    awaddr;
    Tuser                    awuser;
    logic                    wvalid;
    logic                    wready;
    Tdata                    wdata;
    logic [TdataWidth/8-1:0] wstrb;
    logic                    bvalid;
    logic                    bready;
    gaxilite_pkg::resp_t     bresp;
    logic                    arvalid;
    logic                    arready;
    Taddr                    araddr;
    Tuser                    aruser;
    logic                    rvalid;
    logic                    rready;
    Tdata                    rdata;
    gaxilite_pkg::resp_t     rresp;

    modport manager (
        output awvalid,
        input  awready,
        output awaddr,
        output awuser,
        output wvalid,
        input  wready,
        output wdata,
        output wstrb,
        input  bvalid,
        output bready,
        input  bresp,
        output arvalid,
        input  arready,
        output araddr,
        output aruser,
        input  rvalid,
        output rready,
        input  rdata,
        input  rresp
    );

    modport subordinate (
        input  awvalid,
        output awready,
        input  awaddr,
        input  awuser,
        input  wvalid,
        output wready,
        input  wdata,
        input  wstrb,
        output bvalid,
        input  bready,
        output bresp,
        input  arvalid,
        output arready,
        input  araddr,
        input  aruser,
        output rvalid,
        input  rready,
        output rdata,
        output rresp
    );

    modport monitor (
        input  awvalid,
        input  awready,
        input  awaddr,
        input  awuser,
        input  wvalid,
        input  wready,
        input  wdata,
        input  wstrb,
        input  bvalid,
        input  bready,
        input  bresp,
        input  arvalid,
        input  arready,
        input  araddr,
        input  aruser,
        input  rvalid,
        input  rready,
        input  rdata,
        input  rresp
    );

endinterface : axil_i
