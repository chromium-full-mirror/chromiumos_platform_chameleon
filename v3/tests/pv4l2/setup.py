# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from setuptools import Extension, setup

setup(
    ext_modules = [
        Extension(
            name = "pv4l2",
            sources = ["pv4l2.c"],
        ),
    ]
)
