# Copyright (c) 2013 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

SHELL := bash
VERSION := 0.0.2
CC := armv7a-cros-linux-gnueabihf-gcc
CFLAGS := -g -Wall -O2
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
IDENTITY_FILE := ~/trunk/src/scripts/mod_for_test_scripts/ssh_keys/testing_rsa
COMMIT_FILE := $(DISTDIR)/commit
PY_VERSION_FILE := $(DISTDIR)/py_version

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
	@echo python3 setup.py install -f
	@python3 setup.py install -f
else
	@echo python2 setup.py install -f
	@python setup.py install -f
endif

ifeq ($(PLATFORM), Chrome OS)
	@cp -f $(INITDIR)/$(CONFFILES) $(CONFDIR)
	@echo Installing chameleon package on chrome os platform is completed.
	@echo Please do \"\$ start chameleond\" or \"\$ restart chameleond\".
else
	@BUNDLE_VERSION=$(BUNDLE_VERSION) CHAMELEON_BOARD=$(CHAMELEON_BOARD) \
	deploy/deploy $(PLATFORM) $(PY_VERSION) $(NEEDS_SYSTEM_UPDATE)
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
	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -i $(IDENTITY_FILE) -p $(CHAMELEON_SSH_PORT) \
	    $(CHAMELEON_USER)@$(CHAMELEON_HOST) \
	    "cd /tmp && rm -rf $(BUNDLEDIR) && tar zxf $(BUNDLE) &&" \
	    "cd $(BUNDLEDIR) && find -exec touch -c {} \; &&" \
	    "make install " \
	        "REMOTE_INSTALL=TRUE" \
	        "HOST_NOW=\"$(HOST_NOW)\"" \
	        "BUNDLE_VERSION=$(BUNDLE_VERSION) " \
	        "CHAMELEON_BOARD=$(CHAMELEON_BOARD)"\
	        "PY_VERSION=$(PY_VERSION)"\
	        "NEEDS_SYSTEM_UPDATE=$(NEEDS_SYSTEM_UPDATE)"
else
	$(error CHAMELEON_HOST is undefined)
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
