/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

interface axis_i #(
    parameter int UserWidth = 1,
    type Tuser = logic [UserWidth-1:0],
    parameter int DataWidth = 512,
    type Tdata = logic [DataWidth-1:0],
    parameter int WordWidth = 32,
    parameter int KeepWidth = $bits(Tdata)/WordWidth,
    type Tkeep = logic [KeepWidth-1:0],
    // add this parameters as workaround for Quartus bug
    // if use construct such a $bits(Tdata) outside interface
    // Quartus return 1 width of Tdata
    parameter int TdataWidth = $bits(Tdata),
    parameter int TuserWidth = $bits(Tuser),
    parameter int TkeepWidth = $bits(Tkeep)
) ();
    logic tvalid;
    logic tready;
    Tdata tdata;
    Tkeep tkeep;
    Tuser tuser;
    logic tlast;

    modport host (
        output tdata,
        output tkeep,
        output tlast,
        input  tready,
        output tuser,
        output tvalid
    );

    modport agent (
        input  tdata,
        input  tkeep,
        input  tlast,
        output tready,
        input  tuser,
        input  tvalid
    );

    modport monitor (
        input  tdata,
        input  tkeep,
        input  tlast,
        input  tready,
        input  tuser,
        input  tvalid
    );

    modport driver (
        output tdata,
        output tkeep,
        output tlast,
        output tready,
        output tuser,
        output tvalid
    );

endinterface : axis_i
