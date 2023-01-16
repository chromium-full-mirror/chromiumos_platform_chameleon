SPDX-License-Identifier: BSD-3-Clause

Copyright 2023 The Chromium OS Authors
Use of this source code is governed by a BSD-style license that can be
found in the LICENSE file.

VIPs are design to simplify testing modules with standard interfaces
such a AMBA AXI-Stream and AMBA AXI-MemoryMaped which uses handshake to
accept transactions.

# File structure
 - common - packages and classes with are common for vips
   - gvip_policy_pkg.sv - handshake policies which could be used in tests
   - greporter_pkg.sv - implementation of reporting mechanism
   - svunit_greporter_pkg.sv - global reporter implementation for SvUnit environment
   - gvip_handshake_pkg.sv - handshake class implementation. It is vip's base functionality.
   - gclk_if.sv - clock and reset aggregator
   - assertions - directory contains README with usage instructions
 - axis - directory with vip files and examples for AMBA AXI-Stream interface
 - filelist.f - global filelist which has connected all filelist from all vips
 - Makefile - can be used to run test from all Makefiles in the examples
 - Makefile.common - common instructions for example's Makefiles
 - settings.sh - script which sets the enviorment
 - README.md - this file


# Configuration
1. Set VIPS_DIR enviorment variable. This can be done by sourcing settings.sh script
2. To compile VIPs use filelist.f filelist.


# How to use
Each vip for each interface has its own README with detail description
but general way is to instantiate gvip_*_if interface. In it there is
instantiation of the RTL interface (which should be connected to DUT) and
vip core class instantiation. Use core's methodts to drive interface's
signals and to monitor them.
