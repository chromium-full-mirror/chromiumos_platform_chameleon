/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package gaxim_pkg;
    parameter int BurstWidth = 2;
    parameter int ProtWidth = 3;
    parameter int CacheWidth = 4;
    parameter int RegionWidth = 4;
    parameter int SizeWidth = 3;

    typedef enum logic [BurstWidth-1:0] {
        kFixed = 2'b00,
        kIncr  = 2'b01,
        kWrap  = 2'b10,
        kRsvd  = 2'b11
    } burst_t;

    /* Below table is based on Table A3-2 Burst size encoding from ARM IHI 0022D document */
    typedef enum logic [SizeWidth-1:0] {
        kBytes1     = 3'b000,
        kBytes2     = 3'b001,
        kBytes4     = 3'b010,
        kBytes8     = 3'b011,
        kBytes16    = 3'b100,
        kBytes32    = 3'b101,
        kBytes64    = 3'b110,
        kBytes128   = 3'b111
    } burst_incr_size_t;

endpackage : gaxim_pkg
