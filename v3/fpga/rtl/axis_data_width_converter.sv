/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Module changes DataWidth in axis interface
 *
 *  - One DataWitdh must be a factor of another
 *  - WordWidth must be the same on both interfaces
 *  - One UserWidth must be the same
 */
module axis_data_width_converter #(
    parameter reg_handshake_pkg::reg_type_e InputRegType  = reg_handshake_pkg::kBypass,
    parameter reg_handshake_pkg::reg_type_e OutputRegType = reg_handshake_pkg::kBypass
)
(
    input logic   clk,
    input logic   rst,
    axis_i.agent  i_axis_in,
    axis_i.host   i_axis_out
);

  localparam int InTdataWidth  = i_axis_in.TdataWidth;
  localparam int InTuserWidth  = i_axis_in.TuserWidth;
  localparam int InTkeepWidth  = i_axis_in.TkeepWidth;
  localparam int OutTdataWidth = i_axis_out.TdataWidth;
  localparam int OutTuserWidth = i_axis_out.TuserWidth;
  localparam int OutTkeepWidth = i_axis_out.TkeepWidth;

  localparam int InOutRatio = (InTdataWidth > OutTdataWidth) ?
                              (InTdataWidth / OutTdataWidth) :
                              (OutTdataWidth / InTdataWidth);

  axis_i #(.DataWidth(InTdataWidth),
           .KeepWidth(InTkeepWidth),
           .UserWidth(InTuserWidth)) i_axis_reg_in();
  axis_i #(.DataWidth(OutTdataWidth),
           .KeepWidth(OutTkeepWidth),
           .UserWidth(OutTuserWidth)) i_axis_reg_out();

  axis_reg_handshake #(
      .RegType    ( InputRegType    )
  ) u_reg_input   (
      .clk        ( clk               ),
      .rst        ( rst               ),
      .axis_in    ( i_axis_in         ),
      .axis_out   ( i_axis_reg_in     )
  );

  generate
    if (OutTdataWidth < InTdataWidth) begin: BiggerWidthToSmaller

      logic [InOutRatio-1:0][OutTdataWidth-1:0] out_data_reg;
      logic [InOutRatio-1:0][OutTkeepWidth-1:0] out_keep_reg;
      logic [OutTuserWidth-1:0]                 out_user_reg;
      logic                                     out_last_reg;

      logic                                     data_ready;
      logic                                     is_last_data;
      logic [$clog2(InOutRatio)-1:0]            ptr;
      logic [$clog2(InOutRatio)-1:0]            max_ptr;

      assign i_axis_reg_in.tready = !data_ready || (i_axis_reg_out.tready && (ptr == max_ptr));
      assign is_last_data = (data_ready && i_axis_reg_out.tready && (ptr == max_ptr));

      always @(posedge clk) begin
        if (rst) begin
          i_axis_reg_out.tvalid <= 1'b0;
          data_ready <= 1'b0;
          max_ptr <= InOutRatio - 1;
          out_last_reg <= '0;
        end else begin

          if (i_axis_reg_out.tready) begin
            i_axis_reg_out.tvalid <= 1'b0;
          end

          if (data_ready && (i_axis_reg_out.tready || !i_axis_reg_out.tvalid)) begin
            i_axis_reg_out.tvalid <= 1'b1;
            i_axis_reg_out.tdata  <= out_data_reg[ptr];
            i_axis_reg_out.tuser  <= out_user_reg;
            i_axis_reg_out.tkeep  <= out_keep_reg[ptr];
            i_axis_reg_out.tlast  <= 1'b0;
            if (ptr == max_ptr) begin
              i_axis_reg_out.tlast <= out_last_reg;
              data_ready <= 1'b0;
            end
          end

          if (i_axis_reg_in.tready && i_axis_reg_in.tvalid) begin
            data_ready <= 1'b1;
            out_data_reg <= i_axis_reg_in.tdata;
            out_keep_reg <= i_axis_reg_in.tkeep;
            out_user_reg <= i_axis_reg_in.tuser;
            out_last_reg <= i_axis_reg_in.tlast;
            max_ptr <= InOutRatio-1;
            if (i_axis_reg_in.tlast) begin
              for (int i = 0; i < InOutRatio; i++) begin
                if (!(|i_axis_reg_in.tkeep[OutTkeepWidth*(i+1)-1-:OutTkeepWidth])) begin
                  max_ptr <= i - 1;
                end else begin
                  max_ptr <= InOutRatio - 1;
                end
              end
            end
          end
        end
      end

      always @(posedge clk) begin
        if (!data_ready || is_last_data) begin
          ptr <= 0;
        end
        else if (data_ready && (i_axis_reg_out.tready || !i_axis_reg_out.tvalid)) begin
          ptr <= ptr + 1;
        end
      end

    end else if (OutTdataWidth > InTdataWidth) begin: SmallerWidthToBigger

      logic [InOutRatio-1:0][InTdataWidth-1:0] data_reg;
      logic [InOutRatio-1:0][InTkeepWidth-1:0] keep_reg;
      logic [InTuserWidth-1:0]                 user_reg;
      logic                                    data_ready;
      logic                                    last_reg;
      logic [$clog2(InOutRatio)-1 : 0]         ptr;

      assign i_axis_reg_in.tready = !data_ready || (data_ready && i_axis_reg_out.tready);
      always @(posedge clk) begin
        if (rst) begin
          i_axis_reg_out.tvalid <= 1'b0;
          data_ready <= 1'b0;
          keep_reg <= '0;
          ptr <= '0;
          last_reg <= '0;
        end
        else begin
          if (i_axis_reg_out.tready) begin
            i_axis_reg_out.tvalid <= 1'b0;
          end
          if (data_ready && (i_axis_reg_out.tready || !i_axis_reg_out.tvalid)) begin
            data_ready <= 1'b0;
            keep_reg <= '0;
            i_axis_reg_out.tvalid <= 1'b1;
            i_axis_reg_out.tkeep  <= keep_reg;
            i_axis_reg_out.tdata  <= data_reg;
            i_axis_reg_out.tuser  <= user_reg;
            i_axis_reg_out.tlast  <= last_reg;
          end
          if (i_axis_reg_in.tready && i_axis_reg_in.tvalid) begin
            data_reg[ptr] <= i_axis_reg_in.tdata;
            user_reg      <= i_axis_reg_in.tuser;
            keep_reg[ptr] <= i_axis_reg_in.tkeep;
            last_reg      <= i_axis_reg_in.tlast;
            ptr           <= ptr + 1;
            if (ptr == InOutRatio-1 || i_axis_reg_in.tlast) begin
              ptr        <= '0;
              data_ready <= 1'b1;
            end
          end
        end
      end

    end else if (OutTdataWidth == InTdataWidth) begin: SameWidth
      axis_reg_handshake #(
          .RegType    ( reg_handshake_pkg::kBypass )
      ) bypass        (
          .clk        ( clk            ),
          .rst        ( rst            ),
          .axis_in    ( i_axis_reg_in  ),
          .axis_out   ( i_axis_reg_out )
      );
    end

  endgenerate

  axis_reg_handshake #(
      .RegType    ( OutputRegType   )
  ) u_reg_output  (
      .clk        ( clk               ),
      .rst        ( rst               ),
      .axis_in    ( i_axis_reg_out    ),
      .axis_out   ( i_axis_out        )
  );

endmodule : axis_data_width_converter
