/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package i2s_pkg;
  parameter int I2sTxNum = 1;
  parameter int I2sRxSsm = 1;
  parameter int I2sRxIt  = 6;
  parameter int I2sRxNum = I2sRxIt + I2sRxSsm;
  parameter int I2sRxNumWidth = $clog2(I2sRxNum);
  parameter int I2sRxItNumWidth = $clog2(I2sRxIt);

  parameter int I2sMaxSampleWidth = 32;

  parameter int I2sMaxRingBytes = 2048;
  parameter int I2sMaxRingBytesWidth = $clog2(I2sMaxRingBytes);
  parameter int I2sRingAlignmentBytes = I2sMaxRingBytes;
  parameter int I2sRingAlignmentBytesWidth = $clog2(I2sRingAlignmentBytes);

  parameter int I2sAddressWidth = 32;

  parameter int ClkFrequencyMhz = 250;

  typedef struct packed {
    logic [I2sMaxSampleWidth-1:0] left;
    logic [I2sMaxSampleWidth-1:0] right;
  } sample_t;

  class tx_src;
    typedef enum logic [3:0] {
      kNone   = 4'd0,
      kRxSsm  = 4'd1,
      kRxIt0  = 4'd2,
      kRxIt1  = 4'd3,
      kRxIt2  = 4'd4,
      kRxIt3  = 4'd5,
      kRxIt4  = 4'd6,
      kRxIt5  = 4'd7,
      kTxHost = 4'd8
    } source_for_tx_e;
  endclass // tx_src

  class wr_src;
    typedef enum logic [3:0] {
      kNone   = 4'd0,
      kRxSsm  = 4'd1,
      kRxIt0  = 4'd2,
      kRxIt1  = 4'd3,
      kRxIt2  = 4'd4,
      kRxIt3  = 4'd5,
      kRxIt4  = 4'd6,
      kRxIt5  = 4'd7,
      kAllIt  = 4'd8,
      kAllRx  = 4'd9,
      kTxHost = 4'd10
    } source_for_writer_e;
  endclass // wr_src

  typedef struct packed {
    logic tx;
    logic rx;
  } irq_source_t;

endpackage : i2s_pkg
