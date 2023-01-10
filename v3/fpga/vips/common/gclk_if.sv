/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/////////////////////
// Clock interface //
/////////////////////

// GVIPs uses this interface as clock and reset aggregator
interface gclk_if (
    input logic clk,
    input logic rst);
endinterface : gclk_if

