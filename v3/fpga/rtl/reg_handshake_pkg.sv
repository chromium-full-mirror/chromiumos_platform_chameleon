/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package reg_handshake_pkg;
  parameter int RegTypeWidth = 2;

  typedef enum logic [RegTypeWidth-1:0] {
    kBypass = 0,
    kPayload = 1,
    kPayloadCtrl = 2
  } reg_type_e;

endpackage : reg_handshake_pkg
