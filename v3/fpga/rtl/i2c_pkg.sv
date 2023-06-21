/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package i2c_pkg;

  typedef struct packed {
    logic scl_i;
    logic scl_oe;
    logic sda_i;
    logic sda_oe;
  } i2c_buf_t;

endpackage : i2c_pkg
