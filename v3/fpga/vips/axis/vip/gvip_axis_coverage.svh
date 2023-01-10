/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: gvip_axis_coverage
//
// Basic coverage
//
class gvip_axis_coverage #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0]);

  virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif;
  virtual gclk_if vclk;

  // Functional coverage for handshake
  covergroup cg_transfer (string name)
    @(posedge vclk.clk iff vclk.rst == 0);

    option.name = {name, "::transfer"};
    option.per_instance = 1;
    option.comment = "Counts handshake events";

    TVALID: coverpoint vif.tvalid {
      bins high            = {1};
      bins low             = {0};
      bins to_low          = (1=>0);
      bins to_high         = (0=>1);
    }

    TREADY: coverpoint vif.tready {
      bins high            = {1};
      bins low             = {0};
      bins to_low          = (1=>0);
      bins to_high         = (0=>1);
    }

    // AMBA 4 AXI4-Stream Protocol Specification, Handshake process (2.2.1)
    HANDSHAKE: cross TVALID, TREADY {
      // For a transfer to occur both the TVALID and TREADY signals must be asserted
      bins high_ready_high_valid = binsof(TREADY.high) && binsof(TVALID.high); //transfer
      bins high_ready_low_valid  = binsof(TREADY.high) && binsof(TVALID.low);  //no transfer
      bins low_ready_high_valid  = binsof(TREADY.low)  && binsof(TVALID.high); //no transfer
      bins low_ready_low_valid   = binsof(TREADY.low)  && binsof(TVALID.low);  //no transfer

      // Either TVALID or TREADY can be asserted first or both can be asserted in the same ACLK cycle.
      bins assert_ready__low_valid    = binsof(TREADY.to_high) && binsof(TVALID.low);
      bins assert_ready__high_valid   = binsof(TREADY.to_high) && binsof(TVALID.high);
      bins assert_ready__assert_valid = binsof(TREADY.to_high) && binsof(TVALID.to_high);
      bins low_ready__assert_valid    = binsof(TREADY.low)     && binsof(TVALID.to_high);
      bins high_ready__assert_valid   = binsof(TREADY.high)    && binsof(TVALID.to_high);

      // Once TVALID is asserted it must remain asserted until the handshake occurs.
      bins high_ready__deassert_valid           = binsof(TREADY.high)    && binsof(TVALID.to_low);
      bins deassert_ready__deassert_valid       = binsof(TREADY.to_low)  && binsof(TVALID.to_low);

      // If a slave asserts TREADY, it is permitted to deassert TREADY before TVALID is asserted.
      bins deassert_ready__low_valid    = binsof(TREADY.to_low) && binsof(TVALID.low);
      bins deassert_ready__high_valid   = binsof(TREADY.to_low) && binsof(TVALID.high);
      bins deassert_ready__assert_valid = binsof(TREADY.to_low) && binsof(TVALID.to_high);
    }

  endgroup : cg_transfer

  // Functional coverage for tkeep byte qualifier
  covergroup cg_keep(string name)
    @(posedge vclk.clk iff vclk.rst == 0 && vif.tvalid & vif.tready);

    option.name = {name, "::keep"};
    option.per_instance = 1;

    TKEEP: coverpoint vif.tkeep { bins values[] = {[0:(N**2)-1]}; }
  endgroup : cg_keep

  // Functional coverage for tstrb byte qualifier
  covergroup cg_tstrb(string name)
    @(posedge vclk.clk iff vclk.rst == 0 && vif.tvalid & vif.tready);

    option.name = {name, "::strb"};
    option.per_instance = 1;

    TSTRB: coverpoint vif.tstrb { bins values[] = {[0:(N**2)-1]}; }
  endgroup : cg_tstrb

  // Functional cross coverage byte qualifiers
  covergroup cg_byte_qualifiers(string name, int index)
    @(posedge vclk.clk iff vclk.rst == 0 && vif.tvalid & vif.tready);

    option.name = $sformatf("%s::byte_qualifiers_%0d", name, index);
    option.per_instance = 1;

    // Valid combinations for TKEEP and TSTRB byte qualifications
    BYTE:  coverpoint {vif.tkeep[index], vif.tstrb[index]} {
      bins data[]             = {2'b11};
      bins position[]         = {2'b10};
      bins null_byte[]        = {2'b00};
      illegal_bins reserved[] = {2'b01};
    }

  endgroup : cg_byte_qualifiers


  function new(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    string name
  );
    this.vif = vif;
    this.vclk = c;

    cg_transfer = new(name);
    cg_keep = new(name);
    cg_tstrb = new(name);
    for(int i = 0; i < N; ++i) begin
      cg_byte_qualifiers = new(name, i);
    end
  endfunction : new


endclass: gvip_axis_coverage
