/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package axis_to_aximm_pkg;

  typedef enum logic [2:0] {
    kIdIt68051Dma  = 3'b000,
    kIdSsm2603Dma  = 3'b001,
    kIdFb0Dma      = 3'b010,
    kIdFbDpMst02   = 3'b011,
    kIdFbDpMst13   = 3'b100,
    kIdFbDpSst     = 3'b101,
    kIdFbDpMstAud  = 3'b110,
    kIdFbDpSstAud  = 3'b111
  } ap_id_e;

  parameter int AddrWidth       = 32;
  parameter int DataWidth       = 16;
  parameter int Value4k         = 4096;
  parameter int Boundary4kWidth = $clog2(Value4k);

  typedef struct packed {
    logic [DataWidth-1:0] data_size;
    logic [AddrWidth-1:0] addr;
  } meta_t;

endpackage : axis_to_aximm_pkg
