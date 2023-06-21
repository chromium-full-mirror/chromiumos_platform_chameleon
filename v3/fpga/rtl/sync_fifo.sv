/*
 * Copyright 2023 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */


module sync_fifo #(
    parameter int DataWidth       = 8,
    parameter int DataDepth       = 8,
    parameter int CntWidth        = $clog2(DataDepth+1),
    parameter int Fwft            = 0,
    parameter int AfullThreshold  = DataDepth-1,
    parameter int AemptyThreshold = 1,
    parameter int DataCountSrc    = 1,  // 0 - input counter, 1 - output counter
    parameter reg_handshake_pkg::reg_type_e RegStage = reg_handshake_pkg::kBypass
)
(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 wr_en,
    input  logic [DataWidth-1:0] din,
    output logic                 full = 1'b1,
    output logic                 almost_full = 1'b1,

    input  logic                 rd_en,
    output logic [DataWidth-1:0] dout,
    output logic                 empty = 1'b1,
    output logic                 almost_empty = 1'b1,

    output logic [CntWidth-1:0]  data_count,
    output logic                 overflow = 1'b0,
    output logic                 underflow = 1'b0
);

  localparam CntWidthInternal = $clog2(DataDepth+1);
  localparam WrEnIdx = RegStage ? 2 : 1;
  localparam MemDataDepth = 2**CntWidthInternal;

  logic [DataWidth-1:0] memory [0:MemDataDepth-1];
  logic [DataWidth-1:0] data_out_reg;
  logic [CntWidthInternal:0] data_count_i;
  logic [CntWidthInternal:0] data_count_o;
  logic [CntWidthInternal:0] data_count_src;
  logic [CntWidthInternal:0] wr_ptr;
  logic [CntWidthInternal:0] rd_ptr;
  logic [CntWidthInternal:0] rd_ptr_d;
  logic [CntWidthInternal:0] wr_addr;
  logic [CntWidthInternal:0] rd_addr;
  logic rd_ptr_en;
  logic full_i;
  logic empty_i;
  logic almost_full_i;
  logic almost_empty_i;
  logic rd_en_i;
  logic rd_en_d;
  logic [3:0] wr_en_a;
  logic wr_en_i;
  logic pre_rd_en;
  logic mem_rd_en;
  logic mem_rd_reg_en;


  assign rd_en_i = rd_en & ~empty;
  assign wr_en_i = wr_en & ~full;

  assign mem_rd_en = rd_en_i | Fwft | RegStage;
  assign mem_rd_reg_en = Fwft ? pre_rd_en : rd_en_i;

  assign wr_addr = wr_ptr[CntWidthInternal-1:0];
  assign rd_addr = rd_ptr[CntWidthInternal-1:0];

  always @(posedge clk) begin : Write
    if (wr_en_i) begin
      memory[wr_addr] <= din;
    end
  end

  always @(posedge clk) begin : Read
    if (mem_rd_en) begin
      data_out_reg <= memory[rd_addr];
    end
  end

  generate
    if (RegStage) begin : RegLayer
      always @(posedge clk) begin
        if (mem_rd_reg_en) begin
          dout <= data_out_reg;
        end
      end
    end
    else begin : NoRegLayer
      assign dout = data_out_reg;
    end
  endgenerate

  always @(posedge clk) begin : Flags
    if (rst) begin
      overflow <= 1'b0;
      underflow <= 1'b0;
    end else begin
      if (rd_en & empty) begin
       underflow <= 1'b1;
      end
      if (wr_en & full) begin
        overflow <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin : CounterIn
    if (rst) begin
      data_count_i <= '0;
    end else begin
      if (wr_en_i & ~rd_en_i) begin
        data_count_i <= data_count_i + 1;
      end
      else if (~wr_en_i & rd_en_i) begin
        data_count_i <= data_count_i - 1;
      end
    end
  end

  always @(posedge clk) begin : CounterOut
    if (rst) begin
      data_count_o <= '0;
    end else begin
      if (wr_en_a[WrEnIdx] & ~rd_en_i) begin
        data_count_o <= data_count_o + 1;
      end
      else if (~wr_en_a[WrEnIdx] & rd_en_i) begin
        data_count_o <= data_count_o - 1;
      end
    end
  end

  always_comb begin : FullEmpty
    almost_full_i  = (data_count_i > AfullThreshold)                            ||
                     ((data_count_i == AfullThreshold) && (~rd_en_i | wr_en_i)) ||
                     ((data_count_i == AfullThreshold-1) && (wr_en_i & ~rd_en_i));

    almost_empty_i = (data_count_o < AemptyThreshold)                                     ||
                     ((data_count_o == AemptyThreshold) && (~wr_en_a[WrEnIdx] | rd_en_i)) ||
                     ((data_count_o == AemptyThreshold+1) && (~wr_en_a[WrEnIdx] & rd_en_i));

    full_i         = ((data_count_i == DataDepth) && (~rd_en_i | wr_en_i)) ||
                     ((data_count_i == DataDepth-1) && (wr_en_i & ~rd_en_i));

    empty_i        = ((data_count_o == 0) && (~wr_en_a[WrEnIdx] | rd_en_i)) ||
                     ((data_count_o == 1) && (~wr_en_a[WrEnIdx] & rd_en_i));
  end

  generate
    if (CntWidth == 0) begin : CntWidthNotUsed
      assign data_count = '0;
    end else if (CntWidth == CntWidthInternal) begin : CntWidthEqual
      assign data_count = data_count_o;
    end else if (CntWidth > CntWidthInternal) begin : CntWidthTooWide
      assign data_count = { {(CntWidth-CntWidthInternal){1'b0}}, data_count_o };
    end else begin : CntWidthTooNarrow
      assign data_count = data_count_o[CntWidth-1:0];
    end
  endgenerate

  always @(posedge clk) begin : ResetInternalSignals
    if (rst) begin
      full         <= 1'b0;
      empty        <= 1'b1;
      almost_full  <= 1'b0;
      almost_empty <= 1'b1;
      rd_ptr_d     <= '0;
      rd_en_d      <= '0;
      wr_en_a      <= '0;
    end else begin
      full         <= full_i;
      empty        <= empty_i;
      almost_full  <= almost_full_i;
      almost_empty <= almost_empty_i;
      rd_ptr_d     <= rd_ptr;
      rd_en_d      <= rd_en_i;
      wr_en_a      <= {wr_en_a, wr_en_i};
    end
  end

  always @(posedge clk) begin : WritePointer
    if (rst) begin
      wr_ptr <= 0;
    end else begin
      if (wr_en_i) begin
        if (wr_ptr == DataDepth-1) begin
          wr_ptr <= 0;
        end else begin
          wr_ptr <= wr_ptr + 1;
        end
      end
    end
  end

  assign pre_rd_en = (wr_en_a[2] & (data_count_o == 0)) |
    (rd_en_i & (data_count_o != 1 | (data_count_o == 1 & wr_en_a[WrEnIdx])));

  assign rd_ptr_en = RegStage ? (Fwft ? pre_rd_en : rd_en_i) :
                                (Fwft ? pre_rd_en | rd_en_i : rd_en_d);

  always_comb begin
    if (rd_ptr_en) begin
      if (rd_ptr_d == DataDepth-1) begin
        rd_ptr <= 0;
      end else begin
        rd_ptr <= rd_ptr_d + 1;
      end
    end else begin
      rd_ptr <= rd_ptr_d;
    end
  end

endmodule : sync_fifo
