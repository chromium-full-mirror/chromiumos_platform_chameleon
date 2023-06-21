/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module i2s_registers #(
    parameter int DataWidth        = gaxilite_pkg::DataWidth,
    parameter int SoftResetCycles  = 10
) (
    input  logic                                clk,
    input  logic                                rst,

    axil_i.subordinate                                i_axi_lite,

    output i2s_registers_pkg::tx_enable_t       tx_enable,
    output i2s_registers_pkg::tx_base_addr_t    tx_base_addr,
    output i2s_registers_pkg::tx_buffer_size_t  tx_buffer_size,
    output i2s_registers_pkg::tx_producer_idx_t tx_prod_idx,
    input  i2s_registers_pkg::tx_consumer_idx_t tx_cons_idx,

    output i2s_registers_pkg::rx_enable_t       rx_enable,
    output i2s_registers_pkg::rx_base_addr_t    rx_base_addr,
    output i2s_registers_pkg::rx_buffer_size_t  rx_buffer_size,
    input  i2s_registers_pkg::rx_producer_idx_t rx_prod_idx,
    output i2s_registers_pkg::rx_consumer_idx_t rx_cons_idx,

    input  i2s_registers_pkg::error_t           error,
    output i2s_registers_pkg::soft_reset_t      soft_reset,
    input  i2s_registers_pkg::config_const_t    config_const,

    input i2s_registers_pkg::counter_t          tx_clk_counter,
    input i2s_registers_pkg::counter_t          tx_ws_counter,
    input i2s_registers_pkg::counter_t          rx_clk_counter,
    input i2s_registers_pkg::counter_t          rx_ws_counter,

    output i2s_registers_pkg::irq_t             tx_irq_meta,
    output i2s_registers_pkg::irq_t             rx_irq_meta,
    input  i2s_registers_pkg::irq_ro_t          tx_irq_const,
    input  i2s_registers_pkg::irq_ro_t          rx_irq_const,
    input  i2s_registers_pkg::sampling_freq_t   sampling_freq,
    input  i2s_registers_pkg::hdmi_n_t          n,
    input  i2s_registers_pkg::hdmi_cts_t        cts,
    input  i2s_registers_pkg::hdmi_tmds_clk_t   tmds_clk
);

  import gaxilite_pkg::kOkay;
  import gaxilite_pkg::kDecErr;
  import gaxilite_pkg::resp_t;
  import i2s_registers_pkg::*;


  ////////////////////////////////////////////////////////////////////////////
  // AXI Lite Memory Manager Interface
  logic [AddrWidth-1:0]           axil_addr;
  logic                           axil_wr_en;
  logic [DataWidth-1:0]           axil_wr_data;
  resp_t                          axil_wr_resp;
  logic                           axil_rd_resp_en;
  logic [AddrWidth-1:0]           axil_rd_resp_addr;
  logic [DataWidth-1:0]           axil_rd_resp_data;
  resp_t                          axil_rd_resp;

  soft_reset_t soft_reset_trigger;
  logic [$clog2(SoftResetCycles+1)-1:0] soft_reset_rx_cnt;
  logic [$clog2(SoftResetCycles+1)-1:0] soft_reset_tx_cnt;
  always @(posedge clk) begin
    if (rst) begin
      soft_reset        <= '0;
      soft_reset_rx_cnt <= SoftResetCycles;
      soft_reset_tx_cnt <= SoftResetCycles;
    end else begin

      if (soft_reset_trigger.tx) begin
        soft_reset_tx_cnt <= '0;
      end

      if (soft_reset_tx_cnt != SoftResetCycles) begin
        soft_reset.tx     <= 1'b1;
        soft_reset_tx_cnt <= soft_reset_tx_cnt + 1;
      end else begin
        soft_reset.tx     <= 1'b0;
      end

      if (soft_reset_trigger.rx) begin
        soft_reset_rx_cnt <= '0;
      end

      if (soft_reset_rx_cnt != SoftResetCycles) begin
        soft_reset.rx     <= 1'b1;
        soft_reset_rx_cnt <= soft_reset_rx_cnt + 1;
      end else begin
        soft_reset.rx     <= 1'b0;
      end
    end
  end

  axi_lite_manager #(
    .RrespFifoDepth ( 8             )
  ) u_axi_lite_manager (
    .clk          ( clk               ),
    .rst          ( rst               ),
    .axi          ( i_axi_lite        ),
    .addr         ( axil_addr         ),
    .wr_en        ( axil_wr_en        ),
    .wr_data      ( axil_wr_data      ),
    .wr_resp      ( axil_wr_resp      ),
    .rd_resp_en   ( axil_rd_resp_en   ),
    .rd_resp_addr ( axil_rd_resp_addr ),
    .rd_resp_data ( axil_rd_resp_data ),
    .rd_resp      ( axil_rd_resp      )
  );


  function bit[DataWidth-1:0] mask(int mask_size);
    for (int i=0; i < DataWidth; i++) begin
      mask[i] = i < mask_size ? 1'b0 : 1'b1;
    end
  endfunction : mask

  ////////////////////////////////////////////////////////////////////////////
  // Handle AXI Lite write request/response
  always_ff @(posedge clk) begin
    soft_reset_trigger <= '0;
    if (axil_wr_en) begin
      axil_wr_resp <= kOkay;
      unique case (axil_addr)
        AddrTxEnable:       tx_enable           <= axil_wr_data[$bits(tx_enable)-1:0];
        AddrTxBaseAddr:     tx_base_addr        <= axil_wr_data[$bits(tx_base_addr)-1:0] &
                                                   mask(axis_to_aximm_pkg::Boundary4kWidth);
        AddrTxBufferSize:   tx_buffer_size      <= axil_wr_data[$bits(tx_buffer_size)-1:0] &
                                                   mask(axis_to_aximm_pkg::Boundary4kWidth);
        AddrTxProducerIdx:  tx_prod_idx         <= axil_wr_data[$bits(tx_prod_idx)-1:0];

        AddrRxEnable:       rx_enable           <= axil_wr_data[$bits(rx_enable)-1:0];
        AddrRxBaseAddr:     rx_base_addr        <= axil_wr_data[$bits(rx_base_addr)-1:0] &
                                                   mask(axis_to_aximm_pkg::Boundary4kWidth);
        AddrRxBufferSize:   rx_buffer_size      <= axil_wr_data[$bits(rx_buffer_size)-1:0] &
                                                   mask(axis_to_aximm_pkg::Boundary4kWidth);
        AddrRxConsumerIdx:  rx_cons_idx         <= axil_wr_data[$bits(rx_cons_idx)-1:0];

        AddrSoftReset:      soft_reset_trigger  <= axil_wr_data[$bits(soft_reset)-1:0];

        AddrTxIrq:          tx_irq_meta         <= axil_wr_data[$bits(irq_t)-1:0];
        AddrRxIrq:          rx_irq_meta         <= axil_wr_data[$bits(irq_t)-1:0];

        default:            axil_wr_resp <= kDecErr;
      endcase
    end

    if (rst) begin
      axil_wr_resp    <= kOkay;
      tx_enable       <= '0;
      tx_base_addr    <= '0;
      tx_buffer_size  <= '0;
      tx_prod_idx     <= '0;
      rx_enable       <= '0;
      rx_base_addr    <= '0;
      rx_buffer_size  <= '0;
      rx_cons_idx     <= '0;
      tx_irq_meta     <= '0;
      rx_irq_meta     <= '0;
    end

    if (soft_reset.rx) begin
      rx_enable       <= '0;
      rx_base_addr    <= '0;
      rx_buffer_size  <= '0;
      rx_cons_idx     <= '0;
      rx_irq_meta     <= '0;
    end

    if (soft_reset.tx) begin
      tx_enable       <= '0;
      tx_base_addr    <= '0;
      tx_buffer_size  <= '0;
      tx_prod_idx     <= '0;
      tx_irq_meta     <= '0;
    end

  end

  ////////////////////////////////////////////////////////////////////////////
  // Handle AXI Lite read response
  always_ff @(posedge clk) begin
    if (axil_rd_resp_en) begin
      axil_rd_resp <= kOkay;
      axil_rd_resp_data <= '0;
      unique case (axil_rd_resp_addr) inside
        AddrTxEnable:        axil_rd_resp_data <= tx_enable;
        AddrTxBaseAddr:      axil_rd_resp_data <= tx_base_addr;
        AddrTxBufferSize:    axil_rd_resp_data <= tx_buffer_size;
        AddrTxProducerIdx:   axil_rd_resp_data <= tx_prod_idx;
        AddrTxConsumerIdx:   axil_rd_resp_data <= tx_cons_idx;

        AddrRxEnable:        axil_rd_resp_data <= rx_enable;
        AddrRxBaseAddr:      axil_rd_resp_data <= rx_base_addr;
        AddrRxBufferSize:    axil_rd_resp_data <= rx_buffer_size;
        AddrRxProducerIdx:   axil_rd_resp_data <= rx_prod_idx;
        AddrRxConsumerIdx:   axil_rd_resp_data <= rx_cons_idx;

        AddrError:           axil_rd_resp_data <= error;
        AddrConfigConst:     axil_rd_resp_data <= config_const;

        AddrTxClkCounter:    axil_rd_resp_data[CounterWidth-1:0] <= tx_clk_counter;
        AddrTxWsCounter:     axil_rd_resp_data[CounterWidth-1:0] <= tx_ws_counter;
        AddrRxClkCounter:    axil_rd_resp_data[CounterWidth-1:0] <= rx_clk_counter;
        AddrRxWsCounter:     axil_rd_resp_data[CounterWidth-1:0] <= rx_ws_counter;
        AddrCounterWidth:    axil_rd_resp_data <= CounterWidth;
        AddrClkFrequencyMhz: axil_rd_resp_data <= i2s_pkg::ClkFrequencyMhz;

        AddrRxIrq:           axil_rd_resp_data <= rx_irq_meta;
        AddrRxIrqConst:      axil_rd_resp_data <= rx_irq_const;
        AddrTxIrq:           axil_rd_resp_data <= tx_irq_meta;
        AddrTxIrqConst:      axil_rd_resp_data <= tx_irq_const;
        AddrSamplingFreq:    axil_rd_resp_data <= sampling_freq;
        AddrHdmiN:           axil_rd_resp_data <= n;
        AddrHdmiCts:         axil_rd_resp_data <= cts;
        AddrTmdsClk:         axil_rd_resp_data <= tmds_clk;

        default: begin
          axil_rd_resp <= kOkay;
        end
      endcase
    end

    if (rst) begin
      axil_rd_resp_data <= '0;
      axil_rd_resp <= kOkay;
    end
  end

endmodule : i2s_registers
