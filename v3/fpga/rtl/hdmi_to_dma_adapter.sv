/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Adapter from HDMI interfaces to DMA-friendly interfaces
 */

module hdmi_to_dma_adapter (
    input  logic                        clk,
    input  logic                        rst,

    input  logic                        vid_clk,

    input  vid_rx_pkg::vid_dma_format_e vid_format,
    output logic                        overflow,

    hdmi_data_i.agent                   i_hdmi_vid,
    axis_i.host                         i_hdmi_dma
);
  import hdmi_rx_pkg::HdmiVidDataWidth;
  import hdmi_rx_pkg::HdmiVidPxPerBeat;
  import hdmi_rx_pkg::HdmiToDmaAdapterFifoDepth;
  import vid_rx_pkg::*;

  typedef struct packed {
    logic [PixelDataWidth-1:0] data;
    logic [PixelKeepWidth-1:0] keep;
    vid_meta_t user;
    logic last;
  } hdmi_vid_t;

  logic vid_rst;
  logic fifo_error;
  logic [$clog2(HdmiToDmaAdapterFifoDepth):0] fifo_data_cnt;
  logic hdmi_lock_cdc;
  hdmi_vid_t hdmi_vid_cdc_in;
  hdmi_vid_t hdmi_vid_cdc_out;

  axis_i #(.DataWidth(HdmiVidDataWidth),
           .KeepWidth(HdmiVidPxPerBeat),
           .Tuser(vid_meta_t)) i_axis_vid();
  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_hdmi_vid_conv();
  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_hdmi_vid_cdc();
  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_hdmi_vid_format();
  axis_i #(.Tdata(vid_input_format_u),
           .KeepWidth(PixelKeepWidth),
           .Tuser(vid_meta_t)) i_hdmi_fifo();

  clock_crosser #(
      .W ( 1 )
  ) u_cdc_rst (
      .in_clk     ( clk     ),
      .in_reset   ( 1'b0    ),
      .out_clk    ( vid_clk ),
      .out_reset  ( 1'b0    ),
      .in         ( rst     ),
      .out        ( vid_rst )
  );

  clock_crosser #(
      .W ( 1 )
  ) u_cdc_lock (
      .in_clk     ( vid_clk         ),
      .in_reset   ( 1'b0            ),
      .out_clk    ( clk             ),
      .out_reset  ( 1'b0            ),
      .in         ( i_hdmi_vid.lock ),
      .out        ( hdmi_lock_cdc   )
  );

  hdmi_to_axi u_hdmi_to_axi (
      .clk             ( vid_clk                    ),
      .rst             ( vid_rst | ~i_hdmi_vid.lock ),
      .i_hdmi_data     ( i_hdmi_vid                 ),
      .i_axis_vid      ( i_axis_vid                 )
  );

  axis_data_width_converter #(
      .InputRegType ( reg_handshake_pkg::kPayload )
  ) u_data_width_conv (
      .clk        ( vid_clk                    ),
      .rst        ( vid_rst | ~i_hdmi_vid.lock ),
      .i_axis_in  ( i_axis_vid                 ),
      .i_axis_out ( i_hdmi_vid_conv            )
  );

  always_comb begin : axis_to_cdc
    hdmi_vid_cdc_in.data = i_hdmi_vid_conv.tdata;
    hdmi_vid_cdc_in.keep = i_hdmi_vid_conv.tkeep;
    hdmi_vid_cdc_in.user = i_hdmi_vid_conv.tuser;
    hdmi_vid_cdc_in.last = i_hdmi_vid_conv.tlast;
  end

  assign i_hdmi_vid_conv.tready = i_hdmi_vid_cdc.tready;
  cdc_synchronizer_data #(
      .Width     ( $bits(hdmi_vid_t) )
  ) u_cdc_hdmi (
      .in_clk    ( vid_clk                                   ),
      .out_clk   ( clk                                       ),
      .in_valid  ( i_hdmi_vid_conv.tvalid && i_hdmi_vid.lock ),
      .in_data   ( hdmi_vid_cdc_in                           ),
      .out_valid ( i_hdmi_vid_cdc.tvalid                     ),
      .out_data  ( hdmi_vid_cdc_out                          )
  );

  always_comb begin : cdc_to_axis
    i_hdmi_vid_cdc.tdata = hdmi_vid_cdc_out.data;
    i_hdmi_vid_cdc.tkeep = hdmi_vid_cdc_out.keep;
    i_hdmi_vid_cdc.tuser = hdmi_vid_cdc_out.user;
    i_hdmi_vid_cdc.tlast = hdmi_vid_cdc_out.last;
  end

  vid_format_selector u_vid_format_sel (
      .clk        ( clk                  ),
      .rst        ( rst | ~hdmi_lock_cdc ),
      .vid_format ( vid_format           ),
      .i_axis_in  ( i_hdmi_vid_cdc       ),
      .i_axis_out ( i_hdmi_vid_format    )
  );

  // FIFO has to be able to collect all incoming data
  always @(posedge clk) begin
    if (rst) begin
      overflow <= 1'b0;
    end else begin
      if (i_hdmi_vid_format.tvalid && !i_hdmi_vid_format.tready &&
          (fifo_data_cnt == HdmiToDmaAdapterFifoDepth)) begin
        overflow <= 1'b1;
      end
    end
  end

  axis_fifo #(
      .FifoDepth      ( HdmiToDmaAdapterFifoDepth           ),
      .DataCntWidth   ( $clog2(HdmiToDmaAdapterFifoDepth+1) ),
      .OutputRegType  ( reg_handshake_pkg::kPayload         )
  ) u_vid_hdmi_fifo (
      .clk        ( clk                  ),
      .rst        ( rst | ~hdmi_lock_cdc ),
      .axis_in    ( i_hdmi_vid_format    ),
      .axis_out   ( i_hdmi_fifo          ),
      .error      ( fifo_error           ),
      .data_count ( fifo_data_cnt        )
  );

  vid_to_dma_data_width_conv u_vid_data_width_conv (
      .clk        ( clk                  ),
      .rst        ( rst | ~hdmi_lock_cdc ),
      .i_axis_in  ( i_hdmi_fifo          ),
      .i_axis_out ( i_hdmi_dma           )
  );

endmodule : hdmi_to_dma_adapter
