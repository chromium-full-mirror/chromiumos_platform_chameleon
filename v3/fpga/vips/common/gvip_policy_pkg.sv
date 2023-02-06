/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

////////////////////////////////
// Handshake policies package //
////////////////////////////////

package gvip_policy_pkg;

  // In this package various handshake signals policy can be found
  // Each policy base on ~policy~ class and always implements at least two methods
  // new - constructor with two arguments, policy instance name witch can be specify in test and
  //       type_name - class type name which in most cases it should have default value
  //       of $typename(this) and should not be overwritten in test
  // next - callback function which sets next value of valid/ready signal (sig_value), this callback
  //       will be called on each clock cycle. Function has got one argument with actual value of
  //       handshake partner signal (for master VIP policy generates valid signal and
  //       tpartner = ready, for slave VIP policy generates ready signal and tpartner = valid)
  //
  // async_event_cb - optional in async policy, this callback will be called by handshake object
  //       at ~async_event~ e.g. can be used to clear signal value

  typedef policy;
  import greporter_pkg::greporter;

  // common part of the code for different policies
  `define POLICY_UTILS(T) \
    typedef T this_type; \
    static function this_type create(string name = `"T`"); \
      create = new(name); \
    endfunction : create \
    \
    virtual function policy clone(); \
      clone = this_type::create(name); \
      clone.copy(this); \
    endfunction : clone


  // Class: always_active
  //
  // With this policy VIP is always ready for new data in slave configuration
  // In master configuration any outstanding transaction will be put on bus as single burst
  //
  class always_active extends policy;
    `POLICY_UTILS(always_active)

    function new(string name = "always_active", string type_name = $typename(this));
      super.new(name, type_name);
      interval_c.constraint_mode(0);
    endfunction : new

    virtual function void next(logic tpartner);
      sig_value = 1;
    endfunction : next

  endclass : always_active


  // Class: random
  //
  // With this policy valid or ready signals will we stimulated according to randomized
  // arrays values (active_interval and not_active_interval)
  //
  class random extends policy;
    `POLICY_UTILS(random)

    function new(string name = "random", string type_name = $typename(this));
      super.new(name, type_name);
    endfunction : new

    virtual function void next(logic tpartner);
      is_randomize_done();
      nactive();
      active();
    endfunction : next

  endclass : random


  // Class: policy_after_partner_active
  //
  // Activate random policy only after partner is active
  // when partner is deasserted the value is also immediately deasserted
  //
  class policy_after_partner_active extends policy;
    `POLICY_UTILS(policy_after_partner_active)

    function new(string name = "policy_after_partner_active", string type_name = $typename(this));
      super.new(name, type_name);
      is_async = 1; // since this policy can deassert in async way
    endfunction : new

    virtual function void next(logic tpartner);
      is_randomize_done();
      if (tpartner !== 1) begin
        next_interval(.request_value(0));
      end else begin
        nactive();
        active();
      end
    endfunction : next

    virtual function void async_event_cb(logic tpartner);
      if (tpartner == 0) next_interval(.request_value(0));
    endfunction : async_event_cb

  endclass : policy_after_partner_active


  // Class: random_std
  //
  // With this policy interface will do not go to not active state if partner is deasseted,
  // like in Axi4Stream: Once TVALID is asserted, it must remain asserted until TREADY is high.
  // Spec: section 2.2.1, and figure 2-1 on page 2-3.
  //
  class random_std extends policy;
    `POLICY_UTILS(random_std)

    function new(string name = "random_std", string type_name = $typename(this));
      super.new(name, type_name);
    endfunction : new

    virtual function void next(logic tpartner);
      is_randomize_done();
      nactive();
      if (tpartner) begin
        active();
      end
    endfunction : next

  endclass : random_std


  // Class: single_ack
  //
  // Asserts only for one cycle after tpartner is active
  //
  class single_ack extends policy;
    `POLICY_UTILS(single_ack)

    function new(string name = "single_ack", string type_name = $typename(this));
      super.new(name, type_name);
    endfunction : new

    virtual function void next(logic tpartner);
        is_randomize_done();
        if (sig_value) begin
          sig_value = '0;
        end else if (tpartner) begin
          nactive();
        end
    endfunction : next

  endclass : single_ack

  // Class: always_inactive
  //
  // Valid/ready signal is always inactive.
  //
  class always_inactive extends policy;
    `POLICY_UTILS(always_inactive)
    function new(string name = "always_inactive", string type_name = $typename(this));
      super.new(name, type_name);
      sig_value = '0;
    endfunction : new
    virtual function void next(logic tpartner);
      is_randomize_done();
      sig_value = '0;
    endfunction : next
  endclass : always_inactive

  ///////////////////////////////
  // Functional implementation //
  ///////////////////////////////

  // Class: policy
  //
  // Base class for policies, any policy must extend this class
  // The general principle of operation is to set next value of valid/ready in ~next~
  // method which is called at each clock cycle by handshake object
  // Value of valid/ready in most cases are calculated based on randomized ~active_interval~ and
  // ~not_active_interval~ arrays but can be also calculated in any other way
  //
  virtual class policy;
    // instance name
    const string       name;

    // policy type name - defined in ~new~ by $typename(this)
    const string       type_name;

    // active and not_active arrays size
    rand  int unsigned interval_length;

    // interval max value, any value in active and not_active arrays will be less then this value
    rand  int unsigned max_interval;

    // each value of ~active_interval~ define number of clocks cycles when valid/ready
    // is in active state
    rand  int unsigned active_interval[];

    // each value of ~not_active_interval~ define number of clocks cycles when valid/ready
    // is in not active state
    rand  int unsigned not_active_interval[];

    // randomize done flag
    rand  bit          randomized;

    // index of current interval from active and not_active arrays
    int                interval_idx = 0;

    // clock cycle counter
    int                interval = 0;

    // current signal value (0/1) of ready/valid, ~next~ must set this
    bit                sig_value = 0;

    // policies which asynchronously asserts or deasserts value must set this flag
    // only then async_event_cb will be called
    bit                is_async = 0;

    // create polcy with instance ~name~ and ~type_name~
    // ~type_name~ always should have default 'type_name = $typename(this)'
    extern         function new(string name, string type_name = $typename(this));

    // returns policy instance name
    extern         function string get_name();

    // returns policy type name
    extern         function string get_type_name();

    // check if policy was randomized if not call fatal
    extern         function void is_randomize_done();

    // this function increments clock counter in active state and if reach
    // ~active_interval[interval_idx]~ value call ~next_interval~
    extern virtual function void active();

    // this function increments clock counter in not active state and if reach
    // ~not_active_interval[interval_idx]~ value call ~next_interval~
    extern virtual function void nactive();

    // increments ~interval_idx~ and switches ~sig_value~ to ~request_value~
    extern virtual function void next_interval(bit request_value);

    // copy fields from ~rhs~ to this policy object
    // if extended policy adds new fileds also should extend this method
    extern virtual function void copy(policy rhs);

    // concrete policy must implement this method
    // this method according (or not) to tpartner value sets and returns ~sig_value~
    pure   virtual function void next(logic tpartner);

    // create new object of the same type and copy all members
    // concrete and all extended policy must implement this method
    // In most cases it will be:
    // | virtual function policy clone();
    // |   clone = this_type::create(name);
    // |   clone.copy(this);
    // | endfunction
    // ~this_type~ is type of concrete/extended policy
    pure   virtual function policy clone();

    // asynchronous callback
    // this function will be called by handshake instance at tpartner change event
    // asynchronous to clock
    virtual function void async_event_cb(logic tpartner); endfunction

    // call ~next~ from policy and return new value to handshake object
    extern function bit get_next(logic tpartner);

    // call ~async_event_cb~ from policy in case of async one and
    // return new value to handshake object
    extern function logic get_post_async_event_cb(logic tpartner);

    // This function restart all policy counters
    extern virtual function void restart();

    // active and not_active arrays constraint
    extern constraint interval_c;

    // active/not_active interval max value constraint
    extern constraint interval_max_c;

    // size of active/not_active arrays constraint
    extern constraint interval_length_c;

    // internal flags constraint
    extern constraint flags_c;

  endclass : policy


  ///////////////////////////
  // Policy implementation //
  ///////////////////////////

  constraint policy::interval_max_c {
    soft max_interval == 50;
  }

  constraint policy::interval_length_c {
    interval_length < 100;
    interval_length > 0;
  }

  constraint policy::interval_c {
    solve interval_length before active_interval;
    solve interval_length before not_active_interval;
    active_interval.size() == interval_length;
    not_active_interval.size() == interval_length;
    foreach(active_interval[i]) soft active_interval[i] < max_interval;
    foreach(not_active_interval[i]) soft not_active_interval[i] < max_interval;
    active_interval.sum() != 0;
  }

  constraint policy::flags_c {
      randomized == 1;
  }

  function policy::new(string name, string type_name = $typename(this));
    this.name = name;
    // trim leading 'class' string from type_name
    this.type_name = (type_name.substr(0, 5) == "class ") ?
                      type_name.substr(6, type_name.len()-1) :
                      type_name;
  endfunction : new


  function string policy::get_name();
    return name;
  endfunction : get_name


  function string policy::get_type_name();
    return type_name;
  endfunction : get_type_name


  function void policy::is_randomize_done();
    if(!randomized)
      greporter::fatal("GVIP-POLICY",
          $sformatf("Policy %s must be randomize before use", get_name()));
  endfunction : is_randomize_done


  function void policy::active();
    if (sig_value == 1) begin
      if (interval >= active_interval[interval_idx]) begin
        next_interval(.request_value(0));
        return;
      end
      interval++;
    end
  endfunction : active


  function void policy::nactive();
    if (sig_value == 0) begin
      if (interval >= not_active_interval[interval_idx]) begin
        next_interval(.request_value(1));
        return;
      end
      interval++;
    end
  endfunction : nactive


  function void policy::next_interval(bit request_value);
    if (sig_value != request_value) begin
      interval_idx = (interval_idx + 1) % interval_length;
    end
    interval = 0;
    sig_value = request_value;
  endfunction : next_interval


  function void policy::copy(policy rhs);
    this.randomized             = rhs.randomized;
    this.interval_length        = rhs.interval_length;
    this.active_interval        = {rhs.active_interval};
    this.not_active_interval    = {rhs.not_active_interval};
    this.max_interval           = rhs.max_interval;
    this.interval_idx           = rhs.interval_idx;
    this.interval               = rhs.interval;
    this.sig_value              = rhs.sig_value;
    this.is_async               = rhs.is_async;
  endfunction : copy


  function void policy::restart();
    interval_idx = 0;
    interval = 0;
    sig_value = 0;
  endfunction : restart


  function bit policy::get_next(logic tpartner);
    next(tpartner);
    return sig_value;
  endfunction : get_next


  function logic policy::get_post_async_event_cb(logic tpartner);
    async_event_cb(tpartner);
    return sig_value;
  endfunction : get_post_async_event_cb


  `undef POLICY_UTILS


endpackage : gvip_policy_pkg
