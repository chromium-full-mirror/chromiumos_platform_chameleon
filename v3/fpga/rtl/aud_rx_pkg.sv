/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package aud_rx_pkg;

  localparam SingleChannelWidth = 32;

  // Refer to CEA-861-D, table 17
  typedef enum logic [2:0] {
    kCCRefHdrStr = 0,
    k2ch         = 1,
    k3ch         = 2,
    k4ch         = 3,
    k5ch         = 4,
    k6ch         = 5,
    k7ch         = 6,
    k8ch         = 7
  } cc_e;

  // Refer to CEA-861-D, table 18
  typedef enum logic [1:0] {
    kSSRefHdrStr = 0,
    k16bit       = 1,
    k20bit       = 2,
    k24bit       = 3
  } ss_e;

  // Refer to CEA-861-D, table 18
  typedef enum logic [2:0] {
    kSFRefHdrStr = 0,
    k32kHz       = 1,
    k44_1kHz     = 2,
    k48kHz       = 3,
    k88_2kHz     = 4,
    k96kHz       = 5,
    k176_4kHz    = 6,
    k192kHz      = 7
  } sf_e;

endpackage : aud_rx_pkg
