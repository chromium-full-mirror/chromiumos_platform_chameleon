#!/usr/bin/env python3
# Copyright 2022 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Super simple python script to talk to the EC using the proto.
Tip: Run it with: python -i connect.py
"""

import inspect
import pathlib
import pw_hdlc.rpc
import pw_protobuf_compiler
import serial

EC_SERIAL_PORT = "/dev/ttyS0"
EC_PROTO_PATH = (pathlib.Path(__file__)/"../v3.proto").resolve()
EC_PROTO = pw_protobuf_compiler.python_protos.Library.from_paths([EC_PROTO_PATH]).modules_by_package[""][0]

ec_serial = serial.Serial(EC_SERIAL_PORT, 115200, timeout=0.01)
ec_client = pw_hdlc.rpc.HdlcRpcClient(
  read = lambda: ec_serial.read(4096),
  paths_or_modules = [EC_PROTO],
  channels = pw_hdlc.rpc.default_channels(ec_serial.write),
)

for service in ec_client.rpcs():
  service_name = service._service.full_name
  print(f"{service_name} = {service!r}")
  globals()[service_name] = service
  for method_name in [m.name for m in service._service.methods]:
    print(f"\t.{method_name} = {inspect.signature(getattr(service, method_name))!r}")
print("EC_PROTO " + ' '.join("."+x for x in dir(EC_PROTO) if not x.startswith("_")))
