SPDX-License-Identifier: BSD-3-Clause

Copyright 2023 The Chromium OS Authors
Use of this source code is governed by a BSD-style license that can be
found in the LICENSE file.

VIP for AMBA AXI-Stream interface


# File structure
 - vip - VIP files specyfic for AMBA AXI-Stream interface
   - gaxis_if.sv - RTL interface definition
   - gvip_axis_pkg.sv - Core class implementation. Use those methods to comunicate with VIP
   - gvip_axis_if.sv - Wrapper for VIP which simplifies VIP instantion
   - gvip_axis_array_if.sv - Wrapper for VIP which simplifies VIP instantion
   - gvip_axis_policy.svh - Policies specific for AMBA AXI-Stream interface
   - gvip_axis_item_pkg.sv - Defines items which could be send to vip and receive from it
   - gvip_axis_coverage.svh - Functional coverage for gaxis_if interface
   - gvip_axis_imp.svh - Internal VIP implementation
 - examples - examples which shows VIP's base functionality.
              Each test has its own Makefile.


# How to use
1. Use gaxis_if in the DUT. See examples directory as a reference
2. Get familiar with classes and functions from gvip_axis_pkg.sv file
3. To monitor transactions use one of the analysis ports interfaces
4. To send data use send_item task
5. To control tvalid/tready behaviour use policies and set_policy method
6. The easies way to start is to instantiate the gvip_axis_if interface and connect it
   to DUT. After that, one shall call .init function in gvip_axis_if,
   then call .core.run_phase
