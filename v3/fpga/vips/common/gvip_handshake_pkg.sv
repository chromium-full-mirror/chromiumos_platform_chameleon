/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////
// Handshake classes implementation //
//////////////////////////////////////

package gvip_handshake_pkg;

  import greporter_pkg::greporter;
  import gvip_policy_pkg::policy;


  // Class: handshake
  //
  // This class implements interface handshake
  // It is vip's base functionality. It assumes that
  // interface uses handshake mechanism, has
  // two sides (master/slave) and is monitored.
  //
  virtual class handshake;

    virtual gclk_if clk; // clock interface
    protected process p;
    protected event policy_set_e; // event for async polisy in case of policy change
    protected gvip_policy_pkg::policy policy; // current used policy

    extern                        function new(virtual gclk_if c);

    extern                        task start(bit active_in_reset = 0);
    extern protected              function void  single_th();
    extern                        function void  clean();
    extern                virtual function void  set_policy(gvip_policy_pkg::policy obj,
                                                            bit clone = 1);
    extern                virtual function gvip_policy_pkg::policy get_policy();
    extern protected      virtual function logic valid(logic v = 'x);
    extern protected      virtual function logic ready(logic v = 'x);
    extern protected      virtual task async_event();

           pure virtual task main_th(bit active_in_reset = 0);
           pure virtual function void do_clean();
           pure virtual function void set_valid(logic v);
           pure virtual function void set_ready(logic v);
           pure virtual function logic get_valid();
           pure virtual function logic get_ready();

  endclass : handshake

  //////////////////////////
  // Specific heandshakes //
  //////////////////////////

  virtual class master_hs extends handshake;

    function new(virtual gclk_if c);
      super.new(c);
      set_policy(gvip_policy_pkg::always_active::create("default_always_valid"), 0);
    endfunction : new

    extern virtual task main_th(bit active_in_reset = 0);
    pure virtual task pre_transaction_cb();
    pure virtual task post_transaction_cb();
  endclass : master_hs


  virtual class slave_hs extends handshake;

    function new(virtual gclk_if c);
      super.new(c);
      set_policy(gvip_policy_pkg::always_active::create("default_always_ready"), 0);
    endfunction : new

    extern virtual task main_th(bit active_in_reset = 0);
  endclass : slave_hs


  virtual class monitor_hs extends handshake;

    function new(virtual gclk_if c);
      super.new(c);
    endfunction : new

    extern virtual task main_th(bit active_in_reset = 0);
    pure virtual function void transaction_cb();
    pure virtual function void reset_cb();
  endclass : monitor_hs


  ///////////////////////
  // Handshake methods //
  ///////////////////////

  function handshake::new(virtual gclk_if c);
    clk = c;
  endfunction : new

  function void handshake::set_policy(gvip_policy_pkg::policy obj, bit clone = 1);
    greporter::info("GVIP-HS",
                    $sformatf("Policy set to %s [%s]", obj.get_name(), obj.get_type_name()),
                    greporter_pkg::FULL);
    policy = clone ? obj.clone() : obj;
    ->policy_set_e;
  endfunction : set_policy

  function gvip_policy_pkg::policy handshake::get_policy();
    return policy;
  endfunction : get_policy

  function logic handshake::valid(logic v = 'x);
    if (v !== 'x) set_valid(v);
    return get_valid();
  endfunction : valid

  function logic handshake::ready(logic v = 'x);
    if (v !== 'x) set_ready(v);
    return get_ready();
  endfunction : ready

  task handshake::start(bit active_in_reset = 0);
    fork
      begin
        single_th();
        main_th(active_in_reset);
      end
    join
  endtask : start

  function void handshake::single_th();
    if (p != null && (p.status() != process::KILLED
            && p.status() != process::FINISHED)) begin
        greporter::fatal("GVIP-HS", $sformatf("Multi %m process call"));
    end

    p = process::self();
  endfunction : single_th

  task handshake::async_event();
    greporter::warning("GVIP-HS", "Endless async_event, VIP' deadlock possible");
    wait(0);
  endtask : async_event

  function void handshake::clean();
    if (p != null) p.suspend();
    do_clean();
    policy.restart();
    if (p != null) p.kill();
  endfunction : clean


  /////////////////////
  // Handshake slave //
  /////////////////////

  task slave_hs::main_th(bit active_in_reset = 0);
    void'(ready(0));

    @(posedge clk.clk);
    fork
      // main loop for slave thread
      forever begin
        if (clk.rst & !active_in_reset) begin
          void'(ready(0));
        end else begin
          void'(ready(policy.get_next(valid)));
        end
        @(posedge clk.clk);
      end
      // loop calls asynchronous policies callback
      forever begin
        if (policy.is_async) begin
          async_event();
          // policy can change during wait for event
          if (policy.is_async) begin
            void'(ready(policy.get_post_async_event_cb(valid)));
          end
        end else begin
          @(policy_set_e);
        end
      end
    join
  endtask : main_th


  //////////////////////
  // Handshake master //
  //////////////////////

  task master_hs::main_th(bit active_in_reset = 0);
    void'(valid(0));

    @(posedge clk.clk);
    fork
      // main loop for master thread
      forever begin
        pre_transaction_cb();

        do begin
          if (clk.rst & !active_in_reset) begin
            void'(valid(0));
          end else begin
            void'(valid(policy.get_next(ready)));
          end
          @(posedge clk.clk);
        end while((valid & ready) !== 1'b1);

        void'(valid(0));

        post_transaction_cb();
      end
      // loop calls asynchronous policies callback
      forever begin
        if (policy.is_async) begin
          async_event();
          // policy can change during wait for event
          if (policy.is_async) begin
            void'(valid(policy.get_post_async_event_cb(ready)));
          end
        end else begin
          @(policy_set_e);
        end
      end
    join
  endtask : main_th


  ///////////////////////
  // Handshake monitor //
  ///////////////////////

  task monitor_hs::main_th(bit active_in_reset = 0);
    // loop for monitor
    forever begin
      if (clk.rst & !active_in_reset) begin
        reset_cb();
      end else if (ready && valid) begin
        transaction_cb();
      end
      @(posedge clk.clk);
    end
  endtask : main_th



  ///////////////
  // Auxiliary //
  ///////////////

  // Class: items_policy_setter
  //
  // This is helper class that sets HS policy taken from given item if is not null,
  // making a backup that can be restored later
  // assumption item_t has a ~policy~ field of gvip_policy_pkg::policy type
  //
  class items_policy_setter #(type item_t = struct {gvip_policy_pkg::policy policy;});
    local handshake hs;
    local policy backup_vip_main_policy;

    function new(handshake hs);
      this.hs = hs;
    endfunction : new

    virtual function policy get_policy_from_item(item_t item);
      return item.policy;
    endfunction : get_policy_from_item

    virtual function void policy_from_item(item_t item);
      policy item_policy = get_policy_from_item(item);
      if (item_policy != null) begin
        backup_vip_main_policy = hs.get_policy();
        hs.set_policy(item_policy);
      end
    endfunction : policy_from_item

    virtual function void restore_original_policy();
      if (backup_vip_main_policy != null) begin
        hs.set_policy(backup_vip_main_policy);
        backup_vip_main_policy = null;
      end
    endfunction : restore_original_policy
  endclass : items_policy_setter

endpackage : gvip_handshake_pkg
