/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Synchronizer module based on Intel's dcfifo
 * - no overflow/error control
 * - continuous synchronization from slow to fast clock domain
 */
module cdc_synchronizer_data #(
    parameter int Width = 8,
    parameter int Detph = 16
)(
    input  logic            in_clk,
    input  logic            out_clk,

    input  logic[Width-1:0] in_data,
    input  logic            in_valid,
    output logic[Width-1:0] out_data,
    output logic            out_valid
);


  logic dcfifo_rd_empty;
  logic dcfifo_wr_full;
  logic wr_req;

  assign wr_req = ~dcfifo_wr_full && in_valid;

  dcfifo #(
      .lpm_width         ( Width         ),
      .lpm_widthu        ( $clog2(Detph) ),
      .lpm_numwords      ( Detph         ),
      .lpm_showahead     ( "OFF"         ),
      .overflow_checking ( "ON"          ),
      .underflow_checking( "ON"          ),
      .add_usedw_msb_bit ( "OFF"         ),
      .rdsync_delaypipe  ( 4             ),
      .wrsync_delaypipe  ( 4             )
  ) u_dcfifo (
      .wrclk    ( in_clk           ),
      .data     ( in_data          ),
      .wrreq    ( wr_req           ),
      .wrfull   ( dcfifo_wr_full   ),
      .wrempty  (                  ),
      .wrusedw  (                  ),

      .rdclk    ( out_clk          ),
      .q        ( out_data         ),
      .rdempty  ( dcfifo_rd_empty  ),
      .rdreq    ( ~dcfifo_rd_empty ),
      .rdfull   (                  ),
      .rdusedw  (                  ),

      .aclr     ( 1'b0             ),
      .eccstatus(                  )
  );

  always_ff @(posedge out_clk) begin
    out_valid <= ~dcfifo_rd_empty;
  end

endmodule : cdc_synchronizer_data
