/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: axil_r_hs
//
// Virtual class with R channel handshake support
// This class partially implements interface required by gvip_handshake_pkg::handshake
virtual class axil_r_hs #(`IF_PARAMS, type base = handshake) extends base;
  virtual gaxil_if #(`IF_PARAMS_MAP) vif;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(c);
    this.vif = vif;
  endfunction : new

  virtual function void set_valid(logic v);
    vif.g_sim.sim_rvalid <= v;
  endfunction : set_valid

  virtual function void set_ready(logic v);
    vif.g_sim.sim_rready <= v;
  endfunction : set_ready

  virtual function logic get_valid();
    return vif.rvalid;
  endfunction : get_valid

  virtual function logic get_ready();
    return vif.rready;
  endfunction : get_ready
endclass : axil_r_hs



// Class: axil_r_receiver
//
// Receiver for R channel (provide ~rready~ signal handling)
//
class axil_r_receiver #(`IF_PARAMS) extends axil_r_hs #(`IF_PARAMS_MAP, .base(slave_hs));

  typedef axil_r_receiver #(`IF_PARAMS_MAP) this_type;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  static function this_type create(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    create = new(vif, c);
  endfunction : create

  virtual task async_event();
    @(vif.rvalid);
  endtask : async_event

  virtual function void do_clean();
    // nothing to do
  endfunction : do_clean
endclass : axil_r_receiver



// Class: axil_r_transmitter
//
// Transmitter for R channel
// Puts r* items fields to R channel
//
class axil_r_transmitter #(`IF_PARAMS, type item_t = gvip_axil_item_pkg::item #(`IF_PARAMS_MAP))
      extends axil_r_hs #(`IF_PARAMS_MAP, .base(amba_transmitter_for_single_transfer #(item_t)));

  typedef axil_r_transmitter #(`IF_PARAMS_MAP, .item_t(item_t)) this_type;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  static function this_type create(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    create = new(vif, c);
  endfunction : create

  task async_event();
    @(vif.rready);
  endtask : async_event

  virtual function void interface_transaction(item_t item);
    vif.g_sim.sim_rdata <= item.rdata;
    vif.g_sim.sim_rresp <= item.rresp;
  endfunction : interface_transaction

endclass : axil_r_transmitter



// Class: axil_r_monitor
//
// Monitor for R channel
//
class axil_r_monitor #(`IF_PARAMS, type item_t = gvip_axil_item_pkg::item #(`IF_PARAMS_MAP))
      extends axil_r_hs #(`IF_PARAMS_MAP,
                          .base(amba_monitor_ap_support_for_single_transfers #(item_t)));

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  virtual function void interface_transaction(ref item_t item);
    item.tr_type = gvip::R;
    item.rresp = vif.rresp;
    item.rdata = vif.rdata;
  endfunction : interface_transaction

  virtual function void send_response(item_t response);
    greporter::error("axil",
      "Can't send responce for R transaction, if really required implement this in test");
  endfunction : send_response
endclass : axil_r_monitor
