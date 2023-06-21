/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

interface i2c_i ();

  wire scl;
  wire sda;

  modport host (
    inout scl,
    inout sda
  );

  modport agent (
    inout scl,
    inout sda
  );
endinterface : i2c_i
