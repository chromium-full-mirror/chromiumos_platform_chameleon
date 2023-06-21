/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module dma_data_reader #(
    parameter  reg_handshake_pkg::reg_type_e OutputRegType = reg_handshake_pkg::kBypass,
    parameter  int MaxRingBytes            = 32'h0020_0000,
    parameter  int AddressWidth            = axis_to_aximm_pkg::AddrWidth,
    parameter  int BytesToFetch            = 64,
    parameter  int FifoDepth               = 64,
    parameter  int RespDataWidth           = 128,
    localparam int MaxRingBytesWidth       = $clog2(MaxRingBytes+1)
) (
    input logic                          clk,
    input logic                          rst,

    axis_i.host                          i_read_rq,
    axis_i.agent                         i_read_resp_ap,
    axis_i.host                          i_read_resp,

    input  logic                         ring_enable,
    input  logic [MaxRingBytesWidth-1:0] ring_size,
    input  logic [AddressWidth-1:0]      ring_address,
    input  logic [MaxRingBytesWidth-1:0] ring_prod_idx,
    output logic [MaxRingBytesWidth-1:0] ring_cons_idx,
    input  logic                         ring_cons_idx_rst,
    output logic                         ring_cons_idx_change
);

  localparam int QueueId = 0;

  localparam int BytesToFetchWidth = $clog2(BytesToFetch);
  localparam bit[MaxRingBytesWidth-1:0] BytesToFetchMask = {{(MaxRingBytesWidth-1){1'b1}},
                                                            {BytesToFetchWidth{1'b0}}};

  typedef enum bit [1:0] {
      kDataFit       = 2'b00,
      kDataNotFit    = 2'b01,
      kDataFitModulo = 2'b10
  } idx_wr_t;

  // Assertions
  assert property (@(posedge clk) disable iff (rst !== '0)
    (i_axis_ring_request.tvalid && i_axis_ring_request.tready) |->
    (i_axis_ring_request.tdata.data_size < 2**axis_to_aximm_pkg::DataWidth))
  else begin
    $fatal(1, "Ring request cannot exceed maximum supported data size");
  end

  // Interfaces and signals definition
  axis_i #(.Tdata(axis_to_aximm_pkg::meta_t), .KeepWidth(1)) i_axis_ring_request();
  axis_i #(.Tdata(axis_to_aximm_pkg::meta_t), .KeepWidth(1)) i_axis_ring_request_out();
  axis_i #(.DataWidth(1), .WordWidth(1),
           .Tuser(axis_to_aximm_pkg::meta_t))  i_read_rq_reg();

  logic fifo_error;
  logic [$clog2(FifoDepth+1)-1:0] fifo_data_count;
  logic [$clog2(FifoDepth*RespDataWidth/8+1)-1:0] in_flight_requested_data;
  logic space_in_fifo;
  logic fetch_idx_valid;
  logic [MaxRingBytesWidth-1:0] fetch_idx_wr;
  logic [MaxRingBytesWidth-1:0] fetch_idx_wr_r;
  logic [MaxRingBytesWidth-1:0] fetch_idx_rd;
  logic [MaxRingBytesWidth:0]   fetched_idx_sum;
  idx_wr_t idx_wr;

  always_ff @(posedge clk) begin : ring_cons
    if (rst) begin
      ring_cons_idx <= '0;
    end else begin
      if (i_read_resp_ap.tvalid && i_read_resp_ap.tready && i_read_resp_ap.tlast) begin
        ring_cons_idx <= (ring_cons_idx + BytesToFetch) & (ring_size - 1);
      end
    end
  end

  always_ff @(posedge clk) begin : ring_cons_change
    if (rst) begin
      ring_cons_idx_change <= '0;
    end else begin
      ring_cons_idx_change <= i_read_resp_ap.tvalid && i_read_resp_ap.tready && i_read_resp_ap.tlast;
    end
  end

  // FIFO to keep incoming responses (to not request more than we do have space for)
  axis_fifo #(
      .FifoDepth    ( FifoDepth           ),
      .DataCntWidth ( $clog2(FifoDepth+1) ),
      .OutputRegType( reg_handshake_pkg::kBypass )
  ) u_data_reader_fifo (
      .clk        ( clk               ),
      .rst        ( rst               ),
      .axis_in    ( i_read_resp_ap    ),
      .axis_out   ( i_read_resp       ),
      .error      ( fifo_error        ),
      .data_count ( fifo_data_count   )
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      in_flight_requested_data <= '0;
    end else begin
      if (i_read_rq.tvalid && i_read_rq.tready) begin
        in_flight_requested_data <= in_flight_requested_data + i_read_rq.tuser.data_size;
      end
      if (i_read_resp_ap.tvalid && i_read_resp_ap.tready) begin
        in_flight_requested_data <= in_flight_requested_data - RespDataWidth/8;
      end
      if (i_read_rq.tvalid && i_read_rq.tready &&
          i_read_resp_ap.tvalid && i_read_resp_ap.tready) begin
        in_flight_requested_data <= in_flight_requested_data +
                                    i_read_rq.tuser.data_size -
                                    RespDataWidth/8;
      end
    end
  end

  // Calculate if we do have enough space for next request
  assign space_in_fifo = (FifoDepth*RespDataWidth/8 -
                         (fifo_data_count*RespDataWidth/8 + in_flight_requested_data)) >
                         BytesToFetch;

  // Ring handling
  always @(posedge clk) begin : FetchIdxWr
    if (rst) begin
      fetch_idx_wr_r <= '0;
    end else begin
      if (fetch_idx_valid) begin
        fetch_idx_wr_r <= fetch_idx_wr;
      end
    end
  end

  always_comb begin : RingRequest
    if (fetch_idx_valid) begin
      fetch_idx_rd = fetch_idx_wr;
    end else begin
      fetch_idx_rd = fetch_idx_wr_r;
    end

    i_axis_ring_request.tvalid = 1'b0;
    if (ring_enable && (fetch_idx_rd[MaxRingBytesWidth-1:BytesToFetchWidth] !=
                        ring_prod_idx[MaxRingBytesWidth-1:BytesToFetchWidth])) begin
      i_axis_ring_request.tvalid = 1'b1;
    end

    i_axis_ring_request.tdata.data_size = BytesToFetch;
    i_axis_ring_request.tdata.addr = ring_address + fetch_idx_rd;
    i_axis_ring_request.tlast = '1;
    i_axis_ring_request.tkeep = '0;
    i_axis_ring_request.tuser = '0;
  end

  assign fetched_idx_sum = BytesToFetch + (fetch_idx_rd&BytesToFetchMask);
  always @(posedge clk) begin
    fetch_idx_valid <= i_axis_ring_request.tvalid && i_axis_ring_request.tready;
    case (idx_wr)
      kDataFit:       fetch_idx_wr <= fetched_idx_sum;
      kDataNotFit:    fetch_idx_wr <= (ring_prod_idx&BytesToFetchMask);
      kDataFitModulo: fetch_idx_wr <= fetched_idx_sum - ring_size;
    endcase
  end

  always_comb begin
    if (fetch_idx_rd <= ring_prod_idx) begin
      if (BytesToFetch <= ((ring_prod_idx&BytesToFetchMask) - (fetch_idx_rd&BytesToFetchMask))) begin
        idx_wr = kDataFit;
      end else begin
        idx_wr = kDataNotFit;
      end
    end else begin
      if (BytesToFetch <= ring_size - (fetch_idx_rd&BytesToFetchMask) + (ring_prod_idx&BytesToFetchMask)) begin
        if (fetched_idx_sum < ring_size) begin
          idx_wr = kDataFit;
        end else begin
          idx_wr = kDataFitModulo;
        end
      end else begin
        idx_wr = kDataNotFit;
      end
    end
  end

  axis_reg_handshake #(
      .RegType        ( reg_handshake_pkg::kPayloadCtrl )
  ) u_axis_ring_request_reg (
      .clk            ( clk                     ),
      .rst            ( rst                     ),
      .axis_in        ( i_axis_ring_request     ),
      .axis_out       ( i_axis_ring_request_out )
  );

  always_comb begin
    i_read_rq_reg.tvalid            = i_axis_ring_request_out.tvalid && space_in_fifo;
    i_axis_ring_request_out.tready  = i_read_rq_reg.tready && space_in_fifo;
    i_read_rq_reg.tdata             = '0;
    i_read_rq_reg.tuser.addr        = i_axis_ring_request_out.tdata.addr;
    i_read_rq_reg.tuser.data_size   = i_axis_ring_request_out.tdata.data_size;
    i_read_rq_reg.tkeep             = 1'b1;
    i_read_rq_reg.tlast             = 1'b1;
  end

  axis_reg_handshake #(
      .RegType        ( OutputRegType )
  ) u_read_rq_reg (
      .clk            ( clk           ),
      .rst            ( rst           ),
      .axis_in        ( i_read_rq_reg ),
      .axis_out       ( i_read_rq     )
  );

endmodule : dma_data_reader
