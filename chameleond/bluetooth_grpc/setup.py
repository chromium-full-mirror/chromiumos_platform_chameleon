# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Setup script for the pandora."""

import setuptools


setuptools.setup(
    name="bluetooth_grpc",
    packages=["pandora", "pandora_experimental"],
    package_dir={"": "./python"},
    description="Bluetooth test gRPC interfaces",
)
