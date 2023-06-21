/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Adapter from DisplayPort interfaces to DMA-friendly interfaces
 */

module dp_to_dma_adapter #(
    parameter int PixelDataWidth = vid_rx_pkg::PixelDataWidth,
    parameter int PixelKeepWidth = vid_rx_pkg::PixelKeepWidth,
    parameter int DmaDataWidth   = vid_rx_pkg::DmaDataWidth
) (
    input  logic                        clk,
    input  logic                        rst,
    input  vid_rx_pkg::vid_dma_format_e vid_format,
    output logic                        overflow,
    dp_video_i.agent                    i_dp_vid,
    axis_i.host                         i_dp_dma
);
  import dp_rx_pkg::DpToDmaAdapterFifoDepth;
  import vid_rx_pkg::*;

  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_axis_dp();

  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_dp_cdc();

  axis_i #(.Tdata(vid_dma_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_dp_format();

  axis_i #(.Tdata(vid_dma_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_dp_fifo();

  typedef struct packed {
    logic [PixelDataWidth-1:0] data;
    logic [PixelKeepWidth-1:0] keep;
    vid_meta_t user;
    logic last;
  } dp_vid_rx_t;

  dp_vid_rx_t dp_vid_cdc_in;
  dp_vid_rx_t dp_vid_cdc_out;

  logic fifo_error;
  logic [$clog2(DpToDmaAdapterFifoDepth):0] fifo_data_cnt;
  dp_to_axi u_dp_to_axi (
      .i_dp_vid_in    ( i_dp_vid  ),
      .i_axis_dp_vid  ( i_axis_dp )
  );

  always_comb begin : axis_to_cdc
    dp_vid_cdc_in.data = i_axis_dp.tdata;
    dp_vid_cdc_in.keep = i_axis_dp.tkeep;
    dp_vid_cdc_in.user = i_axis_dp.tuser;
    dp_vid_cdc_in.last = i_axis_dp.tlast;
  end

  assign i_axis_dp.tready = i_dp_cdc.tready;
  cdc_synchronizer_data #(
      .Width ( $bits(dp_vid_rx_t) )
  ) u_cdc_dp (
      .in_clk    ( i_dp_vid.clk          ),
      .out_clk   ( clk                   ),
      .in_valid  ( i_axis_dp.tvalid      ),
      .in_data   ( dp_vid_cdc_in         ),
      .out_valid ( i_dp_cdc.tvalid       ),
      .out_data  ( dp_vid_cdc_out        )
  );

  always_comb begin : cdc_to_axis
    i_dp_cdc.tdata = dp_vid_cdc_out.data;
    i_dp_cdc.tkeep = dp_vid_cdc_out.keep;
    i_dp_cdc.tuser = dp_vid_cdc_out.user;
    i_dp_cdc.tlast = dp_vid_cdc_out.last;
  end

  vid_format_selector u_vid_format_sel (
      .clk        ( clk         ),
      .rst        ( rst         ),
      .vid_format ( vid_format  ),
      .i_axis_in  ( i_dp_cdc    ),
      .i_axis_out ( i_dp_format )
  );

  // FIFO has to be able to collect all incoming data
  always @(posedge clk) begin
    if (rst) begin
    overflow <= 1'b0;
    end else begin
      if (i_dp_format.tvalid && !i_dp_format.tready &&
          (fifo_data_cnt == DpToDmaAdapterFifoDepth)) begin
        overflow <= 1'b1;
      end
    end
  end

  axis_fifo #(
      .FifoDepth      ( DpToDmaAdapterFifoDepth           ),
      .DataCntWidth   ( $clog2(DpToDmaAdapterFifoDepth+1) ),
      .OutputRegType  ( reg_handshake_pkg::kPayload       )
  ) u_vid_dp_fifo (
      .clk        ( clk           ),
      .rst        ( rst           ),
      .axis_in    ( i_dp_format   ),
      .axis_out   ( i_dp_fifo     ),
      .error      ( fifo_error    ),
      .data_count ( fifo_data_cnt )
  );

  vid_to_dma_data_width_conv u_data_width_conv (
      .clk        ( clk         ),
      .rst        ( rst         ),
      .i_axis_in  ( i_dp_fifo   ),
      .i_axis_out ( i_dp_dma    )
  );

endmodule : dp_to_dma_adapter
