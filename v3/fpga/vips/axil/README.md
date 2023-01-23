SPDX-License-Identifier: BSD-3-Clause

Copyright 2023 The Chromium OS Authors
Use of this source code is governed by a BSD-style license that can be
found in the LICENSE file.


VIP for AMBA AXI-Lite interface

# File structure
 - vip - VIP files specyfic for AMBA AXI-Lite interface
   - [gaxil_if.sv](vip/gaxil_if.sv) - RTL interface definition
   - [gvip_axil_pkg.sv](vip/gvip_axil_pkg.sv) - Core implementation.
                                                Use those methods to comunicate with VIP
   - [gvip_axil_types_pkg.sv](vip/gvip_axil_types_pkg.sv) - enum types used in core methods
   - [gvip_axil_if.sv](vip/gvip_axil_if.sv) - Wrapper for VIP which simplifies VIP instantion
   - [gvip_axil_item_pkg.sv](vip/gvip_axil_item_pkg.sv) - Defines items which could be send to
                                                          VIP and receive from it
   - [gvip_axil_imp.svh](vip/gvip_axil_imp.svh) - Internal VIP implementation
   - [gvip_axil_imp_ar.svh](vip/gvip_axil_imp_ar.svh) - Internal VIP components implementation
                                                        for AR channel
   - [gvip_axil_imp_aw.svh](vip/gvip_axil_imp_aw.svh) - Internal VIP components implementation
                                                        for AW channel
   - [gvip_axil_imp_w.svh](vip/gvip_axil_imp_w.svh) - Internal VIP components implementation
                                                      for W channel
   - [gvip_axil_imp_r.svh](vip/gvip_axil_imp_r.svh) - Internal VIP components implementation
                                                      for R channel
   - [gvip_axil_imp_b.svh](vip/gvip_axil_imp_b.svh) - Internal VIP components implementation
                                                      for B channel
   - [filelist.f](vip/filelist.f) - compilation file list, for proper compilation
                          [common/filelist.f](../common/filelist.f) is also requied
 - examples - examples which shows VIP's base functionality.


# How to use
1. Use *gaxil_if* in the DUT. See examples directory as a reference
2. Get familiar with classes and functions from gvip_axil_pkg.sv and gvip_axil_types_pkg.sv files
3. To monitor transactions use one of the analysis ports interfaces
4. To send data use send_item function
5. To control *valid/ready* behaviour use policies and set_policy method for each channel
6. The easiest way to start is to instantiate the gvip_axil_if interface and connect internal axil
   interface with DUT. Then in procedural block call *gvip_axil_if.init()* function
   (this will build required infrastructure) and run vip with *gvip_axil_if.core.run_phase()*
   method. More detailed description can be found in [test.sv](example/native/test.sv)
