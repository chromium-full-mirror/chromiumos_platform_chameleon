/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Configuration registers that shall be used across the project
 */

package config_registers_pkg;

`ifdef CFG_GUID
  parameter int unsigned GUID = `CFG_GUID;
`else
  parameter int unsigned GUID = 0;
`endif;

`ifdef CFG_CHIP_ID
  parameter int unsigned CHIP_ID = `CFG_CHIP_ID;
`else
  parameter int unsigned CHIP_ID = 0;
`endif;

  parameter int AddrWidth     = 'h8;

  typedef struct packed {
    logic gpio;
  } spi_t;

  localparam int AddrGitHash  = 'h0;
  localparam int AddrChipId   = 'h4;
  localparam int AddrSpiGpio  = 'h8;

endpackage : config_registers_pkg
