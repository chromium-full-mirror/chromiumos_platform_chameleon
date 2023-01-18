/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

////////////////////////////////////////////
// example's DUT - just passing interface //
////////////////////////////////////////////

module dut(
  gaximm_if.manager     i_aximm_in,
  gaximm_if.subordinate i_aximm_out
);

  assign i_aximm_out.awvalid     =     i_aximm_in.awvalid;
  assign i_aximm_in.awready      =     i_aximm_out.awready;
  assign i_aximm_out.awid        =     i_aximm_in.awid;
  assign i_aximm_out.awaddr      =     i_aximm_in.awaddr;
  assign i_aximm_out.awlen       =     i_aximm_in.awlen;
  assign i_aximm_out.awsize      =     i_aximm_in.awsize;
  assign i_aximm_out.awburst     =     i_aximm_in.awburst;
  assign i_aximm_out.awlock      =     i_aximm_in.awlock;
  assign i_aximm_out.awcache     =     i_aximm_in.awcache;
  assign i_aximm_out.awprot      =     i_aximm_in.awprot;
  assign i_aximm_out.awqos       =     i_aximm_in.awqos;
  assign i_aximm_out.awregion    =     i_aximm_in.awregion;
  assign i_aximm_out.awuser      =     i_aximm_in.awuser;
  assign i_aximm_out.wvalid      =     i_aximm_in.wvalid;
  assign i_aximm_in.wready       =     i_aximm_out.wready;
  assign i_aximm_out.wlast       =     i_aximm_in.wlast;
  assign i_aximm_out.wdata       =     i_aximm_in.wdata;
  assign i_aximm_out.wstrb       =     i_aximm_in.wstrb;
  assign i_aximm_out.wuser       =     i_aximm_in.wuser;
  assign i_aximm_in.bvalid       =     i_aximm_out.bvalid;
  assign i_aximm_out.bready      =     i_aximm_in.bready;
  assign i_aximm_in.bid          =     i_aximm_out.bid;
  assign i_aximm_in.bresp        =     i_aximm_out.bresp;
  assign i_aximm_in.buser        =     i_aximm_out.buser;
  assign i_aximm_out.arvalid     =     i_aximm_in.arvalid;
  assign i_aximm_in.arready      =     i_aximm_out.arready;
  assign i_aximm_out.arid        =     i_aximm_in.arid;
  assign i_aximm_out.araddr      =     i_aximm_in.araddr;
  assign i_aximm_out.arlen       =     i_aximm_in.arlen;
  assign i_aximm_out.arsize      =     i_aximm_in.arsize;
  assign i_aximm_out.arburst     =     i_aximm_in.arburst;
  assign i_aximm_out.arlock      =     i_aximm_in.arlock;
  assign i_aximm_out.arcache     =     i_aximm_in.arcache;
  assign i_aximm_out.arprot      =     i_aximm_in.arprot;
  assign i_aximm_out.arqos       =     i_aximm_in.arqos;
  assign i_aximm_out.arregion    =     i_aximm_in.arregion;
  assign i_aximm_out.aruser      =     i_aximm_in.aruser;
  assign i_aximm_in.rvalid       =     i_aximm_out.rvalid;
  assign i_aximm_out.rready      =     i_aximm_in.rready;
  assign i_aximm_in.rlast        =     i_aximm_out.rlast;
  assign i_aximm_in.rid          =     i_aximm_out.rid;
  assign i_aximm_in.rdata        =     i_aximm_out.rdata;
  assign i_aximm_in.rresp        =     i_aximm_out.rresp;
  assign i_aximm_in.ruser        =     i_aximm_out.ruser;

endmodule