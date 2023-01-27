/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: aximm_r_hs
//
// Virtual class with R channel handshake support
// This class partialy implements interface required by gvip_handshake_pkg::handshake
virtual class aximm_r_hs #(`IF_PARAMS, type base = handshake) extends base;
  virtual gaximm_if #(`IF_PARAMS_MAP) vif;

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
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
endclass : aximm_r_hs



// Class: aximm_r_receiver
//
// Receiver for R channel (provide ~rready~ signal handling)
//
class aximm_r_receiver #(`IF_PARAMS) extends aximm_r_hs #(`IF_PARAMS_MAP, .base(slave_hs));

  typedef aximm_r_receiver #(`IF_PARAMS_MAP) this_type;

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

  virtual task async_event();
    @(vif.rvalid);
  endtask : async_event

  virtual function void do_clean();
    // nothing to do
  endfunction : do_clean
endclass : aximm_r_receiver



// Class: aximm_r_transmitter
//
// Transmitter for R channel
// Puts r* items fields to R channel
//
class aximm_r_transmitter #(`IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #(`IF_PARAMS_MAP))
      extends aximm_r_hs #(`IF_PARAMS_MAP, .base(aximm_transmitter_for_multi_transfers #(item_t)));

  typedef aximm_r_transmitter #(`IF_PARAMS_MAP, .item_t(item_t)) this_type;

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
    @(vif.rready);
  endtask : async_event

  virtual function void interface_transaction(item_t item, int unsigned transfer_idx, int is_last);
    vif.g_sim.sim_rlast <= is_last;
    vif.g_sim.sim_rid   <= item.rid;
    vif.g_sim.sim_rdata <= item.rdata[transfer_idx];
    vif.g_sim.sim_ruser <= item.ruser[transfer_idx];
    vif.g_sim.sim_rresp <= item.rresp;
  endfunction : interface_transaction

  virtual function int get_data_size(item_t item);
    return item.rdata.size();
  endfunction : get_data_size
endclass : aximm_r_transmitter



// Class: aximm_r_monitor
//
// Monitor for R channel
//
class aximm_r_monitor #(`IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #(`IF_PARAMS_MAP))
      extends aximm_r_hs #(`IF_PARAMS_MAP,
                          .base(aximm_monitor_ap_support_for_multi_transfers #(item_t)));

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(vif, c);
  endfunction : new

  virtual function void interface_transaction(ref item_t item);
    item.tr_type = gvip::R;
    item.rid = vif.rid;
    item.rresp = vif.rresp;
    item.rdata = {vif.rdata};
    item.ruser = {vif.ruser};
  endfunction : interface_transaction

  virtual function bit build_packet(ref item_t pkt, item_t item);
    pkt.tr_type = gvip::R;
    pkt.rid   = item.rid;
    pkt.rresp = item.rresp;
    pkt.rdata = {pkt.rdata, item.rdata};
    pkt.ruser = {pkt.ruser, item.ruser};
    return vif.rlast;
  endfunction : build_packet

  virtual function void send_response(item_t response);
    greporter::error("AXIMM",
      "Can't send responce for R transaction, if really required implement this in test");
  endfunction : send_response
endclass : aximm_r_monitor
