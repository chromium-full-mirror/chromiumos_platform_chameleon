/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package gvip_aximm_types_pkg;

  class gvip;

    // Enum: type_e
    //
    // This is used as VIP type choose
    // MASTER  - VIP initiates transactions on AR/AW/W channels
    // SLAVE   - VIP initiates transactions on R/B channels
    // MONITOR - VIP only observe channels and report transactions with analysis port
    //
    typedef enum logic [1:0] {
      MASTER,
      SLAVE,
      MONITOR
    } type_e;


    typedef enum bit [2:0] {
      AW,   // Write address channel
      W,    // Write data channel
      AW_W, // Write address with data
      B,    // Write response channel
      AR,   // Read address channel
      R     // Read data channel
    } channel_e;

  endclass : gvip

endpackage : gvip_aximm_types_pkg
