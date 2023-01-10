/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////////////////////////////
// Defines items which could be send to vip and receive from it //
//////////////////////////////////////////////////////////////////

`define ITEM_MAX_BYTES 16384

package gvip_axis_item_pkg;

  import greporter_pkg::greporter;

  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Class: bitem
  //
  // Common fields and constraints for item and generic_item
  virtual class bitem;
    // Time when first beat was accepted (valid && ready && first)
    time tr_time_begin;

    // Time when last beat was accepted (valid && ready && last)
    time tr_time_end;

    // Optional policy which defines how tvalid whould behave during sending this item
    gvip_policy_pkg::policy policy;

    // Internal event used to control nonposed mechanism
    event post;

    // When not set, send_item task would finish after whole item would be putted on bus
    bit is_posted;

    // Constraint: posted_c
    //
    // Optional constraint which forces is_posted to 1
    extern constraint posted_c;

    // copy fields from ~rhs~ to this item
    extern virtual function void copy(bitem rhs);

    // returns new copy of this object
    extern function bitem clone();
  endclass : bitem

  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Class: generic_item
  //
  // Vip's parameters independent item
  class generic_item extends bitem;

    // Each element of tdata has coresponding tkeep and tstrb element
    // it could be converted to item object where each tdata, tkeep,
    // tstrb would be packed into beat elements
    rand byte tdata[];
    rand bit tkeep[];
    rand bit tstrb[];

    // Each group of tuser bytes which fills U_T could be converted
    // into beat element in item
    rand byte tuser[];

    // Those value are constant for whole packet transfer
    rand int unsigned tid;
    rand int unsigned tdest;

    // Function: compare
    //
    // Compares this item with rhs. It does not check fields from bitem
    // rhs - generic_item to compare with
    // returns: 1 - match
    //          0 - unmatch
    extern virtual function bit compare(generic_item rhs);

    // Function: convert2string
    //
    // Provides item representation in the form of a string
    extern virtual function string convert2string();

    // Function: squize_by_tkeep
    //
    // tdata bytes and tstrb bits with corresponding tkeep equal 0 will be removed -
    // item will have only valid bytes in tdata and all tkeep set to 1
    extern virtual function void squize_by_tkeep();

    // Function: mask_data_with_tkeep
    //
    // tdata bytes with corresponding tkeep equal 0 will be cleared
    extern virtual function void mask_data_with_tkeep();

    // Function: copy
    //
    // copy fields from ~rhs~ to this item
    extern virtual function void copy(bitem rhs);

    // Function clone
    //
    // returns new copy of this object
    extern function generic_item clone();

    // Constraint: size_c
    //
    // Basic constraints
    extern constraint size_c;

    // Constraint: size_max_c
    //
    // Optional constraints which limits maximum bytes number
    extern constraint size_max_c;

  endclass : generic_item;


  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Class: item
  //
  // Vip's parameters specific item
  class item #(int N = 1, int I = 1, int D = 1, type U_T = logic[0:0]) extends bitem;
    typedef item #(N, I, D, U_T) this_type;

    // Each element coresponds to beat at gaxis_if interface
    rand logic [N*8-1:0] tdata[];
    rand logic [N-1:0]   tkeep[];
    rand logic [N-1:0]   tstrb[];
    rand U_T             tuser[];

    // If set tlast would be aserted at last beat
    rand logic           tlast;

    // Those value are constant for whole packet transfer
    rand logic [I-1:0]   tid;
    rand logic [D-1:0]   tdest;

    // Function: compare
    //
    // Compares this item with rhs. It does not check fields from bitem
    // rhs - item to compare with
    // returns: 1 - match
    //          0 - unmatch
    extern virtual function bit compare(this_type rhs);

    // Function: convert2string
    //
    // Provides item representation in the form of a string
    extern virtual function string convert2string();

    // Function: mask_data_with_tkeep
    //
    // tdata bytes with corresponding tkeep equal 0 will be cleared
    extern virtual function void mask_data_with_tkeep();

    // Function: copy
    //
    // copy fields from ~rhs~ to this item
    extern virtual function void copy(bitem rhs);

    // Function: clone
    //
    // returns new copy of this object
    extern function this_type clone();

    // Constraint: size_c
    //
    // Basic constraints
    extern constraint size_c;

    // Constraint: size_max_c
    //
    // Optional constraints which limits maximum bytes number
    extern constraint size_max_c;

    // Constraint: last_c
    //
    // Optional constraint which forces tlast to 1
    extern constraint last_c;

    // Constraint: strb_c
    //
    // Optional constraint which forces tstrb to 0 when tkeep is 0
    extern constraint strb_c;

  endclass : item


  /////////////////////////////////////////////////////////////////////////////////////////////////

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
      return $sformatf("%s\n%s", prefix, printer #()::add_indentation(s, 3, 1));
    endfunction : add_prefix
  endclass

  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Function: copy
  //
  // copy fields from ~rhs~ to this item
  function void bitem::copy(bitem rhs);
    this.tr_time_begin = rhs.tr_time_begin;
    this.tr_time_end = rhs.tr_time_end;
    if (rhs.policy != null) this.policy = rhs.policy.clone();
    this.is_posted = rhs.is_posted;
  endfunction : copy

  // Function: clone
  //
  // returns new copy of this object
  function bitem bitem::clone();
    clone = new();
    clone.copy(this);
  endfunction : clone

  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Constraint: posted_c
  //
  // Optional constraint which forces is_posted to 1
  constraint bitem::posted_c {
    soft is_posted == 1;
  }

  // Constraint: size_c
  //
  // Basic constraints
  constraint generic_item::size_c {
    tkeep.size() == tdata.size();
    tstrb.size() == tdata.size();
    tdata.size() > 0;
    solve tdata before tuser;
    solve tdata before tkeep;
    solve tdata before tstrb;
  }

  // Constraint: size_max_c
  //
  // Optional constraints which limits maximum bytes number
  constraint generic_item::size_max_c {
    soft tdata.size() < `ITEM_MAX_BYTES;
  }

  // Constraint: size_c
  //
  // Basic constraints
  constraint item::size_c {
    tuser.size() == tdata.size();
    tkeep.size() == tdata.size();
    tstrb.size() == tdata.size();
    tdata.size() > 0;
    solve tdata before tuser;
    solve tdata before tkeep;
    solve tdata before tstrb;
  }

  // Constraint: size_max_c
  //
  // Optional constraints which limits maximum bytes number
  constraint item::size_max_c {
    soft tdata.size() < `ITEM_MAX_BYTES / N;
  }

  // Constraint: last_c
  //
  // Optional constraint which forces tlast to 1
  constraint item::last_c {
    soft tlast == 1;
  }

  // Constraint: strb_c
  //
  // Optional constraint which forces tstrb to 0 when tkeep is 0
  constraint item::strb_c {
    solve tkeep before tstrb;
    foreach (tstrb[i,j]) {
      soft !tkeep[i][j] -> tstrb[i][j] == 1'b0;
    }
  }


  /////////////////////////////////////////////////////////////////////////////////////////////////


  // Function: compare
  //
  // Compares this item with rhs. It does not check fields from bitem
  // rhs - generic_item to compare with
  // 1 - match
  // 0 - unmatch
  function bit generic_item::compare(generic_item rhs);
    if (tdata.size() != rhs.tdata.size())
      return 0;
    foreach (tdata[i]) begin
      if (tdata[i] != rhs.tdata[i])
        return 0;
    end

    if (tkeep.size() != rhs.tkeep.size())
      return 0;
    foreach (tkeep[i]) begin
      if (tkeep[i] != rhs.tkeep[i])
        return 0;
    end

    if (tstrb.size() != rhs.tstrb.size())
      return 0;
    foreach (tstrb[i]) begin
      if (tstrb[i] != rhs.tstrb[i])
        return 0;
    end

    if (tuser.size() != rhs.tuser.size())
      return 0;
    foreach (tuser[i]) begin
      if (tuser[i] != rhs.tuser[i])
        return 0;
    end

    if (tid != rhs.tid)
        return 0;

    if (tdest != rhs.tdest)
        return 0;

    return 1;
  endfunction : compare

  // Function: mask_data_with_tkeep
  //
  // tdata bytes with corresponding tkeep equal 0 will be cleared
  function void generic_item::mask_data_with_tkeep();
    foreach (tdata[i]) tdata[i] &= {8{tkeep[i]}};
  endfunction : mask_data_with_tkeep

  // Function: convert2string
  //
  // Provides item information in the form of a string
  function string generic_item::convert2string();
    convert2string = $sformatf({
      "begin_time: %0t\n",
      "end_time:   %0t\n",
      "tdata:      %s\n",
      "tkeep:      %s\n",
      "tstrb:      %s\n",
      "tuser:      %s\n",
      "tid:        %0t\n",
      "tdest:      %0t\n"
    }, tr_time_begin, tr_time_end,
      printer #()::add_indentation(printer #(byte)::array2string(tdata, ""), 12),
      printer #()::add_indentation(printer #(bit)::array2string(tkeep, ""), 12),
      printer #()::add_indentation(printer #(bit)::array2string(tstrb, ""), 12),
      printer #()::add_indentation(printer #(byte)::array2string(tuser, ""), 12),
      tid, tdest
    );
  endfunction : convert2string


  // Function: squize_by_tkeep
  //
  // tdata bytes and tstrb bits with corresponding tkeep equal 0 will be removed -
  // item will have only valid bytes in tdata and all tkeep set to 1
  function void generic_item::squize_by_tkeep();
`ifdef XILINX_SIMULATOR
    greporter::fatal ("AXI-VIP", "generic_item_squize_by_tkeep option is not supported in Vivado simulator");
`else
    int kidx[$] = tkeep.find_index() with (item);
    tdata = tdata.find() with (item.index inside {kidx});
    tstrb = tstrb.find() with (item.index inside {kidx});
    tkeep = tkeep.find() with (item.index inside {kidx});
`endif
  endfunction : squize_by_tkeep

  // Function: copy
  //
  // copy fields from ~rhs~ to this item
  function void generic_item::copy(bitem rhs);
    generic_item _rhs;
    void'($cast(_rhs, rhs));
    super.copy(_rhs);
    this.tdata = _rhs.tdata;
    this.tkeep = _rhs.tkeep;
    this.tstrb = _rhs.tstrb;
    this.tuser = _rhs.tuser;
    this.tid   = _rhs.tid;
    this.tdest = _rhs.tdest;
  endfunction : copy

  // Function: clone
  //
  // returns new copy of this object
  function generic_item generic_item::clone();
    generic_item c = new();
    c.copy(this);
    return c;
  endfunction : clone


  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Function: compare
  //
  // Compares this item with rhs. It does not check fields from bitem
  // rhs - item to compare with
  // 1 - match
  // 0 - unmatch
  function bit item::compare(this_type rhs);
    if (tdata.size() != rhs.tdata.size())
      return 0;
    foreach (tdata[i]) begin
      if (tdata[i] !== rhs.tdata[i])
        return 0;
    end

    if (tkeep.size() != rhs.tkeep.size())
      return 0;
    foreach (tkeep[i]) begin
      if (tkeep[i] !== rhs.tkeep[i])
        return 0;
    end

    if (tstrb.size() != rhs.tstrb.size())
      return 0;
    foreach (tstrb[i]) begin
      if (tstrb[i] !== rhs.tstrb[i])
        return 0;
    end

    if (tuser.size() != rhs.tuser.size())
      return 0;
    foreach (tuser[i]) begin
      if (tuser[i] !== rhs.tuser[i])
        return 0;
    end

    if (tlast !== rhs.tlast)
        return 0;

    if (tid !== rhs.tid)
        return 0;

    if (tdest !== rhs.tdest)
        return 0;

    return 1;
  endfunction : compare

  // Function: convert2string
  //
  // Provides item information in the form of a string
  function string item::convert2string();
    convert2string = $sformatf({
      "begin_time: %0t\n",
      "end_time:   %0t\n",
      "tdata:      %s\n",
      "tkeep:      %s\n",
      "tstrb:      %s\n",
      "tuser:      %s\n",
      "tid:        %0t\n",
      "tdest:      %0t\n",
      "tlast:      %0t\n"
    }, tr_time_begin, tr_time_end,
      printer #()::add_indentation(printer #(logic [N*8-1:0])::array2string(tdata), 12),
      printer #()::add_indentation(printer #(logic [N-1:0])::array2string(tkeep), 12),
      printer #()::add_indentation(printer #(logic [N-1:0])::array2string(tstrb), 12),
      printer #()::add_indentation(printer #(U_T)::array2string(tuser), 12),
      tid, tdest, tlast
    );
  endfunction : convert2string

  // Function: mask_data_with_tkeep
  //
  // tdata bytes with corresponding tkeep equal 0 will be cleared
  function void item::mask_data_with_tkeep();
    foreach(tkeep[i,j]) tdata[i][8*j+:8] &= {8{tkeep[i][j]}};
  endfunction : mask_data_with_tkeep

  // Function: copy
  //
  // copy fields from ~rhs~ to this item
  function void item::copy(bitem rhs);
    this_type _rhs;
    void'($cast(_rhs, rhs));
    super.copy(_rhs);
    this.tdata = _rhs.tdata;
    this.tkeep = _rhs.tkeep;
    this.tstrb = _rhs.tstrb;
    this.tuser = _rhs.tuser;
    this.tlast = _rhs.tlast;
    this.tid   = _rhs.tid;
    this.tdest = _rhs.tdest;
  endfunction : copy

  // Function: clone
  //
  // returns new copy of this object
  function item::this_type item::clone();
    this_type c = new();
    c.copy(this);
    return c;
  endfunction : clone

  /////////////////////////////////////////////////////////////////////////////////////////////////

  // Class: item_conv
  //
  // Used to item convertion (item <-> generic_item)
  // item_t - concrete type of item to/from which conversion take place
  class item_conv #(type item_t = logic);
    typedef item_t::U_T U_T;
    localparam int UserWordSizeExtendedToBytes = int'($ceil(real'($bits(U_T))/8));
    localparam int N = item_t::N;
    localparam int B = 8*N;
    typedef logic[8*UserWordSizeExtendedToBytes-1:0] user_extended_to_bytes_t;

    // Function: item2generic
    //
    // Converts item to generic_item
    static function generic_item item2generic(item_t arg, bit squize_by_tkeep = 0);
      item_t reversed = new();

      user_extended_to_bytes_t user_extended_to_bytes_reversed[] = new[arg.tuser.size()];
      foreach (arg.tuser[i]) user_extended_to_bytes_reversed[i] = arg.tuser[arg.tuser.size()-i-1];

      reversed.tdata = {<<B{arg.tdata}};
      reversed.tkeep = {<<N{arg.tkeep}};
      reversed.tstrb = {<<N{arg.tstrb}};

      item2generic = new();
      item2generic.tdata = {<<8{reversed.tdata}};
      item2generic.tuser = {<<8{user_extended_to_bytes_reversed}};
      item2generic.tkeep = {<<{reversed.tkeep}};
      item2generic.tstrb = {<<{reversed.tstrb}};
      item2generic.tid   = arg.tid;
      item2generic.tdest = arg.tdest;

      if (squize_by_tkeep) begin
        item2generic.squize_by_tkeep();
      end
    endfunction : item2generic

    // Function: generic2item
    //
    // Converts generic_item to item
    static function item_t generic2item(generic_item arg, bit warn_resize = 1,
                                          bit squize_by_tkeep = 0, string report_id = "AXI-VIP");
      item_t reversed = new();
      generic_item arg_ex = new();
      user_extended_to_bytes_t user_extended_to_bytes_reversed[];
      int u_size = (((arg.tuser.size()-1) / UserWordSizeExtendedToBytes) + 1)
                    * UserWordSizeExtendedToBytes;

      if (squize_by_tkeep) begin
        arg.squize_by_tkeep();
      end

      if (warn_resize) begin
        if (arg.tdata.size() % N)
          greporter::warning(report_id, "tdata does not fit in interface, posible missmatch");
        if (arg.tkeep.size() % N)
          greporter::warning(report_id, "tkeep does not fit in interface, posible missmatch");
        if (arg.tstrb.size() % N)
          greporter::warning(report_id, "tstrb does not fit in interface, posible missmatch");
        if (arg.tuser.size() % UserWordSizeExtendedToBytes)
          greporter::warning(report_id, "tuser does not fit in interface, posible missmatch");
      end
      arg_ex.tdata = new[(((arg.tdata.size()-1)/N)+1)*N](arg.tdata);
      arg_ex.tstrb = new[(((arg.tstrb.size()-1)/N)+1)*N](arg.tstrb);
      arg_ex.tkeep = new[(((arg.tkeep.size()-1)/N)+1)*N](arg.tkeep);
      arg_ex.tuser = new[u_size](arg.tuser);

      generic2item = new();
      reversed.tdata = {<<8{arg_ex.tdata}};
      reversed.tkeep = {<<{arg_ex.tkeep}};
      reversed.tstrb = {<<{arg_ex.tstrb}};
      user_extended_to_bytes_reversed = {<<8{arg_ex.tuser}};

      generic2item.tdata = {<<B{reversed.tdata}};
      generic2item.tkeep = {<<N{reversed.tkeep}};
      generic2item.tstrb = {<<N{reversed.tstrb}};
      generic2item.tid   = arg.tid;
      generic2item.tdest = arg.tdest;
      generic2item.tlast = 1;
      generic2item.tuser = new[generic2item.tdata.size()];
      foreach (generic2item.tuser[i]) begin
        generic2item.tuser[i] = user_extended_to_bytes_reversed[generic2item.tuser.size()-i-1];
      end
    endfunction : generic2item
  endclass : item_conv


  /////////////////////////////////////////////////////////////////////////////////////////////////


endpackage : gvip_axis_item_pkg
