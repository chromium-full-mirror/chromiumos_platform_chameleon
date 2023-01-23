/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */


// Interfaces parameters definition and mapping, used for code clarity
`define IF_PARAMS int N=1, int A=1
`define IF_PARAMS_MAP .N(N), .A(A)


//////////////////////
// Channels support //
//////////////////////
import gvip_amba_axi4_pkg::*;

`include "gvip_axil_imp_aw.svh"
`include "gvip_axil_imp_w.svh"
`include "gvip_axil_imp_b.svh"
`include "gvip_axil_imp_ar.svh"
`include "gvip_axil_imp_r.svh"


// Class: axil_aw_w_monitor
//
// Monitor for pseudo channel AW_W, registers itself as analysis ports for AW and W channels
// Combines items from this two interfaces into single item and send it to user's registered
// analysis port. Forwards returning item to AW or W monitor
//
class axil_aw_w_monitor #(type item_t = logic) extends amba_aw_w_monitor #(item_t);
  function new(amba_monitor_ap_support_for_single_transfers #(item_t) mon_aw,
               amba_monitor_ap_support_for_multi_transfers #(item_t) mon_w);
    super.new(mon_aw, mon_w);
  endfunction : new

  function item_t concat_items(item_t aw, item_t w);
    concat_items = new aw;
    concat_items.tr_type = gvip::AW_W;
    concat_items.wdata = w.wdata;
    concat_items.wstrb = w.wstrb;
  endfunction : concat_items
endclass : axil_aw_w_monitor


// Class: core_imp
//
// Hides core class' internal fields
class core_imp #( `IF_PARAMS, type item_t = gvip_axil_item_pkg::item #( `IF_PARAMS_MAP ) );
  protected virtual gaxil_if #(`IF_PARAMS_MAP) vif;
  protected virtual gclk_if vclk;
  protected string name;
  protected gvip::type_e vip_type;
  protected gvip_config cfg;
  protected handshake ch_aw;
  protected handshake ch_w;
  protected handshake ch_b;
  protected handshake ch_ar;
  protected handshake ch_r;
  protected axil_aw_monitor #( `IF_PARAMS_MAP, .item_t(item_t)) mon_ch_aw;
  protected axil_ar_monitor #( `IF_PARAMS_MAP, .item_t(item_t)) mon_ch_ar;
  protected axil_w_monitor #( `IF_PARAMS_MAP, .item_t(item_t))  mon_ch_w;
  protected axil_b_monitor #( `IF_PARAMS_MAP, .item_t(item_t))  mon_ch_b;
  protected axil_r_monitor #( `IF_PARAMS_MAP, .item_t(item_t))  mon_ch_r;
  protected axil_aw_w_monitor #(.item_t(item_t)) mon_aw_w;
endclass : core_imp



class channel_send #(type channel_t, type item_t);
  static function void put(handshake hs, item_t item, gvip_config cfg, string name);
    channel_t ch;
    if (hs == null) begin // there is no transmitter or receiver on this channel
      greporter::error(cfg.report_id,
        $sformatf("This VIP's configuration does not support transaction at %s channel", name));
    end else if (!$cast(ch, hs)) begin
      // VIP type is master but for some reason we can't cast
      // this should never happen
      greporter::fatal(cfg.report_id, "Wrong master VIP type");
    end else begin
      // put requested item to queue, CH main thread will take item and put on bus
      ch.put(item);
    end
  endfunction : put
endclass : channel_send


`undef IF_PARAMS
`undef IF_PARAMS_MAP
