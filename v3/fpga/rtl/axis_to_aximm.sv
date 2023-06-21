
/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module to convert AXI4Stream buses to AXI4 (Memory Mapped).
 *
 * Module assumes that address to write resides on i_write.tuser.addr
 * and data size (in bytes) comes on i_write.tuser.data_size.
 *
 * i_write.tuser data needs to be valid in first beat of packet.
 */
module axis_to_aximm #(
    parameter int Id          = 0,
    parameter int DataWidth   = 128
) (
    input  logic    clk,
    input  logic    rst,

    axis_i.agent    i_write,
    output logic    write_done,
    axis_i.agent    i_read_rq,
    axis_i.host     i_read_resp,

    aximm_i.manager  i_mm
);

  /* Imports and local parameters */
  import axis_to_aximm_pkg::Value4k;
  import axis_to_aximm_pkg::Boundary4kWidth;
  import axis_to_aximm_pkg::AddrWidth;
  import axis_to_aximm_pkg::meta_t;
  localparam int AxiMmLenWidth = i_mm.LenWidth;
  localparam int AxiReadRespKeepWidth = $bits(i_read_resp.tkeep);
  localparam int DataSizeWidth = axis_to_aximm_pkg::DataWidth;

  /* Helper signals */
  logic w_transaction_in_progress;
  logic w_transaction_in_progress_reg;
  logic ar_split_transaction;
  logic ar_split_transaction_reg;
  logic write_tfirst;
  meta_t ar_second;
  meta_t ar_second_reg;

  axis_tfirst u_tfirst(clk, rst, i_write.tvalid, i_write.tready, i_write.tlast, write_tfirst);

  /* Assertions for module assumptions */
  assert property (@(posedge clk) disable iff (rst !== '0)
    (i_write.tvalid && i_write.tready && write_tfirst) |-> (i_write.tuser.addr % 4 == 0))
  else begin
    $fatal(1, "Input write addr shall be aligned to 32bits");
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (i_write.tvalid && i_write.tready && write_tfirst) |-> (i_write.tuser.data_size <= Value4k))
  else begin
    $fatal(1, "On write interface transaction bigger than 4K boundary is not supported");
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (i_write.tvalid && i_write.tready && write_tfirst) |->
      (i_write.tuser.addr[Boundary4kWidth-1:0] +
        i_write.tuser.data_size[Boundary4kWidth-1:0] <= Value4k))
  else begin
    $fatal(1, {"On write interface transaction overlapping 4K boundary is not supported.",
               "Add support for it in case of performance issues"});
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (i_read_rq.tvalid && i_read_rq.tready) |-> (i_read_rq.tuser.addr % 4 == 0))
  else begin
    $fatal(1, "Input read addr shall be aligned to 32bits");
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (i_read_rq.tvalid && i_read_rq.tready) |-> (i_read_rq.tuser.data_size <= Value4k))
  else begin
    $fatal(1, "On read interface transaction bigger than 4K boundary is not supported");
  end

  assert property (@(posedge clk) disable iff (rst !== '0)
    (DataWidth % 8 == 0))
  else begin
    $fatal(1, "DataWidth has to be multiples of 8");
  end

  /* Helper functions */
  function automatic logic[AddrWidth-1:0] mask_addr(int mask_size);
    for (int i=0; i < AddrWidth; i++) begin
      mask_addr[i] = i < mask_size ? 1'b0 : 1'b1;
    end
  endfunction : mask_addr

  function automatic logic[AxiMmLenWidth-1:0] get_axlen(logic [DataSizeWidth-1:0] data_size,
                                                        int DataWidth);
    const int BytesInBeat = DataWidth/8;
    get_axlen = data_size/BytesInBeat - 1 + ((data_size % BytesInBeat) != 0);
  endfunction : get_axlen

  /* Handle W transaction */
  always_comb begin : w_transaction
    w_transaction_in_progress = w_transaction_in_progress_reg;
    if (i_write.tvalid && i_write.tready) begin
      if (i_write.tlast) begin
        w_transaction_in_progress = 1'b0;
      end else begin
        w_transaction_in_progress = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin : w_transaction_ff
    if (rst) begin
      w_transaction_in_progress_reg <= 1'b0;
    end else begin
      w_transaction_in_progress_reg <= w_transaction_in_progress;
    end
  end

  /* AW, W and B interface parts assignment */
  always_comb begin : i_write_transaction
    i_write.tready  = (i_mm.awready && i_mm.wready) ||
                      (w_transaction_in_progress_reg && i_mm.wready);
    i_mm.awvalid    = i_write.tvalid && write_tfirst && i_mm.wready;
    i_mm.awid       = Id;
    i_mm.awaddr     = i_write.tuser.addr;
    i_mm.awlen      = get_axlen(i_write.tuser.data_size, DataWidth);
    i_mm.awburst    = gaxim_pkg::kIncr;
    i_mm.awsize     = gaxim_pkg::kBytes16;
    i_mm.awprot     = '0;
    i_mm.awlock     = '0;
    i_mm.awcache    = '0;
    i_mm.awregion   = '0;

    i_mm.wvalid     = i_write.tvalid && (i_mm.awready || w_transaction_in_progress_reg);
    i_mm.wdata      = i_write.tdata;
    i_mm.wstrb      = i_write.tkeep;
    i_mm.wlast      = i_write.tlast;

    i_mm.bready     = 1'b1;
    write_done      = i_mm.bvalid;
  end

  /* Request must not overlap boundary 4K. Ensure this by splitting transaction in such cases */
  always_comb begin : split_ar_transaction
    ar_second.addr       = ar_second_reg.addr;
    ar_second.data_size  = ar_second_reg.data_size;
    ar_split_transaction = ar_split_transaction_reg;
    if (i_read_rq.tvalid && i_read_rq.tready) begin
      if ((i_read_rq.tuser.addr[Boundary4kWidth-1:0] +
           i_read_rq.tuser.data_size[Boundary4kWidth-1:0]) > Value4k) begin
        ar_second.addr       = i_read_rq.tuser.addr & mask_addr(Boundary4kWidth);
        ar_second.data_size  = i_read_rq.tuser.data_size -
                              (Value4k - i_read_rq.tuser.addr[Boundary4kWidth-1:0]);
        ar_split_transaction = 1'b1;
      end
    end

    if (i_mm.arvalid && i_mm.arready && ar_split_transaction_reg) begin
      ar_split_transaction = 1'b0;
    end

  end

  always_ff @(posedge clk) begin : split_ar_transaction_ff
    if (rst) begin
      ar_split_transaction_reg <= 1'b0;
      ar_second_reg        <= '0;
    end else begin
      ar_split_transaction_reg <= ar_split_transaction;
      ar_second_reg.addr       <= ar_second.addr;
      ar_second_reg.data_size  <= ar_second.data_size;
    end
  end

  /* AR transaction assignments */
  always_comb begin : i_read_rq_transaction
    i_read_rq.tready = i_mm.arready && !ar_split_transaction_reg;

    i_mm.arvalid     = i_read_rq.tvalid || ar_split_transaction_reg;
    i_mm.arid        = Id;

    if ((i_read_rq.tuser.addr[Boundary4kWidth-1:0] +
         i_read_rq.tuser.data_size[Boundary4kWidth-1:0] > Value4k) ||
         ar_split_transaction_reg) begin
      if (ar_split_transaction_reg) begin
        i_mm.araddr  = ar_second_reg.addr;
        i_mm.arlen   = get_axlen(ar_second_reg.data_size, DataWidth);
      end else begin
        i_mm.araddr  = i_read_rq.tuser.addr;
        i_mm.arlen   = get_axlen((Value4k - i_read_rq.tuser.addr[Boundary4kWidth-1:0]), DataWidth);
      end
    end else begin
      i_mm.araddr    = i_read_rq.tuser.addr;
      i_mm.arlen     = get_axlen(i_read_rq.tuser.data_size, DataWidth);
    end

    i_mm.arburst     = gaxim_pkg::kIncr;
    i_mm.arsize      = gaxim_pkg::kBytes16;
    i_mm.arprot      = '0;
    i_mm.arlock      = '0;
    i_mm.arcache     = '0;
    i_mm.arregion    = '0;
  end

  /* R transaction assignments */
  always_comb begin : i_read_resp_transaction
    i_mm.rready         = i_read_resp.tready;
    i_read_resp.tvalid  = i_mm.rvalid;
    i_read_resp.tdata   = i_mm.rdata;
    i_read_resp.tuser   = '0;
    i_read_resp.tkeep   = '{AxiReadRespKeepWidth{'b1}};
    i_read_resp.tlast   = i_mm.rlast;
  end

endmodule : axis_to_aximm
