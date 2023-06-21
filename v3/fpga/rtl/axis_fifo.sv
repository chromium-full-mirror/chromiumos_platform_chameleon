/*
 * Copyright 2023 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module axis_fifo #(
    parameter FifoDepth = 512,
    parameter PacketMode = 0, // 0 - single beat mode, 1 - packet mode
    parameter MaxPacketsInBuffer = FifoDepth,
    parameter DataCntWidth = $clog2(FifoDepth+1),
    parameter reg_handshake_pkg::reg_type_e OutputRegType = reg_handshake_pkg::kBypass
)
(
    input logic   clk,
    input logic   rst,
    axis_i.agent  axis_in,
    axis_i.host   axis_out,
    output logic  error,
    output logic [DataCntWidth-1:0] data_count = '0
);

  typedef struct packed {
      logic [axis_in.TdataWidth-1:0] tdata;
      logic [axis_in.TkeepWidth-1:0] tkeep;
      logic [axis_in.TuserWidth-1:0] tuser;
      logic                          tlast;
  } fifo_data_t;

  localparam FifoWidth = $bits(fifo_data_t);

  logic                    wr_en;
  logic                    rd_en;
  logic                    rd_en_i;
  logic                    empty;
  logic                    full;
  logic                    aempty;
  logic                    afull;
  logic                    overflow;
  logic                    underflow;
  fifo_data_t              din;
  fifo_data_t              dout;
  fifo_data_t              buf_reg;
  logic                    buf_valid;

  logic                    axis_in_tready;
  logic                    axis_in_tr;
  logic                    axis_reg_tr;
  logic [DataCntWidth-1:0] data_count_dummy;
  logic                    reg_valid;
  logic                    can_be_ready;
  logic                    place_for_tlast;
  logic                    has_tlast_valid;

  axis_i #(
      .DataWidth(axis_in.TdataWidth),
      .WordWidth(axis_in.TdataWidth/axis_in.TkeepWidth),
      .UserWidth(axis_in.TuserWidth)) i_axis_reg();

  always @(posedge clk) begin
    if (rst) begin
      error <= 1'b0;
    end else begin
      if (overflow) begin
        assert(0) $fatal(1, "axis_fifo overflow");
        error <= 1'b1;
      end
      if (underflow) begin
        assert(0) $fatal(1, "axis_fifo underflow");
        error <= 1'b1;
      end
    end
  end

  sync_fifo #(
      .DataWidth       ( FifoWidth          ),
      .DataDepth       ( FifoDepth          ),
      .CntWidth        ( DataCntWidth       ),
      .Fwft            ( 1                  ),
      .AfullThreshold  ( FifoDepth-2        ),
      .AemptyThreshold ( 2                  ),
      .RegStage        ( reg_handshake_pkg::reg_type_e'(OutputRegType ==
                                                        reg_handshake_pkg::kPayload) )
  ) fifo (
      .clk            ( clk              ),
      .rst            ( rst              ),
      .wr_en          ( wr_en            ),
      .din            ( din              ),
      .full           ( full             ),
      .almost_full    ( afull            ),
      .rd_en          ( rd_en            ),
      .dout           ( dout             ),
      .empty          ( empty            ),
      .almost_empty   ( aempty           ),
      .data_count     ( data_count_dummy ),
      .overflow       ( overflow         ),
      .underflow      ( underflow        )
  );

  assign axis_in_tr     = axis_in.tvalid && axis_in.tready;
  assign axis_reg_tr    = i_axis_reg.tvalid && i_axis_reg.tready;
  assign axis_in.tready = axis_in_tready && can_be_ready;

  always @(posedge clk) begin : Write
    if (rst) begin
      wr_en <= 1'b0;
      axis_in_tready <= 1'b0;
    end else begin
      wr_en <= 1'b0;

      if (!full & !wr_en) begin
        axis_in_tready <= 1'b1;
      end

      if (axis_in.tvalid && axis_in.tready) begin
        wr_en <= 1'b1;
        if (!afull) begin
          axis_in_tready <= 1'b1;
        end
        else begin
          axis_in_tready <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk) begin : Read
    if (rst) begin
      i_axis_reg.tvalid <= 1'b0;
      buf_valid <= 1'b0;
      rd_en_i <= 1'b0;
    end else begin

      if (i_axis_reg.tready) begin
        i_axis_reg.tvalid <= 1'b0;
      end

      if (~buf_valid | i_axis_reg.tready) begin
        rd_en_i <= 1'b1;
      end

      if (rd_en) begin
        buf_valid <= 1'b1;
      end

      if (reg_valid) begin
        i_axis_reg.tvalid <= 1'b1;
        if (~buf_valid | ~rd_en) begin
          buf_valid <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk) begin : DataPass
    if (axis_in.tvalid && axis_in.tready) begin
      din.tdata <= axis_in.tdata;
      din.tkeep <= axis_in.tkeep;
      din.tuser <= axis_in.tuser;
      din.tlast <= axis_in.tlast;
    end

    if (rd_en) begin
      buf_reg <= dout;
    end

    if ((~empty | buf_valid) & (~i_axis_reg.tvalid | i_axis_reg.tready)) begin
      if (buf_valid) begin
        i_axis_reg.tdata <= buf_reg.tdata;
        i_axis_reg.tkeep <= buf_reg.tkeep;
        i_axis_reg.tuser <= buf_reg.tuser;
        i_axis_reg.tlast <= buf_reg.tlast;
      end else begin
        i_axis_reg.tdata <= dout.tdata;
        i_axis_reg.tkeep <= dout.tkeep;
        i_axis_reg.tuser <= dout.tuser;
        i_axis_reg.tlast <= dout.tlast;
      end
    end
  end

  always @(posedge clk) begin : DataCounter
    if (rst) begin
      data_count <= '0;
    end else begin
      if (axis_in_tr & ~axis_reg_tr) begin
        data_count <= data_count+1;
      end else if (~axis_in_tr & axis_reg_tr) begin
        data_count <= data_count-1;
      end
    end
  end

  generate
    if(PacketMode) begin
      localparam int IMaxPacketsInBuffer = (MaxPacketsInBuffer > FifoDepth) ? FifoDepth :
                                            MaxPacketsInBuffer;
      localparam int TlastCnt = $clog2(IMaxPacketsInBuffer+1);
      localparam int Latency = 1 + ((OutputRegType == reg_handshake_pkg::kPayload ||
                                    OutputRegType == reg_handshake_pkg::kPayloadCtrl) ? 1 : 0);

      logic [TlastCnt-1:0] tlasts_in_fifo;
      logic                has_tlast;
      logic                has_more_tlast;
      logic                axis_reg_tlast_tr;
      logic [Latency:0]    axis_in_tlast_tr;

      assign axis_reg_tlast_tr = axis_reg_tr && i_axis_reg.tlast;

      always @(posedge clk) begin : ShiftTlastReg
        axis_in_tlast_tr <= {axis_in_tlast_tr, (axis_in_tr & axis_in.tlast)};
      end

      always @(posedge clk) begin
        if (rst) begin
          tlasts_in_fifo <= '0;
        end else begin
          if (axis_in_tlast_tr[Latency] & ~axis_reg_tlast_tr) begin
            tlasts_in_fifo <= tlasts_in_fifo+1;
          end else if (~axis_in_tlast_tr[Latency] & axis_reg_tlast_tr) begin
            tlasts_in_fifo <= tlasts_in_fifo-1;
          end
        end
      end

      assign has_tlast = |tlasts_in_fifo;
      assign has_more_tlast = tlasts_in_fifo > 1;
      assign has_tlast_valid = ~axis_reg_tlast_tr & has_tlast | has_more_tlast;
      assign place_for_tlast = ((tlasts_in_fifo < IMaxPacketsInBuffer-Latency) ||
                                (tlasts_in_fifo < IMaxPacketsInBuffer &&
                                 !(|axis_in_tlast_tr[Latency:1])));
    end else begin
      assign place_for_tlast = 1'b1;
      assign has_tlast_valid = 1'b1;
    end

  endgenerate

  assign rd_en = rd_en_i && !empty && has_tlast_valid &&
                 !(i_axis_reg.tvalid && !i_axis_reg.tready && buf_valid);
  assign reg_valid = (!empty || buf_valid) && has_tlast_valid &&
                     (!i_axis_reg.tvalid || i_axis_reg.tready);
  assign can_be_ready = place_for_tlast;

  axis_reg_handshake #(
      .RegType  ( OutputRegType == reg_handshake_pkg::kPayloadCtrl ?
                                   reg_handshake_pkg::kPayloadCtrl :
                                   reg_handshake_pkg::kBypass)
  ) u_axis_reg_handshake (
      .clk      ( clk             ),
      .rst      ( rst             ),
      .axis_in  ( i_axis_reg      ),
      .axis_out ( axis_out        )
  );

endmodule : axis_fifo
