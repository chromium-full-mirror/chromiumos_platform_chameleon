# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# AXI Stream protocol check assertions

### Set up manual

1. Download AXI Stream assertions from this link: https://developer.arm.com/downloads/view/BP063 (you'll need to log in).
2. Extract downloaded file.
3. Copy `sva` folder to `TOP_DIR/common/assertions/`

### Using assertions during tests
While running tests set `ASSERT` (`make ASSERT=1`)
