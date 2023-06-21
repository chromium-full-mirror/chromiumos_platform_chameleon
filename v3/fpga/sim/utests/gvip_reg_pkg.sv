/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/* Registers VIP to verify register values */
interface reg_if #(parameter int unsigned DataWidth = 1) ();
  logic [DataWidth-1:0] data;

  modport host (
    output data
  );
  modport agent (
    input  data
  );
endinterface : reg_if

package gvip_reg_pkg;
  import greporter_pkg::greporter;

  typedef enum {
    kWrite,
    kRead
  } msg_type_e;

  localparam int DataWidth = 32;

  function logic [] unpack(logic [DataWidth-1:0] d);
    unpack = {>>{d}};
  endfunction

  function logic [DataWidth-1:0] pack(logic d []);
    logic [DataWidth-1:0] data;
    {>>{data}} = d;
    pack = data;
  endfunction

  class reg_msg #(parameter int unsigned AddrWidth = 32,
                  parameter int unsigned DataWidth = 32);
    typedef reg_msg #(AddrWidth, DataWidth) this_type;

    rand msg_type_e              msg_type;
    rand logic [AddrWidth-1:0]   addr;
    rand logic [DataWidth/8-1:0] strb;
    rand logic [DataWidth-1:0]   data;

    constraint c_addr {
      soft addr % 4 == 0;
    };

    constraint c_strb {
      soft strb == 4'hf;
    };

    virtual function void copy(this_type to_copy);
      this.msg_type = to_copy.msg_type;
      this.addr     = to_copy.addr;
      this.strb     = to_copy.strb;
      this.data     = to_copy.data;
    endfunction : copy

    function this_type clone();
      clone = new();
      clone.copy(this);
    endfunction

  endclass : reg_msg

  virtual class reg_meta #(parameter int unsigned AddrWidth = 32);

    typedef enum {
      kRw,
      kRo,
      kRoConst,
      kWo
    } type_e;

    const string          name;
    const type_e          reg_type;
    logic [AddrWidth-1:0] reg_addr;
    function new (string name = "",
                  logic [AddrWidth-1:0] addr,
                  type_e t);
      this.name = name;
      this.reg_addr = addr;
      this.reg_type = t;
    endfunction : new

    virtual function logic [] get();
      return unsigned'(0);
    endfunction : get

    virtual function void update(logic val []);
    endfunction : update

    virtual function void check();
    endfunction : check

  endclass : reg_meta

  virtual class reg_base #(parameter int unsigned DataWidth = 32,
                           parameter int unsigned AddrWidth = 32)
    extends reg_meta #(AddrWidth);

    virtual reg_if #(DataWidth) reg_i;
    logic [DataWidth-1:0]       reg_value;
    logic [DataWidth-1:0]       reg_mask;

    function logic [DataWidth-1:0] mask(int unsigned reg_align, int unsigned reg_size);
      mask = '0;
      for (int i = reg_align; i < reg_size; i++) begin
        mask[i] = 1'b1;
      end
    endfunction : mask

    function new(string name = "",
                 virtual reg_if #(DataWidth) r,
                 type_e                      t,
                 logic [AddrWidth-1:0]       addr,
                 int unsigned                reg_size,
                 logic [DataWidth-1:0]       reset_val = 0,
                 int unsigned                reg_align = 0);
      super.new(name, addr, t);
      this.reg_i      = r;
      this.reg_value  = reset_val;
      this.reg_mask   = mask(reg_align, reg_size);
    endfunction : new

    virtual function void check();
      if (this.reg_i.data !== this.reg_value & this.reg_mask) begin
        greporter::error(name, $sformatf("%t: %s: addr %h, dut = %h, pattern = %h",
                                         $time, name, this.reg_addr,
                                         this.reg_i.data, this.reg_value));
      end
    endfunction : check

  endclass : reg_base

  class reg_rw #(parameter int unsigned DataWidth = 32,
                 parameter int unsigned AddrWidth = 32)
    extends reg_base #(.DataWidth(DataWidth), .AddrWidth(AddrWidth));

    function new(string name = "",
                 virtual reg_if #(DataWidth) r,
                 logic [AddrWidth-1:0] addr,
                 int unsigned          reg_size,
                 logic [DataWidth-1:0] reset_val = 0,
                 int unsigned          reg_align = 0);
      super.new(name, r, kRw, addr, reg_size, reset_val, reg_align);
    endfunction : new

    virtual function logic [] get();
      return unpack(reg_value);
    endfunction : get

    virtual function void update(logic val []);
      this.reg_value = pack(val);
    endfunction : update

  endclass : reg_rw

  class reg_wo #(parameter int unsigned DataWidth = 32,
                 parameter int unsigned AddrWidth = 32)
    extends reg_base #(.DataWidth(DataWidth), .AddrWidth(AddrWidth));

    function new(string name = "",
                 virtual reg_if #(DataWidth) r,
                 logic [AddrWidth-1:0] addr,
                 int unsigned          reg_size,
                 logic [DataWidth-1:0] reset_val = 0,
                 int unsigned          reg_align = 0);
      super.new(name, r, kWo, addr, reg_size, reset_val, reg_align);
    endfunction : new

    virtual function void update(logic val []);
      this.reg_value = pack(val);
    endfunction : update

  endclass : reg_wo

  class reg_ro #(parameter int unsigned DataWidth = 32,
                 parameter int unsigned AddrWidth = 32)
    extends reg_base #(.DataWidth(DataWidth), .AddrWidth(AddrWidth));

    function new(string name = "",
                 virtual reg_if #(DataWidth) r,
                 logic [AddrWidth-1:0] addr,
                 int unsigned          reg_size,
                 logic [DataWidth-1:0] reset_val = 0,
                 int unsigned          reg_align = 0);
      super.new(name, r, kRo, addr, reg_size, reset_val, reg_align);
    endfunction : new

    virtual function logic [] get();
      return unpack(reg_value);
    endfunction : get

  endclass : reg_ro

  class reg_ro_const #(parameter int unsigned DataWidth = 32,
                       parameter int unsigned AddrWidth = 32)
    extends reg_base #(.DataWidth(DataWidth), .AddrWidth(AddrWidth));

    function new(string name = "",
                 virtual reg_if #(DataWidth) r,
                 logic [AddrWidth-1:0] addr,
                 int unsigned          reg_size,
                 logic [DataWidth-1:0] reset_val = 0,
                 int unsigned          reg_align = 0);
      super.new(name, r, kRoConst, addr, reg_size, reset_val, reg_align);
    endfunction : new

    virtual function logic [] get();
      return unpack(reg_value);
    endfunction : get

  endclass : reg_ro_const

  class reg_mon;
    protected virtual gclk_if     clk;
    protected reg_meta            regs[$];
    protected reg_msg             msg_update[$];
    protected reg_msg             msg_response[$];
    protected const int unsigned  verify_delay;

    function new(virtual gclk_if clk, int unsigned verify_delay = 0);
      this.clk          = clk;
      this.verify_delay = verify_delay;
    endfunction : new

    function void add_msg_update(input reg_msg msg);
      msg_update.push_back(msg);
    endfunction : add_msg_update

    function void add_msg_response(input reg_msg msg);
      msg_response.push_back(msg);
    endfunction : add_msg_response

    function void add_reg(input reg_meta r);
      regs.push_back(r);
    endfunction : add_reg

    function bit done();
      return (msg_update.size()) == 0 && (msg_response.size() == 0);
    endfunction : done

    task reg_update();
      reg_msg pat;
      reg_meta register[$];
      forever begin
        wait(msg_update.size());
        pat = msg_update.pop_front();
        repeat (verify_delay) @(posedge clk.clk);
        if (pat.msg_type == gvip_reg_pkg::kWrite) begin
          register = regs.find(r) with (r.reg_addr == pat.addr);
          foreach(register[i]) begin
            register[i].update(unpack(pat.data));
          end
        end
      end
    endtask : reg_update

    task reg_monitor();
      reg_msg pat;
      reg_meta register[$];
      forever begin
        wait(msg_response.size());
        pat = msg_response.pop_front();
        register = regs.find(r) with (r.reg_addr == pat.addr);
        repeat (verify_delay) @(posedge clk.clk);
        @(negedge clk.clk);
        foreach(register[i]) begin
          register[i].check();
        end
      end
    endtask : reg_monitor

  endclass : reg_mon

endpackage : gvip_reg_pkg
