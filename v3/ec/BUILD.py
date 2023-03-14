# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Zmake project configuration."""

# register_raw_project comes from zmake.
# pylint: disable=undefined-variable

register_raw_project(
    project_name="chameleon",
    zephyr_board="chameleon",
    modules=["hal_stm32", "nanopb", "pigweed"],
)
