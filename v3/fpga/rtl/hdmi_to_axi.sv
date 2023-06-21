/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module hdmi_to_axi (
    input  logic      clk, // vid_clk, up to 300MHz
    input  logic      rst,

    hdmi_data_i.agent i_hdmi_data,
    axis_i.host       i_axis_vid
);

  import hdmi_rx_pkg::*;
  import vid_rx_pkg::vid_meta_t;

  localparam int TrCount = 3; // Hold last three transactions to detect EOL/EOF

  hdmi_data_t data_d;
  hdmi_data_t data_aligned;
  hdmi_data_t data_polarity;
  hdmi_data_t data_edges;

  logic any_valid_d;
  logic align_required;
  logic align_required_d;
  logic inv_polarity_vsync;
  logic inv_polarity_hsync;

  typedef struct packed {
    logic pos;
    logic neg;
  } edge_t;

  typedef struct packed {
    logic eol;
    logic eof;
  } eol_eof_t;

  typedef struct packed {
    logic [HdmiVidDataWidth-1:0] data;
    logic [HdmiVidPxPerBeat-1:0] keep;
    vid_meta_t user;
    logic last;
  } buf_vid_t;

  edge_t hsync_edge;
  edge_t vsync_edge;
  logic was_de;
  logic hsync_edge_done;
  eol_eof_t flags;
  eol_eof_t flags_d;
  buf_vid_t buffer_input;
  buf_vid_t [TrCount-1:0] buffer_meta;

  logic input_tr;
  logic output_tr;
  logic [TrCount-1:0] buffer_valid;
  logic eof_to_send;

  axis_i #(.DataWidth(HdmiVidDataWidth),
           .KeepWidth(HdmiVidPxPerBeat),
           .Tuser(vid_meta_t)) i_axis_hdmi_vid();

  always @(posedge clk) begin : delay_for_alignment
    any_valid_d      <= |i_hdmi_data.de || |i_hdmi_data.hsync || |i_hdmi_data.vsync;
    align_required_d <= align_required;
    data_d.de        <= i_hdmi_data.de;
    data_d.hsync     <= i_hdmi_data.hsync;
    data_d.vsync     <= i_hdmi_data.vsync;
    data_d.lock      <= i_hdmi_data.lock;
    data_d.data      <= i_hdmi_data.data;
  end

  always_comb begin : detect_alignment
    if (!any_valid_d) begin
      align_required = (i_hdmi_data.de[1] && !i_hdmi_data.de[0]) ||
                       (i_hdmi_data.hsync[1] && !i_hdmi_data.hsync[0]) ||
                       (i_hdmi_data.vsync[1] && !i_hdmi_data.vsync[0]);
    end else begin
      align_required = align_required_d;
    end
  end

  always_comb begin : set_alignment
    if (align_required_d) begin
      data_aligned.de[0]    = data_d.de[1];
      data_aligned.de[1]    = i_hdmi_data.de[0];
      data_aligned.hsync[0] = data_d.hsync[1];
      data_aligned.hsync[1] = i_hdmi_data.hsync[0];
      data_aligned.vsync[0] = data_d.vsync[1];
      data_aligned.vsync[1] = i_hdmi_data.vsync[0];
      data_aligned.lock     = data_d.lock;
      data_aligned.data[HdmiVidDataWidth/2-1:0] =
        data_d.data[HdmiVidDataWidth-1-:HdmiVidDataWidth/2];
      data_aligned.data[HdmiVidDataWidth-1-:HdmiVidDataWidth/2] =
        i_hdmi_data.data[HdmiVidDataWidth/2-1:0];
    end else begin
      data_aligned.de    = data_d.de;
      data_aligned.hsync = data_d.hsync;
      data_aligned.vsync = data_d.vsync;
      data_aligned.data  = data_d.data;
      data_aligned.lock  = data_d.lock;
    end
  end

  always @(posedge clk) begin : detect_polarity
    if (|data_aligned.de) begin
      if (|data_aligned.hsync) begin
        inv_polarity_hsync <= 1'b1;
      end else begin
        inv_polarity_hsync <= 1'b0;
      end

      if (|data_aligned.vsync) begin
        inv_polarity_vsync <= 1'b1;
      end else begin
        inv_polarity_vsync <= 1'b0;
      end
    end
  end

  always_comb begin : polarity_assignment
    data_polarity.data = data_aligned.data;
    data_polarity.de   = data_aligned.de;
    data_polarity.lock = data_aligned.lock;
    if (inv_polarity_hsync) begin
      data_polarity.hsync = ~data_aligned.hsync;
    end else begin
      data_polarity.hsync = data_aligned.hsync;
    end
    if (inv_polarity_vsync) begin
      data_polarity.vsync = ~data_aligned.vsync;
    end else begin
      data_polarity.vsync = data_aligned.vsync;
    end
  end

  always @(posedge clk) begin : delay_edge_detection
    data_edges <= data_polarity;
  end

  always_comb begin : detect_edge
    hsync_edge.pos = |data_polarity.hsync & ~(|data_edges.hsync);
    hsync_edge.neg = ~(|data_polarity.hsync) & |data_edges.hsync;
    vsync_edge.pos = |data_polarity.vsync & ~(|data_edges.vsync);
    vsync_edge.neg = ~(|data_polarity.vsync) & |data_edges.vsync;
  end

  always @(posedge clk) begin
    if (rst) begin
      was_de <= 1'b1;
      hsync_edge_done <= 1'b1;
    end else begin
      if (hsync_edge.neg) begin
        hsync_edge_done <= 1'b1;
        was_de <= 1'b0;
      end
      if (hsync_edge.pos) begin
        hsync_edge_done <= 1'b0;
      end

      if (hsync_edge_done && |data_polarity.de) begin
        was_de <= 1'b1;
      end
    end
  end
  always_comb begin : first_axi
    i_axis_hdmi_vid.tvalid                = (|data_polarity.de) | (was_de & hsync_edge.pos) |
                                            vsync_edge.pos;
    i_axis_hdmi_vid.tdata                 = data_polarity.data;
    i_axis_hdmi_vid.tuser.vid.sof         = vsync_edge.neg;
    i_axis_hdmi_vid.tuser.vid.sol         = hsync_edge.neg;
    i_axis_hdmi_vid.tuser.vid.eol         = hsync_edge.pos;
    i_axis_hdmi_vid.tuser.vid.eof         = vsync_edge.pos;
    i_axis_hdmi_vid.tuser.vid.data_valid  = |data_polarity.de;
    i_axis_hdmi_vid.tuser.vid.interlace   = '0;
    i_axis_hdmi_vid.tuser.vid.error       = (data_polarity.hsync[0] ^ data_polarity.hsync[1]) |
                                            (data_polarity.vsync[0] ^ data_polarity.vsync[1]);
    i_axis_hdmi_vid.tuser.aud             = '0;
    i_axis_hdmi_vid.tkeep                 = data_polarity.de;
    i_axis_hdmi_vid.tlast                 = vsync_edge.pos | hsync_edge.pos;
  end

  always_comb begin : helpers
    input_tr  = i_axis_hdmi_vid.tvalid && i_axis_hdmi_vid.tready;
    output_tr = i_axis_vid.tvalid && i_axis_vid.tready;
    buffer_input.data = i_axis_hdmi_vid.tdata;
    buffer_input.keep = i_axis_hdmi_vid.tkeep;
    buffer_input.user = i_axis_hdmi_vid.tuser;
    buffer_input.last = i_axis_hdmi_vid.tuser.vid.eof;
  end

  always @(posedge clk) begin : delay_first_cycle
    if (rst) begin
      buffer_valid <= '0;
      buffer_meta  <= '0;
    end else begin
      if (input_tr) begin
        buffer_valid <= {buffer_valid, 1'b1};
        buffer_meta  <= {buffer_meta, buffer_input};
      end else if (&buffer_valid) begin
        buffer_valid[TrCount-1] <= 1'b0;
      end

      if (buffer_meta[TrCount-3].user.vid.eof &&
          (buffer_meta[TrCount-2].user.vid.eol || eof_to_send)) begin
        buffer_valid <= '0;
        buffer_meta  <= '0;
      end
    end
  end

  assign i_axis_hdmi_vid.tready = i_axis_vid.tready;
  always @(posedge clk) begin
    if (rst) begin
      i_axis_vid.tvalid <= 1'b0;
      eof_to_send <= 1'b0;
    end else begin
      if (i_axis_vid.tready) begin
        i_axis_vid.tvalid <= 1'b0;
      end

      i_axis_vid.tdata <= buffer_meta[TrCount-1].data;
      i_axis_vid.tkeep <= buffer_meta[TrCount-1].keep;
      i_axis_vid.tuser <= buffer_meta[TrCount-1].user;
      i_axis_vid.tlast <= 1'b0;
      if (&buffer_valid || eof_to_send) begin
        if (buffer_meta[TrCount-2].user.vid.eol && !buffer_meta[TrCount-3].user.vid.eof) begin : eol
            i_axis_vid.tvalid <= 1'b1;
            i_axis_vid.tuser  <= buffer_meta[TrCount-2].user;
            i_axis_vid.tuser.vid.data_valid <= buffer_meta[TrCount-1].user.vid.data_valid;
        end else if (buffer_meta[TrCount-3].user.vid.eof) begin : eof
          if (buffer_meta[TrCount-2].user.vid.eol || eof_to_send) begin : eol_prev_beat
            i_axis_vid.tvalid <= 1'b1;
            i_axis_vid.tuser  <= buffer_meta[TrCount-3].user;
            i_axis_vid.tuser.vid.eol <= 1'b1;
            i_axis_vid.tuser.vid.data_valid <= buffer_meta[TrCount-1].user.vid.data_valid;
            i_axis_vid.tlast  <= 1'b1;
            if (eof_to_send) begin
              i_axis_vid.tdata <= buffer_meta[TrCount-2].data;
              i_axis_vid.tkeep <= buffer_meta[TrCount-2].keep;
            end
            eof_to_send <= 1'b0;
          end else if (buffer_meta[TrCount-3].user.vid.eol) begin : eol_with_eof
            i_axis_vid.tvalid <= 1'b1;
            i_axis_vid.tuser  <= buffer_meta[TrCount-2].user;
            i_axis_vid.tuser.vid.eol <= '0;
            eof_to_send <= 1'b1;
          end
        end else begin : bypass
          i_axis_vid.tvalid <= buffer_meta[TrCount-1].user.vid.eol ? 1'b0 : 1'b1;
        end
      end
    end
  end


endmodule : hdmi_to_axi
