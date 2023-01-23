/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Class: axil_ar_hs
//
// Virtual class with AR channel handshake support
// This class partially implements interface required by gvip_handshake_pkg::handshake
virtual class axil_ar_hs #(`IF_PARAMS, type base = handshake) extends base;
  virtual gaxil_if #(`IF_PARAMS_MAP) vif;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c
  );
    super.new(c);
    this.vif = vif;
  endfunction : new

  virtual function void set_valid(logic v);
    vif.g_sim.sim_arvalid <= v;
  endfunction : set_valid

  virtual function void set_ready(logic v);
    vif.g_sim.sim_arready <= v;
  endfunction : set_ready

  virtual function logic get_valid();
    return vif.arvalid;
  endfunction : get_valid

  virtual function logic get_ready();
    return vif.arready;
  endfunction : get_ready
endclass : axil_ar_hs



// Class: axil_ar_receiver
//
// Receiver for AR channel (provide ~arready~ signal handling)
//
class axil_ar_receiver #(`IF_PARAMS) extends axil_ar_hs #(`IF_PARAMS_MAP, .base(slave_hs));

  typedef axil_ar_receiver #(`IF_PARAMS_MAP) this_type;

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
    @(vif.arvalid);
  endtask : async_event

  function void do_clean();
    // nothing to do
  endfunction : do_clean
endclass : axil_ar_receiver



// Class: axil_ar_transmitter
//
// Transmitter for AR channel
// Puts ar* items fields to AR channel
//
class axil_ar_transmitter #(`IF_PARAMS, type item_t = gvip_axil_item_pkg::item #(`IF_PARAMS_MAP))
      extends axil_ar_hs #(`IF_PARAMS_MAP, .base(amba_transmitter_for_single_transfer #(item_t)));

  typedef axil_ar_transmitter #( `IF_PARAMS_MAP, .item_t(item_t)) this_type;

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
    @(vif.arready);
  endtask : async_event

  virtual function void interface_transaction(item_t item);
    vif.g_sim.sim_araddr   <= item.araddr;
    vif.g_sim.sim_arprot   <= item.arprot;
  endfunction : interface_transaction
endclass : axil_ar_transmitter



// Class: axil_ar_monitor
//
// Monitor for AR channel
// Since this is AR channel there can be response from AP which must be send
// to R channel, so this monitor need to have handler to R channel's transmitter
//
class axil_ar_monitor #(`IF_PARAMS, type item_t = gvip_axil_item_pkg::item #(`IF_PARAMS_MAP))
      extends axil_ar_hs #(`IF_PARAMS_MAP,
                           .base(amba_monitor_ap_support_for_single_transfers #(item_t)));

  put_item_ic #(item_t) transmitter;

  function new(
    virtual gaxil_if #(`IF_PARAMS_MAP) vif,
    virtual gclk_if c,
    handshake transmitter_r_channel
  );
    super.new(vif, c);
    void'($cast(transmitter, transmitter_r_channel));
  endfunction : new

  virtual function void interface_transaction(ref item_t item);
    item.tr_type = gvip::AR;
    item.araddr = vif.araddr;
    item.arprot = vif.arprot;
  endfunction : interface_transaction

  virtual function void send_response(item_t response);
    if (transmitter != null) transmitter.put(response);
    else greporter::warning("axil", "AR channel - Only monitor instance, can't send response");
  endfunction : send_response
endclass : axil_ar_monitor
