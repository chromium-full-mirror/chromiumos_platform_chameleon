/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */


// Interfaces parameters definition and mapping, used for code clarity
`define IF_PARAMS int N=1, int I=1, int A=1, type U_REQ=logic[0:0], \
                                             type U_DATA=logic[0:0], \
                                             type U_RESP=logic[0:0]
`define IF_PARAMS_MAP .N(N), .I(I), .A(A), \
                      .U_REQ(U_REQ), .U_DATA(U_DATA), .U_RESP(U_RESP)


// Class: item_mailbox_wrp
//
// Helper mailbox wrapper class
class item_mailbox_wrp #(type item_t = logic);
  local mailbox #(item_t) mb;

  function new();
    mb = new();
  endfunction : new

  function void put(item_t item);
    void'(mb.try_put(item));
  endfunction : put

  task get(output item_t item);
    mb.get(item);
  endtask : get

  function void clean();
    item_t dummy;
    while (mb.try_get(dummy));
  endfunction : clean

endclass : item_mailbox_wrp



// Interface class: put_item_ic
//
// interface class with put method used by send_response from analysis ports
interface class put_item_ic #(type item_t = logic);
  pure virtual function void put(item_t item);
endclass : put_item_ic



// Class: aximm_transmitter_for_single_transfer
//
// This class implements common item processing for single beat interfaces (AW, AR, B)
//
virtual class aximm_transmitter_for_single_transfer #(type item_t = logic) extends master_hs
                                                                  implements put_item_ic #(item_t);

  local item_mailbox_wrp #(item_t) pending_items;
  local items_policy_setter #(item_t) pbuckup;
  local item_t current_item;

  pure virtual function void interface_transaction(item_t item);

  function new(virtual gclk_if c);
    super.new(c);
    pbuckup = new(this);
    pending_items = new();
    do_clean();
  endfunction : new

  virtual function void put(item_t item);
    pending_items.put(item);
  endfunction : put

  virtual task pre_transaction_cb();
    get_new_item(current_item);
    pbuckup.policy_from_item(current_item);
    interface_transaction(current_item);
  endtask : pre_transaction_cb

  virtual task post_transaction_cb();
    pbuckup.restore_original_policy();
  endtask : post_transaction_cb

  virtual task get_new_item(output item_t next_item);
    pending_items.get(next_item);
  endtask : get_new_item

  virtual function void do_clean();
    pending_items.clean();
  endfunction : do_clean

endclass : aximm_transmitter_for_single_transfer



// Class: aximm_transmitter_for_multi_transfers
//
// This class implements common item processing for multi beat interfaces (W, R)
//
virtual class aximm_transmitter_for_multi_transfers #(type item_t) extends master_hs
                                                    implements put_item_ic #(item_t);
  local item_mailbox_wrp #(item_t) pending_items;
  local items_policy_setter #(item_t) pbuckup;
  local item_t current_item;
  local int transfers_in_item;
  local int pending_transfers;

  pure virtual function int get_data_size(item_t item);
  pure virtual function void interface_transaction(item_t item,
                                                   int unsigned transfer_idx,
                                                   int is_last);

  function new(virtual gclk_if c);
    super.new(c);
    pbuckup = new(this);
    pending_items = new();
    do_clean();
  endfunction : new

  virtual function void put(item_t item);
    pending_items.put(item);
  endfunction : put

  virtual task pre_transaction_cb();
    if (current_item == null) begin
      get_new_item(current_item, transfers_in_item);
      pbuckup.policy_from_item(current_item);
      pending_transfers = transfers_in_item;
    end

    interface_transaction(current_item,
                          transfers_in_item-pending_transfers,
                          pending_transfers==1);
    pending_transfers--;
  endtask : pre_transaction_cb

  virtual task post_transaction_cb();
    if (pending_transfers == 0) post_last();
  endtask : post_transaction_cb

  virtual function void post_last();
    prepare_for_next_item();
  endfunction : post_last

  virtual function void prepare_for_next_item();
    current_item = null;
    pbuckup.restore_original_policy();
  endfunction : prepare_for_next_item

  virtual task get_new_item(output item_t next_item, output int size);
    pending_items.get(next_item);
    size = get_data_size(next_item);
  endtask : get_new_item

  virtual function void do_clean();
    pending_items.clean();
    prepare_for_next_item();
  endfunction : do_clean

endclass : aximm_transmitter_for_multi_transfers



// Class: aximm_monitor_ap_support_for_multi_transfers
//
// This class implements common analysis port support
// for multi beat interfaces (W, R)
//
virtual class aximm_monitor_ap_support_for_multi_transfers #(type item_t = logic)
                                                            extends monitor_hs;

  protected analysis_port_ic #(item_t) item_pkt_cb[$]; // packet analysis port database
  protected analysis_port_ic #(item_t) item_tr_cb[$];  // transfer analysis port database
  local     item_t                    pkt;            // the currently assembled packet
  local     bit                       pkt_first_item = 1; // first transfer for packet assemble

  pure virtual function void interface_transaction(ref item_t item);
  pure virtual function void send_response(item_t response);
  pure virtual function bit build_packet(ref item_t pkt, item_t item);

  function new(virtual gclk_if c);
    super.new(c);
  endfunction : new

  // Function: add_ap2pkt
  //
  // Use this function to register object with analysis port interface implementation,
  // `write` function from this interface will be called with tlast occurrence
  virtual function void add_ap2pkt(analysis_port_ic #(item_t) ap);
    item_pkt_cb.push_back(ap);
  endfunction : add_ap2pkt

  // Function: add_ap2transfer
  //
  // Use this function to register object with analysis port interface implementation,
  // `write` function from this interface will be called with each transfer occurrence
  virtual function void add_ap2transfer(analysis_port_ic #(item_t) ap);
    item_tr_cb.push_back(ap);
  endfunction : add_ap2transfer

  // Function: reset_cb
  //
  // monitor_hs::reset_cb callback implementation
  protected virtual function void reset_cb();
    do_clean();
  endfunction : reset_cb

  // Function: write_to_ap
  //
  // Call ~write~ function with ~item~ for registered analysis ports
  // Validate if only one AP returns responce object, if not warning is printed
  // and only response for last registered port will be handed over for processing
  virtual function item_t write_to_ap(ref analysis_port_ic #(item_t) aports[$], item_t item);
    item_t ap_resp;
    foreach(aports[i]) begin
      ap_resp = aports[i].write(item);
      if (write_to_ap != null && ap_resp != null) begin
        greporter::warning("AXIMM", "Multi response from AP");
      end
      write_to_ap = ap_resp;
    end
  endfunction : write_to_ap

  // Function: transaction_cb
  //
  // Callects values from the interface and process
  protected virtual function void transaction_cb();
    item_t resp;
    item_t ap_resp;
    item_t tr = new();
    tr.tr_time_begin = $realtime;
    tr.tr_time_end = $realtime;

    // collect transaction item from interface
    interface_transaction(tr);

    // send transaction item to transaction analysis ports
    resp = write_to_ap(item_tr_cb, tr);

    // compose package from single transactions
    package_compose(tr, resp);

    // send response received from AP if any
    if (resp != null) send_response(resp);

  endfunction : transaction_cb

  // Function: package_compose
  //
  // Combine beats to packet
  protected virtual function void package_compose(item_t tr, ref item_t resp);
    bit completed;
    if (item_pkt_cb.size()) begin
      if (pkt_first_item) begin
        pkt = new();
        pkt.tr_time_begin = $realtime;
        pkt_first_item = 0;
      end
      pkt.tr_time_end = $realtime;
      completed = build_packet(pkt, tr);

      if (completed) begin
        resp = write_to_ap(item_pkt_cb, pkt);
        pkt_first_item = 1;
      end
    end
  endfunction : package_compose

  // Function: do_clear
  //
  // Clear internal states
  virtual function void do_clean();
    pkt = null;
    pkt_first_item = 1;
  endfunction : do_clean

endclass : aximm_monitor_ap_support_for_multi_transfers



// Class: aximm_monitor_ap_support_for_single_transfers
//
// Specialisation of aximm_monitor_ap_support_for_multi_transfers class for sinle beat
// disable packet building from single beats
//
virtual class aximm_monitor_ap_support_for_single_transfers #(type item_t = logic)
  extends aximm_monitor_ap_support_for_multi_transfers #(item_t);

  function new(virtual gclk_if c);
    super.new(c);
  endfunction: new

  virtual function void add_ap2pkt(analysis_port_ic #(item_t) ap);
    add_ap2transfer(ap);
  endfunction : add_ap2pkt

  virtual function bit build_packet(ref item_t pkt, item_t item);
    // empty - only extended mutil beat class must implement this
    return 1;
  endfunction : build_packet

  protected virtual function void package_compose(item_t tr, ref item_t resp);
    // empty - only for multi beat interfaces class
  endfunction : package_compose

endclass : aximm_monitor_ap_support_for_single_transfers


//////////////////////
// Channels support //
//////////////////////

`include "gvip_aximm_imp_aw.svh"
`include "gvip_aximm_imp_w.svh"
`include "gvip_aximm_imp_b.svh"
`include "gvip_aximm_imp_ar.svh"
`include "gvip_aximm_imp_r.svh"


/////////////////////////
// AW_W pseudo channel //
/////////////////////////

// Interface class: aww_analysis_port_ic
//
// Interface for AW_W monitor with AW and W channels
//
interface class aww_analysis_port_ic #(type item_t = logic);
  pure virtual function item_t write_aw (item_t item);
  pure virtual function item_t write_w (item_t item);
endclass



// Class: aww_ap_aw_ch
//
// AW channel analisis port for AW_W agregator
//
class aww_ap_aw_ch #(type item_t = logic) implements analysis_port_ic #(item_t);
  aww_analysis_port_ic#(item_t) aww_mon;

  function new(aww_analysis_port_ic #(item_t) aww);
    aww_mon = aww;
  endfunction : new

  virtual function item_t write (item_t item);
    return aww_mon.write_aw(item);
  endfunction : write
endclass : aww_ap_aw_ch



// Class: aww_ap_w_ch
//
// W channel analisis port for AW_W agregator
//
class aww_ap_w_ch #(type item_t = logic) implements analysis_port_ic #(item_t);
  aww_analysis_port_ic#(item_t) aww_mon;

  function new(aww_analysis_port_ic #(item_t) aww);
    aww_mon = aww;
  endfunction : new

  virtual function item_t write (item_t item);
    return aww_mon.write_w(item);
  endfunction : write
endclass : aww_ap_w_ch



// Class: aximm_aw_w_monitor
//
// Monitor for pseudo channel AW_W, registers itself as analysis ports for AW and W channels
// Combines items from this two interfaces into single item and send it to user's registered
// analysis port. Forwards returning item to AW or W monitor
//
class aximm_aw_w_monitor #(type item_t = logic) implements aww_analysis_port_ic #(item_t);

  protected analysis_port_ic #(item_t) item_pkt_cb[$];
  aximm_monitor_ap_support_for_single_transfers #(item_t) mon_aw;
  aximm_monitor_ap_support_for_multi_transfers #(item_t) mon_w;

  aww_ap_w_ch #(item_t)  w_ap;  // W channel analysis port
  aww_ap_aw_ch #(item_t) aw_ap; // AW channel analysis port

  mailbox #(item_t) w_mb = new();  // outstending W items
  mailbox #(item_t) aw_mb = new(); // outstending AW items

  function new(aximm_monitor_ap_support_for_single_transfers #(item_t) mon_aw,
               aximm_monitor_ap_support_for_multi_transfers #(item_t) mon_w);
    this.mon_aw = mon_aw;
    this.mon_w = mon_w;
  endfunction : new

  virtual function item_t write_aw (item_t item);
    item_t w;
    if (!w_mb.try_get(w)) begin
      if (!aw_mb.try_put(item)) greporter::fatal("AXIMM", "Something went wrong");
      return null;
    end else begin
      item_t aw_w_item = concat_items(item, w);
      return write_to_ap(aw_w_item);
    end
  endfunction : write_aw

  virtual function item_t write_w (item_t item);
    item_t aw;
    if (!aw_mb.try_get(aw)) begin
      if (!w_mb.try_put(item)) greporter::fatal("AXIMM", "Something went wrong");
      return null;
    end else begin
      item_t aw_w_item = concat_items(aw, item);
      return write_to_ap(aw_w_item);
    end
  endfunction : write_w

  function item_t write_to_ap (item_t aw_w_item);
    item_t ap_resp;
    foreach(item_pkt_cb[i]) begin
      ap_resp = item_pkt_cb[i].write(aw_w_item);
      if (write_to_ap != null && ap_resp != null) begin
        greporter::warning("AXIMM", "Multi response from AP");
      end
      write_to_ap = ap_resp;
    end
  endfunction : write_to_ap

  function void add_ap2pkt(analysis_port_ic #(item_t) ap);
    if (item_pkt_cb.size() == 0) begin
      aw_ap = new(this);
      w_ap = new(this);
      mon_aw.add_ap2pkt(aw_ap);
      mon_w.add_ap2pkt(w_ap);
    end
    item_pkt_cb.push_back(ap);
  endfunction : add_ap2pkt

  function item_t concat_items(item_t aw, item_t w);
    concat_items = new aw;
    concat_items.tr_type = gvip::AW_W;
    concat_items.wdata = w.wdata;
    concat_items.wstrb = w.wstrb;
    concat_items.wuser = w.wuser;
  endfunction : concat_items

endclass : aximm_aw_w_monitor



// Class: core_imp
//
// Hides core class' internal fields
class core_imp #( `IF_PARAMS, type item_t = gvip_aximm_item_pkg::item #( `IF_PARAMS_MAP ) );
  protected virtual gaximm_if #(`IF_PARAMS_MAP) vif;
  protected virtual gclk_if vclk;
  protected string name;
  protected gvip::type_e vip_type;
  protected gvip_config cfg;
  protected handshake ch_aw;
  protected handshake ch_w;
  protected handshake ch_b;
  protected handshake ch_ar;
  protected handshake ch_r;
  protected aximm_aw_monitor #( `IF_PARAMS_MAP, .item_t(item_t)) mon_ch_aw;
  protected aximm_ar_monitor #( `IF_PARAMS_MAP, .item_t(item_t)) mon_ch_ar;
  protected aximm_w_monitor #( `IF_PARAMS_MAP, .item_t(item_t))  mon_ch_w;
  protected aximm_b_monitor #( `IF_PARAMS_MAP, .item_t(item_t))  mon_ch_b;
  protected aximm_r_monitor #( `IF_PARAMS_MAP, .item_t(item_t))  mon_ch_r;
  protected aximm_aw_w_monitor #(.item_t(item_t)) mon_aw_w;
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
