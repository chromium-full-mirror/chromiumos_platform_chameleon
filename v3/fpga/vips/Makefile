# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

SHELL := bash


CURRENT_DIR=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

ifeq ($(TESTS_DIR),)
	TESTS_DIR=$(CURRENT_DIR)
endif

RESULTS?=results.log

export RESULTS_FILE=$(CURRENT_DIR)/$(RESULTS)

MAKEFILES_DIRS=$(shell find $(TESTS_DIR)/*/ -name "Makefile" \
  | sed 's/Makefile//g')

.DEFAULT_GOAL = all
.PHONY: all
all: test check

.PHONY: test
test:
	@source $(CURRENT_DIR)/settings.sh; \
	$(foreach var,$(MAKEFILES_DIRS),export TEST_DIR=$(var); make -s -C $(var);)

.PHONY: check
check:
	@rm -f $(RESULTS_FILE)
	@touch $(RESULTS_FILE)
	@source $(CURRENT_DIR)/settings.sh; \
	$(foreach var,$(MAKEFILES_DIRS),export TEST_DIR=$(var); \
	make -s -C $(var) check;)
	@cat $(RESULTS_FILE) | sed -E "s/PASSED/\o033[1;32mPASSED\o033[0m/g" \
	| sed -E "s/FAILED/\o033[1;31mFAILED\o033[0m/g"

.PHONY: clean
clean:
	@rm -f $(RESULTS_FILE)
	@source $(CURRENT_DIR)/settings.sh; \
	$(foreach var,$(MAKEFILES_DIRS),export TEST_DIR=$(var); \
	make -s -C $(var) clean;)
