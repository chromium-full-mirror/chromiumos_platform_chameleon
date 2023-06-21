/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module i2s_ssm_unit_test;


  //Unit test name
  parameter string name = "i2s_ssm_unit_test";

  //Packages and classes import from test environment
  import svunit_pkg::svunit_testcase;
  svunit_testcase svunit_ut;
  import i2s_vip_pkg::*;

  localparam int AxiLiteDataWidth = gaxilite_pkg::DataWidth;
  localparam int AxiLiteAddrWidth = i2s_registers_pkg::AddrWidth;
  localparam int MaxRingBytes     = 524288;
  localparam int DataWidth        = 128;
  localparam int TxBytesToFetch   = 64;
  localparam int SamplesInBeat    = DataWidth/$bits(i2s_pkg::sample_t);
  localparam int Id               = axis_to_aximm_pkg::kIdSsm2603Dma;

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

  i2s_vip_if #(.Name("i2s_rx"), .IsTransmitter(1), .IsMaster(1)) i2s_rx_vip(clk_i2s, rst);
  i2s_vip_if #(.Name("i2s_tx"), .IsTransmitter(0), .IsMaster(1)) i2s_tx_vip(clk_i2s, rst);
  gvip_aximm_if #(.N(DataWidth/8), .A(axis_to_aximm_pkg::AddrWidth), .NAME("mm_slv"),
                  .CORE_TYPE(gvip_aximm_types_pkg::gvip::SLAVE)) mm_vip(clk, rst);

  `AXIMM_TO_GAXIMM_VIP(mm_vip)
  `GAXIL_VIP_TO_AXIL(drv_axi)

  i2s_pkg::irq_source_t irq;

  i2s_ssm #(
    .DataOutWidth      ( DataWidth         ),
    .MaxRingBytes      ( MaxRingBytes      ),
    .TxBytesToFetch    ( TxBytesToFetch    ),
    .I2sDmaId          ( Id                )
  )
  dut (
    .clk               ( clk               ),
    .rst               ( rst               ),
    .i_axi_lite        ( axil_drv_axi      ),
    .i_i2s_rx          ( i2s_rx_vip.inf    ),
    .i_i2s_tx          ( i2s_tx_vip.inf    ),
    .i_data_out        ( aximm_mm_vip      ),
    .irq               ( irq               )
  );

  typedef i2s_rx_vip.item_t i2s_rx_item_t;
  typedef i2s_tx_vip.item_t i2s_tx_item_t;
  typedef mm_vip.item_t mm_item_t;
  typedef drv_axi.item_t axil_item_t;

  class i2s_tx_ap implements i2s_analysis_port_ic;
    protected i2s_tx_item_t pattern_queue[$];

    function void add_pattern(i2s_tx_item_t pattern);
      pattern_queue.push_back(pattern.clone());
    endfunction : add_pattern

    function void delete_pattern_queue();
      pattern_queue.delete();
    endfunction : delete_pattern_queue

    function bit is_pattern_queue_empty();
      return (pattern_queue.size() == 0);
    endfunction : is_pattern_queue_empty

    virtual task write(i2s_item item);
      i2s_tx_item_t pattern;
      `FAIL_IF(is_pattern_queue_empty())
      pattern = pattern_queue.pop_front();

      foreach (pattern.left[i]) begin
        `FAIL_IF_LOG(pattern.left[i] != item.left[i],
                     $sformatf("Mismatch in bit %d in left: pattern = 0x%0h, dut = 0x%0h",
                               i, pattern.left, item.left))
      end

      foreach (pattern.right[i]) begin
        `FAIL_IF_LOG(pattern.right[i] != item.right[i],
                     $sformatf("Mismatch in bit %d in right: pattern = 0x%0h, dut = 0x%0h",
                               i, pattern.right, item.right))
      end

    endtask : write

  endclass : i2s_tx_ap

  i2s_tx_ap tx_ap;

  class mm_ap implements gvip_aximm_pkg::analysis_port_ic#(mm_item_t);
    protected mm_item_t r_item_q[$];
    protected mm_item_t w_item_q[$];
    protected logic[7:0] pattern_in_bytes[$];
    protected int serialize_rr_ptr;
    i2s_rx_item_t rx_patterns[$];
    time wr_delay;

    typedef enum {
      kHalf = 0,
      kFull,
      kEmpty
    } cn_ring_policy_e;

    int rx_ring_base = 0;
    int rx_ring_size = 4096;
    int rx_ring_data_wr_addr = 0;
    int rx_ring_cn_idx = 0;
    cn_ring_policy_e cn_rx_ring_policy;

    int tx_ring_base = 0;
    int tx_ring_size = 4096;
    int tx_ring_data_rd_addr = 0;
    int tx_ring_pr_idx = 0;
    cn_ring_policy_e cn_tx_ring_policy;

    function void init();
      rx_patterns.delete();
      pattern_in_bytes.delete();
      r_item_q.delete();
      w_item_q.delete();
      serialize_rr_ptr = 0;
      rx_ring_size = 4096;
      rx_ring_data_wr_addr = 0;
      rx_ring_cn_idx = 0;
      tx_ring_size = 4096;
      tx_ring_data_rd_addr = 0;
      tx_ring_pr_idx = 0;
      cn_rx_ring_policy = kHalf;
      cn_tx_ring_policy = kHalf;
      wr_delay = 0;
    endfunction

    function bit rx_is_empty();
      return (rx_patterns.size() == 0);
    endfunction

    task serialize_pattern();
      i2s_rx_item_t c_item;
      `FAIL_IF_LOG(!rx_patterns.size(),
        $sformatf("Empty rx_patterns for CH#%0d", serialize_rr_ptr))

      c_item = rx_patterns.pop_front();
      for (int i = 0; i < int'($ceil(real'(c_item.MaxChannelSize)/8)); ++i) begin
        pattern_in_bytes.push_back(c_item.right[7:0]);
        c_item.right >>= 8;
      end
      for (int i = 0; i < int'($ceil(real'(c_item.MaxChannelSize)/8)); ++i) begin
        pattern_in_bytes.push_back(c_item.left[7:0]);
        c_item.left >>= 8;
      end
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
      if (item.tr_type == gvip_aximm_types_pkg::gvip::AR) begin
        i2s_tx_item_t pattern = new();
        logic [DataWidth-1:0] data[];

        r_item_q.push_back(item.clone());
        void'(item.set_tr_type(gvip_aximm_types_pkg::gvip::R));

        data = new[(TxBytesToFetch*8)/DataWidth];
        for (int i = 0; i < (TxBytesToFetch*8)/DataWidth; i++) begin
          for (int j = 0; j < SamplesInBeat; j++) begin
            pattern.randomize();
            data[i][((j+1)*DataWidth/2)-1-:DataWidth/2] = {pattern.left, pattern.right};
            tx_ap.add_pattern(pattern);
          end
        end
        item.rresp = gaximm_pkg::OKAY;
        item.rdata = data;
        item.rid   = item.arid;
        return item;
      end
      return null;
    endfunction : write

    task r_analyzer();
      mm_item_t item;
      forever begin
        wait(r_item_q.size());
        item = r_item_q.pop_front();

        `FAIL_IF(item.arburst != 1)
        `FAIL_IF(item.arprot != 0)
        `FAIL_IF(item.arlock != 0)
        `FAIL_IF(item.arcache != 0)
        `FAIL_IF(item.arregion != 0)
        `FAIL_IF(item.arlen != (TxBytesToFetch*8)/DataWidth - 1)
        `FAIL_IF(item.arsize != ((TxBytesToFetch*8)/DataWidth))
        `FAIL_IF(item.arid != Id)
      end
    endtask : r_analyzer

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
        `FAIL_IF(item.awid != Id)

        item.awaddr -= rx_ring_base;

        `FAIL_IF_LOG(item.awaddr != rx_ring_data_wr_addr,
          $sformatf("Lack of address continuity, addr:%0h, should be: %0h",
                    item.awaddr, rx_ring_data_wr_addr))

        rx_ring_data_wr_addr = (rx_ring_data_wr_addr + 8) % rx_ring_size;

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

        rx_consumer_idx(item.awaddr);
      end
    endtask : process_wr

    virtual function bit move_rx_consumer_idx_policy(int cn_pr_delta);
      case(cn_rx_ring_policy)
        kHalf : return (cn_pr_delta > (rx_ring_size / 2));
        kFull : return (cn_pr_delta == rx_ring_size - 16);
      endcase
    endfunction : move_rx_consumer_idx_policy

    task rx_consumer_idx(int rx_producer_idx);
      axil_item_t item;
      item = new();
      void'(item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      item.awaddr = i2s_registers_pkg::AddrRxConsumerIdx;
      item.wstrb = '1;

      if (!move_rx_consumer_idx_policy((rx_producer_idx - rx_ring_cn_idx + rx_ring_size) %
                                       rx_ring_size)) return;

      rx_ring_cn_idx = rx_producer_idx;

      fork begin
        @(posedge clk);
        item.wdata = rx_ring_cn_idx;
        drv_axi.core.send_item(item.clone());
      end join_none
    endtask : rx_consumer_idx

    virtual function bit wait_tx_producer_idx_policy(int cn_pr_delta);
      case(cn_tx_ring_policy)
        kEmpty : return (cn_pr_delta == 0);
        kHalf  : return (cn_pr_delta < (tx_ring_size / 2));
      endcase
    endfunction : wait_tx_producer_idx_policy

    task tx_producer_idx(int tx_consumer_idx);
      axil_item_t item;
      item = new();
      void'(item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      item.awaddr = i2s_registers_pkg::AddrTxProducerIdx;
      item.wstrb = '1;

      if (!wait_tx_producer_idx_policy((tx_ring_pr_idx - tx_consumer_idx + tx_ring_size) %
                                       tx_ring_size)) return;

      tx_ring_pr_idx = (tx_consumer_idx - TxBytesToFetch + tx_ring_size) % tx_ring_size;

      fork begin
        @(posedge clk);
        item.wdata = tx_ring_pr_idx;
        drv_axi.core.send_item(item.clone());
      end join_none
    endtask : tx_producer_idx

  endclass : mm_ap

  class axil_ap implements gvip_axil_pkg::analysis_port_ic#(axil_item_t);
    axil_item_t ar[$];
    int reg_cons_idx_q[$];
    int reg_prod_idx_q[$];
    mm_ap ap;

    function new(ref mm_ap ap);
      this.ap = ap;
    endfunction : new

    virtual function axil_item_t write(input axil_item_t item);
      axil_item_t ar_tr;
      ar_tr = ar.pop_front();
      if (item.tr_type == gvip_axil_types_pkg::gvip::R) begin
        if (ar_tr.araddr == i2s_registers_pkg::AddrTxConsumerIdx) begin
          reg_cons_idx_q.push_back(item.rdata);
        end
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
        reg_pr_idx_norm = (reg_pr_idx - ap.rx_ring_cn_idx) % ap.rx_ring_size;
        ring_pr_idx_norm = (ap.rx_ring_data_wr_addr - ap.rx_ring_cn_idx) %
                            ap.rx_ring_size;

        `FAIL_IF_LOG(reg_pr_idx_norm > ring_pr_idx_norm,
          $sformatf("PR IDX [%0d] must be inside (%0d : %0d] ring size: %0d",
            reg_pr_idx, ap.rx_ring_cn_idx, ap.rx_ring_data_wr_addr, ap.rx_ring_size))
      end
    endtask : prod_analyzer

    task cons_analyzer();
      forever begin
        @(posedge clk);
        wait(reg_cons_idx_q.size());
        ap.tx_producer_idx(reg_cons_idx_q.pop_front());
      end
    endtask : cons_analyzer

  endclass : axil_ap

  axil_ap drv_axi_ap;
  mm_ap u_mm_ap;

  function void build();
    svunit_ut = new(name);
    $timeformat(-9,3,"ns",5);

    i2s_rx_vip.init();
    i2s_tx_vip.init();
    tx_ap = new();
    i2s_tx_vip.add_ap2mon(tx_ap);

    mm_vip.init();
    u_mm_ap = new();
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AW_W, u_mm_ap);
    mm_vip.core.add_ap2pkt(gvip_aximm_types_pkg::gvip::AR, u_mm_ap);

    drv_axi_ap = new(u_mm_ap);
    drv_axi.init();
    drv_axi.core.add_ap(gvip_axil_types_pkg::gvip::R, drv_axi_ap);

    i2s_rx_vip.run_phase();
    i2s_tx_vip.run_phase();
    mm_vip.core.run_phase();
    drv_axi.core.run_phase();

    fork
      begin
        u_mm_ap.process_wr();
      end
      begin
        u_mm_ap.r_analyzer();
      end
    join_none

  endfunction

  task setup();
    int reset_cycles;
    i2s_tx_item_t i2s_tx_data;

    svunit_ut.setup();
    u_mm_ap.init();
    `FAIL_IF(!std::randomize(reset_cycles) with {reset_cycles > I2sClkPeriod/2 &&
                                                 reset_cycles < I2sClkPeriod;})
    rst <= 1'b1;
    repeat(reset_cycles) @(posedge clk);

    i2s_tx_data = new();
    i2s_tx_data.repeat_this = -1;   // repeat until the end of test
    i2s_tx_data.ws_bclk_ratio = 64; // for 44,1 kHz

    // Only for utest purposes, force at least two cycles
    // of BCLK (slow) reset.
    //
    // The reason behind it is that WS signal is set on negedge
    // of BCLK and probed by RTL on posedge of BCLK,
    // according to SSM2603 specification.
    //
    // So in hardware it's fine to have the first sample
    // from axis delayed by single i2s transaction period.
    //
    // In unit test it isn't, so there's a need to keep reset longer
    // (to make sure that first WS falling edge will be correctly probed
    // by RTL.
    repeat(2) @(posedge clk_i2s);
    rst <= 1'b0;
    @(posedge clk);

    // force i2s_vip to set ws
    i2s_tx_vip.write_item(i2s_tx_data);

  endtask

  task teardown();
    tx_ap.delete_pattern_queue();
    svunit_ut.teardown();
  endtask : teardown


  task automatic exec_test(int used_bits = 32, int ws_bclk_ratio = 64, tx_prod_idx_updates = 10);
      i2s_rx_item_t i2s_item = new();
      axil_item_t axil_item = new();

      axil_item.wstrb  = '1;
      void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AW_W));
      axil_item.awaddr = i2s_registers_pkg::AddrRxBaseAddr;
      axil_item.wdata  = u_mm_ap.rx_ring_base;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrRxBufferSize;
      axil_item.wdata  = u_mm_ap.rx_ring_size;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrRxEnable;
      axil_item.wdata  = 1;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrTxBaseAddr;
      axil_item.wdata  = u_mm_ap.tx_ring_base;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrTxBufferSize;
      axil_item.wdata  = u_mm_ap.tx_ring_size;
      drv_axi.core.send_item(axil_item.clone());
      axil_item.awaddr = i2s_registers_pkg::AddrTxEnable;
      axil_item.wdata  = 1;
      drv_axi.core.send_item(axil_item.clone());

      fork
        begin
          for (int j = 0; j < 100; ++j) begin
            `FAIL_IF(!i2s_item.randomize() with {
                ws_bclk_ratio == local::ws_bclk_ratio;
                used_bits == local::used_bits;
              } )
            u_mm_ap.rx_patterns.push_back(i2s_item.clone);
            i2s_rx_vip.write_item(i2s_item.clone);
          end
        end
        begin
          void'(axil_item.set_tr_type(gvip_axil_types_pkg::gvip::AR));
          axil_item.araddr = i2s_registers_pkg::AddrTxConsumerIdx;
          drv_axi_ap.ar.push_back(axil_item.clone());
          drv_axi.core.send_item(axil_item.clone());
        end
        begin
          drv_axi_ap.cons_analyzer();
        end
      join_none
  endtask

  task drain_test();
    do begin
      @(posedge clk_i2s);
    end while (!u_mm_ap.rx_is_empty());
    wait(tx_ap.is_pattern_queue_empty());
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

    `SVTEST(always_ready_4096_32bits)
      int used_bits = 32;
      int ws_bclk_ratio = 64;

      u_mm_ap.rx_ring_size = 4096;
      u_mm_ap.rx_ring_base = 0;
      u_mm_ap.cn_rx_ring_policy = mm_ap::kFull;

      u_mm_ap.tx_ring_size = 4096;
      u_mm_ap.tx_ring_base = 0;
      u_mm_ap.cn_tx_ring_policy = mm_ap::kEmpty;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    `SVTEST(always_ready_8192_16bits)

      int used_bits = 16;
      int ws_bclk_ratio = 64;
      u_mm_ap.rx_ring_size = 8192;
      u_mm_ap.rx_ring_base = 'h2000_0000;

      u_mm_ap.tx_ring_size = 8192;
      u_mm_ap.tx_ring_base = 'h2000_0000;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    `SVTEST(always_ready_4096_20bits)

      int used_bits = 20;
      int ws_bclk_ratio = 64;
      u_mm_ap.rx_ring_size = 4096;
      u_mm_ap.rx_ring_base = 'h2000_0000;

      u_mm_ap.tx_ring_size = 4096;
      u_mm_ap.tx_ring_base = 'h2000_0000;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    `SVTEST(always_ready_4096_32bits_r144)

      int used_bits = 32;
      int ws_bclk_ratio = 144;
      u_mm_ap.rx_ring_size = 4096;
      u_mm_ap.rx_ring_base = 'h2000_0000;

      u_mm_ap.tx_ring_size = 4096;
      u_mm_ap.tx_ring_base = 'h2000_0000;


      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::always_active::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR,
                             gvip_policy_pkg::always_active::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    `SVTEST(random_mm_ready)
      int used_bits = 32;
      int ws_bclk_ratio = 64;
      u_mm_ap.rx_ring_size = 4096;
      u_mm_ap.rx_ring_base = 0;

      u_mm_ap.tx_ring_size = 4096;
      u_mm_ap.tx_ring_base = 0;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR,
                             gvip_policy_pkg::random_std::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      drain_test();

    `SVTEST_END

    `SVTEST(common_random_mm_ready)

      int used_bits = 32;
      int ws_bclk_ratio = 64;
      u_mm_ap.rx_ring_size = 4096;
      u_mm_ap.rx_ring_base = 0;
      u_mm_ap.cn_rx_ring_policy = mm_ap::kFull;

      u_mm_ap.tx_ring_size = 4096;
      u_mm_ap.tx_ring_base = 0;
      u_mm_ap.cn_tx_ring_policy = mm_ap::kEmpty;

      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AW,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::W,
                             gvip_policy_pkg::random_std::create(), 1);
      mm_vip.core.set_policy(gvip_aximm_types_pkg::gvip::AR,
                             gvip_policy_pkg::random_std::create(), 1);

      exec_test(used_bits, ws_bclk_ratio);

      fork
        pull_pr_idx();
      join_none

      #2us

      drain_test();

    `SVTEST_END

  `SVUNIT_TESTS_END

endmodule : i2s_ssm_unit_test
