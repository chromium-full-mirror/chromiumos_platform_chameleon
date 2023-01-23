/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

////////////////////////////////////////////////////////////
// Wrapper for ARM's assertions                           //
// Set up manual: $(VIPS_DIR)/common/assertions/README.md //
////////////////////////////////////////////////////////////


function void arm_amba4_pc_msg_err(string msg);
  greporter_pkg::greporter::error("SVA", msg);
endfunction : arm_amba4_pc_msg_err

function void arm_amba4_pc_msg_warn(string msg);
  greporter_pkg::greporter::warning("SVA", msg);
endfunction : arm_amba4_pc_msg_warn

`define ARM_AMBA4_PC_MSG_ERR arm_amba4_pc_msg_err
`define ARM_AMBA4_PC_MSG_WARN arm_amba4_pc_msg_warn


`ifdef ASSERT_AXIMM
  `include "Axi4PC.sv"

  `define ASSERT_AXIMM_INF(clk, rst, inf, name, not_ready_threshold=16) \
    localparam int MaxWaits``name = not_ready_threshold ? not_ready_threshold : 1; \
    localparam bit RecMaxWaitOn``name = not_ready_threshold != 0; \
    Axi4PC #( \
      .DATA_WIDTH    ( inf.N * 8          ), \
      .WID_WIDTH     ( inf.I              ), \
      .RID_WIDTH     ( inf.I              ), \
      .AWUSER_WIDTH  ( inf.U_REQ_WIDTH    ), \
      .WUSER_WIDTH   ( inf.U_DATA_WIDTH   ), \
      .BUSER_WIDTH   ( inf.U_RESP_WIDTH   ), \
      .ARUSER_WIDTH  ( inf.U_REQ_WIDTH    ), \
      .RUSER_WIDTH   ( inf.U_DATA_WIDTH   ), \
      .MAXWAITS      ( MaxWaits``name     ), \
      .RecMaxWaitOn  ( RecMaxWaitOn``name ), \
      .ADDR_WIDTH    ( inf.A              )  \
    ) assert_``name (             \
      .ACLK     ( clk          ), \
      .ARESETn  ( !rst         ), \
      .AWID     ( inf.awid     ), \
      .AWADDR   ( inf.awaddr   ), \
      .AWLEN    ( inf.awlen    ), \
      .AWSIZE   ( inf.awsize   ), \
      .AWBURST  ( inf.awburst  ), \
      .AWLOCK   ( inf.awlock[0]), \
      .AWCACHE  ( inf.awcache  ), \
      .AWPROT   ( inf.awprot   ), \
      .AWQOS    ( inf.awqos    ), \
      .AWREGION ( inf.awregion ), \
      .AWUSER   ( inf.awuser   ), \
      .AWVALID  ( inf.awvalid  ), \
      .AWREADY  ( inf.awready  ), \
      .WLAST    ( inf.wlast    ), \
      .WDATA    ( inf.wdata    ), \
      .WSTRB    ( inf.wstrb    ), \
      .WUSER    ( inf.wuser    ), \
      .WVALID   ( inf.wvalid   ), \
      .WREADY   ( inf.wready   ), \
      .BID      ( inf.bid      ), \
      .BRESP    ( inf.bresp    ), \
      .BUSER    ( inf.buser    ), \
      .BVALID   ( inf.bvalid   ), \
      .BREADY   ( inf.bready   ), \
      .ARID     ( inf.arid     ), \
      .ARADDR   ( inf.araddr   ), \
      .ARLEN    ( inf.arlen    ), \
      .ARSIZE   ( inf.arsize   ), \
      .ARBURST  ( inf.arburst  ), \
      .ARLOCK   ( inf.arlock[0]), \
      .ARCACHE  ( inf.arcache  ), \
      .ARPROT   ( inf.arprot   ), \
      .ARQOS    ( inf.arqos    ), \
      .ARREGION ( inf.arregion ), \
      .ARUSER   ( inf.aruser   ), \
      .ARVALID  ( inf.arvalid  ), \
      .ARREADY  ( inf.arready  ), \
      .RID      ( inf.rid      ), \
      .RLAST    ( inf.rlast    ), \
      .RDATA    ( inf.rdata    ), \
      .RRESP    ( inf.rresp    ), \
      .RUSER    ( inf.ruser    ), \
      .RVALID   ( inf.rvalid   ), \
      .RREADY   ( inf.rready   ), \
      .CACTIVE ( '0 ), \
      .CSYSREQ ( '0 ), \
      .CSYSACK ( '0 )  \
    );

`else
  `define ASSERT_AXIMM_INF(clk, rst, inf, name, not_ready_threshold=16) \
    greporter_pkg::build_warning bw``name = new("ASSERT", \
      {"AXI Memory Mapped assertions are not set up!", \
      "(Set up manual here: $(VIPS_DIR)/common/assertions/README.md)"}, \
      0, `__FILE__, `__LINE__);
`endif


`ifdef ASSERT_AXIL
  `include "Axi4LitePC.sv"

  `define ASSERT_AXIL_INF(clk, rst, inf, name, not_ready_threshold=16) \
    localparam int MaxWaits``name = not_ready_threshold ? not_ready_threshold : 1; \
    localparam bit RecMaxWaitOn``name = not_ready_threshold != 0; \
    Axi4LitePC #( \
      .DATA_WIDTH    ( inf.N * 8          ), \
      .MAXWAITS      ( MaxWaits``name     ), \
      .RecMaxWaitOn  ( RecMaxWaitOn``name ), \
      .ADDR_WIDTH    ( inf.A              )  \
    ) assert_``name (             \
      .ACLK     ( clk          ), \
      .ARESETn  ( !rst         ), \
      .AWADDR   ( inf.awaddr   ), \
      .AWPROT   ( inf.awprot   ), \
      .AWVALID  ( inf.awvalid  ), \
      .AWREADY  ( inf.awready  ), \
      .WDATA    ( inf.wdata    ), \
      .WSTRB    ( inf.wstrb    ), \
      .WVALID   ( inf.wvalid   ), \
      .WREADY   ( inf.wready   ), \
      .BRESP    ( inf.bresp    ), \
      .BVALID   ( inf.bvalid   ), \
      .BREADY   ( inf.bready   ), \
      .ARADDR   ( inf.araddr   ), \
      .ARPROT   ( inf.arprot   ), \
      .ARVALID  ( inf.arvalid  ), \
      .ARREADY  ( inf.arready  ), \
      .RDATA    ( inf.rdata    ), \
      .RRESP    ( inf.rresp    ), \
      .RVALID   ( inf.rvalid   ), \
      .RREADY   ( inf.rready   )  \
    );
`else
    `define ASSERT_AXIL_INF(clk, rst, inf, name, not_ready_threshold=16) \
      greporter_pkg::build_warning bw``name = new("ASSERT", \
        {"AXI Lite assertions are not set up!", \
        "(Set up manual here: $(VIPS_DIR)/common/assertions/README.md)"}, \
        0, `__FILE__, `__LINE__);
`endif

`ifdef ASSERT_AXIS
  `include "Axi4StreamPC.sv"

  `define ASSERT_AXIS_INF(clk, rst, inf, name, not_ready_threshold=16) \
    logic [inf.U_T_WIDTH-1:0] tuser_bits_``name;    \
    assign tuser_bits_``name = inf.tuser;           \
    localparam int MaxWaits``name = not_ready_threshold ? not_ready_threshold : 1; \
    localparam bit RecMaxWaitOn``name = not_ready_threshold != 0; \
    Axi4StreamPC #(                             \
      .DATA_WIDTH_BYTES ( inf.N              ), \
      .DEST_WIDTH       ( inf.D              ), \
      .ID_WIDTH         ( inf.I              ), \
      .USER_WIDTH       ( inf.U_T_WIDTH      ), \
      .MAXWAITS         ( MaxWaits``name     ), \
      .RecMaxWaitOn     ( RecMaxWaitOn``name )  \
    ) assert_``name (                           \
      .ACLK    ( clk               ),           \
      .ARESETn ( !rst              ),           \
      .TDATA   ( inf.tdata         ),           \
      .TSTRB   ( inf.tstrb         ),           \
      .TKEEP   ( inf.tkeep         ),           \
      .TLAST   ( inf.tlast         ),           \
      .TID     ( inf.tid           ),           \
      .TDEST   ( inf.tdest         ),           \
      .TUSER   ( tuser_bits_``name ),           \
      .TVALID  ( inf.tvalid        ),           \
      .TREADY  ( inf.tready        )            \
    );

`else
  string pwd = `__FILE__;
  `define ASSERT_AXIS_INF(clk, rst, inf, name) \
    greporter_pkg::build_warning bw``name = new("ASSERT", \
      {"AXI Stream assertions are not set up!", \
      "(Set up manual here: $(VIPS_DIR)/common/assertions/README.md)"}, \
      0, `__FILE__, `__LINE__);
`endif
