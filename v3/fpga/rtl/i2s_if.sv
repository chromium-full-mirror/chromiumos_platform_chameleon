/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

`ifndef __I2S_IF_SV__
`define __I2S_IF_SV__

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


`endif // __I2S_IF_SV__
