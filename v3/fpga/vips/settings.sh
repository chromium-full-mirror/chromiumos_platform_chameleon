#!/bin/shell
# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

VIPS_DIR=$( cd -- "$( dirname -- \
  "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export VIPS_DIR
echo "VIPS_DIR: ${VIPS_DIR}"
