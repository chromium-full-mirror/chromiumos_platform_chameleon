#!/usr/bin/env python3
# Copyright 2022 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Super simple python script to talk to the EC using the proto.
Tip: Run it with: python -i connect.py
"""

import pathlib
from pw_hdlc.rpc import HdlcRpcClient, default_channels
import serial

EC_SERIAL_PORT = "/dev/ttyS0"
EC_PROTO = (pathlib.Path(__file__)/"../v3.proto").resolve()

ec_serial = serial.Serial(EC_SERIAL_PORT, 115200, timeout=0.01)
ec_client = HdlcRpcClient(
  read = lambda: ec_serial.read(4096),
  paths_or_modules = [EC_PROTO],
  channels = default_channels(ec_serial.write),
  #channels = default_channels(lambda b: print(f"write_callback({b!r})"))),
)

for service in ec_client.rpcs():
  service_name = service._service.full_name
  print(f"{service_name} = {service!r}")
  globals()[service_name] = service
