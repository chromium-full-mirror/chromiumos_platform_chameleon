/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: aximm_b_hs
//
// Virtual class with B channel handshake support
// This class partialy implements interface required by gvip_handshake_pkg::handshake
virtual class aximm_b_hs #(`IF_PARAMS, type base = handshake) extends base;
  virtual gaximm_if #(`IF_PARAMS_MAP) vif;

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(c);
    this.vif = vif;
  endfunction : new

  virtual function void set_valid(logic v);
    vif.g_sim.sim_bvalid <= v;
  endfunction : set_valid

  virtual function void set_ready(logic v);
    vif.g_sim.sim_bready <= v;
  endfunction : set_ready

  virtual function logic get_valid();
    return vif.bvalid;
  endfunction : get_valid

  virtual function logic get_ready();
    return vif.bready;
  endfunction : get_ready
endclass : aximm_b_hs



// Class: aximm_b_receiver
//
// Receiver for B channel (provide ~bready~ signal handling)
//
class aximm_b_receiver #(`IF_PARAMS) extends aximm_b_hs #(`IF_PARAMS_MAP, .base(slave_hs));

  typedef aximm_b_receiver #(`IF_PARAMS_MAP) this_type;

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  static function this_type create(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    create = new(vif, c);
  endfunction : create

  task async_event();
    @(vif.bvalid);
  endtask : async_event

  function void do_clean();
    // nothing to do
  endfunction : do_clean
endclass : aximm_b_receiver



// Class: aximm_b_transmitter
//
// Transmitter for B channel
// Puts b* items fields to B channel
//
class aximm_b_transmitter #(`IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #(`IF_PARAMS_MAP))
      extends aximm_b_hs #(`IF_PARAMS_MAP, .base(amba_transmitter_for_single_transfer #(item_t)));

  typedef aximm_b_transmitter #(`IF_PARAMS_MAP, .item_t(item_t)) this_type;

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  static function this_type create(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    create = new(vif, c);
  endfunction : create

  task async_event();
    @(vif.bready);
  endtask : async_event

  virtual function void interface_transaction(item_t item);
    vif.g_sim.sim_bid   <= item.bid;
    vif.g_sim.sim_bresp <= item.bresp;
    vif.g_sim.sim_buser <= item.buser;
  endfunction : interface_transaction
endclass : aximm_b_transmitter



// Class: aximm_b_monitor
//
// Monitor for B channel
//
class aximm_b_monitor #(`IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #(`IF_PARAMS_MAP))
      extends aximm_b_hs #(`IF_PARAMS_MAP,
                          .base(amba_monitor_ap_support_for_single_transfers #(item_t)));

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  virtual function void interface_transaction(ref item_t item);
    item.tr_type = gvip::B;
    item.bid = vif.bid;
    item.bresp = vif.bresp;
    item.buser = vif.buser;
  endfunction : interface_transaction

  virtual function void send_response(item_t response);
    greporter::error("AXIMM",
      "Can't send responce for B transaction, if really required implement this in test");
  endfunction : send_response
endclass : aximm_b_monitor
