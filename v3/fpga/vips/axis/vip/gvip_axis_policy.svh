/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

///////////////////////////////////////////////
// Policies definitions specyfic to axis vip //
///////////////////////////////////////////////

// verilog_syntax: parse-as-package-body

// Virtual class: last_policyaxis/vip/gvip_axis_policy.svh
//
// Internal policy class which makes possible using tlast in calculation
virtual class last_policy #(type base_policy = logic) extends base_policy
                                                      implements policy_tlast_setup_ic;
  typedef last_policy#(base_policy) this_type;
  policy_tlast_ic hs;

  function new(string name = "", string type_name = $typename(this));
    super.new(name, type_name);
  endfunction

  virtual function void next(logic tpartner);
    next_last(tpartner, hs.get_last());
  endfunction

  virtual function void set_hs_tlast_access(policy_tlast_ic obj);
    hs = obj;
  endfunction

  virtual function void copy(policy rhs);
    this_type _rhs;
    void'($cast(_rhs, rhs));
    super.copy(rhs);
    this.hs = _rhs.hs;
  endfunction

  pure virtual function void next_last(logic tpartner, logic tlast);
endclass : last_policy


// Class: active_to_last
//
// With this policy VIP would keep valid/ready signal asserted
// from first to last beat of the packet.
class active_to_last extends last_policy#(gvip_policy_pkg::policy);
  typedef active_to_last this_type;

  function new(string name = "active_to_last", string type_name = $typename(this));
    super.new(name, type_name);
  endfunction : new

  static function active_to_last create(string name = "active_to_last");
    create = new(name);
  endfunction : create

  virtual function gvip_policy_pkg::policy clone();
    clone = this_type::create(name);
    clone.copy(this);
  endfunction : clone

  virtual function void next_last(logic tpartner, logic tlast);
    bit previous_value;
    is_randomize_done();
    previous_value = sig_value;
    nactive();
    if (tpartner && tlast && previous_value) begin
      next_interval(.request_value(0));
    end
  endfunction : next_last
endclass : active_to_last

