/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////////////////////////
// gaxis vip example with generic items //
//////////////////////////////////////////

module test;
  parameter int iterations = 10;
  parameter int N = 8;
  parameter int I = 4;
  parameter int D = 3;
  parameter type U_T = logic[31:0];

  logic clk;
  logic rst;

  // vips declaration
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_in", gvip_axis_pkg::MASTER) gaxis_vip_in(clk, rst);
  gvip_axis_if #(N, I, D, U_T, "gaxis_vip_out", gvip_axis_pkg::SLAVE) gaxis_vip_out(clk, rst);

  // get generic item type from package
  import gvip_axis_item_pkg::generic_item;
  generic_item item;
  bit test_passed;
  gvip_axis_pkg::gvip_config vcfg;

  dut dut(
    .clk       ( clk                ),
    .rst       ( rst                ),
    .i_axis_in ( gaxis_vip_in.axis  ),
    .i_axis_out( gaxis_vip_out.axis )
  );

  // class which is analyzing incomming packets from i_axis_out
  class ap_impl implements gvip_axis_pkg::generic_analysis_port_ic;
    generic_item pat_queue[$];

    virtual function void write (input generic_item item);
      generic_item pat;

      vcfg = gaxis_vip_out.core.get_config();

      if (pat_queue.size() == 0) begin
        test_passed = 1'b0;
        $error ("pattern queue is empty");
      end

      pat = pat_queue.pop_front();
      if (vcfg.generic_item_squize_by_tkeep) begin
        byte data[$];
        bit strb[$];
        bit keep[$];
        foreach (pat.tkeep[i]) begin
          if (pat.tkeep[i]) begin
            data.push_back(pat.tdata[i]);
            strb.push_back(pat.tstrb[i]);
            keep.push_back(1'b1);
          end
        end
        pat.tdata = data;
        pat.tkeep = keep;
        pat.tstrb = strb;
      end

      if (!item.compare(pat)) begin
        test_passed = 1'b0;
        $error("%t Packet missmatch\n%s\n%s", $time,
          gvip_axis_item_pkg::printer #()::add_prefix(pat.convert2string(), "pattern"),
          gvip_axis_item_pkg::printer #()::add_prefix(item.convert2string(), "result"));
      end
    endfunction : write

    function void add_pat(generic_item arg);
      pat_queue.push_back(arg);
    endfunction : add_pat

    function bit is_empty();
      return (pat_queue.size() == 0);
    endfunction : is_empty

    function void clear();
      pat_queue.delete();
    endfunction : clear

  endclass : ap_impl

  ap_impl ap;

  initial begin
    clk = 0;
    forever begin
      #2;
      clk <= !clk;
    end
  end

  initial begin
    rst <= 1;
    test_passed = 1'b1;
    repeat(4) @(posedge clk);
    rst <= 0;
  end

  int file;
  string result_file_name;
  initial begin
    gaxis_vip_in.init();
    gaxis_vip_out.init();
    ap = new();

    gaxis_vip_out.core.add_generic_ap2pkt(ap);
    gaxis_vip_out.core.cfg.generic_item_squize_by_tkeep = 1;
    gaxis_vip_out.core.cfg.warn_resize_mismatch_from_generic = 0;
    gaxis_vip_in.core.cfg.warn_resize_mismatch_from_generic = 0;

    gaxis_vip_in.core.run_phase();
    gaxis_vip_out.core.run_phase();

    repeat (iterations) begin
      item = new();
      if (!(item.randomize() with {
        tdata.size() < 32;
        tid < (1<<I);
        tdest < (1<<D);
        tuser.size() == ($bits(U_T)*((tdata.size()+N-1)/N))/8;
        // foreach(tkeep[i]) tkeep[i] == 1;
      })) begin
        test_passed = 1'b0;
        $error("Can't randomize item");
      end
      ap.add_pat(item);
      // send packet
      gaxis_vip_in.core.send_item(item);
    end

    while (!ap.is_empty) @(posedge clk);

    if (!$value$plusargs("RESULT_PREFIX=%s",result_file_name)) begin
      result_file_name="test_result";
    end

    if (test_passed) begin
      file = $fopen($sformatf("%s-ok",result_file_name),"a+");
    end
    else begin
      file = $fopen($sformatf("%s-ko",result_file_name),"a+");
    end
    $fwrite(file, "Test ended");
    $fclose(file);

    $finish;
  end

endmodule : test
