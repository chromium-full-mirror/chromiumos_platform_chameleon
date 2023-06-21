/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */


/*
 * Those guards are for for convenience of compilation
 * We deliver i2s_vip as whole, together with interface and file list
 * but this is obvious that in design file list must be also this interface
 * so for protect overriding guards are used
 */
`ifndef __SH_I2S_IF_SV__
`define __SH_I2S_IF_SV__

interface i2s_if ();
  logic clk;
  logic ws;
  logic data;

  modport transmitter(
    input  clk,
    input  ws,
    output data
  );

  modport receiver(
    input clk,
    input ws,
    input data
  );

endinterface : i2s_if

`endif // __SH_I2S_IF_SV__
