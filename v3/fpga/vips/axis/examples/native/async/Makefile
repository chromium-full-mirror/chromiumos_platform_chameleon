# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

TOP_NAME=test

ifeq ($(VIPS_DIR),)
  VIPS_DIR=$(shell dirname $(realpath \
    $(firstword $(MAKEFILE_LIST))))/../../../..
endif

include $(VIPS_DIR)/Makefile.common
FILELIST=$(TEST_DIR)/../filelist.f
export TEST_FILELIST_DIR=$(TEST_DIR)/..
VSIM_ARGS += -g ACK_TIME=0
XVLOG_ARGS= -d ACK_TIME=0

.DEFAULT_GOAL = all
.PHONY: all
all: test_native
