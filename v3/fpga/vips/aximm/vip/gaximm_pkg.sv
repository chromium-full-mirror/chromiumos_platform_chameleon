/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

///////////////////////////////////
// gaximm_pkg package definition //
///////////////////////////////////

// AMBA AXI Memory Mapped enums and constants
package gaximm_pkg;

  parameter LEN_WIDTH = 8;
  parameter SIZE_WIDTH = 3;
  parameter BURST_TYPE_WIDTH = 2;
  parameter LOCK_WIDTH = 2;
  parameter CACHE_WIDTH = 4;
  parameter PROT_WIDTH = 3;
  parameter QOS_WIDTH = 4;
  parameter REGION_WIDTH = 4;
  parameter RESP_WIDTH = 2;

  typedef enum logic [BURST_TYPE_WIDTH-1:0] {
    FIXED,
    INCR,
    WRAP,
    RESERVED
  } burst_type_e;

  typedef enum logic [RESP_WIDTH-1:0] {
    OKAY,
    EXOKAY,
    SLVERR,
    DECERR
  } resp_e;

endpackage : gaximm_pkg
