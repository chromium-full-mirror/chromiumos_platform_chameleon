/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: aximm_w_hs
//
// Virtual class with W channel handshake support
// This class partialy implements interface required by gvip_handshake_pkg::handshake
virtual class aximm_w_hs #(`IF_PARAMS, type base = handshake) extends base;
  virtual gaximm_if #(`IF_PARAMS_MAP) vif;

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(c);
    this.vif = vif;
  endfunction : new

  virtual function void set_valid(logic v);
    vif.g_sim.sim_wvalid <= v;
  endfunction : set_valid

  virtual function void set_ready(logic v);
    vif.g_sim.sim_wready <= v;
  endfunction : set_ready

  virtual function logic get_valid();
    return vif.wvalid;
  endfunction : get_valid

  virtual function logic get_ready();
    return vif.wready;
  endfunction : get_ready
endclass : aximm_w_hs



// Class: aximm_w_receiver
//
// Receiver for W channel (provide ~wready~ signal handling)
//
class aximm_w_receiver #(`IF_PARAMS) extends aximm_w_hs #( `IF_PARAMS_MAP, .base(slave_hs));

  typedef aximm_w_receiver #(`IF_PARAMS_MAP) this_type;

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
    @(vif.wvalid);
  endtask : async_event

  function void do_clean();
    // nothing to do
  endfunction : do_clean
endclass : aximm_w_receiver



// Class: aximm_w_transmitter
//
// Transmitter for W channel
// Puts w* items fields to W channel
//
class aximm_w_transmitter #(`IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #(`IF_PARAMS_MAP))
      extends aximm_w_hs #(`IF_PARAMS_MAP, .base(amba_transmitter_for_multi_transfers #(item_t)));

  typedef aximm_w_transmitter #(`IF_PARAMS_MAP, .item_t(item_t)) this_type;

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
    @(vif.wready);
  endtask : async_event

  virtual function void interface_transaction(item_t item, int unsigned transfer_idx, int is_last);
    vif.g_sim.sim_wlast <= is_last;
    vif.g_sim.sim_wdata <= item.wdata[transfer_idx];
    vif.g_sim.sim_wstrb <= item.wstrb[transfer_idx];
    vif.g_sim.sim_wuser <= item.wuser[transfer_idx];
  endfunction : interface_transaction

  virtual function int get_data_size(item_t item);
    return item.wdata.size();
  endfunction : get_data_size
endclass : aximm_w_transmitter



// Class: aximm_w_monitor
//
// Monitor for W channel
// Since this is W channel there can be response from AP which must be send
// to B channel, so this monitor need to have handler to B channel's transmitter
//
class aximm_w_monitor #(`IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #(`IF_PARAMS_MAP))
      extends aximm_w_hs #(`IF_PARAMS_MAP,
                           .base(amba_monitor_ap_support_for_multi_transfers #(item_t)));

  put_item_ic #(item_t) transmitter;

  function new(
    virtual gaximm_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c,
    handshake transmitter_b_channel
  );
    super.new(vif, c);
    void'($cast(transmitter, transmitter_b_channel));
  endfunction : new

  virtual function void interface_transaction(ref item_t item);
    item.tr_type = gvip::W;
    item.wdata = {vif.wdata};
    item.wstrb = {vif.wstrb};
    item.wuser = {vif.wuser};
  endfunction : interface_transaction

  virtual function bit build_packet(ref item_t pkt, item_t item);
    pkt.tr_type = gvip::W;
    pkt.wdata = {pkt.wdata, item.wdata};
    pkt.wstrb = {pkt.wstrb, item.wstrb};
    pkt.wuser = {pkt.wuser, item.wuser};
    return vif.wlast;
  endfunction : build_packet

  virtual function void send_response(item_t response);
    if (transmitter != null) transmitter.put(response);
    else greporter::warning("AXIMM", "W channel - Only monitor instance, can't send response");
  endfunction : send_response
endclass : aximm_w_monitor
