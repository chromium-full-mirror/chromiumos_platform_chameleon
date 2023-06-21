/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

interface avalon_mm_i #(
    parameter int AddrWidth       = 32,
    parameter int DataWidth       = 32,
    parameter int BurstCountWidth = 1
) ();

  logic                       cs;
  logic [AddrWidth-1:0]       address;
  logic [DataWidth/8-1:0]     byteenable;
  logic                       read;
  logic                       readdatavalid;
  logic [DataWidth-1:0]       readdata;
  logic                       write;
  logic                       waitrequest;
  logic [DataWidth-1:0]       writedata;
  logic [BurstCountWidth-1:0] burstcount;

  modport host (
    output cs,
    output address,
    output byteenable,
    output read,
    input  readdatavalid,
    input  readdata,
    output write,
    input  waitrequest,
    output writedata,
    output burstcount
  );

  modport agent (
    input  cs,
    input  address,
    input  byteenable,
    input  read,
    output readdatavalid,
    output readdata,
    input  write,
    output waitrequest,
    input  writedata,
    input  burstcount
  );

endinterface : avalon_mm_i
