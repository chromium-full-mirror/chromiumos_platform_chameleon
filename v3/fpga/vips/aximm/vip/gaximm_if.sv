/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////
// RTL interface definition //
//////////////////////////////


// Interface: gaximm_if
//
//   N      - number of bytes of tdata
//   I      - id signal width
//   A      - address signal width
//   U_REQ  - awuser and aruser type
//   U_DATA - wuser and ruser type
//   U_RESP - buser type
interface gaximm_if #(
    parameter int N=1,
    parameter int I=1,
    parameter int A=1,
    parameter type U_REQ=logic[0:0],
    parameter type U_DATA=logic[0:0],
    parameter type U_RESP=logic[0:0],

    // This parameter is a workaround for vivado bug
    // if construct such a $bits(U_REQ) would be used outside interface
    // vivado will return width of default U_REQ
    parameter int U_REQ_WIDTH = $bits(U_REQ),
    parameter int U_DATA_WIDTH = $bits(U_DATA),
    parameter int U_RESP_WIDTH = $bits(U_RESP)
  ) ();

  logic                                awvalid;
  logic                                awready;
  logic [I-1:0]                        awid;
  logic [A-1:0]                        awaddr;
  logic [gaximm_pkg::LEN_WIDTH-1:0]    awlen;
  logic [gaximm_pkg::SIZE_WIDTH-1:0]   awsize;
  gaximm_pkg::burst_type_e             awburst;
  logic [gaximm_pkg::LOCK_WIDTH-1:0]   awlock;
  logic [gaximm_pkg::CACHE_WIDTH-1:0]  awcache;
  logic [gaximm_pkg::PROT_WIDTH-1:0]   awprot;
  logic [gaximm_pkg::QOS_WIDTH-1:0]    awqos;
  logic [gaximm_pkg::REGION_WIDTH-1:0] awregion;
  U_REQ                                awuser;

  logic                                wvalid;
  logic                                wready;
  logic                                wlast;
  logic [N*8-1:0]                      wdata;
  logic [N-1:0]                        wstrb;
  U_DATA                               wuser;

  logic                                bvalid;
  logic                                bready;
  logic [I-1:0]                        bid;
  gaximm_pkg::resp_e                   bresp;
  U_RESP                               buser;

  logic                                arvalid;
  logic                                arready;
  logic [I-1:0]                        arid;
  logic [A-1:0]                        araddr;
  logic [gaximm_pkg::LEN_WIDTH-1:0]    arlen;
  logic [gaximm_pkg::SIZE_WIDTH-1:0]   arsize;
  gaximm_pkg::burst_type_e             arburst;
  logic [gaximm_pkg::LOCK_WIDTH-1:0]   arlock;
  logic [gaximm_pkg::CACHE_WIDTH-1:0]  arcache;
  logic [gaximm_pkg::PROT_WIDTH-1:0]   arprot;
  logic [gaximm_pkg::QOS_WIDTH-1:0]    arqos;
  logic [gaximm_pkg::REGION_WIDTH-1:0] arregion;
  U_REQ                                aruser;

  logic                                rvalid;
  logic                                rready;
  logic                                rlast;
  logic [I-1:0]                        rid;
  logic [N*8-1:0]                      rdata;
  gaximm_pkg::resp_e                   rresp;
  U_DATA                               ruser;


  // synthesis translate_off

  // Just for simulation - used by gvip_aximm
  // With it, vip is able to force signals of assigned interfaces
  generate
    begin : g_sim
      logic                                sim_awvalid;
      logic                                sim_awready;
      logic [I-1:0]                        sim_awid;
      logic [A-1:0]                        sim_awaddr;
      logic [gaximm_pkg::LEN_WIDTH-1:0]    sim_awlen;
      logic [gaximm_pkg::SIZE_WIDTH-1:0]   sim_awsize;
      gaximm_pkg::burst_type_e             sim_awburst;
      logic [gaximm_pkg::LOCK_WIDTH-1:0]   sim_awlock;
      logic [gaximm_pkg::CACHE_WIDTH-1:0]  sim_awcache;
      logic [gaximm_pkg::PROT_WIDTH-1:0]   sim_awprot;
      logic [gaximm_pkg::QOS_WIDTH-1:0]    sim_awqos;
      logic [gaximm_pkg::REGION_WIDTH-1:0] sim_awregion;
      U_REQ                                sim_awuser;
      logic                                sim_wvalid;
      logic                                sim_wready;
      logic                                sim_wlast;
      logic [N*8-1:0]                      sim_wdata;
      logic [N-1:0]                        sim_wstrb;
      U_DATA                               sim_wuser;
      logic                                sim_bvalid;
      logic                                sim_bready;
      logic [I-1:0]                        sim_bid;
      gaximm_pkg::resp_e                   sim_bresp;
      U_RESP                               sim_buser;
      logic                                sim_arvalid;
      logic                                sim_arready;
      logic [I-1:0]                        sim_arid;
      logic [A-1:0]                        sim_araddr;
      logic [gaximm_pkg::LEN_WIDTH-1:0]    sim_arlen;
      logic [gaximm_pkg::SIZE_WIDTH-1:0]   sim_arsize;
      gaximm_pkg::burst_type_e             sim_arburst;
      logic [gaximm_pkg::LOCK_WIDTH-1:0]   sim_arlock;
      logic [gaximm_pkg::CACHE_WIDTH-1:0]  sim_arcache;
      logic [gaximm_pkg::PROT_WIDTH-1:0]   sim_arprot;
      logic [gaximm_pkg::QOS_WIDTH-1:0]    sim_arqos;
      logic [gaximm_pkg::REGION_WIDTH-1:0] sim_arregion;
      U_REQ                                sim_aruser;
      logic                                sim_rvalid;
      logic                                sim_rready;
      logic                                sim_rlast;
      logic [I-1:0]                        sim_rid;
      logic [N*8-1:0]                      sim_rdata;
      gaximm_pkg::resp_e                   sim_rresp;
      U_DATA                               sim_ruser;

      function automatic void force_as_manager();
        force awvalid  = sim_awvalid;
        force awid     = sim_awid;
        force awaddr   = sim_awaddr;
        force awlen    = sim_awlen;
        force awsize   = sim_awsize;
        force awburst  = sim_awburst;
        force awlock   = sim_awlock;
        force awcache  = sim_awcache;
        force awprot   = sim_awprot;
        force awqos    = sim_awqos;
        force awregion = sim_awregion;
        force awuser   = sim_awuser;
        force wvalid   = sim_wvalid;
        force wlast    = sim_wlast;
        force wdata    = sim_wdata;
        force wstrb    = sim_wstrb;
        force wuser    = sim_wuser;
        force bready   = sim_bready;
        force arvalid  = sim_arvalid;
        force arid     = sim_arid;
        force araddr   = sim_araddr;
        force arlen    = sim_arlen;
        force arsize   = sim_arsize;
        force arburst  = sim_arburst;
        force arlock   = sim_arlock;
        force arcache  = sim_arcache;
        force arprot   = sim_arprot;
        force arqos    = sim_arqos;
        force arregion = sim_arregion;
        force aruser   = sim_aruser;
        force rready   = sim_rready;
      endfunction : force_as_manager

      function automatic void release_manager();
        release awvalid;
        release awid;
        release awaddr;
        release awlen;
        release awsize;
        release awburst;
        release awlock;
        release awcache;
        release awprot;
        release awqos;
        release awregion;
        release awuser;
        release wvalid;
        release wlast;
        release wdata;
        release wstrb;
        release wuser;
        release bready;
        release arvalid;
        release arid;
        release araddr;
        release arlen;
        release arsize;
        release arburst;
        release arlock;
        release arcache;
        release arprot;
        release arqos;
        release arregion;
        release aruser;
        release rready;
      endfunction : release_manager

      function automatic void force_as_subordinate();
        force awready = sim_awready;
        force wready  = sim_wready;
        force bvalid  = sim_bvalid;
        force bid     = sim_bid;
        force bresp   = sim_bresp;
        force buser   = sim_buser;
        force arready = sim_arready;
        force rvalid  = sim_rvalid;
        force rlast   = sim_rlast;
        force rid     = sim_rid;
        force rdata   = sim_rdata;
        force rresp   = sim_rresp;
        force ruser   = sim_ruser;
      endfunction : force_as_subordinate

      function automatic void release_subordinate();
        release awready;
        release wready;
        release bvalid;
        release bid;
        release bresp;
        release buser;
        release arready;
        release rvalid;
        release rlast;
        release rid;
        release rdata;
        release rresp;
        release ruser;
      endfunction : release_subordinate
    end : g_sim
  endgenerate

  // synthesis translate_on

  modport manager (
    input  awvalid,
    output awready,
    input  awid,
    input  awaddr,
    input  awlen,
    input  awsize,
    input  awburst,
    input  awlock,
    input  awcache,
    input  awprot,
    input  awqos,
    input  awregion,
    input  awuser,
    input  wvalid,
    output wready,
    input  wlast,
    input  wdata,
    input  wstrb,
    input  wuser,
    output bvalid,
    input  bready,
    output bid,
    output bresp,
    output buser,
    input  arvalid,
    output arready,
    input  arid,
    input  araddr,
    input  arlen,
    input  arsize,
    input  arburst,
    input  arlock,
    input  arcache,
    input  arprot,
    input  arqos,
    input  arregion,
    input  aruser,
    output rvalid,
    input  rready,
    output rlast,
    output rid,
    output rdata,
    output rresp,
    output ruser
  );

  modport subordinate (
    output awvalid,
    input  awready,
    output awid,
    output awaddr,
    output awlen,
    output awsize,
    output awburst,
    output awlock,
    output awcache,
    output awprot,
    output awqos,
    output awregion,
    output awuser,
    output wvalid,
    input  wready,
    output wlast,
    output wdata,
    output wstrb,
    output wuser,
    input  bvalid,
    output bready,
    input  bid,
    input  bresp,
    input  buser,
    output arvalid,
    input  arready,
    output arid,
    output araddr,
    output arlen,
    output arsize,
    output arburst,
    output arlock,
    output arcache,
    output arprot,
    output arqos,
    output arregion,
    output aruser,
    input  rvalid,
    output rready,
    input  rlast,
    input  rid,
    input  rdata,
    input  rresp,
    input  ruser
  );

  modport monitor (
    input awvalid,
    input awready,
    input awid,
    input awaddr,
    input awlen,
    input awsize,
    input awburst,
    input awlock,
    input awcache,
    input awprot,
    input awqos,
    input awregion,
    input awuser,
    input wvalid,
    input wready,
    input wlast,
    input wdata,
    input wstrb,
    input wuser,
    input bvalid,
    input bready,
    input bid,
    input bresp,
    input buser,
    input arvalid,
    input arready,
    input arid,
    input araddr,
    input arlen,
    input arsize,
    input arburst,
    input arlock,
    input arcache,
    input arprot,
    input arqos,
    input arregion,
    input aruser,
    input rvalid,
    input rready,
    input rlast,
    input rid,
    input rdata,
    input rresp,
    input ruser
  );

  modport driver (
    output awvalid,
    output awready,
    output awid,
    output awaddr,
    output awlen,
    output awsize,
    output awburst,
    output awlock,
    output awcache,
    output awprot,
    output awqos,
    output awregion,
    output awuser,
    output wvalid,
    output wready,
    output wlast,
    output wdata,
    output wstrb,
    output wuser,
    output bvalid,
    output bready,
    output bid,
    output bresp,
    output buser,
    output arvalid,
    output arready,
    output arid,
    output araddr,
    output arlen,
    output arsize,
    output arburst,
    output arlock,
    output arcache,
    output arprot,
    output arqos,
    output arregion,
    output aruser,
    output rvalid,
    output rready,
    output rlast,
    output rid,
    output rdata,
    output rresp,
    output ruser
  );

endinterface : gaximm_if
