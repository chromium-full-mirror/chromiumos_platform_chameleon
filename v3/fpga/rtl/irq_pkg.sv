/*
 * Copyright 2022 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package irq_pkg;

  typedef enum logic [3:0] {
    kFb0        = 0, // Maps to offset 19 (51-32) in GICv3
    kI2sIt      = 1,
    kI2sSsm     = 2,
    kFbDpMst0   = 3,
    kFbDpMst1   = 4,
    kFbDpMst2   = 5,
    kFbDpMst3   = 6,
    kFbDpSst    = 7,
    kDpMstMgmt  = 8,
    kI2sDpMst0  = 9,
    kI2sDpMst1  = 10,
    kI2sDpMst2  = 11,
    kI2sDpMst3  = 12,
    kI2sDpSst   = 13,
    kDpSstMgmt  = 14
  } irq_source_e;

endpackage : irq_pkg
