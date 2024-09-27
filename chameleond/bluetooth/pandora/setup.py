# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Setup script for the pandora."""

import setuptools


setuptools.setup(
    name="pandora",
    packages=["pandora", "pandora_experimental"],
    package_dir={"": "./python"},
    description="AOSP bluetooth test interfaces",
)
