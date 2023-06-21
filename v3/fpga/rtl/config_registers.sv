/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

module config_registers #(
    parameter int DataWidth        = gaxilite_pkg::DataWidth
) (
    input  logic                                clk,
    input  logic                                rst,

    output config_registers_pkg::spi_t          spi,

    axil_i.subordinate                                i_axi_lite
);

  import gaxilite_pkg::kOkay;
  import gaxilite_pkg::kDecErr;
  import gaxilite_pkg::resp_t;
  import config_registers_pkg::*;

  // AXI Lite Manager Interface
  logic [AddrWidth-1:0]           axil_addr;
  logic                           axil_wr_en;
  logic [DataWidth-1:0]           axil_wr_data;
  resp_t                          axil_wr_resp;
  logic                           axil_rd_resp_en;
  logic [AddrWidth-1:0]           axil_rd_resp_addr;
  logic [DataWidth-1:0]           axil_rd_resp_data;
  resp_t                          axil_rd_resp;

  axi_lite_manager #(
    .RegType        ( reg_handshake_pkg::kPayloadCtrl ), // only to ease timing requirements
    .RrespDelay     ( 2             ), // delay Rresp by this number of cycles, to ease timing
                                         // on output
    .RrespFifoDepth ( 8             )  // store up to 8 Rresp messages
  ) u_axi_lite_manager (
    .clk          ( clk               ),
    .rst          ( rst               ),
    .axi          ( i_axi_lite        ),
    .addr         ( axil_addr         ),
    .wr_en        ( axil_wr_en        ),
    .wr_data      ( axil_wr_data      ),
    .wr_resp      ( axil_wr_resp      ),
    .rd_resp_en   ( axil_rd_resp_en   ),
    .rd_resp_addr ( axil_rd_resp_addr ),
    .rd_resp_data ( axil_rd_resp_data ),
    .rd_resp      ( axil_rd_resp      )
  );

  ////////////////////////////////////////////////////////////////////////////
  // Handle AXI Lite write request/response
  always_ff @(posedge clk) begin
    if (rst) begin
      axil_wr_resp    <= kOkay;
      spi             <= '0;
    end else begin
      if (axil_wr_en) begin
        axil_wr_resp <= kOkay;
        unique case (axil_addr)
          AddrSpiGpio: spi <= axil_wr_data;
          default:     axil_wr_resp <= kDecErr;
        endcase
      end
    end
  end

  ////////////////////////////////////////////////////////////////////////////
  // Handle AXI Lite read response
  always_ff @(posedge clk) begin
    if (rst) begin
      axil_rd_resp_data <= '0;
      axil_rd_resp <= kOkay;
    end else begin
      if (axil_rd_resp_en) begin
        axil_rd_resp <= kOkay;
        axil_rd_resp_data <= '0;
        unique case (axil_rd_resp_addr) inside
          AddrGitHash: axil_rd_resp_data <= config_registers_pkg::GUID;
          AddrChipId:  axil_rd_resp_data <= config_registers_pkg::CHIP_ID;
          AddrSpiGpio: axil_rd_resp_data <= spi;

          default:     axil_rd_resp <= kOkay;
        endcase
      end
    end
  end

endmodule : config_registers
