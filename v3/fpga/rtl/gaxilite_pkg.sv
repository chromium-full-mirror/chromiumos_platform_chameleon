/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package gaxilite_pkg;

    parameter int AxiLiteRespWidth = 2;
    parameter int AddrWidth        = 32;
    parameter int DataWidth        = 32;
    parameter int StrbWidth        = DataWidth/8;

    typedef enum logic [AxiLiteRespWidth-1:0] {
        kOkay   = 2'b00,
        kExOkay = 2'b01,
        kSubErr = 2'b10,
        kDecErr = 2'b11
    } resp_t;

endpackage : gaxilite_pkg

