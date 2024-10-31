# Copyright 2013 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

SHELL := bash
VERSION := 0.0.2
CC := armv7a-cros-linux-gnueabihf-gcc
CFLAGS := -g -Wall -O2 -static
ifeq ($(PLATFORM), x86-generic)
	CC := gcc
endif
INCLUDES := -Iinclude
DESTDIR := /usr/bin
BINDIR := ./bin
SRCDIR := ./src
DISTDIR := ./dist
CONFDIR := /etc/init
INITDIR := ./deploy/init
EGGDIR := ./chameleond.egg-info
STREAM_SRCS = $(wildcard $(SRCDIR)/stream_server/*.c)
STREAM_OBJS = $(patsubst $(SRCDIR)/stream_server/*.c,$(BINDIR)/%.o,$(STREAM_SRCS))
CONFFILES = chameleond.conf
IDENTITY_FILE := ~/.ssh/testing_rsa  # follow https://chromium.googlesource.com/chromiumos/docs/+/main/developer_guide.md#set-up-ssh-connection-between-chroot-and-dut
COMMIT_FILE := $(DISTDIR)/commit
PY_VERSION_FILE := $(DISTDIR)/py_version
CHAMELEOND_DIR := /usr/bin

BLUETOOTH_GRPC_ROOT_DIR := /tmp/bluetooth_grpc
PANDORA_STABLE_VERSION := 0.0.6
PANDORA_TMP_DIR := ${BLUETOOTH_GRPC_ROOT_DIR}/bt-test-interfaces-${PANDORA_STABLE_VERSION}
PANDORA_EXPERIMENTAL_VERSION := 0.0.0
PANDORA_EXPERIMENTAL_TMP_DIR := ${BLUETOOTH_GRPC_ROOT_DIR}/pandora-experimental-${PANDORA_EXPERIMENTAL_VERSION}
BLUESHIP_VERSION := 0.0.0
BLUESHIP_TMP_DIR := ${BLUETOOTH_GRPC_ROOT_DIR}/blueship-${BLUESHIP_VERSION}


# Set python3 as default after all teams using chameleon finish switching
# to python3.
PY_VERSION := python3

TARGETS = check_git_tree_clean directories chameleond

COMMIT = $(shell git log HEAD^..HEAD --pretty=format:"%h")

.PHONY: all
all: $(TARGETS)

.PHONY: check_git_tree_clean
check_git_tree_clean:
	@if [ -n "$(shell git status --porcelain)" ]; then \
	    echo "Git work tree should be clean."; \
	    echo "Please commit your changes and make chameleon in order to" \
	         "keep a record in the commit history on chameleon hosts."; \
	    exit 1; \
	fi

.PHONY: check_git_commit_HEAD
check_git_commit_HEAD:
	@if [ $(COMMIT) != $(shell cat $(COMMIT_FILE))  ]; then \
	    echo "Your commit HEAD is different from that in the" \
	         "chameleon bundle."; \
	    echo "Please re-make chameleon again."; \
	    exit 1; \
	fi

.PHONY: directories
directories:
	@mkdir -p $(BINDIR)
	@mkdir -p $(DISTDIR)

BINARIES = $(BINDIR)/histogram $(BINDIR)/hpd_control $(BINDIR)/pixeldump \
	  $(BINDIR)/avsync $(BINDIR)/stream_server $(BINDIR)/printer

.PHONY: binaries
binaries: $(BINARIES)

.PHONY: chameleond
chameleond: binaries
	@echo $(COMMIT) > $(COMMIT_FILE)
	@echo $(PY_VERSION) > $(PY_VERSION_FILE)

ifeq ($(PY_VERSION), python3)
	@echo PY_VERSION: $(PY_VERSION)
	@echo python3 setup.py sdist
	@python3 setup.py sdist
else
	@echo PY_VERSION: $(PY_VERSION)
	@echo python2 setup.py sdist
	@python setup.py sdist
endif

$(BINDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(BINDIR)/%: $(BINDIR)/%.o
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ $^

$(BINDIR)/stream_server.o: $(SRCDIR)/stream_server/%.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(BINDIR)/stream_server: $(STREAM_OBJS)
	$(CC) $(CFLAGS) -lpthread $(INCLUDES) -o $@ $^


BUNDLE_VERSION ?= '9999'
CHAMELEON_BOARD ?= 'fpga_tio'
# Get current time from the host.
HOST_NOW := `date "+%Y-%m-%d %H:%M:%S"`

# If this is a Chrome OS platform, PLATFORM would be 'Chrome OS'.
#     The '$' symbol in awk has to be doubled in Makefile.
# else if this is a raspberry pi, PLATFORM would be 'raspberrypi'.
PLATFORM = $(shell awk -F= '/CHROMEOS_RELEASE_NAME/ {print $$2}' \
	     /etc/lsb-release 2>/dev/null || cat /etc/hostname)

# Valid value: true / false.
NEEDS_SYSTEM_UPDATE ?= 'false'

ifndef INSTALL_GRPC
	INSTALL_GRPC := false
endif

SETUP_SUFFIX =
ifeq ($(PLATFORM), cyclone5)
	SETUP_SUFFIX = --cyclone5
endif
ifeq ($(INSTALL_GRPC), true)
	SETUP_SUFFIX += --grpc
endif



.PHONY: install
install:
	@mkdir -p $(DESTDIR)
	@cp -f $(BINARIES) "$(DESTDIR)"
ifeq ($(REMOTE_INSTALL), TRUE)
	@echo sync time with host...
	@NOW="$(HOST_NOW)" PY_VERSION="$(PY_VERSION)" PLATFORM="$(PLATFORM)" \
		sh deploy/deploy_pip
else
	@echo sync time with the chameleon mirror server...
	@NOW="`chameleond/utils/server_time`" PY_VERSION="$(PY_VERSION)" \
		PLATFORM="$(PLATFORM)" sh deploy/deploy_pip
endif

ifeq ($(PY_VERSION), python3)
	# Ensure that the scripts are installed under CHAMELEOND_DIR (/usr/bin).
	# Otherwise, the installation path might vary unpredictably between
	# /usr/bin and /usr/local/bin.
	# This path aligns with the CHAMELEOND_DIR in deploy/deploy.
	@echo python3 setup.py install -f $(SETUP_SUFFIX) \
		--install-scripts=$(CHAMELEOND_DIR)
	@python3 setup.py install -f $(SETUP_SUFFIX) \
		--install-scripts=$(CHAMELEOND_DIR)
else
	@echo python2 setup.py install -f $(SETUP_SUFFIX)
	@python setup.py install -f $(SETUP_SUFFIX)
endif

ifeq ($(PLATFORM), Chrome OS)
	@cp -f $(INITDIR)/$(CONFFILES) $(CONFDIR)
	@echo Installing chameleon package on chrome os platform is completed.
	@echo Please do \"\$ start chameleond\" or \"\$ restart chameleond\".
else
	@BUNDLE_VERSION=$(BUNDLE_VERSION) CHAMELEON_BOARD=$(CHAMELEON_BOARD) \
	deploy/deploy $(PLATFORM) $(PY_VERSION) $(NEEDS_SYSTEM_UPDATE) \
	$(CHAMELEOND_DIR)
	@echo Installing chameleon package on $(PLATFORM) platform is completed.
endif

CHAMELEON_USER ?= root
# Allow users to override the SSH port to allow remote installs to devices
# that use a non-standard SSH port. This includes devices forwarded using SSH
# port forwarding, or for devices exposed to the internet using router port
# forwarding.
CHAMELEON_SSH_PORT ?= 22
BUNDLE = chameleond-$(VERSION).tar.gz
BUNDLEDIR = chameleond-$(VERSION)

define get_chameleon_hostname
$(shell ssh -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -i $(IDENTITY_FILE) -p $(CHAMELEON_SSH_PORT) \
      $(CHAMELEON_USER)@$(CHAMELEON_HOST) \
      "cat /etc/hostname")
endef

ifdef CHAMELEON_HOST
	CHAMELEON_HOSTNAME := $(call get_chameleon_hostname)
endif

.PHONY: check_pi_make
check_pi_make:
ifeq ($(CHAMELEON_HOSTNAME), raspberrypi)
	$(eval PY_VERSION := python3)
	@if [ $(shell cat $(PY_VERSION_FILE)) != $(PY_VERSION) ]; then \
	    echo "Raspberry Pi has switched to python3."; \
	    echo "You need to explicitly make with python3 for Raspberry" \
	     "Pi now until all other platforms have switched to python3" \
	     "as well."; \
	    echo; \
	    echo "Please make with python3 and then install as"; \
	    echo "(cr) $$ make PY_VERSION=python3"; \
	    echo '(cr) $$ make remote-install' \
	        'CHAMELEON_HOST=$$RASPBERRY_IP'; \
	    echo; \
	    exit 1; \
	fi;
endif

.PHONY: remote-install
remote-install: check_git_tree_clean check_git_commit_HEAD check_pi_make
	@echo "Set bundle version to $(BUNDLE_VERSION)"
	@echo "Set bundle commit to $(COMMIT)"
	@echo "Set board to $(CHAMELEON_BOARD)"
	@echo "Current host time: $(HOST_NOW)"
	@echo "Python version: $(PY_VERSION)"
ifdef CHAMELEON_HOST
	@scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -i $(IDENTITY_FILE) -P $(CHAMELEON_SSH_PORT) \
	    $(DISTDIR)/$(BUNDLE) $(CHAMELEON_USER)@$(CHAMELEON_HOST):/tmp
else
	$(error CHAMELEON_HOST is undefined)
endif

ifeq ($(INSTALL_GRPC), true)
#	Recreate the caching directory to ensure a fresh start.
	rm -rf $(BLUETOOTH_GRPC_ROOT_DIR)
	mkdir $(BLUETOOTH_GRPC_ROOT_DIR)
	mkdir -p ${PANDORA_TMP_DIR}
	mkdir -p ${BLUESHIP_TMP_DIR}
	mkdir -p ${PANDORA_EXPERIMENTAL_TMP_DIR}
#	Download the pandora repo from the archive.
	wget https://github.com/google/bt-test-interfaces/archive/v\
	$(PANDORA_STABLE_VERSION).tar.gz -P /tmp
# 	Extract the downloaded archive into a temporary directory.
#	--strip-components=1 removes the top-level directory from the archive
	tar -xvzf /tmp/v$(PANDORA_STABLE_VERSION).tar.gz -C $(PANDORA_TMP_DIR) --strip-components=1
# 	Copy all protos to the temporary directory
	cp -r ./chameleond/bluetooth_grpc/pandora_experimental/interface $(PANDORA_EXPERIMENTAL_TMP_DIR)/pandora_experimental
	cp -r ./chameleond/bluetooth_grpc/blueship/interface $(BLUESHIP_TMP_DIR)/blueship
# 	Copy necessary tools for installing package to the temporary directory
	cp ./chameleond/bluetooth_grpc/setup.py $(BLUETOOTH_GRPC_ROOT_DIR)/
	cp ./chameleond/bluetooth_grpc/protoc-gen-custom_grpc $(BLUETOOTH_GRPC_ROOT_DIR)/
	cp -r ./chameleond/bluetooth_grpc/python $(BLUETOOTH_GRPC_ROOT_DIR)
#	Move the python files of stable pandora to the root python directory
	mv ${PANDORA_TMP_DIR}/python/pandora ${BLUETOOTH_GRPC_ROOT_DIR}/python

	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -i $(IDENTITY_FILE) -p $(CHAMELEON_SSH_PORT) \
	    $(CHAMELEON_USER)@$(CHAMELEON_HOST) \
	    "rm -rf $(BLUETOOTH_GRPC_ROOT_DIR)"

	@scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -i $(IDENTITY_FILE) -P $(CHAMELEON_SSH_PORT) \
	    $(BLUETOOTH_GRPC_ROOT_DIR) $(CHAMELEON_USER)@$(CHAMELEON_HOST):/tmp

	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -i $(IDENTITY_FILE) -p $(CHAMELEON_SSH_PORT) \
	    $(CHAMELEON_USER)@$(CHAMELEON_HOST) \
	    "cd /tmp && rm -rf $(BUNDLEDIR) && tar zxf $(BUNDLE) &&" \
	    "cd $(BUNDLEDIR) && find -exec touch -c {} \; &&" \
	    "make install " \
	        "REMOTE_INSTALL=TRUE" \
	        "HOST_NOW=\"$(HOST_NOW)\"" \
	        "BUNDLE_VERSION=$(BUNDLE_VERSION)" \
	        "CHAMELEON_BOARD=$(CHAMELEON_BOARD)"\
	        "PY_VERSION=$(PY_VERSION)"\
	        "NEEDS_SYSTEM_UPDATE=$(NEEDS_SYSTEM_UPDATE)"\
		"INSTALL_GRPC=$(INSTALL_GRPC)"\
		"BLUETOOTH_GRPC_ROOT_DIR=${BLUETOOTH_GRPC_ROOT_DIR}"\
		"PANDORA_TMP_DIR=$(PANDORA_TMP_DIR)"\
		"PANDORA_EXPERIMENTAL_TMP_DIR=${PANDORA_EXPERIMENTAL_TMP_DIR}"\
		"BLUESHIP_TMP_DIR=${BLUESHIP_TMP_DIR}"
else
	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -i $(IDENTITY_FILE) -p $(CHAMELEON_SSH_PORT) \
	    $(CHAMELEON_USER)@$(CHAMELEON_HOST) \
	    "cd /tmp && rm -rf $(BUNDLEDIR) && tar zxf $(BUNDLE) &&" \
	    "cd $(BUNDLEDIR) && find -exec touch -c {} \; &&" \
	    "make install " \
	        "REMOTE_INSTALL=TRUE" \
	        "HOST_NOW=\"$(HOST_NOW)\"" \
	        "BUNDLE_VERSION=$(BUNDLE_VERSION)" \
	        "CHAMELEON_BOARD=$(CHAMELEON_BOARD)"\
	        "PY_VERSION=$(PY_VERSION)"\
	        "NEEDS_SYSTEM_UPDATE=$(NEEDS_SYSTEM_UPDATE)"
endif

.PHONY: setup-usb-audio-testbed
setup-usb-audio-testbed:
ifeq ($(CHAMELEON_HOSTNAME), raspberrypi)
	@echo Setup raspberry pi: Enable USB gadget mode.
	sh deploy/setup_raspberrypi_as_usb_gadget $(CHAMELEON_HOST)
	@echo Setup usb audio testbed on $(CHAMELEON_HOST) is completed.
	@echo The raspberry pi will be ready after reboot.
endif

.PHONY: clean
clean:
	@rm -rf $(BINDIR) $(DISTDIR) $(EGGDIR)

PYLINTRC = $(CROS_WORKON_SRCROOT)/chromite/pylintrc
PYLINT_OPTIONS = \
	--rcfile=$(PYLINTRC) \
	--disable=R0921,R0922,R0923,R9100

LINT_FILES = $(shell find -name '*.py' -type f | sort)
LINT_BLOCKLIST =
LINT_ALLOWLIST = $(filter-out $(LINT_BLOCKLIST),$(LINT_FILES))

lint:
	@set -e -o pipefail; \
	out=$$(mktemp); \
	echo Linting $(shell echo $(LINT_ALLOWLIST) | wc -w) files...; \
	if [ -n "$(LINT_ALLOWLIST)" ] && \
	    ! env \
	    PYTHONPATH=.:chameleond:../chameleon-private:../video-chameleon \
	    pylint $(PYLINT_OPTIONS) $(LINT_ALLOWLIST) \
	    |& tee $$out; then \
	  echo; \
	  echo To re-lint failed files, run:; \
	  echo make lint LINT_ALLOWLIST=\""$$( \
	    grep '^\*' $$out | cut -c22- | tr . / | \
	    sed 's/$$/.py/' | tr '\n' ' ' | sed -e 's/ $$//')"\"; \
	  echo; \
	  rm -f $$out; \
	  exit 1; \
	fi; \
	echo ...no lint errors! You are awesome!; \
	rm -f $$out

PRESUBMIT_FILES := $(if $(PRESUBMIT_FILES),\
	             $(shell realpath --relative-to=. $$PRESUBMIT_FILES))

lint-presubmit:
	$(MAKE) lint \
	    LINT_FILES="$(filter %.py,$(PRESUBMIT_FILES))" \
	    2>/dev/null

chroot-presubmit:
	if [ ! -e /etc/debian_chroot ]; then \
	    echo "This script must be run inside the chroot. Run this first:"; \
	    echo "    cros_sdk"; \
	    exit 1; \
	fi
