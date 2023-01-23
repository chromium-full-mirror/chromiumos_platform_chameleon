/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////////////////////////////
// Defines items which could be send to vip and receive from it //
//////////////////////////////////////////////////////////////////

package gvip_axil_item_pkg;

  import gaxil_pkg::*;
  import gvip_axil_types_pkg::gvip;

  class item #(int N=1, int A=1);

    typedef item #(N, A) this_type;

    // Transaction type
    local gvip::channel_e tr_type = set_tr_type(gvip::AW_W);

    // Time when first beat was accepted (valid && ready && first)
    time tr_time_begin;

    // Time when last beat was accepted (valid && ready && last)
    time tr_time_end;

    // Optional policy which defines how valid whould behave during sending this item
    gvip_policy_pkg::policy policy;

    rand logic [A-1:0]            awaddr  = '0;
    rand logic [PROT_WIDTH-1:0]   awprot;

    rand logic [N*8-1:0]          wdata;
    rand logic [N-1:0]            wstrb   = '0;

    rand resp_e                   bresp;

    rand logic [A-1:0]            araddr  = '0;
    rand logic [PROT_WIDTH-1:0]   arprot;

    rand logic [N*8-1:0]          rdata;
    rand resp_e                   rresp;

    // config fields
    bit cfg_wstrb_force_one = 1;


    // Function: copy
    //
    // copy fields from ~rhs~ to this item
    virtual function void copy(this_type rhs);
      if (rhs.policy != null) this.policy = rhs.policy.clone();
      void'(this.set_tr_type(rhs.get_tr_type()));
      this.tr_time_begin = rhs.tr_time_begin;
      this.tr_time_end = rhs.tr_time_end;
      this.awaddr = rhs.awaddr;
      this.awprot = rhs.awprot;
      this.wdata  = rhs.wdata;
      this.wstrb  = rhs.wstrb;
      this.bresp  = rhs.bresp;
      this.araddr = rhs.araddr;
      this.arprot = rhs.arprot;
      this.rdata  = rhs.rdata;
      this.rresp  = rhs.rresp;
      this.cfg_wstrb_force_one = rhs.cfg_wstrb_force_one;
    endfunction : copy

    // Function: clone
    //
    // returns new copy of this object
    function this_type clone();
      clone = new();
      clone.copy(this);
    endfunction : clone

    // Function: set_tr_type
    //
    // Sets transaction type.
    // It also disables randomizationa for all unused variables
    // tr_type - transaction type
    // Returns current transaction type
    function gvip::channel_e set_tr_type(gvip::channel_e tr_type);
      this.tr_type = tr_type;
      case (tr_type)
        gvip::AW: begin
          rand_disable_all();
          rand_set_aw(1);
        end
        gvip::W: begin
          rand_disable_all();
          rand_set_aw(1);
          rand_set_w(1);
        end
        gvip::AW_W: begin
          rand_disable_all();
          rand_set_aw(1);
          rand_set_w(1);
        end
        gvip::B: begin
          rand_disable_all();
          rand_set_b(1);
        end
        gvip::AR: begin
          rand_disable_all();
          rand_set_ar(1);
        end
        gvip::R: begin
          rand_disable_all();
          rand_set_ar(1);
          rand_set_r(1);
        end
        default: begin
          rand_disable_all();
        end
      endcase
      return tr_type;
    endfunction : set_tr_type

    // Function: get_tr_type
    //
    // returns transaction type.
    function gvip::channel_e get_tr_type();
      return tr_type;
    endfunction : get_tr_type

    // Function: rand_disable_all
    //
    // Disable randomization for all variables
    local function void rand_disable_all();
      rand_set_aw(0);
      rand_set_w(0);
      rand_set_b(0);
      rand_set_ar(0);
      rand_set_r(0);
    endfunction : rand_disable_all

    // Function: rand_set_aw
    //
    // Sets rand_mode for aw variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_aw(bit mode);
      awaddr.rand_mode(mode);
      awprot.rand_mode(mode);
    endfunction : rand_set_aw

    // Function: rand_set_w
    //
    // Sets rand_mode for w variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_w(bit mode);
      wdata.rand_mode(mode);
      wstrb.rand_mode(mode);
    endfunction : rand_set_w

    // Function: rand_set_b
    //
    // Sets rand_mode for b variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_b(bit mode);
      bresp.rand_mode(mode);
    endfunction : rand_set_b

    // Function: rand_set_ar
    //
    // Sets rand_mode for ar variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_ar(bit mode);
      araddr.rand_mode(mode);
      arprot.rand_mode(mode);
    endfunction : rand_set_ar

    // Function: rand_set_r
    //
    // Sets rand_mode for r variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_r(bit mode);
      rdata.rand_mode(mode);
      rresp.rand_mode(mode);
    endfunction : rand_set_r


    constraint wstrb_awaddr_c {
      solve awaddr before wstrb;

      // constraint for wstrb if awaddr is unalign
      foreach (wstrb[i]) {
        if (i < (awaddr % N)) {
          wstrb[i] == 1'b0;
        }
        else if(cfg_wstrb_force_one) {
          soft wstrb[i] == '1;
        }
      }
    }


    function string convert2string();
      string content;

      string aw = $sformatf({
                "  awaddr   : %0h\n",
                "  awprot   : %0d\n"
              }, awaddr, awprot);

      string w = $sformatf({
                "  wdata    : %h\n",
                "  wstrb    : %h\n"
              }, wdata, wstrb);

      string b = $sformatf({
                " bresp     : %s\n"
              }, bresp);

      string ar = $sformatf({
                "  araddr   : %0h\n",
                "  arprot   : %0d\n"
              }, araddr, arprot);

      string r = $sformatf({
                " rresp     : %s\n",
                " rdata     : %h\n"
              }, rresp, rdata);

    case (tr_type)
      gvip::AW   : content = aw;
      gvip::W    : content = w;
      gvip::AW_W : content = {aw, w};
      gvip::B    : content = b;
      gvip::AR   : content = ar;
      gvip::R    : content = r;
    endcase

    convert2string = $sformatf({
      "begin_time : %0t\n",
      "end_time   : %0t\n",
      "type       : %s\n",
      "%s"}, tr_time_begin, tr_time_end, tr_type, content);

    endfunction : convert2string

  endclass : item

endpackage : gvip_axil_item_pkg
