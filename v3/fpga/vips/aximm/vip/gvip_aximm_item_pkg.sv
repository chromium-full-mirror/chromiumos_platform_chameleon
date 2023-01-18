/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////////////////////////////
// Defines items which could be send to vip and receive from it //
//////////////////////////////////////////////////////////////////

// max transaction len
`define ITEM_MAX_LEN 32

package gvip_aximm_item_pkg;

  import gaximm_pkg::*;
  import gvip_aximm_types_pkg::gvip;

  class item #(int N=1, int I=1, int A=1,
               type U_REQ=logic[0:0], type U_DATA=logic[0:0], type U_RESP=logic[0:0]);

    typedef item #(N, I, A, U_REQ, U_DATA, U_RESP) this_type;

    // Transaction type
    local gvip::channel_e tr_type = set_tr_type(gvip::AW_W);

    // Time when first beat was accepted (valid && ready && first)
    time tr_time_begin;

    // Time when last beat was accepted (valid && ready && last)
    time tr_time_end;

    // Optional policy which defines how valid whould behave during sending this item
    gvip_policy_pkg::policy policy;

    rand logic [I-1:0]            awid;
    rand logic [A-1:0]            awaddr  = '0;
    rand logic [LEN_WIDTH-1:0]    awlen   = '0;
    rand logic [SIZE_WIDTH-1:0]   awsize  = '0;
    rand burst_type_e             awburst = FIXED;
    rand logic [LOCK_WIDTH-1:0]   awlock;
    rand logic [CACHE_WIDTH-1:0]  awcache;
    rand logic [PROT_WIDTH-1:0]   awprot;
    rand logic [QOS_WIDTH-1:0]    awqos;
    rand logic [REGION_WIDTH-1:0] awregion;
    rand U_REQ                    awuser;

    rand logic [N*8-1:0]          wdata[];
    rand logic [N-1:0]            wstrb[];
    rand U_DATA                   wuser[];

    rand logic [I-1:0]            bid;
    rand resp_e                   bresp;
    rand U_RESP                   buser;

    rand logic [I-1:0]            arid;
    rand logic [A-1:0]            araddr  = '0;
    rand logic [LEN_WIDTH-1:0]    arlen   = '0;
    rand logic [SIZE_WIDTH-1:0]   arsize  = '0;
    rand burst_type_e             arburst = FIXED;
    rand logic [LOCK_WIDTH-1:0]   arlock;
    rand logic [CACHE_WIDTH-1:0]  arcache;
    rand logic [PROT_WIDTH-1:0]   arprot;
    rand logic [QOS_WIDTH-1:0]    arqos;
    rand logic [REGION_WIDTH-1:0] arregion;
    rand U_REQ                    aruser;

    rand logic [I-1:0]            rid;
    rand logic [N*8-1:0]          rdata[];
    rand resp_e                   rresp;
    rand U_DATA                   ruser[];

    // config fields
    logic cfg_awsize_force_max = 1;
    logic cfg_arsize_force_max = 1;
    logic cfg_wstrb_force_one = 1;
    logic cfg_use_regular_transactions = 0;

    // wrapper for $clog2 to use in constraints
    local function int unsigned clog2(int unsigned arg);
      return $clog2(arg);
    endfunction : clog2


    // Function: copy
    //
    // copy fields from ~rhs~ to this item
    virtual function void copy(this_type rhs);
      if (rhs.policy != null) this.policy = rhs.policy.clone();
      void'(this.set_tr_type(rhs.get_tr_type()));
      this.tr_time_begin = rhs.tr_time_begin;
      this.tr_time_end   = rhs.tr_time_end;
      this.awid          = rhs.awid;
      this.awaddr        = rhs.awaddr;
      this.awlen         = rhs.awlen;
      this.awsize        = rhs.awsize;
      this.awburst       = rhs.awburst;
      this.awlock        = rhs.awlock;
      this.awcache       = rhs.awcache;
      this.awprot        = rhs.awprot;
      this.awqos         = rhs.awqos;
      this.awregion      = rhs.awregion;
      this.awuser        = rhs.awuser;
      this.wdata         = rhs.wdata;
      this.wstrb         = rhs.wstrb;
      this.wuser         = rhs.wuser;
      this.bid           = rhs.bid;
      this.bresp         = rhs.bresp;
      this.buser         = rhs.buser;
      this.arid          = rhs.arid;
      this.araddr        = rhs.araddr;
      this.arlen         = rhs.arlen;
      this.arsize        = rhs.arsize;
      this.arburst       = rhs.arburst;
      this.arlock        = rhs.arlock;
      this.arcache       = rhs.arcache;
      this.arprot        = rhs.arprot;
      this.arqos         = rhs.arqos;
      this.arregion      = rhs.arregion;
      this.aruser        = rhs.aruser;
      this.rid           = rhs.rid;
      this.rdata         = rhs.rdata;
      this.rresp         = rhs.rresp;
      this.ruser         = rhs.ruser;
      this.cfg_awsize_force_max         = rhs.cfg_awsize_force_max;
      this.cfg_arsize_force_max         = rhs.cfg_arsize_force_max;
      this.cfg_wstrb_force_one          = rhs.cfg_wstrb_force_one;
      this.cfg_use_regular_transactions = rhs.cfg_use_regular_transactions;
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
    // It also disables randomization for all unused variables
    // tr_type - transaction type
    // Returns current transaction type
    function gvip::channel_e set_tr_type(gvip::channel_e tr_type);
      this.tr_type = tr_type;
      rand_disable_all();
      case (tr_type)
        gvip::AW: begin
          rand_set_aw(1);
        end
        gvip::W: begin
          rand_set_aw(1);
          rand_set_w(1);
        end
        gvip::AW_W: begin
          rand_set_aw(1);
          rand_set_w(1);
        end
        gvip::B: begin
          rand_set_b(1);
        end
        gvip::AR: begin
          rand_set_ar(1);
        end
        gvip::R: begin
          rand_set_ar(1);
          rand_set_r(1);
        end
        default: begin
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
      awid.rand_mode(mode);
      awaddr.rand_mode(mode);
      awlen.rand_mode(mode);
      awsize.rand_mode(mode);
      awburst.rand_mode(mode);
      awlock.rand_mode(mode);
      awcache.rand_mode(mode);
      awprot.rand_mode(mode);
      awqos.rand_mode(mode);
      awregion.rand_mode(mode);
      awuser.rand_mode(mode);
    endfunction : rand_set_aw

    // Function: rand_set_w
    //
    // Sets rand_mode for w variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_w(bit mode);
      wdata.rand_mode(mode);
      wstrb.rand_mode(mode);
      wuser.rand_mode(mode);
    endfunction : rand_set_w

    // Function: rand_set_b
    //
    // Sets rand_mode for b variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_b(bit mode);
      bid.rand_mode(mode);
      bresp.rand_mode(mode);
      buser.rand_mode(mode);
    endfunction : rand_set_b

    // Function: rand_set_ar
    //
    // Sets rand_mode for ar variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_ar(bit mode);
      arid.rand_mode(mode);
      araddr.rand_mode(mode);
      arlen.rand_mode(mode);
      arsize.rand_mode(mode);
      arburst.rand_mode(mode);
      arlock.rand_mode(mode);
      arcache.rand_mode(mode);
      arprot.rand_mode(mode);
      arqos.rand_mode(mode);
      arregion.rand_mode(mode);
      aruser.rand_mode(mode);
    endfunction : rand_set_ar

    // Function: rand_set_r
    //
    // Sets rand_mode for r variables
    // mode - 1 randomization enable, 0 randomization disable
    local function void rand_set_r(bit mode);
      rid.rand_mode(mode);
      rdata.rand_mode(mode);
      rresp.rand_mode(mode);
      ruser.rand_mode(mode);
    endfunction : rand_set_r


    constraint soft_len_max_c {
      soft awlen < `ITEM_MAX_LEN;
      soft arlen < `ITEM_MAX_LEN;
    }

    constraint w_size_c {
      wstrb.size() == wdata.size();
      wuser.size() == wdata.size();
      if (tr_type == gvip::W || tr_type == gvip::AW_W) wdata.size() == awlen+1;
      else wdata.size() == 0;
      solve awlen before wdata;
      solve wdata before wstrb;
      solve wdata before wuser;
    }

    constraint soft_awsize_c {
      if (cfg_awsize_force_max) {
        soft awsize == clog2(N);
      }
    }

    constraint awsize_c {
      awsize <= clog2(N);
    }

    constraint r_size_c {
      ruser.size() == rdata.size();
      if (tr_type == gvip::R) rdata.size() == arlen+1;
      else rdata.size() == 0;
      solve arlen before rdata;
      solve rdata before ruser;
    }

    constraint soft_arsize_c {
      if (cfg_arsize_force_max) {
        soft arsize == clog2(N);
      }
    }

    constraint arsize_c {
      arsize <= clog2(N);
    }

    constraint wstrb_awaddr_c {
      solve awaddr before wstrb;
      solve awsize before wstrb;
      solve awburst before wstrb;

      // force wstrb to 1 for all possible bytes
      if(cfg_wstrb_force_one) {
        foreach (wstrb[i]) {
          soft wstrb[i] == '1;
        }
      }
      // constraint for wstrb if awaddr is unalign
      if (wstrb.size()) {
        if (awburst == FIXED) {
          foreach (wstrb[beat, i]) {
            if (i < (awaddr % N)) {
              wstrb[beat][i] == 1'b0;
            }
            else if(cfg_wstrb_force_one) {
              soft wstrb[beat][i] == '1;
            }
          }
        }
        else { // awburst != FIXED
          foreach (wstrb[0][i]) {
            if (i < (awaddr % N)) {
              wstrb[0][i] == 1'b0;
            }
            else if(cfg_wstrb_force_one) {
              soft wstrb[0][i] == '1;
            }
          }
        }
      }

      // constraint for wstrb if transfers are narrow
      if (2**awsize != N) {
        foreach (wstrb[beat, i]) {
          if (awburst == FIXED) {
            if (i < (awaddr % N) - (awaddr % (2**awsize))) {
              wstrb[beat][i] == 1'b0;
            }
            else if(cfg_wstrb_force_one) {
              soft wstrb[beat][i] == 1'b1;
            }
            if (i >= ((awaddr % N) - (awaddr % (2**awsize)) + (2**awsize))) {
              wstrb[beat][i] == 1'b0;
            }
            else if(cfg_wstrb_force_one) {
              soft wstrb[beat][i] == 1'b1;
            }
          }
          else { // awburst != FIXED
            if (i < ((awaddr + beat * (2**awsize)) % N) - (awaddr % (2**awsize))) {
              wstrb[beat][i] == 1'b0;
            }
            else if(cfg_wstrb_force_one) {
              soft wstrb[beat][i] == 1'b1;
            }
            if (i >= (((awaddr + beat * (2**awsize)) % N) - (awaddr % (2**awsize)) +
                (2**awsize))) {
              wstrb[beat][i] == 1'b0;
            }
            else if(cfg_wstrb_force_one) {
              soft wstrb[beat][i] == 1'b1;
            }
          }
        }
      }
    }

    constraint aw_4k_boundary_c {
      // burst could not cross 4k boundary
      (awaddr / (4 * 1024)) * (4 * 1024) ==
          (((awaddr / (2**awsize)) * (2**awsize) + ((awlen+1) * (2**awsize)) -1) /
           (4 * 1024)) * (4 * 1024);
    }

    constraint ar_4k_boundary_c {
      // burst could not cross 4k boundary
      (araddr / (4 * 1024)) * (4 * 1024) ==
          (((araddr / (2**arsize)) * (2**arsize) + ((arlen+1) * (2**arsize)) -1) /
           (4 * 1024)) * (4 * 1024);
    }

    constraint burst_c {
      awburst inside {FIXED, INCR, WRAP};
      arburst inside {FIXED, INCR, WRAP};
    }

    constraint aw_regular_transactions_c {
      solve awlen before awsize;
      solve awsize before awaddr;
      solve awburst before awaddr;
      if (cfg_use_regular_transactions) {
        awlen inside {0, 1, 3, 7, 15};
        (awlen != 0) -> awsize == clog2(N);
        awburst inside {INCR, WRAP};
        (awburst == INCR) -> (awaddr % N) == 0;
        (awburst == WRAP) -> (awaddr % (2**awsize)) == 0;
      }
    }

    constraint ar_regular_transactions_c {
      solve arlen before arsize;
      solve arsize before araddr;
      solve arburst before araddr;
      if (cfg_use_regular_transactions) {
        arlen inside {0, 1, 3, 7, 15};
        (arlen != 0) -> arsize == clog2(N);
        arburst inside {INCR, WRAP};
        (arburst == INCR) -> (araddr % N) == 0;
        (arburst == WRAP) -> (araddr % (2**arsize)) == 0;
      }
    }


    // Class: printer
    //
    // Used in convert2string to string formatting
    class printer #(type word = byte);
      static function string array2string(word w[], string new_line = "\n");
        foreach (w[i]) array2string = $sformatf("%s%s%h", array2string, new_line, w[i]);
        return array2string.substr(new_line.len(), array2string.len()-1);
      endfunction : array2string

      static function string add_indentation(string s, int size, bit first = 0);
        if (first) add_indentation = {size{" "}};
        foreach (s[i]) begin
          if (s[i] == "\n") add_indentation = {add_indentation, "\n", {size{" "}}};
          else add_indentation = {add_indentation, s[i]};
        end
      endfunction : add_indentation

      static function string add_prefix(string s, string prefix="unknown");
        return $sformatf("%s\n%s", prefix, printer#()::add_indentation(s, 3, 1));
      endfunction : add_prefix
    endclass : printer


    function string convert2string();
      string content;

      string aw = $sformatf({
                "  awid     : %0d\n",
                "  awaddr   : %0h\n",
                "  awlen    : %0d\n",
                "  awsize   : %0d\n",
                "  awburst  : %s\n",
                "  awlock   : %0b\n",
                "  awcache  : %0b\n",
                "  awprot   : %0d\n",
                "  awqos    : %0b\n",
                "  awregion : %0h\n",
                "  awuser   : %0h\n"
              }, awid, awaddr, awlen, awsize, awburst, awlock,
                 awcache, awprot, awqos, awregion, awuser);

      string w = $sformatf({
                "  wdata    : %s\n",
                "  wstrb    : %s\n",
                "  wuser    : %s\n"
              },
                printer#()::add_indentation(printer#(logic [N*8-1:0])::array2string(wdata), 13),
                printer#()::add_indentation(printer#(logic [N-1:0])::array2string(wstrb), 13),
                printer#()::add_indentation(printer#(U_DATA)::array2string(wuser), 13));

      string b = $sformatf({
                " bid       : %0d\n",
                " bresp     : %s\n",
                " buser     : %0h\n"
              }, bid, bresp, buser);

      string ar = $sformatf({
                "  arid     : %0d\n",
                "  araddr   : %0h\n",
                "  arlen    : %0d\n",
                "  arsize   : %0d\n",
                "  arburst  : %s\n",
                "  arlock   : %0b\n",
                "  arcache  : %0b\n",
                "  arprot   : %0d\n",
                "  arqos    : %0b\n",
                "  arregion : %0h\n",
                "  aruser   : %0h\n"
              }, arid, araddr, arlen, arsize, arburst, arlock,
                 arcache, arprot, arqos, arregion, aruser);

      string r = $sformatf({
                " rid       : %0d\n",
                " rresp     : %s\n",
                " rdata     : %s\n",
                " ruser     : %s\n"
              }, rid, rresp,
              printer#()::add_indentation(printer#(logic [N*8-1:0])::array2string(rdata), 13),
              printer#()::add_indentation(printer#(U_DATA)::array2string(ruser), 13));

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

endpackage : gvip_aximm_item_pkg
