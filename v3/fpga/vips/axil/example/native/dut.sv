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
  gaxil_if.manager     i_axil_in,
  gaxil_if.subordinate i_axil_out
);

  assign i_axil_out.awvalid     =     i_axil_in.awvalid;
  assign i_axil_in.awready      =     i_axil_out.awready;
  assign i_axil_out.awaddr      =     i_axil_in.awaddr;
  assign i_axil_out.awprot      =     i_axil_in.awprot;
  assign i_axil_out.wvalid      =     i_axil_in.wvalid;
  assign i_axil_in.wready       =     i_axil_out.wready;
  assign i_axil_out.wdata       =     i_axil_in.wdata;
  assign i_axil_out.wstrb       =     i_axil_in.wstrb;
  assign i_axil_in.bvalid       =     i_axil_out.bvalid;
  assign i_axil_out.bready      =     i_axil_in.bready;
  assign i_axil_in.bresp        =     i_axil_out.bresp;
  assign i_axil_out.arvalid     =     i_axil_in.arvalid;
  assign i_axil_in.arready      =     i_axil_out.arready;
  assign i_axil_out.araddr      =     i_axil_in.araddr;
  assign i_axil_out.arprot      =     i_axil_in.arprot;
  assign i_axil_in.rvalid       =     i_axil_out.rvalid;
  assign i_axil_out.rready      =     i_axil_in.rready;
  assign i_axil_in.rdata        =     i_axil_out.rdata;
  assign i_axil_in.rresp        =     i_axil_out.rresp;

endmodule
