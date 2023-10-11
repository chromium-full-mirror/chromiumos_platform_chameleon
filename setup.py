# Copyright 2014 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Setup script to distribute and install Chameleond library and scripts."""

import sys

# Needs to import setup from setuptools instead of distutils.core
# in order to use the install_requires argument.
# To install setuptools on Debian:
# sudo apt-get install python3-setuptool
from setuptools import setup


install_requires = ["pyserial", "schedule", "future"]

# cryptography is for bluetooth only, which is not required on cyclone5
# platform.
if "--cyclone5" not in sys.argv:
    install_requires += ["cryptography==2.6.1"]
else:
    sys.argv.remove("--cyclone5")

setup(
    name="chameleond",
    version="0.0.2",
    packages=[
        "chameleond",
        "chameleond.devices",
        "chameleond.drivers",
        "chameleond.utils",
    ],
    package_data={
        "chameleond": [
            "data/*.bin",
            "data/*.bitmap",
            "utils/*.xml",
            "utils/*.conf",
            "utils/data/*/*",
        ]
    },
    url="http://www.chromium.org",
    maintainer="The ChromiumOS Authors",
    maintainer_email="chromium-os-dev@chromium.org",
    license="Chromium",
    description="Server to communicate and control Chameleon board.",
    long_description="Server to communicate and control Chameleon board.",
    install_requires=install_requires,
    scripts=[
        "utils/lock_u_boot_console",
        "utils/run_chameleond",
        "utils/run_displayd",
        "utils/run_stream_server",
        "chameleond/utils/server_time",
        "utils/run_scheduler",
        "utils/run_chameleon_updater",
        "utils/check_audiobox_jackplugger",
    ],
)
