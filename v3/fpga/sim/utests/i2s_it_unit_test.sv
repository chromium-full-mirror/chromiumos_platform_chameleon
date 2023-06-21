/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Test for i2s_it module.
//
// Integrate full i2s_it68051 path (from I2S pins to AP DMA).
// Generate patterns on i2s_vip interface array input,
// compare on output in axim_vip_i.
//
// Simulate software behavior via CSR configuration
// (ring_enable, ring_addr, ring_size etc). due to used
// dma_data_writer module.
//
module i2s_it_unit_test;


  //Unit test name
  parameter string name = "i2s_it_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;

  localparam int AxiLiteDataWidth = gaxilite_pkg::DataWidth;
  localparam int AxiLiteAddrWidth = i2s_registers_pkg::AddrWidth;
  localparam int ItChannelNum     = 6;
  localparam int MaxRingBytes     = 524288;
  localparam int DataWidth        = 128;

  logic clk = 1'b0;
  logic clk_i2s = 1'b0;
  logic rst;

  localparam int ClkPeriod = 5;       //200MHz
  localparam int I2sClkPeriod = 354;  //11.2896 MHz (MCLK) / 4, table 30, row 15

  `SVUNIT_CLK_GEN(clk,     ClkPeriod)
  `SVUNIT_CLK_GEN(clk_i2s, I2sClkPeriod)

  gvip_axil_if #(.N(AxiLiteDataWidth/8), .A(AxiLiteAddrWidth),
                 .NAME("drv_axi"),
                 .CORE_TYPE(gvip_axil_types_pkg::gvip::MASTER)) drv_axi(clk, rst);

  i2s_vip_if #(.Name("i2s_tx"), .IsTransmitter(1),
               .IsMaster(1), .InterfaceArraySize(ItChannelNum)) i2s_vip (clk_i2s, rst);
  gvip_aximm_if #(.N(DataWidth/8), .A(axis_to_aximm_pkg::AddrWidth), .NAME("mm_slv"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) mm_vip(clk, rst);

  `AXIMM_TO_GAXIMM_VIP(mm_vip)
  `GAXIL_VIP_TO_AXIL(drv_axi)

  i2s_pkg::irq_source_t irq;

  i2s_it #(
    .I2sDmaId          ( 0                ),
    .MaxRingBytes      ( MaxRingBytes     ),
    .AddressWidth      ( AxiLiteDataWidth ),
    .DataOutWidth      ( DataWidth        ),
    .ItChannelNum      ( ItChannelNum     ),
    .TimingRegType     ( 0                )
  ) dut (
    .clk        ( clk          ),
    .rst        ( rst          ),
    .i_axi_lite ( axil_drv_axi ),
    .i_i2s_rx   ( i2s_vip.infa ),
    .i_data_out ( aximm_mm_vip ),
    .irq        ( irq          )
  );

  typedef i2s_vip.item_t i2s_item_t;
  typedef mm_vip.item_t mm_item_t;
  typedef drv_axi.item_t axil_item_t;

  class mm_ap implements gvip_aximm_pkg::analysis_port_ic#(mm_item_t);
    i2s_item_t patterns[ItChannelNum-1:0][$];
    protected mm_item_t w_item_q[$];
    protected logic[7:0] pattern_in_bytes[$];
    protected int serialize_rr_ptr;
    time wr_delay;

    typedef enum {
      kHalf = 0,
      kFull
    } cn_ring_policy_e;

    int ring_base = 0;
    int ring_size = 4096;
    int ring_data_wr_addr = 0;
    int ring_cn_idx = 0;
    cn_ring_policy_e cn_ring_policy;

    function void init();
      foreach (patterns[i]) patterns[i].delete();
      pattern_in_bytes.delete();
      w_item_q.delete();
      serialize_rr_ptr = 0;
      ring_size = 4096;
      ring_data_wr_addr = 0;
      ring_cn_idx = 0;
      cn_ring_policy = kHalf;
      wr_delay = 0;
    endfunction

    function bit is_empty();
      is_empty = 1;
      foreach (patterns[i]) is_empty &= (patterns[i].size() == 0);
      is_empty &= (pattern_in_bytes.size() == 0);
      return is_empty;
    endfunction

    task serialize_pattern();
      logic[7:0] pattern_in_bytes_left[$];
      logic[7:0] pattern_in_bytes_right[$];
      i2s_item_t c_item;
      `FAIL_IF_LOG(!patterns[serialize_rr_ptr].size(),
        $sformatf("Empty patterns for CH#%0d", serialize_rr_ptr))

      c_item = patterns[serialize_rr_ptr].pop_front();

      pattern_in_bytes_right = {<<byte{c_item.right}};
      pattern_in_bytes_left  = {<<byte{c_item.left}};
      pattern_in_bytes       = {pattern_in_bytes_right, pattern_in_bytes_left};

      serialize_rr_ptr++;

      if (serialize_rr_ptr == ItChannelNum) serialize_rr_ptr = 0;
    endtask

    virtual function mm_item_t write (input mm_item_t item);
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AW_W) begin
        w_item_q.push_back(item.clone());
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::B));
        item.bresp = gaximm_pkg::OKAY;
        item.bid   = item.awid;
        item.buser = item.awuser;
        return item;
      end
      return null;
    endfunction : write

    virtual task process_wr();
      mm_item_t item;
      forever begin
        wait(w_item_q.size());
        #wr_delay;
        item = w_item_q.pop_front();
        `FAIL_IF(item.awburst != 1)
        `FAIL_IF(item.awprot != 0)
        `FAIL_IF(item.awlock != 0)
        `FAIL_IF(item.awcache != 0)
        `FAIL_IF(item.awregion != 0)
        `FAIL_IF(item.awlen != 0)
        `FAIL_IF(item.awsize != 4)
        `FAIL_IF(item.awid != 0)

        item.awaddr -= ring_base;

        `FAIL_IF_LOG(item.awaddr != ring_data_wr_addr,
          $sformatf("Lack of address continuity, addr:%0h, should be: %0h",
                    item.awaddr, ring_data_wr_addr))

        ring_data_wr_addr = (ring_data_wr_addr + 8) % ring_size;

        foreach (item.wdata[i]) begin
          for (int j = 0; j < $bits(item.wstrb[i]); ++j) begin
            if (!item.wstrb[i][j]) continue;
            else begin
              logic [7:0] bp;
              if (!pattern_in_bytes.size()) serialize_pattern();

              bp = pattern_in_bytes.pop_front();
              `FAIL_IF_LOG(bp != item.wdata[i][j*8+7-:8],
                $sformatf("pattern-> %0h != %0h <-data | byte_idx: %0d",
                          bp, item.wdata[i][j*8+7-:8], j));
            end
          end
        end

        consumer_idx(item.awaddr);
      end
    endtask : process_wr

    virtual function bit move_consumer_idx_policy(int cn_pr_delta);
      unique case(cn_ring_policy)
        kHalf   : return (cn_pr_delta > (ring_size / 2));
        kFull   : return (cn_pr_delta == ring_size - 16);
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
        drv_axi.core.send_item(item.clone());
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

    i2s_vip.init();
    mm_vip.init();
    drv_axi.init();

    u_mm_ap = new();
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, u_mm_ap);

    drv_axi_ap = new(u_mm_ap);
    drv_axi.core.add_ap(gvip_axil_types_pkg::gvip::R, drv_axi_ap);

    i2s_vip.run_phase();
    mm_vip.core.run_phase();
    drv_axi.core.run_phase();

    fork
      u_mm_ap.process_wr();
    join_none
  endfunction

  task setup();
    int reset_cycles;
    svunit_ut.setup();
    u_mm_ap.init();
    `FAIL_IF(!std::randomize(reset_cycles) with {reset_cycles > I2sClkPeriod/2 &&
                                                 reset_cycles < I2sClkPeriod;})
    rst <= 1'b1;
    repeat(reset_cycles) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);

  endtask

  task teardown();
    svunit_ut.teardown();
  endtask : teardown

  task automatic exec_test(int used_bits = 32, int ws_bclk_ratio = 64);
      i2s_item_t i2s_item = new();
      axil_item_t axil_item = new();

      axil_item.wstrb  = '1;
      void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      axil_item.awaddr = i2s_registers_pkg::AddrRxBaseAddr;
      axil_item.wdata  = u_mm_ap.ring_base;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrRxBufferSize;
      axil_item.wdata  = u_mm_ap.ring_size;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrRxEnable;
      axil_item.wdata  = 1;
      drv_axi.core.send_item(axil_item.clone());

      fork
        for (int ch = 0; ch < ItChannelNum; ++ch) begin
          automatic int ii = ch;
          repeat (100) begin
            `FAIL_IF(!i2s_item.randomize() with {
                ws_bclk_ratio == local::ws_bclk_ratio;
                used_bits == local::used_bits;
              } )
            u_mm_ap.patterns[ii].push_back(i2s_item.clone);
            i2s_vip.write_item(i2s_item.clone, ii);
          end
        end
      join_none
  endtask

  task drain_test();
    do begin
      @(posedge clk_i2s);
    end while (!u_mm_ap.is_empty());
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
          drv_axi.core.send_item(axil_item.clone());
        end
      end
      begin
        drv_axi_ap.prod_analyzer();
      end
    join_none
  endtask

  `SVUNIT_TESTS_BEGIN

    // Set always_ready on AW/W parts of axi_mm, configure i2s bus parameters
    // (ws_bclk_ratio and used_bits), set consumer_idx policy to get all available data
    // from ring in every update.

    `SVTEST(always_ready_4096_32bits)
      int used_bits = 32;
      int ws_bclk_ratio = 64;

      u_mm_ap.ring_size = 4096;
      u_mm_ap.ring_base = 0;
      u_mm_ap.cn_ring_policy = mm_ap::kFull;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    // Set always_ready on AW/W parts of axi_mm, configure i2s bus parameters
    // (ws_bclk_ratio and used_bits), set consumer_idx policy to get half of available data
    // from ring in every update.
    `SVTEST(always_ready_8192_16bits)

      int used_bits = 16;
      int ws_bclk_ratio = 64;
      u_mm_ap.ring_size = 8192;
      u_mm_ap.ring_base = 'h2000_0000;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    // Set always_ready on AW/W parts of axi_mm, configure i2s bus parameters
    // (ws_bclk_ratio and used_bits), set consumer_idx policy to get half of available data
    // from ring in every update.
    `SVTEST(always_ready_4096_20bits)

      int used_bits = 20;
      int ws_bclk_ratio = 64;
      u_mm_ap.ring_size = 4096;
      u_mm_ap.ring_base = 'h2000_0000;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    // Set always_ready on AW/W parts of axi_mm, configure i2s bus parameters
    // (ws_bclk_ratio and used_bits), set consumer_idx policy to get half of available data
    // from ring in every update.
    `SVTEST(always_ready_4096_32bits_r144)
      int used_bits = 32;
      int ws_bclk_ratio = 144;
      u_mm_ap.ring_size = 4096;
      u_mm_ap.ring_base = 'h2000_0000;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    // Set random_ready on AW/W parts of axi_mm, configure i2s bus parameters
    // (ws_bclk_ratio and used_bits), set consumer_idx policy to get half of available data
    // from ring in every update.
    `SVTEST(random_mm_ready)
      int used_bits = 32;
      int ws_bclk_ratio = 64;
      u_mm_ap.ring_size = 4096;
      u_mm_ap.ring_base = 0;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::random_std::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    // Set random_ready on AW/W parts (same policy) of axi_mm, configure i2s bus parameters
    // (ws_bclk_ratio and used_bits), set consumer_idx policy to get all of available data
    // from ring in every update. Verify updates of producer_idx.
    `SVTEST(common_random_mm_ready)

      int used_bits = 32;
      int ws_bclk_ratio = 64;
      u_mm_ap.ring_size = 4096;
      u_mm_ap.ring_base = 0;
      u_mm_ap.cn_ring_policy = mm_ap::kFull;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::random_std::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      fork
        pull_pr_idx();
      join_none

      #2us

      drain_test();

    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : i2s_it_unit_test
