/*
 * Copyright 2021-2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module to handle DMA ping-pong (A-B) buffers based on incomming data.
 */
module framebuffer_dma (
    input  logic                                      clk,
    input  logic                                      rst,

    // Interrupt interface
    output logic [3:0]                                irq,

    // Data from CSR
    output framebuffer_registers_pkg::dim_t           height,
    output framebuffer_registers_pkg::dim_t           width,
    input  framebuffer_registers_pkg::enable_t        en,
    input  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_a,
    input  framebuffer_registers_pkg::buffer_addr_t   buffer_addr_b,
    input logic [framebuffer_pkg::BufferCount-1:0]    buffer_write,
    input  framebuffer_registers_pkg::buffer_size_t   buffer_size,
    output framebuffer_registers_pkg::errors_t        errors,
    input  framebuffer_registers_pkg::dma_format_t    dma_format,

    axis_i.agent                                      i_data_in,
    axis_i.host                                       i_data_out
);

  import framebuffer_pkg::*;
  import framebuffer_registers_pkg::*;

  localparam int CountBeatValue = 3;
  localparam int CountBeatsXWidth = 2;

  typedef struct packed {
    logic                   sel;
    logic [BufferCount-1:0] valid;
    logic [BufferCount-1:0] eof;
  } fb_buffer_meta_t;

  typedef struct packed {
    fb_dma_meta_t meta;
    pixel_word_t data;
  } fb_dma_t;

  typedef struct packed {
    logic [BufferCount-1:0] wr;
    logic [BufferCount-1:0] valid;
    logic [BufferCount-1:0] used;
  } fb_buffer_status_t;

  errors_t            errors_d;
  dim_t               y;
  dim_t               x;
  dim_t               height_d;
  dim_t               width_d;
  dim_t               width_mask;
  buffer_addr_t       addr;
  buffer_addr_t       base_addr;
  buffer_addr_t       write_addr;
  enable_t            en_d;
  fb_buffer_meta_t    buffer_meta;
  fb_buffer_status_t  buffer_status;
  logic               addr_valid;
  logic               input_data_valid;
  logic               data_addr_valid;
  logic               falling_edge_en;
  logic               first_frame_skipped;
  logic               swap_buff;
  logic               valid_eof_d;
  logic               new_resolution_detected;
  logic               error_detected;

  fb_dma_t            fifo_in, fifo_out;
  logic               fifo_wr, fifo_rd, fifo_full, fifo_empty;
  logic [CountBeatsXWidth-1:0] valid_cnt;

  assign width_mask.dim = {{(DimWidth-1){1'b1}}, 1'b0};

  always_ff @(posedge clk) begin : addr_count
    if (rst || !en.en) begin
      addr.addr <= '0;
    end else begin
      if (i_data_in.tvalid) begin
        if (i_data_in.tuser.eof) begin
          addr.addr <= '0;
        end else if (i_data_in.tuser.data_valid) begin
          addr.addr <= addr.addr + PixelsInBeat;
        end
      end
    end
  end

  always_ff @(posedge clk) begin : addr_pixel_cnt_beats
    if (rst) begin
      valid_cnt <= '0;
    end else begin
      if (valid_cnt == CountBeatValue ||
          (i_data_in.tvalid && i_data_in.tuser.eol)) begin
        valid_cnt <= '0;
      end else begin
        if (i_data_in.tvalid && i_data_in.tuser.data_valid) begin
          valid_cnt <= valid_cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin : calc_width
    if (rst) begin
      x.dim <= '0;
    end else begin
      if (i_data_in.tvalid) begin
        if (i_data_in.tuser.eol || i_data_in.tuser.eof) begin
          x.dim <= '0;
        end else begin
          if (i_data_in.tuser.data_valid) begin
            unique case (dma_format.format) inside
              vid_rx_pkg::k8bpc: begin
                if (valid_cnt == CountBeatValue-1) begin
                  x.dim <= x.dim + (vid_rx_pkg::DmaDataWidth/
                                    $bits(vid_rx_pkg::vid_dma_format_8bpc_single_t)) + 1;
                end else begin
                  x.dim <= x.dim + (vid_rx_pkg::DmaDataWidth/
                                    $bits(vid_rx_pkg::vid_dma_format_8bpc_single_t));
                end
              end
              [vid_rx_pkg::k10bpcUpper:vid_rx_pkg::kRaw]: begin
                if (valid_cnt == 0) begin
                  x.dim <= x.dim + (vid_rx_pkg::DmaDataWidth/
                                    $bits(vid_rx_pkg::vid_dma_format_16bpc_t));
                end else begin
                  x.dim <= x.dim + (vid_rx_pkg::DmaDataWidth/
                                    $bits(vid_rx_pkg::vid_dma_format_16bpc_t)) + 1;
                end
              end
              vid_rx_pkg::k8bpcPad: x.dim <= x.dim + PixelsInBeat;
              default: x.dim <= x.dim + PixelsInBeat;
            endcase
          end
        end
      end
    end
  end

  always_ff @(posedge clk) begin : calc_height
    if (rst) begin
      y.dim <= '0;
    end else begin
      if (i_data_in.tvalid) begin
        if (i_data_in.tuser.eol) begin
          y.dim <= y.dim + 1;
        end
        if (i_data_in.tuser.eof) begin
          y.dim <= '0;
        end
      end
    end
  end

  always_ff @(posedge clk) begin : store_frame_size
    if (i_data_in.tvalid && i_data_in.tuser.eol) begin
      unique case (dma_format.format) inside
        vid_rx_pkg::k8bpc: width.dim <= (x.dim + (vid_rx_pkg::DmaDataWidth/
                                         $bits(vid_rx_pkg::vid_dma_format_8bpc_single_t)) +
                                         valid_cnt) & width_mask.dim;
        [vid_rx_pkg::k10bpcUpper:vid_rx_pkg::kRaw]: width.dim <=  (x.dim + (vid_rx_pkg::DmaDataWidth/
                                                    $bits(vid_rx_pkg::vid_dma_format_16bpc_t)) +
                                                    valid_cnt) & width_mask.dim;
        vid_rx_pkg::k8bpcPad: width.dim  <= (x.dim & width_mask.dim);
        default: width.dim <= addr.addr;
      endcase
    end
    if (i_data_in.tvalid && i_data_in.tuser.eof) begin
      unique case (dma_format.format)
        vid_rx_pkg::k8bpcPad: height.dim  <= y.dim;
        default: height.dim <= y.dim + 1;
      endcase
    end
  end

  always_ff @(posedge clk) begin : skip_first_frame
    if (rst || !en.en) begin
      first_frame_skipped <= '0;
    end else if (i_data_in.tvalid && i_data_in.tuser.eof) begin
      first_frame_skipped <= 1'b1;
    end
  end

  always_ff @(posedge clk) begin : buffer_ping_pong
    if (rst || !en.en) begin
      swap_buff <= '0;
      buffer_meta.sel <= '0;
      buffer_meta.valid <= '0;
    end else begin
      if (i_data_in.tvalid && i_data_in.tuser.eof && first_frame_skipped) begin
        buffer_meta.valid <= {buffer_status.valid[kBufferB], buffer_status.valid[kBufferA]};
        swap_buff <= 1'b1;
        if (swap_buff) begin
          buffer_meta.sel <= ~buffer_meta.sel;
        end
      end
    end
  end

  always @(posedge clk) begin
    if (i_data_in.tvalid && i_data_in.tuser.eof && first_frame_skipped && swap_buff) begin
      buffer_meta.eof[buffer_meta.sel] <= 1'b1;
    end else begin
      buffer_meta.eof <= '0;
    end
  end

  always_ff @(posedge clk) begin : addr_selector
    base_addr.addr  <= buffer_meta.sel ? buffer_addr_b :
                                         buffer_addr_a;
    write_addr      <= addr.addr;
    addr_valid      <= buffer_meta.valid[buffer_meta.sel];
  end

  always_comb begin
    input_data_valid        = (en.en && i_data_in.tvalid && i_data_in.tuser.data_valid);
    data_addr_valid         = ((input_data_valid && ((4 * write_addr.addr) < buffer_size.size)) ||
                               buffer_meta.eof) && addr_valid;
    fifo_in.meta.addr       = (base_addr.addr + (4 * write_addr.addr)) & ~AddrMaskAlignment;
  end

  always_ff @(posedge clk) begin : delay
    valid_eof_d <= i_data_in.tvalid && i_data_in.tuser.eof;
    en_d <= en;
  end

  always_comb begin : buffer_status_expiry
    falling_edge_en = (en_d.en & !en.en);
    buffer_status.wr[kBufferA] = buffer_write[kBufferA];
    buffer_status.wr[kBufferB] = buffer_write[kBufferB];
    buffer_status.used[kBufferA] = (fifo_wr && (buffer_meta.sel == kBufferA)) || falling_edge_en;
    buffer_status.used[kBufferB] = (fifo_wr && (buffer_meta.sel == kBufferB)) || falling_edge_en;
  end

  always @(posedge clk) begin : buffer_valid
    if (rst) begin
      buffer_status.valid[kBufferA] <= '0;
      buffer_status.valid[kBufferB] <= '0;
    end else begin
      if (buffer_status.wr[kBufferA]) begin
        buffer_status.valid[kBufferA] <= 1'b1;
      end else if (buffer_status.used[kBufferA]) begin
        buffer_status.valid[kBufferA] <= 1'b0;
      end

      if (buffer_status.wr[kBufferB]) begin
        buffer_status.valid[kBufferB] <= 1'b1;
      end else if (buffer_status.used[kBufferB]) begin
        buffer_status.valid[kBufferB] <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin
    fifo_wr           <= data_addr_valid;
    fifo_in.data      <= i_data_in.tdata;
    fifo_in.meta.eof  <= buffer_meta.eof;
  end

  scfifo #(
    .lpm_width                ( $bits(fb_dma_t)             ),
    .lpm_widthu               ( $clog2(PixelToMemFifoDepth) ),
    .lpm_numwords             ( PixelToMemFifoDepth         ),
    .lpm_showahead            ( "ON"                        ),
    .overflow_checking        ( "ON"                        ),
    .underflow_checking       ( "ON"                        ),
    .add_ram_output_register  ( "ON"                        )
  ) u_fb_dma_fifo (
    .clock                    ( clk                         ),
    .data                     ( fifo_in                     ),
    .wrreq                    ( fifo_wr                     ),
    .full                     ( fifo_full                   ),

    .q                        ( fifo_out                    ),
    .empty                    ( fifo_empty                  ),
    .rdreq                    ( fifo_rd                     ),
    .usedw                    (                             ),

    .sclr                     ( rst                         ),
    .aclr                     ( 1'b0                        ),
    .eccstatus                (                             ),

    .almost_empty             (                             ),
    .almost_full              (                             )
  );

  assign fifo_rd = !fifo_empty && i_data_out.tready;

  assign i_data_out.tvalid = !fifo_empty;
  assign i_data_in.tready  = 1'b1;
  assign i_data_out.tdata  = fifo_out.data;
  assign i_data_out.tuser  = fifo_out.meta;
  assign i_data_out.tkeep  = 16'hFFFF;
  assign i_data_out.tlast  = 1'b1;

  //-----------------------------------------------------------------------------------------------
  // Drive IRQs
  always @(posedge clk) begin
    if (rst) begin
      width_d  <= '0;
      height_d <= '0;
    end else begin
      if (valid_eof_d) begin
        width_d.dim  <= width.dim;
        height_d.dim <= height.dim;
      end
    end
  end

  assign new_resolution_detected = valid_eof_d &&
                                   ((width_d.dim ^ width.dim) ||
                                   (height_d.dim ^ height.dim));
  assign error_detected = errors ^ errors_d;

  always_ff @(posedge clk) begin
    errors_d <= errors;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      errors <= '0;
    end else begin
      if (fifo_full && fifo_wr) errors.dma_fifo_overflow <= 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      irq[kIrqError] <= '0;
      irq[kIrqResolution] <= '0;
    end else begin
      irq[kIrqError] <= error_detected;
      irq[kIrqResolution] <= new_resolution_detected;
    end
  end

endmodule : framebuffer_dma
