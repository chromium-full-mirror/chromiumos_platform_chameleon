/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// verilog_syntax: parse-as-package-body

// Interface class: generic_ic
//
// Defines functions and tasks which are
// interface's parameters independent
interface class generic_ic;

  // Function: get_data_width
  //
  // Returns width of tdata in bits
  pure virtual function int unsigned get_data_width();

  // Function: get_user_width
  //
  // Returns width of tuser in bits
  pure virtual function int unsigned get_user_width();

  // Function: get_keep_width
  //
  // Returns width of tkeep in bits
  pure virtual function int unsigned get_keep_width();

  // Function: get_vip_type
  //
  // Returns type of VIP
  pure virtual function gvip_type_e  get_vip_type();

  // Function: set_policy
  //
  // Assign new handshake policy to VIP
  //
  // obj - policy object derived from gvip_policy_pkg::policy
  // do_randomize_policy - if set, VIP will call randomize method at policy object,
  //                       usefull when policy is created without declaration e.g.:
  //                       vip.set_policy(gvip_policy_pkg::random::create("def_random"), 1);
  // clone - in default VIP will clone policy to operate on it
  pure virtual function void set_policy(policy obj, bit do_randomize_policy = 0, bit clone = 1);

  // Function: add_generic_ap2pkt
  //
  // Use this function to register object with generic analysis port interface implementation,
  // `write` function from this interface will be called with tlast occurrence
  // Any number of object can be register but since item does not deliver clone functionality
  // the same object instance will be pass to all subscribers
  pure virtual function void add_generic_ap2pkt(generic_analysis_port_ic ap);

  // Function: add_generic_ap2transfer
  //
  // Use this function to register object with generic analysis port interface implementation,
  // `write` function from this interface will be called with each transfer occurrence
  // Any number of object can be register but since item does not deliver clone functionality
  // the same object instance will be pass to all subscribers
  pure virtual function void add_generic_ap2transfer(generic_analysis_port_ic ap);

  // Function: run_phase
  //
  // Main VIPs service loop - run VIPs processing (must be called by test)
  // This task spawn internal processes and return immediately
  // Spawned processes are endless unless ~gvip_config::stop_vip~ is set
  pure virtual task run_phase();

  // Function: send_item
  //
  // This task sends data item to AxiStream interface
  // If some package is currently trasmited, new item will be added to queue
  // depending ~item.is_posted~ field task ends immediately or block
  // Supports any type derived from bitem (e.g.  ~generic_item~ or ~item_t~)
  pure virtual task send_item(bitem item);

  // Function: clean
  //
  // This function clean VIP
  // Brakes any transfers at interface, clear all queues and any data structures
  pure virtual function void clean();
endclass : generic_ic

// Interface class: policy_tlast_ic
//
// Defines function for policies which uses tlast
interface class policy_tlast_ic;

  // Function: get_last
  //
  // Returns tlast value
  pure virtual function logic get_last();
endclass : policy_tlast_ic


// Interface class: policy_tlast_setup_ic
//
// Defines function to get access to get_last
interface class policy_tlast_setup_ic;
  // Function: set_hs_tlast_access
  //
  // Callback which enables access to get_last function
  pure virtual function void set_hs_tlast_access(policy_tlast_ic obj);
endclass : policy_tlast_setup_ic


///////////////////////////////////////////////////////////////////////////////////////////////////

// Class: to_generic_item_ap
//
// Converts analysis_port_ic callback to generic_analysis_port_ic
class to_generic_item_ap #(type item_t = logic) implements analysis_port_ic #(item_t);

  typedef to_generic_item_ap #(item_t) this_type;

  generic_analysis_port_ic ap;
  gvip_config cfg;

  function new(generic_analysis_port_ic generic_ap, gvip_config vcfg);
    ap = generic_ap;
    cfg = vcfg;
  endfunction : new

  static function this_type create(generic_analysis_port_ic generic_ap, gvip_config vcfg);
    create = new(generic_ap, vcfg);
  endfunction : create

  virtual function void write (input item_t item);
    generic_item gi = gvip_axis_item_pkg::item_conv #(item_t)::item2generic(item,
                                                                cfg.generic_item_squize_by_tkeep);
    ap.write(gi);
  endfunction : write

endclass : to_generic_item_ap


///////////////////////////////////////////////////////////////////////////////////////////////////

// Class: axis_hs
//
// Implements axis specific functions for handshake class
virtual class axis_hs #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0], type base = logic,
                        type item_t = gvip_axis_item_pkg::item #(N, I, D, U_T))
                        extends base implements policy_tlast_ic;

  gvip_config cfg;

  virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif;

  function new(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    gvip_config vcfg
  );
    super.new(c);
    this.vif = vif;
    cfg = vcfg;
  endfunction : new

  function void set_policy(gvip_policy_pkg::policy obj, bit clone = 1);
    policy_tlast_setup_ic ic;
    if ($cast(ic, obj)) ic.set_hs_tlast_access(this);
    super.set_policy(obj);
  endfunction : set_policy

  virtual function void set_valid(logic v);
    vif.g_sim.sim_tvalid <= v;
  endfunction : set_valid

  virtual function void set_ready(logic v);
    vif.g_sim.sim_tready <= v;
  endfunction : set_ready

  virtual function logic get_valid();
    return vif.tvalid;
  endfunction : get_valid

  virtual function logic get_ready();
    return vif.tready;
  endfunction : get_ready

  virtual function logic get_last();
    return vif.tlast;
  endfunction : get_last

endclass : axis_hs


///////////////////////////////////////////////////////////////////////////////////////////////////

// Class: axis_master_hs
//
// Implements axis master specific functions for axis_hs class
class axis_master_hs #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0],
                       type item_t = gvip_axis_item_pkg::item #(N, I, D, U_T))
                       extends axis_hs#(N, I, D, U_T, master_hs, item_t);

  typedef axis_master_hs #(N, I, D, U_T, item_t) this_type;

  local mailbox #(gvip_axis_item_pkg::bitem) items_queue;
  local gvip_axis_item_pkg::bitem bitem_from_q;
  local gvip_policy_pkg::policy backup_vip_main_policy;
  local item_t current_item;
  local int transfers_in_item;
  local int pending_transfers;

  function new(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    gvip_config vcfg
  );
    super.new(vif, c, vcfg);
    items_queue = new();
    do_clean();
  endfunction : new

  static function this_type create(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    gvip_config vcfg
  );
    create = new(vif, c, vcfg);
  endfunction : create

  // Function: put
  //
  // Adds item to send queue
  task put(gvip_axis_item_pkg::bitem item);
    items_queue.put(item);
  endtask : put

  task async_event();
    @(vif.tready);
  endtask : async_event

  virtual task pre_transaction_cb();
    if (current_item == null) begin
      get_new_item(current_item, transfers_in_item);
      set_policy_from_item(current_item);
      pending_transfers = transfers_in_item;
    end

    interface_transaction(current_item, transfers_in_item-pending_transfers, pending_transfers==1);
    pending_transfers--;
  endtask : pre_transaction_cb

  virtual task post_transaction_cb();
    if (pending_transfers == 0) post_last();
  endtask : post_transaction_cb

  virtual function void post_last();
    ->bitem_from_q.post;
    prepare_for_next_item();
  endfunction : post_last

  virtual function void prepare_for_next_item();
    bitem_from_q = null;
    current_item = null;
    restore_vip_policy();
  endfunction : prepare_for_next_item

  virtual task get_new_item(output item_t next_item, output int size);
    generic_item g_item;
    items_queue.get(bitem_from_q);
    // If bitem_from_q is generic_item convert it to item_t
    if ($cast(g_item, bitem_from_q)) begin
      next_item = gvip_axis_item_pkg::item_conv #(item_t)::generic2item(g_item,
        cfg.warn_resize_mismatch_from_generic, cfg.generic_item_squize_by_tkeep, cfg.report_id);
    end else if (!$cast(next_item, bitem_from_q)) begin
      greporter::fatal(cfg.report_id, "item cast issue");
    end
    size = next_item.tdata.size();
  endtask : get_new_item

  virtual function void interface_transaction(item_t item, int unsigned transfer_idx, int is_last);
    vif.g_sim.sim_tdata <= item.tdata[transfer_idx];
    vif.g_sim.sim_tuser <= item.tuser[transfer_idx];
    vif.g_sim.sim_tkeep <= item.tkeep[transfer_idx];
    vif.g_sim.sim_tstrb <= item.tstrb[transfer_idx];
    vif.g_sim.sim_tid   <= item.tid;
    vif.g_sim.sim_tdest <= item.tdest;
    vif.g_sim.sim_tlast <= is_last ? item.tlast : 1'b0;
  endfunction : interface_transaction

  // Function: set_policy_from_item
  //
  // If item has valid policy set as temporarily as vip policy
  virtual function void set_policy_from_item(item_t item);
    if (item.policy != null) begin
      backup_vip_main_policy = get_policy();
      set_policy(item.policy);
    end
  endfunction : set_policy_from_item

  // Function: restore_vip_policy
  //
  // If there is temporarily set policy from item restore the vip one
  virtual function void restore_vip_policy();
    if (backup_vip_main_policy != null) begin
      set_policy(backup_vip_main_policy);
      backup_vip_main_policy = null;
    end
  endfunction : restore_vip_policy

  virtual function void do_clean();
    while (items_queue.try_get(bitem_from_q));
    prepare_for_next_item();
  endfunction : do_clean

endclass : axis_master_hs


///////////////////////////////////////////////////////////////////////////////////////////////////

// Class: axis_slave_hs
//
// Implements axis slave specific functions for axis_hs class
class axis_slave_hs #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0],
                      type item_t = gvip_axis_item_pkg::item #(N, I, D, U_T))
                      extends axis_hs #(N, I, D, U_T, slave_hs, item_t);

  typedef axis_slave_hs #(N, I, D, U_T, item) this_type;

  function new(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    gvip_config vcfg
  );
    super.new(vif, c, vcfg);
  endfunction : new

  static function this_type create(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    gvip_config vcfg
  );
    create = new(vif, c, vcfg);
  endfunction : create

  task async_event();
    @(vif.tvalid);
  endtask : async_event

  function void do_clean();
    // Slave does not require any cleanup
  endfunction : do_clean

endclass : axis_slave_hs


///////////////////////////////////////////////////////////////////////////////////////////////////

// Class: axis_monitor_hs
//
// Implements axis monitor specific functions for axis_hs class
class axis_monitor_hs #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0],
                        type item_t = gvip_axis_item_pkg::item #(N, I, D, U_T))
                        extends axis_hs #(N, I, D, U_T, monitor_hs, item_t);

  protected analysis_port_ic #(item_t) item_pkt_cb[$];
  protected analysis_port_ic #(item_t) item_tr_cb[$];
  local item_t pkt;
  local bit    tfirst = 1;

  function new(
    virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif,
    virtual gclk_if c,
    gvip_config vcfg
  );
    super.new(vif, c, vcfg);
  endfunction : new

  function void add_ap2pkt(analysis_port_ic #(item_t) ap);
    item_pkt_cb.push_back(ap);
  endfunction : add_ap2pkt

  function void add_ap2transfer(analysis_port_ic #(item_t) ap);
    item_tr_cb.push_back(ap);
  endfunction : add_ap2transfer

  protected virtual function void reset_cb();
    tfirst = 1;
    pkt = null;
  endfunction : reset_cb

  // Function: transaction_cb
  //
  // Callects values from the interface and creates item_t with single beat
  protected virtual function void transaction_cb();
    item_t tr = new();
    tr.tdata = {vif.tdata};
    tr.tuser = {vif.tuser};
    tr.tkeep = {vif.tkeep};
    tr.tstrb = {vif.tstrb};
    tr.tlast = vif.tlast;
    tr.tid   = vif.tid;
    tr.tdest = vif.tdest;
    tr.tr_time_begin = $realtime;
    tr.tr_time_end = $realtime;

    if (cfg.mask_data_with_keep_in_ap) begin
      tr.mask_data_with_tkeep();
    end

    foreach(item_tr_cb[i]) begin
      item_tr_cb[i].write(tr);
    end

    package_compose(tr);
  endfunction : transaction_cb

  // Function: package_compose
  //
  // Combine beats to packet
  // tr - item_t with single beat
  protected virtual function void package_compose(item_t tr);
    if (item_pkt_cb.size()) begin
      if (tfirst) begin
        pkt = new();
        pkt.tr_time_begin = $realtime;
      end
      pkt.tdata = {pkt.tdata, tr.tdata};
      pkt.tuser = {pkt.tuser, tr.tuser};
      pkt.tkeep = {pkt.tkeep, tr.tkeep};
      pkt.tstrb = {pkt.tstrb, tr.tstrb};
      pkt.tlast = vif.tlast;
      pkt.tid   = vif.tid;
      pkt.tdest = vif.tdest;
      pkt.tr_time_end = $realtime;

      tfirst = vif.tlast;

      if (vif.tlast) begin
        foreach(item_pkt_cb[i]) begin
          item_pkt_cb[i].write(pkt);
        end
      end
    end
  endfunction : package_compose

  virtual function void do_clean();
    pkt = null;
    tfirst = 1;
  endfunction : do_clean

endclass : axis_monitor_hs


///////////////////////////////////////////////////////////////////////////////////////////////////

// Class: core_imp
//
// Hides core class' internal fields
class core_imp #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0],
                 type item_t = gvip_axis_item_pkg::item #(N, I, D, U_T));

  protected virtual gaxis_if #(.N(N), .I(I), .D(D), .U_T(U_T)) vif;
  protected virtual gclk_if vclk;
  protected string name;
  protected gvip_type_e vip_type;
  protected axis_monitor_hs #(N, I, D, U_T, item_t) mon_hs;
  protected gvip_axis_coverage #(.N(N), .I(I), .D(D), .U_T(U_T)) coverage;
  protected handshake hs;
  protected gvip_config cfg;

endclass : core_imp
