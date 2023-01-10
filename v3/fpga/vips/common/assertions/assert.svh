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

`ifdef ASSERT_AXIS

  function void arm_amba4_pc_msg_err(string msg);
    greporter_pkg::greporter::error("SVA", msg);
  endfunction : arm_amba4_pc_msg_err

  function void arm_amba4_pc_msg_warn(string msg);
    greporter_pkg::greporter::warning("SVA", msg);
  endfunction : arm_amba4_pc_msg_warn

  `define ARM_AMBA4_PC_MSG_ERR arm_amba4_pc_msg_err
  `define ARM_AMBA4_PC_MSG_WARN arm_amba4_pc_msg_warn

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
