/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////
// RTL interface definition //
//////////////////////////////


// Interface: gaxis_if
//
// AMBA AXI Stream interface implementation.
// It could be used anywhare in RTL design.
// It's easy to test with gvip_axis vip.
// NUM - number of gaxis_if interfaces
// N - number of bytes
// I - tid width
// D - tdest width
// U_T - tuser type
interface gaxis_if #(
    parameter int N = 1, // bytes number in tdata, width of tkeep and tstrb
    parameter int I = 1, // tid width
    parameter int D = 1, // tdest width
    parameter type U_T = logic[0:0], // tuser type
    // This parameter is a workaround for vivado bug
    // if construct such a $bits(U_T) would be used outside interface
    // vivado will return width of default U_T
    parameter int U_T_WIDTH = $bits(U_T)
  ) ();

  logic           tvalid;
  logic           tready;
  logic [N*8-1:0] tdata;
  logic [N-1:0]   tkeep;
  logic [N-1:0]   tstrb;
  logic           tlast;
  logic [I-1:0]   tid;
  logic [D-1:0]   tdest;
  U_T             tuser;


  // synthesis translate_off

  // Just for simulation - used by gvip_axis
  // With it, vip is able to force particular signal value of assigned interfaces
  generate
    begin : g_sim
      logic           sim_tvalid;
      logic           sim_tready;
      logic [N*8-1:0] sim_tdata;
      logic [N-1:0]   sim_tkeep;
      logic [N-1:0]   sim_tstrb;
      logic           sim_tlast;
      logic [I-1:0]   sim_tid;
      logic [D-1:0]   sim_tdest;
      U_T             sim_tuser;

      function automatic void force_as_master();
        force tvalid = sim_tvalid;
        force tdata  = sim_tdata;
        force tuser  = sim_tuser;
        force tkeep  = sim_tkeep;
        force tstrb  = sim_tstrb;
        force tid    = sim_tid;
        force tdest  = sim_tdest;
        force tlast  = sim_tlast;
      endfunction : force_as_master

      function automatic void release_master();
        release tvalid;
        release tdata;
        release tuser;
        release tkeep;
        release tstrb;
        release tid;
        release tdest;
        release tlast;
      endfunction : release_master

      function automatic void force_as_slave();
        force tready = sim_tready;
      endfunction : force_as_slave

      function automatic void release_slave();
        release tready;
      endfunction : release_slave
    end : g_sim
  endgenerate

  // synthesis translate_on

  modport master (
    output tdata,
    output tkeep,
    output tlast,
    input  tready,
    output tuser,
    output tstrb,
    output tid,
    output tdest,
    output tvalid
  );

  modport slave (
    input  tdata,
    input  tkeep,
    input  tlast,
    output tready,
    input  tuser,
    input  tstrb,
    input  tid,
    input  tdest,
    input  tvalid
  );

  modport monitor (
    input  tdata,
    input  tkeep,
    input  tlast,
    input  tready,
    input  tuser,
    input  tstrb,
    input  tid,
    input  tdest,
    input  tvalid
  );

  modport driver (
    output tdata,
    output tkeep,
    output tlast,
    output tready,
    output tuser,
    output tstrb,
    output tid,
    output tdest,
    output tvalid
  );

endinterface : gaxis_if
