# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

TOP_NAME=test

ifeq ($(VIPS_DIR),)
  VIPS_DIR=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))/../../..
endif

include $(VIPS_DIR)/Makefile.common

.DEFAULT_GOAL = all
.PHONY: all
all: test_native
