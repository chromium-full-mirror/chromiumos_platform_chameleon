/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`include "svunit_defines.svh"

module dp_audio_adapter_unit_test;

  //Unit test name
  parameter string name = "dp_audio_adapter_unit_test";

  //Packages and classes import
  import svunit_pkg::svunit_testcase;
  import svunit_greporter_pkg::*;
  import axis_to_aximm_pkg::Value4k;
  import axis_to_aximm_pkg::Boundary4kWidth;
  import axis_to_aximm_pkg::AddrWidth;
  svunit_testcase svunit_ut;

  //Clocking
  logic aud_clk = 1'b0;
  logic aud_rst = 1'b0;
  logic clk = 1'b0;
  logic rst;
  `SVUNIT_CLK_GEN(aud_clk, 5)
  `SVUNIT_CLK_GEN(clk,     4)

  localparam int Id = axis_to_aximm_pkg::kIdFbDpMstAud;
  localparam int AudDataWidth = 256;
  localparam int DataWidth = 128;

  localparam int I = 0;
  localparam int D = 0;

  i2s_pkg::irq_source_t aud_irq;

  //Inputs and outputs
  gvip_axis_if #(AudDataWidth/8, I, D, dp_rx_pkg::dp_infoframe_t,
                 "single", gvip_axis_pkg::MASTER) v_aud(aud_clk, aud_rst);
  gvip_aximm_if #(.N(DataWidth/8), .A(AddrWidth), .I(4), .NAME("v_mm"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) v_mm(clk, rst);
  gvip_axil_if #(.N(gaxilite_pkg::DataWidth/8), .A(i2s_registers_pkg::AddrWidth),
                 .NAME("axi"), .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) v_axil(clk, rst);

  axis_i  #(.DataWidth(DataWidth), .WordWidth(8), .Tuser(axis_to_aximm_pkg::meta_t)) i_axis_aud();
  axis_i #(.DataWidth(1), .WordWidth(1), .Tuser(axis_to_aximm_pkg::meta_t)) i_axis_aud_rq_dummy();
  axis_i #(.DataWidth(1), .WordWidth(1), .UserWidth(1))                     i_axis_aud_resp_dummy();
  `AXIMM_TO_GAXIMM_VIP(v_mm)
  `GAXIL_VIP_TO_AXIL(v_axil)

  dp_audio_i i_dp_aud();
  logic write_done;

  assign i_axis_aud_rq_dummy.tvalid = 1'b0;
  assign i_axis_aud_resp_dummy.tready = 1'b0;
  assign i_axis_aud_rq_dummy.tdata = '0;
  assign i_axis_aud_rq_dummy.tkeep = '0;
  assign i_axis_aud_rq_dummy.tuser = '0;
  assign i_axis_aud_rq_dummy.tlast = '0;

  assign v_aud.axis.tready = 1'b1;
  always_comb begin
    i_dp_aud.valid = v_aud.axis.tvalid && v_aud.axis.tready;
    i_dp_aud.lpcm_data = v_aud.axis.tdata;
    i_dp_aud.infoframe = v_aud.axis.tuser;
    i_dp_aud.mute = '0;
  end

  typedef v_aud.item_t aud_item_t;
  typedef v_mm.item_t mm_item_t;
  typedef v_axil.item_t axil_item_t;

  dp_audio_adapter dut (
      .clk             ( clk                        ),
      .rst             ( rst                        ),
      .aud_clk         ( aud_clk                    ),
      .write_done      ( write_done                 ),
      .i_dp_audio      ( i_dp_aud                   ),
      .irq             ( aud_irq                    ),
      .i_aud_dp_csr    ( axil_v_axil                ),
      .i_aud_dp_write  ( i_axis_aud                 )
  );

    axis_to_aximm #(
        .Id           ( axis_to_aximm_pkg::kIdFbDpMstAud ),
        .DataWidth    ( DataWidth                        )
    ) u_aud_axis_to_aximm (
        .clk          ( clk                   ),
        .rst          ( rst                   ),
        .i_write      ( i_axis_aud            ),
        .write_done   ( write_done            ),
        .i_read_rq    ( i_axis_aud_rq_dummy   ),
        .i_read_resp  ( i_axis_aud_resp_dummy ),
        .i_mm         ( aximm_v_mm            )
    );

  class mm_ap implements gvip_aximm_pkg::analysis_port_ic#(mm_item_t);
    protected logic [DataWidth-1:0] pattern_serialized[$];
    protected mm_item_t responses[$];

    typedef enum {
      kHalf = 0,
      kFull
    } cn_ring_policy_e;

    int ring_base = 0;
    int ring_size = 4096;
    int ring_data_wr_addr = 0;
    int ring_cn_idx = 0;
    cn_ring_policy_e cn_ring_policy;
    time wr_delay;

    function void add_aud_pattern(aud_item_t pattern);
      logic [DataWidth-1:0] pat;
      foreach(pattern.tdata[i]) begin
        pat = pattern.tdata[i][DataWidth-1:0];
        for (int i = 0; i < 4; i++) begin
          pat[(i+1)*32-1-:24] = pat[(i+1)*32-1-8-:24];
          pat[(i+1)*32-1-24-:8] = '0;
        end
        pattern_serialized.push_back(pat);
        pat = pattern.tdata[i][DataWidth*2-1-:DataWidth];
        for (int i = 0; i < 4; i++) begin
          pat[(i+1)*32-1-:24] = pat[(i+1)*32-1-8-:24];
          pat[(i+1)*32-1-24-:8] = '0;
        end
        pattern_serialized.push_back(pat);
      end
    endfunction : add_aud_pattern

    function bit is_aud_queue_empty();
      return pattern_serialized.size() == 0;
    endfunction : is_aud_queue_empty

    function void init();
      pattern_serialized.delete();
      responses.delete();
      ring_size = 4096;
      ring_data_wr_addr = 0;
      ring_cn_idx = 0;
      cn_ring_policy = kHalf;
      wr_delay = 0;
    endfunction

    virtual function mm_item_t write (input mm_item_t item);
      responses.push_back(item.clone());
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AW_W) begin
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::B));
        item.bresp = gaximm_pkg::OKAY;
        item.bid   = item.awid;
        item.buser = item.awuser;
        return item;
      end
      return null;
    endfunction : write

    task analyzer();
      mm_item_t    item;
      logic [DataWidth-1:0] aud_pattern;
      forever begin
        wait(responses.size());
        #wr_delay;
        item = responses.pop_front();
        `FAIL_IF(is_aud_queue_empty());
        aud_pattern = pattern_serialized.pop_front();

        `FAIL_IF(item.awburst  != gaxim_pkg::kIncr)
        `FAIL_IF(item.awprot   != '0)
        `FAIL_IF(item.awlock   != '0)
        `FAIL_IF(item.awcache  != '0)
        `FAIL_IF(item.awregion != '0)
        `FAIL_IF_LOG(item.awid     != Id, $sformatf("item = %d, Id = %d", item.awid, Id));
        `FAIL_IF(item.awlen    != '0)
        `FAIL_IF(item.awsize   != gaxim_pkg::kBytes16)

        item.awaddr -= ring_base;

        `FAIL_IF_LOG(item.awaddr != ring_data_wr_addr,
          $sformatf("Lack of address continuity, addr:%0h, should be: %0h",
                    item.awaddr, ring_data_wr_addr))

        ring_data_wr_addr = (ring_data_wr_addr + 16) % ring_size;

        foreach (item.wdata[i]) begin
          `FAIL_IF_LOG(aud_pattern != item.wdata[i], $sformatf("pattern-> %0h != %0h <-data",
                                                               aud_pattern, item.wdata[i]));
        end

        consumer_idx(item.awaddr);
      end
    endtask : analyzer

    virtual function bit move_consumer_idx_policy(int cn_pr_delta);
      unique case(cn_ring_policy)
        kHalf   : return (cn_pr_delta > (ring_size / 2));
        kFull   : return (cn_pr_delta == ring_size - 32);
        default : $fatal(1, "cn_ring_policy set to %d", cn_ring_policy);
      endcase
    endfunction

    task consumer_idx(int producer_idx);
      axil_item_t item;
      item = new();
      void'(item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      item.awaddr = i2s_registers_pkg::AddrRxConsumerIdx;
      item.wstrb = '1;

      if (!move_consumer_idx_policy((producer_idx - ring_cn_idx + ring_size) % ring_size)) return;

      ring_cn_idx = producer_idx;
      fork begin
        @(posedge clk);
        item.wdata = ring_cn_idx;
        v_axil.core.send_item(item.clone());
      end join_none
    endtask : consumer_idx

  endclass : mm_ap

  class axil_ap implements gvip_axil_pkg::analysis_port_ic#(axil_item_t);
    axil_item_t ar[$];
    int reg_prod_idx_q[$];
    mm_ap ap;

    function new(ref mm_ap ap);
      this.ap = ap;
    endfunction : new

    virtual function axil_item_t write(input axil_item_t item);
      axil_item_t ar_tr;
      ar_tr = ar.pop_front();
      if (item.tr_type == gvip_axil_types_pkg::gvip::R) begin
        if (ar_tr.araddr == i2s_registers_pkg::AddrRxProducerIdx) begin
          reg_prod_idx_q.push_back(item.rdata);
        end
      end
      return null;
    endfunction : write

    task prod_analyzer();
      int unsigned reg_pr_idx;
      int unsigned reg_pr_idx_norm;
      int unsigned ring_pr_idx_norm;
      forever begin
        @(posedge clk);
        wait(reg_prod_idx_q.size());
        reg_pr_idx = reg_prod_idx_q.pop_front();
        reg_pr_idx_norm = (reg_pr_idx - ap.ring_cn_idx) % ap.ring_size;
        ring_pr_idx_norm = (ap.ring_data_wr_addr - ap.ring_cn_idx) % ap.ring_size;

        `FAIL_IF_LOG(reg_pr_idx_norm > ring_pr_idx_norm,
          $sformatf("PR IDX [%0d], must be inside [%0d : %0d] ring size: %0d",
            reg_pr_idx, ap.ring_cn_idx, ap.ring_data_wr_addr, ap.ring_size))
      end
    endtask : prod_analyzer

  endclass : axil_ap

  axil_ap drv_axi_ap;
  mm_ap u_mm_ap;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    v_aud.init();
    v_mm.init();
    v_axil.init();

    u_mm_ap = new();
    v_mm.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, u_mm_ap);

    drv_axi_ap = new(u_mm_ap);
    v_axil.core.add_ap(gvip_axil_types_pkg::gvip::R, drv_axi_ap);

    v_aud.core.run_phase();
    v_mm.core.run_phase();
    v_axil.core.run_phase();

    fork
      u_mm_ap.analyzer();
    join_none
  endfunction

  task setup();
    svunit_ut.setup();
    u_mm_ap.init();
    rst <= 1'b1;
    repeat(5) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
  endtask

  task teardown();
    svunit_ut.teardown();
  endtask : teardown

  task automatic exec_test();
    aud_item_t aud_item = new();
    axil_item_t axil_item = new();

    axil_item.wstrb  = '1;
    void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
    axil_item.awaddr = i2s_registers_pkg::AddrRxBaseAddr;
    axil_item.wdata  = u_mm_ap.ring_base;
    v_axil.core.send_item(axil_item.clone());
    axil_item.awaddr = i2s_registers_pkg::AddrRxBufferSize;
    axil_item.wdata  = u_mm_ap.ring_size;
    v_axil.core.send_item(axil_item.clone());
    axil_item.awaddr = i2s_registers_pkg::AddrRxEnable;
    axil_item.wdata  = 1;
    v_axil.core.send_item(axil_item.clone());

    fork
      repeat (50) begin
        `FAIL_IF(!aud_item.randomize())
        u_mm_ap.add_aud_pattern(aud_item.clone());
        v_aud.core.send_item(aud_item.clone());
      end
    join_none
  endtask

  task drain_test();
    do begin
      @(posedge clk);
    end while (!u_mm_ap.is_aud_queue_empty());
  endtask

  task pull_pr_idx();
    automatic axil_item_t axil_item = new();
    void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AR));
    axil_item.araddr = i2s_registers_pkg::AddrRxProducerIdx;
    fork
      begin
        forever begin
          @(posedge clk);
          drv_axi_ap.ar.push_back(axil_item.clone());
          v_axil.core.send_item(axil_item.clone());
        end
      end
      begin
        drv_axi_ap.prod_analyzer();
      end
    join_none
  endtask

  `SVUNIT_TESTS_BEGIN

    // Set always_ready on AW/W parts of axi_mm,
    // set consumer_idx policy to get all available data
    // from ring in every update.

    `SVTEST(always_ready_4096_full)
      gvip_policy_pkg::random_std rr_schema = gvip_policy_pkg::random_std::create();
      u_mm_ap.ring_size = 4096;
      u_mm_ap.ring_base = 0;
      u_mm_ap.cn_ring_policy = mm_ap::kFull;


      `FAIL_IF(!rr_schema.randomize() with {
        foreach(active_interval[i]) active_interval[i] < 8;
      })

      v_aud.core.set_policy(rr_schema);
      v_mm.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                           gvip_policy_pkg::always_active::create(), 1);
      v_mm.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                           gvip_policy_pkg::always_active::create(), 1);
      exec_test();

      drain_test();

    `SVTEST_END

    `SVTEST(always_ready_8192_half)
      gvip_policy_pkg::random_std rr_schema = gvip_policy_pkg::random_std::create();
      u_mm_ap.ring_size = 8192;
      u_mm_ap.ring_base = 0;
      u_mm_ap.cn_ring_policy = mm_ap::kFull;


      `FAIL_IF(!rr_schema.randomize() with {
        foreach(active_interval[i]) active_interval[i] < 8;
      })

      v_aud.core.set_policy(rr_schema);
      v_mm.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                           gvip_policy_pkg::always_active::create(), 1);
      v_mm.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                           gvip_policy_pkg::always_active::create(), 1);
      exec_test();

      drain_test();

    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : dp_audio_adapter_unit_test
