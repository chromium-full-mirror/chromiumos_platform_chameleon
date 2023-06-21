# Copyright 2021 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Default build is for 480K FPGA (development)
FPGA_KLUT_COUNT?=480
FPGA_SPEED_GRADE?=2
FPGA_CHIP?=$(FPGA_KLUT_COUNT)-$(FPGA_SPEED_GRADE)

# Output name
NAME = $(shell git describe --tags --long --dirty)-$(FPGA_CHIP)

# Set to build a bitstream with debug
STP_DEBUG_FILE?=

# Set to build a bitstream with Early I/O Release
EARLY_IO_RELEASE?=0

# Set to create project but do not build bitstream
# This would create Quartus project files
SKIP_COMPILE?=0

# TCL script arguments
TCL_ARGS = --device $(FPGA_CHIP) --name $(NAME)

CPF_ARGS = -o bitstream_compression=on --no_banner -c

# VIPs directory
CHAMELEON_VIPS_DIR = $(PWD)/../../../chameleon/v3/fpga/vips

# svunit arguments
SVUNIT_ARGS = -s questa -o out -c "-sv -timescale 1ns/1ps" \
	      -r "-voptargs=+acc -L altera_mf_ver"

ifneq ($(STP_DEBUG_FILE),)
	TCL_ARGS += --debug $(STP_DEBUG_FILE)
endif

ITS_BASE = v3

ifeq ($(EARLY_IO_RELEASE),1)
	TCL_ARGS += --early
	CPF_ARGS += --hps
	RBFS = $(NAME).periph.rbf $(NAME).core.rbf
	ITS = u-boot/$(ITS_BASE)_core_periph.its
else
	RBFS = $(NAME).rbf
	ITS = u-boot/$(ITS_BASE)_full.its
endif

ifeq ($(SKIP_COMPILE),1)
	TCL_ARGS += --skip-compile
endif

.DEFAULT_GOAL = all
.PHONY: all
all: tests bitstream

# Run all tests
.PHONY: tests
tests:
	export CHAMELEON_DIR=$(PWD); \
	export CHAMELEON_VIPS_DIR=$(CHAMELEON_VIPS_DIR); \
	source $(CHAMELEON_VIPS_DIR)/settings.sh; \
	cd sim/utests; \
	runSVUnit $(SVUNIT_ARGS)

# Run single test
test_%:
	export CHAMELEON_DIR=$(PWD); \
	export CHAMELEON_VIPS_DIR=$(CHAMELEON_VIPS_DIR); \
	source $(CHAMELEON_VIPS_DIR)/settings.sh; \
	cd sim/utests; \
	runSVUnit $(SVUNIT_ARGS) -t $*_unit_test.sv

# Bitstream artifacts
$(NAME).sof $(NAME)_hps.xml:
	$(QUARTUS_PATH)/bin/quartus_sh -t create_bitstream.tcl $(TCL_ARGS) || (exit 1)

$(RBFS): $(NAME).sof
	$(QUARTUS_PATH)/bin/quartus_cpf $(CPF_ARGS) $< $(NAME).rbf

$(NAME).itb: $(RBFS) $(ITS)
	sed s/NAME/$(NAME)/ $(ITS) > u-boot/$(ITS_BASE)_gen.its
	mkimage -E -f u-boot/$(ITS_BASE)_gen.its $@

# Generate and check handoff
$(NAME)_handoff.h: $(NAME)_hps.xml u-boot/qts-filter-a10.sh
	u-boot/qts-filter-a10.sh $< $@

.PHONY: check_handoff
check_handoff: u-boot/v3_$(FPGA_CHIP)_handoff.h $(NAME)_handoff.h
	@diff $^ || printf \
	'\033[31mWARNING: Handoff file changed! U-Boot rebuild required!\033[0m\n'

.PHONY: bitstream
bitstream: $(NAME).itb check_handoff

.PHONY: program
program: $(NAME).sof
	$(QUARTUS_PATH)/bin/quartus_pgm --no_banner --mode=jtag -o "P;$<"

.PHONY: clean
clean:
	-rm -rf *.itb
	-rm -rf *.rbf
	-rm -rf *.sof
	-rm -rf *_hps.xml
	-rm -rf *_handoff.h
	-rm -rf u-boot/*_gen.its
	-rm -rf qdb/*
	-rm -rf qsys/*/ap
	-rm -rf qsys/*/ip/ap/*/
	-rm -rf cocotb/results.xml
	-rm -rf quartus_project_*
	-rm -rf qsys/*/ip/hdmi_rx/*/
	-rm -rf qsys/*/ip/gxb_hdmi_rx/*/
	-rm -rf qsys/*/ip/gxb_dp_rx/*/
	-rm -rf qsys/*/ip/dp_rx/*/

.PHONY: help
help:
	@echo "Targets:"
	@echo "  all (default)    - Run tests and bitstream"
	@echo "  bitstream        - Generate bitstream (.itb), and run check_handoff"
	@echo "  check_handoff    - Generate handoff header and check it against the matching one in u-boot/"
	@echo "  tests            - Run all tests"
	@echo "  test_%           - Run a single test (e.g. make test_config_registers)"
	@echo "  clean            - Remove generated files"
	@echo "  help             - Print this help"
	@echo "Variables:"
	@echo "  FPGA_CHIP        - Target device. Available devices: 480-2 (default), 270-2, 270-3"
	@echo "  STP_DEBUG_FILE   - Signal Tap Logic Analyzer file to be used for debug"
	@echo "  EARLY_IO_RELEASE - Enable early i/o release"
	@echo "  SKIP_COMPILE     - Generate project files, but don't compile the bitstream"
