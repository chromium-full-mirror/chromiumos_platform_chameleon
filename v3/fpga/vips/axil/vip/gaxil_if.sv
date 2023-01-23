/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////
// RTL interface definition //
//////////////////////////////


// Interface: gaxil_if
//
//   N      - number of bytes of tdata
//   A      - address signal width
interface gaxil_if #(
    parameter int N=1,
    parameter int A=1
  ) ();

  logic                                awvalid;
  logic                                awready;
  logic [A-1:0]                        awaddr;
  logic [gaxil_pkg::PROT_WIDTH-1:0]    awprot;

  logic                                wvalid;
  logic                                wready;
  logic [N*8-1:0]                      wdata;
  logic [N-1:0]                        wstrb;

  logic                                bvalid;
  logic                                bready;
  gaxil_pkg::resp_e                    bresp;

  logic                                arvalid;
  logic                                arready;
  logic [A-1:0]                        araddr;
  logic [gaxil_pkg::PROT_WIDTH-1:0]    arprot;

  logic                                rvalid;
  logic                                rready;
  logic [N*8-1:0]                      rdata;
  gaxil_pkg::resp_e                    rresp;


  // synthesis translate_off

  // Just for simulation - used by gvip_axil
  // With it, vip is able to force signals of assigned interfaces
  generate
    begin : g_sim
      logic                                sim_awvalid;
      logic                                sim_awready;
      logic [A-1:0]                        sim_awaddr;
      logic [gaxil_pkg::PROT_WIDTH-1:0]    sim_awprot;
      logic                                sim_wvalid;
      logic                                sim_wready;
      logic [N*8-1:0]                      sim_wdata;
      logic [N-1:0]                        sim_wstrb;
      logic                                sim_bvalid;
      logic                                sim_bready;
      gaxil_pkg::resp_e                    sim_bresp;
      logic                                sim_arvalid;
      logic                                sim_arready;
      logic [A-1:0]                        sim_araddr;
      logic [gaxil_pkg::PROT_WIDTH-1:0]    sim_arprot;
      logic                                sim_rvalid;
      logic                                sim_rready;
      logic [N*8-1:0]                      sim_rdata;
      gaxil_pkg::resp_e                    sim_rresp;

      function automatic void force_as_manager();
        force awvalid  = sim_awvalid;
        force awaddr   = sim_awaddr;
        force awprot   = sim_awprot;
        force wvalid   = sim_wvalid;
        force wdata    = sim_wdata;
        force wstrb    = sim_wstrb;
        force bready   = sim_bready;
        force arvalid  = sim_arvalid;
        force araddr   = sim_araddr;
        force arprot   = sim_arprot;
        force rready   = sim_rready;
      endfunction : force_as_manager

      function automatic void release_manager();
        release awvalid;
        release awaddr;
        release awprot;
        release wvalid;
        release wdata;
        release wstrb;
        release bready;
        release arvalid;
        release araddr;
        release arprot;
        release rready;
      endfunction : release_manager

      function automatic void force_as_subordinate();
        force awready = sim_awready;
        force wready  = sim_wready;
        force bvalid  = sim_bvalid;
        force bresp   = sim_bresp;
        force arready = sim_arready;
        force rvalid  = sim_rvalid;
        force rdata   = sim_rdata;
        force rresp   = sim_rresp;
      endfunction : force_as_subordinate

      function automatic void release_subordinate();
        release awready;
        release wready;
        release bvalid;
        release bresp;
        release arready;
        release rvalid;
        release rdata;
        release rresp;
      endfunction : release_subordinate
    end : g_sim
  endgenerate

  // synthesis translate_on

  modport manager (
    input  awvalid,
    output awready,
    input  awaddr,
    input  awprot,
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
    input  arprot,
    output rvalid,
    input  rready,
    output rdata,
    output rresp
  );

  modport subordinate (
    output awvalid,
    input  awready,
    output awaddr,
    output awprot,
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
    output arprot,
    input  rvalid,
    output rready,
    input  rdata,
    input  rresp
  );

  modport monitor (
    input awvalid,
    input awready,
    input awaddr,
    input awprot,
    input wvalid,
    input wready,
    input wdata,
    input wstrb,
    input bvalid,
    input bready,
    input bresp,
    input arvalid,
    input arready,
    input araddr,
    input arprot,
    input rvalid,
    input rready,
    input rdata,
    input rresp
  );

  modport driver (
    output awvalid,
    output awready,
    output awaddr,
    output awprot,
    output wvalid,
    output wready,
    output wdata,
    output wstrb,
    output bvalid,
    output bready,
    output bresp,
    output arvalid,
    output arready,
    output araddr,
    output arprot,
    output rvalid,
    output rready,
    output rdata,
    output rresp
  );

endinterface : gaxil_if
