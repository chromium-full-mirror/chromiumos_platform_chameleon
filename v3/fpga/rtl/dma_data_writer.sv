/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module dma_data_writer #(
    parameter  reg_handshake_pkg::reg_type_e OutputRegType = reg_handshake_pkg::kPayloadCtrl,
    parameter  int MaxRingBytes            = 1024,
    parameter  int AddressWidth            = 32,
    localparam int RingAddrAlignment       = axis_to_aximm_pkg::Value4k,
    localparam int MaxRingBytesWidth       = $clog2(MaxRingBytes),
    localparam int RingAddrAlignmentWidth  = $clog2(RingAddrAlignment)
) (
    input logic                          clk,
    input logic                          rst,

    axis_i.agent                         i_data_in,
    axis_i.host                          i_data_out,
    input logic                          write_done,

    input  logic                         ring_enable,
    input  logic [MaxRingBytesWidth-1:0] ring_size,
    input  logic [AddressWidth-1:0]      ring_address,
    input  logic [MaxRingBytesWidth-1:0] ring_cons_idx,
    output logic [MaxRingBytesWidth-1:0] ring_prod_idx,
    input  logic                         ring_prod_idx_rst,
    output logic                         ring_prod_idx_change
);

  localparam int DataWidthIn  = i_data_in.TdataWidth;
  localparam int DataWidthOut = i_data_out.TdataWidth;
  localparam int KeepWidthOut = i_data_out.TkeepWidth;
  localparam int UserWidthOut = i_data_out.TuserWidth;
  localparam int DataWidth = DataWidthOut;
  localparam int DataWidthBytes = DataWidth/8;

  function automatic logic[AddressWidth-1:0] mask_addr(integer mask_size);
    for (int i=0; i < AddressWidth; i++) begin
      mask_addr[i] = i < mask_size ? 1'b0 : 1'b1;
    end
  endfunction : mask_addr

  logic [MaxRingBytesWidth-1:0] ring_prod_idx_internal;
  logic [AddressWidth-1:0] ring_address_align;
  logic [MaxRingBytesWidth-1:0] space_in_ring;
  logic fit_in_ring;
  logic data_in_tfirst;
  logic drop_condition;
  logic drop_condition_q;
  logic drop;

  axis_i #(.DataWidth(DataWidthOut), .KeepWidth(KeepWidthOut),
           .UserWidth(UserWidthOut)) i_data_d();

  // Assertions for module assumptions
  assert property (@(posedge clk) disable iff (rst !== '0)
    (DataWidthIn == DataWidthOut))
  else begin
    $fatal(1, "Input(%0d) and output(%0d) data width should be the same",
           DataWidthIn, DataWidthOut);
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (2**$clog2(DataWidthBytes) == DataWidthBytes))
  else begin
    $fatal(1, "Data width bytes(%0d) should be power of 2", DataWidth);
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (UserWidthOut == AddressWidth))
  else begin
    $fatal(1, {"Output user width should be equal to address width(%0d).",
               "Data width bytes(%0d) should be power of 2"},
           UserWidthOut, AddressWidth);
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (UserWidthOut == AddressWidth))
  else begin
    $fatal(1, {"Output user width should be equal to address width(%0d).",
               "Data width bytes(%0d) should be power of 2"},
           UserWidthOut, AddressWidth);
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    ring_enable |-> (ring_address_align == ring_address))
  else begin
    $fatal(1, "(%0d lower address(%h) bits should be zero",
           RingAddrAlignmentWidth, ring_address);
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    ring_enable |-> (ring_size !== '0 && ((ring_size & (ring_size - 1)) === '0)))
  else begin
    $fatal(1, "Ring size (0x%0h) must be a power of two", ring_size);
  end

  axis_tfirst u_tfirst(clk, rst, i_data_in.tvalid, i_data_in.tready,
                       i_data_in.tlast, data_in_tfirst);

  always_comb begin
    space_in_ring = (ring_cons_idx - ring_prod_idx_internal - 1) & (ring_size - 1);
    fit_in_ring = space_in_ring >= DataWidthBytes;
  end

  always_ff @(posedge clk) begin
    if (rst || ring_prod_idx_rst) begin
      ring_prod_idx <= '0;
    end else begin
      if (write_done) begin
        ring_prod_idx <= (ring_prod_idx + DataWidthBytes) & (ring_size - 1);
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst || ring_prod_idx_rst) begin
      ring_prod_idx_internal <= '0;
    end else begin
      if (i_data_d.tvalid && i_data_d.tready) begin
        ring_prod_idx_internal <= (ring_prod_idx_internal + DataWidthBytes) & (ring_size - 1);
      end
    end
  end

  // Set pulse on ring_prod_idx_change when ring_prod_idx changes.
  always_ff @(posedge clk) begin
    if (rst || ring_prod_idx_rst) begin
      ring_prod_idx_change <= 1'b0;
    end else begin
      ring_prod_idx_change <= (i_data_d.tvalid && i_data_d.tready);
    end
  end

  always_comb begin
    drop_condition = drop_condition_q;
    if (!ring_enable) begin
      drop_condition = 1'b1;
    end else if ((i_data_in.tvalid && i_data_in.tready && i_data_in.tlast) || data_in_tfirst) begin
      drop_condition = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      drop_condition_q <= 1'b0;
    end else begin
      drop_condition_q <= drop_condition;
    end
  end

  assign drop = !ring_enable || drop_condition_q;
  assign ring_address_align = ring_address & mask_addr(RingAddrAlignmentWidth);

  always_comb begin
    i_data_in.tready = i_data_d.tready  && fit_in_ring || drop;
    i_data_d.tvalid  = i_data_in.tvalid && fit_in_ring && !drop;
    i_data_d.tdata   = i_data_in.tdata;
    i_data_d.tkeep   = '1;
    i_data_d.tuser   = ring_address_align + ring_prod_idx_internal;
    i_data_d.tlast   = i_data_in.tlast;
  end

  axis_reg_handshake #(
    .RegType ( OutputRegType )
  )
  u_axis_reg_handshake_out (
    .clk     ( clk           ),
    .rst     ( rst           ),
    .axis_in ( i_data_d      ),
    .axis_out( i_data_out    )
  );

endmodule : dma_data_writer
