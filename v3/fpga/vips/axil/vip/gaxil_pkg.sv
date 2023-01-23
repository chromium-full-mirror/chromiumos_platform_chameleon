/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

///////////////////////////////////
// gaxil_pkg package definition //
///////////////////////////////////

// AMBA AXI Lite enums and constants
package gaxil_pkg;

  parameter PROT_WIDTH = 3;
  parameter RESP_WIDTH = 2;

  typedef enum logic [RESP_WIDTH-1:0] {
    OKAY,
    EXOKAY,
    SLVERR,
    DECERR
  } resp_e;

endpackage : gaxil_pkg
