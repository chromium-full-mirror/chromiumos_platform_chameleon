/*
 * Copyright 2023 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module axi_lite_manager #(
    parameter reg_handshake_pkg::reg_type_e RegType = reg_handshake_pkg::kPayloadCtrl,
    parameter int RrespDelay                        = 2,  // clock cycles
    parameter int RrespFifoDepth                    = 8
) (
    input logic                         clk,
    input logic                         rst,

    axil_i.subordinate                  axi,

    output logic [axi.TaddrWidth-1:0]   addr,
    output logic                        wr_en,
    output logic [axi.TdataWidth-1:0]   wr_data,
    input  gaxilite_pkg::resp_t         wr_resp,
    output logic                        rd_resp_en,
    output logic [axi.TaddrWidth-1:0]   rd_resp_addr,
    input  logic [axi.TdataWidth-1:0]   rd_resp_data,
    input  gaxilite_pkg::resp_t         rd_resp
);

  localparam int AxilDataWidth = axi.TdataWidth;
  localparam int AxilAddrWidth = axi.TaddrWidth;
  localparam int AxilStrbWidth = AxilDataWidth/8;
  localparam int RrespFifoThreshold = RrespFifoDepth-RrespDelay-2;

  typedef struct packed {
    logic [AxilDataWidth-1:0] wdata;
    logic [AxilStrbWidth-1:0] wstrb;
  } w_t;

  logic                     waddr_valid;
  logic [AxilAddrWidth-1:0] waddr;

  logic                     wdata_valid;
  w_t                       w_in;
  w_t                       w_out;

  logic                     write_valid;
  logic                     write_ready;

  logic                     wresp_valid;
  logic                     wresp_ready;

  logic [1:0]               axi_bresp;

  logic                     read_valid;
  logic                     read_ready;
  logic                     raddr_valid;
  logic [AxilAddrWidth-1:0] raddr;

  logic                     rresp_valid;
  logic                     rresp_ready;
  logic                     rresp_almostfull;


  axis_i #(.DataWidth(AxilDataWidth), .Tuser(gaxilite_pkg::resp_t)) rresp_in();
  axis_i #(.DataWidth(AxilDataWidth), .UserWidth($bits(gaxilite_pkg::resp_t))) rresp_out();
  logic [$clog2(RrespFifoDepth+1)-1:0] data_count;

  reg_handshake #(
      .Type      ( RegType                    ),
      .DataWidth ( AxilAddrWidth              )
  ) awaddr_reg (
      .clk       ( clk                        ),
      .rst       ( rst                        ),
      .in_valid  ( axi.awvalid                ),
      .in_ready  ( axi.awready                ),
      .in_data   ( axi.awaddr                 ),
      .out_valid ( waddr_valid                ),
      .out_ready ( write_valid && write_ready ),
      .out_data  ( waddr                      )
  );

  assign w_in.wdata = axi.wdata;
  assign w_in.wstrb = axi.wstrb;
  reg_handshake #(
      .Type      ( RegType                    ),
      .DataWidth ( $bits(w_out)               )
  ) wdata_reg (
      .clk       ( clk                        ),
      .rst       ( rst                        ),
      .in_valid  ( axi.wvalid                 ),
      .in_ready  ( axi.wready                 ),
      .in_data   ( w_in                       ),
      .out_valid ( wdata_valid                ),
      .out_ready ( write_valid && write_ready ),
      .out_data  ( w_out                      )
  );

  assign axi.bresp = gaxilite_pkg::resp_t'(axi_bresp);
  reg_handshake #(
      .Type      ( RegType                     ),
      .DataWidth ( $bits(gaxilite_pkg::resp_t) )
  ) bresp_reg (
      .clk       ( clk                         ),
      .rst       ( rst                         ),
      .in_valid  ( wresp_valid                 ),
      .in_ready  ( wresp_ready                 ),
      .in_data   ( wr_resp                     ),
      .out_valid ( axi.bvalid                  ),
      .out_ready ( axi.bready                  ),
      .out_data  ( axi_bresp                   )
  );

  reg_handshake #(
      .Type      ( RegType                  ),
      .DataWidth ( AxilAddrWidth            )
  ) u_araddr_reg (
      .clk       ( clk                      ),
      .rst       ( rst                      ),
      .in_valid  ( axi.arvalid              ),
      .in_ready  ( axi.arready              ),
      .in_data   ( axi.araddr               ),
      .out_valid ( read_valid               ),
      .out_ready ( read_valid && read_ready ),
      .out_data  ( raddr                    )
  );

  delay_register #(
      .Delay     ( RrespDelay ),
      .DataWidth ( AxilAddrWidth )
  ) u_araddr_delay (
      .clk       ( clk                      ),
      .rst       ( rst                      ),
      .in_valid  ( read_valid && read_ready ),
      .in_data   ( raddr                    ),
      .out_valid ( rd_resp_en               ),
      .out_data  ( rd_resp_addr             )
  );

  assign rresp_in.tvalid  = rresp_valid;
  assign rresp_ready      = rresp_in.tready;
  assign rresp_almostfull = (data_count > RrespFifoThreshold);
  assign rresp_in.tdata   = rd_resp_data;
  assign rresp_in.tuser   = rd_resp;

  axis_fifo #(
      .FifoDepth  ( RrespFifoDepth )
  ) u_rresp_fifo (
      .clk        ( clk        ),
      .rst        ( rst        ),
      .axis_in    ( rresp_in   ),
      .axis_out   ( rresp_out  ),
      .error      (            ),
      .data_count ( data_count )
  );

  assign axi.rvalid       = rresp_out.tvalid;
  assign rresp_out.tready = axi.rready;
  assign axi.rdata        = rresp_out.tdata;
  assign axi.rresp        = gaxilite_pkg::resp_t'(rresp_out.tuser);

  // Write
  assign write_valid =  waddr_valid && wdata_valid;
  assign write_ready = !wresp_valid || wresp_ready;

  assign addr    = wr_en ? waddr : raddr;
  assign wr_en   = write_valid && write_ready && &w_out.wstrb;
  assign wr_data = w_out.wdata;

  always @(posedge clk) begin : WriteResponse
    if (rst) begin
      wresp_valid <= '0;
    end else begin
      if (wresp_ready) begin
        wresp_valid <= '0;
      end
      if (write_valid && write_ready) begin
        wresp_valid <= 1'b1;
      end
    end
  end : WriteResponse

  // Read
  assign read_ready = (!rresp_almostfull) && (!write_valid || !write_ready);
  always @(posedge clk) begin : ReadResponse
    if (rst) begin
      rresp_valid <= '0;
    end else begin
      if (rresp_ready) begin
        rresp_valid <= '0;
      end
      if (rd_resp_en) begin
        rresp_valid <= 1'b1;
      end
    end
  end : ReadResponse


endmodule : axi_lite_manager
