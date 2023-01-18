/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */


// Simple example with base VIPs functionality presentation
// for simplicity base dut with asynchronous assigment input to output interface is used
module test;

  import gvip_aximm_pkg::*;
  import gvip_aximm_types_pkg::gvip;

  logic clk;
  logic rst;

  // VIP instance using gvip_aximm_if interface wrapper - this instance is used as 'manager' for DUT
  gvip_aximm_if #(.N(8), .I(2), .A(32), .NAME("i_vip"), .CORE_TYPE(gvip::MASTER)) gvip_in(clk, rst);

  // based on parameters gvip_aximm_if creates item typedef which can be used in test, so let's
  // pull out for easier use
  typedef gvip_in.item_t item_t;

  // to differentiate example let's create subordinate side manually
  // we need core instance with the same parameters as input VIP and the same item type
  gvip_aximm_pkg::core #(.N(8), .I(2), .A(32), .item_t(item_t)) out_core;

  // also we need interface instance
  gaximm_if #(.N(8), .I(2), .A(32)) out_if();

  // and clock interface instance
  gclk_if clk_if(.clk(clk), .rst(rst));

  // DUT instance with interfaces mapping
  dut u_dut (
    .i_aximm_in  ( gvip_in.aximm ),
    .i_aximm_out ( out_if        )
  );


  // We want to have some analysis port which just print incoming item
  // we will use this aport for all channel and both VIPs
  // For AW_W or AR request some random response is sended
  class aport implements analysis_port_ic #(item_t);
    string name; // name of this aport used in display message

    virtual function item_t write (input item_t item);
      $display("ap[%s]: \n%s", name, item.convert2string);

      if (item.get_tr_type() == gvip::AW_W) begin
        // response with OKAY for incoming AW_W request
        void'(item.set_tr_type(gvip::B));
        item.bresp = gaximm_pkg::OKAY;
        item.bid = item.awid;
        item.buser = item.awuser;
        return item; // send response

      end else if (item.get_tr_type() == gvip::AR) begin
        item_t r_resp = new();
        // response with OKAY and some random data for incoming AR request
        void'(r_resp.set_tr_type(gvip::R));
        void'(r_resp.randomize() with {
          arlen == item.arlen;
          rresp == gaximm_pkg::OKAY;
          rid == item.arid;
        });
        return r_resp;
      end

      return null;
    endfunction : write

    function new(string name);
      this.name = name;
    endfunction : new

    static function aport create(string name);
      create = new(name);
    endfunction : create

  endclass : aport


  initial begin
    item_t item;

    gvip_in.init(); // initialize input vip - this call constructor

    // for output VIP we need do the same manually
    out_core = new("out_core", out_if, clk_if, gvip::SLAVE);

    // create and register analysis ports for output VIP
    out_core.add_ap2pkt(gvip::AW, aport::create("out::aw"));
    out_core.add_ap2pkt(gvip::AR, aport::create("out::ar"));
    out_core.add_ap2pkt(gvip::W, aport::create("out::w"));
    out_core.add_ap2pkt(gvip::AW_W, aport::create("out::aw_w"));

    // and input VIP
    gvip_in.core.add_ap2pkt(gvip::B, aport::create("in::b"));
    gvip_in.core.add_ap2pkt(gvip::R, aport::create("in::r"));

    // aport want send response for AW_W or AR transactions no matter if is used in manager
    // or subordinate, so enabling this two lines we get some warrning
    // gvip_in.core.add_ap2pkt(gvip::AW_W, aport::create("in::aw_w"));
    // gvip_in.core.add_ap2pkt(gvip::AR, aport::create("in::ar"));

    // now we can run our VIPs
    gvip_in.core.run_phase();
    out_core.run_phase();

    // TEST
    // create -> randomize -> send AW_W transaction
    item = new();
    void'(item.set_tr_type(gvip::AW_W));
    void'(item.randomize() with {awlen == 2; awcache == '0;});

    $display("generated item: \n%s", item.convert2string());

    gvip_in.core.send_item(item);

    // create -> randomize -> send AR transaction
    item = new();
    void'(item.set_tr_type(gvip::AR));
    void'(item.randomize() with {arlen == 3;});

    $display("generated item: \n%s", item.convert2string());

    gvip_in.core.send_item(item);


    #100ns;
    $finish();
  end


  // Class: test_reporter
  //
  // This class creates report file used by makefiles for summarize
  class test_reporter;

    static function void report();
      int file = open_file(result_file_name);
      $fwrite(file, $sformatf("Reporter statistics:%s",
                              greporter_pkg::greporter::convert2string()));
      close_file(file);
    endfunction : report

    static function string result_file_name();
      if (greporter_pkg::greporter::get_counter_error() ||
          greporter_pkg::greporter::get_counter_fatal()) begin
        result_file_name = $sformatf("%s-ko",result_file_prefix());
      end else begin
        result_file_name = $sformatf("%s-ok",result_file_prefix());
      end
    endfunction : result_file_name

    static function string result_file_prefix();
      if (!$value$plusargs("RESULT_PREFIX=%s",result_file_prefix)) begin
        result_file_prefix="test_result";
      end
    endfunction : result_file_prefix

    static function int open_file(string name);
      open_file = $fopen(name,"a+");
    endfunction : open_file

    static function void close_file(int hfile);
      $fclose(hfile);
    endfunction : close_file

  endclass : test_reporter

  // final report file
  final test_reporter::report();

  // clock generator
  initial begin
    clk = 0;
    forever begin
      #2;
      clk <= !clk;
    end
  end


  // reset generator
  initial begin
    rst <= 1;
    repeat(4) @(posedge clk);
    rst <= 0;
  end

endmodule
