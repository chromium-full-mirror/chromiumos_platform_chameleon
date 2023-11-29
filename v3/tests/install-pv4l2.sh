#!/bin/bash
# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

python3 -m pip install --user --force-reinstall --ignore-installed --no-binary :all: pv4l2/ --break-system-packages
