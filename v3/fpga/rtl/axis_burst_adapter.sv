/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module aggregates numerous of AXIS single transaction (one beat) and produce single AXIS burst
 *
 * max_burst_size - desired maximal burst size (e.g. from register)
 */

module axis_burst_adapter #(
    parameter int BurstLenWidth = 6
)(
    input  logic                     clk,
    input  logic                     reset,
    input  logic [BurstLenWidth-1:0] max_burst_size,
    output logic                     overflow,
    output logic [1:0]               eof_hit,
    axis_i.agent                     i_axis_in,
    axis_i.host                      i_axis_out
);

import framebuffer_pkg::fb_dma_meta_t;

localparam int DataWidth = i_axis_in.TdataWidth;
localparam int Boundary4k = axis_to_aximm_pkg::Value4k;
localparam int BeatBytes = DataWidth / 8;
localparam int AddrWidth = axis_to_aximm_pkg::AddrWidth;

axis_i #(.DataWidth(DataWidth), .WordWidth(8), .Tuser(fb_dma_meta_t)) i_axis_in_ex();
axis_i #(.DataWidth(DataWidth), .WordWidth(8), .Tuser(fb_dma_meta_t)) i_fifo_in();
axis_i #(.DataWidth(DataWidth), .WordWidth(8), .Tuser(fb_dma_meta_t)) i_axis_in_reg();
axis_i #(.DataWidth(DataWidth), .WordWidth(8), .Tuser(fb_dma_meta_t)) i_fifo_out();

logic [BurstLenWidth-1:0] burst_size;
logic [BurstLenWidth-1:0] beat_cnt;
logic [AddrWidth-1:0]     prev_addr;
logic                     burts_overflow;
logic                     burts_size_overflow;

logic fifo_burst_size_wr;
logic fifo_burst_size_rd;

logic axis_in_tr;
logic fifo_tr;

logic addr_not_consistent;
logic burst_size_hit;
logic boundary4K_hit ;
logic burst_tlast;

assign overflow = burts_overflow | burts_size_overflow;

assign fifo_burst_size_wr = i_fifo_in.tlast & i_fifo_in.tvalid & i_fifo_in.tready;
assign fifo_burst_size_rd = i_fifo_out.tlast & i_fifo_out.tvalid & i_fifo_out.tready;

// extend eof transation to two transactions (we need this to flush u_buffer)
logic       ext_eof_valid;
logic       ext_eof_valid_d;
logic [1:0] ext_eof_d;
always_comb begin
  i_axis_in_ex.tvalid = i_axis_in.tvalid || ext_eof_valid_d;
  i_axis_in_ex.tdata  = i_axis_in.tdata;
  i_axis_in_ex.tkeep  = i_axis_in.tkeep;
  i_axis_in_ex.tlast  = i_axis_in.tlast;
  i_axis_in_ex.tuser  = i_axis_in.tuser;
  i_axis_in.tready    = i_axis_in_ex.tready && !ext_eof_valid_d;
  if (ext_eof_valid_d) begin
    i_axis_in_ex.tuser.eof = ext_eof_d;
  end
end

assign ext_eof_valid = i_axis_in.tvalid && i_axis_in.tuser.eof;

always_ff @(posedge clk) begin
  if (reset) begin
    ext_eof_valid_d <= '0;
    ext_eof_d <= '0;
  end else begin
    ext_eof_valid_d <= ext_eof_valid;
    ext_eof_d <= i_axis_in.tuser.eof;
  end
end


/*
 * fifo for burst length value
 */
sync_fifo #(
    .DataWidth ( BurstLenWidth ),
    .DataDepth ( 2 ** (BurstLenWidth+1)/8),
    .RegStage  ( reg_handshake_pkg::kBypass ),
    .Fwft      ( 1             )
) u_burst_size_fifo (
    .clk          ( clk                 ),
    .rst          ( reset               ),
    .wr_en        ( fifo_burst_size_wr  ),
    .din          ( beat_cnt            ),
    .full         (                     ),
    .almost_full  (                     ),
    .rd_en        ( fifo_burst_size_rd  ),
    .dout         ( burst_size          ),
    .empty        (                     ),
    .almost_empty (                     ),
    .data_count   (                     ),
    .overflow     ( burts_size_overflow ),
    .underflow    (                     )
);

// axis bus transactions
assign axis_in_tr = i_axis_in_ex.tvalid && i_axis_in_ex.tready;
assign fifo_tr = i_fifo_in.tready && i_fifo_in.tvalid;

// store address for consistent check
always_ff @(posedge clk) begin
  if (reset) begin
    prev_addr <= '0;
  end else if (axis_in_tr) begin
    prev_addr <= i_axis_in_ex.tuser.addr;
  end
end

// count burst length
always_ff @(posedge clk) begin
  if (reset) begin
    beat_cnt <= 'd1;
  end else if (fifo_tr) begin
    beat_cnt <= beat_cnt + 1;
    if (i_fifo_in.tlast) beat_cnt <= 'd1;
  end
end

assign addr_not_consistent = (i_axis_in_ex.tuser.addr != (prev_addr + BeatBytes));
assign burst_size_hit = (beat_cnt >= max_burst_size);
assign boundary4K_hit = (((i_axis_in_reg.tuser.addr + BeatBytes) % Boundary4k) == 0);
assign burst_tlast = (addr_not_consistent || burst_size_hit || boundary4K_hit ||
                      i_axis_in_ex.tuser.eof || i_axis_in_reg.tuser.eof);

// delay input transaction with one clock cycle
// we need to have time to react for lack of address consistent
axis_reg_handshake #(
    .RegType  ( reg_handshake_pkg::kPayload )
) u_buffer (
    .clk      ( clk           ),
    .rst      ( reset         ),
    .axis_in  ( i_axis_in_ex  ),
    .axis_out ( i_axis_in_reg )
);

// we need fillup pipeline with data so mask first transaction
// data will be stuffed out with next transaction
logic mask_first;
always_ff @(posedge clk) begin
  if (reset) mask_first <= 0;
  else if (i_axis_in_ex.tvalid) mask_first <= 1;
end

always_comb begin
  i_fifo_in.tlast  = burst_tlast; // bursts-end condition hit
  i_fifo_in.tvalid = i_axis_in_ex.tvalid & mask_first;
  i_fifo_in.tdata  = i_axis_in_reg.tdata;
  i_fifo_in.tkeep  = i_axis_in_reg.tkeep;
  i_fifo_in.tuser  = i_axis_in_reg.tuser;
  i_axis_in_reg.tready = i_fifo_in.tready;
end

/**
 * fifo for aggregated burst
 * in packet mode fifo asserts transaction at axis_out only if completed trasaction (with tlast)
 * was introduced at axis_in
 * This module pull down tlast at fifos axis_in for all beats except when:
 *  - beat address is not consistent with previous one
 *  - burst reach requested size
 *  - burst reach 4K boundary
 */
axis_fifo #(
  .FifoDepth      ( 2 ** (BurstLenWidth+1) ), // fifo for two max size bursts
  .PacketMode     ( 1                      ),
  .OutputRegType  ( reg_handshake_pkg::kBypass )
) u_burst_fifo (
  .clk        ( clk            ),
  .rst        ( reset          ),
  .axis_in    ( i_fifo_in      ),
  .axis_out   ( i_fifo_out     ),
  .error      ( burts_overflow ),
  .data_count (                )
);

always_comb begin
  i_axis_out.tvalid          = i_fifo_out.tvalid && !i_fifo_out.tuser.eof;
  i_axis_out.tdata           = i_fifo_out.tdata;
  i_axis_out.tkeep           = i_fifo_out.tkeep;
  i_axis_out.tlast           = i_fifo_out.tlast;
  i_axis_out.tuser.addr      = i_fifo_out.tuser.addr;
  i_axis_out.tuser.data_size = burst_size * BeatBytes;
  i_fifo_out.tready          = i_axis_out.tready;
end

logic       fifo_out_tr;
logic [1:0] fifo_out_user_eof;
always_ff @(posedge clk) begin
  fifo_out_tr <= i_fifo_out.tready && i_fifo_out.tvalid;
  fifo_out_user_eof <= i_fifo_out.tuser.eof;
end

// we need only one eof_hit at rising edge of tuser.eof
assign eof_hit = (i_fifo_out.tuser.eof & ~fifo_out_user_eof) & {2{(fifo_out_tr)}};


endmodule : axis_burst_adapter
