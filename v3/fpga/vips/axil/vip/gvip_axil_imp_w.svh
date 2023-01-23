/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: axil_w_hs
//
// Virtual class with W channel handshake support
// This class partially implements interface required by gvip_handshake_pkg::handshake
virtual class axil_w_hs #(`IF_PARAMS, type base = handshake) extends base;
  virtual gaxil_if #(`IF_PARAMS_MAP) vif;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
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
endclass : axil_w_hs



// Class: axil_w_receiver
//
// Receiver for W channel (provide ~wready~ signal handling)
//
class axil_w_receiver #(`IF_PARAMS) extends axil_w_hs #( `IF_PARAMS_MAP, .base(slave_hs));

  typedef axil_w_receiver #(`IF_PARAMS_MAP) this_type;

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
    @(vif.wvalid);
  endtask : async_event

  function void do_clean();
    // nothing to do
  endfunction : do_clean
endclass : axil_w_receiver



// Class: axil_w_transmitter
//
// Transmitter for W channel
// Puts w* items fields to W channel
//
class axil_w_transmitter #(`IF_PARAMS, type item_t = gvip_axil_item_pkg::item #(`IF_PARAMS_MAP))
      extends axil_w_hs #(`IF_PARAMS_MAP, .base(amba_transmitter_for_single_transfer #(item_t)));

  typedef axil_w_transmitter #(`IF_PARAMS_MAP, .item_t(item_t)) this_type;

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
    @(vif.wready);
  endtask : async_event

  virtual function void interface_transaction(item_t item);
    vif.g_sim.sim_wdata <= item.wdata;
    vif.g_sim.sim_wstrb <= item.wstrb;
  endfunction : interface_transaction
endclass : axil_w_transmitter



// Class: axil_w_monitor
//
// Monitor for W channel
// Since this is W channel there can be response from AP which must be send
// to B channel, so this monitor need to have handler to B channel's transmitter
//
class axil_w_monitor #(`IF_PARAMS, type item_t = gvip_axil_item_pkg::item #(`IF_PARAMS_MAP))
      extends axil_w_hs #(`IF_PARAMS_MAP,
                           .base(amba_monitor_ap_support_for_single_transfers #(item_t)));

  put_item_ic #(item_t) transmitter;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c,
    handshake transmitter_b_channel
  );
    super.new(vif, c);
    void'($cast(transmitter, transmitter_b_channel));
  endfunction : new

  virtual function void interface_transaction(ref item_t item);
    item.tr_type = gvip::W;
    item.wdata = vif.wdata;
    item.wstrb = vif.wstrb;
  endfunction : interface_transaction

  virtual function void send_response(item_t response);
    if (transmitter != null) transmitter.put(response);
    else greporter::warning("axil", "W channel - Only monitor instance, can't send response");
  endfunction : send_response
endclass : axil_w_monitor
