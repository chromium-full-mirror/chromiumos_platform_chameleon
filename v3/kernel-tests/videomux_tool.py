#!/usr/bin/env python3
# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""
Tool to change videomux settings without chameleond running
"""

import argparse
import pathlib
import pw_hdlc.rpc
import pw_protobuf_compiler
import pw_rpc.callback_client.errors
import serial
import sys
import xmlrpc.client

EC_PROTO_PATH = (pathlib.Path(__file__)/"../../../v3/ec/proto/v3.proto").resolve()
EC_PROTO = pw_protobuf_compiler.python_protos.Library.from_paths([EC_PROTO_PATH]).modules_by_package[""][0]
EC_SERIAL_PORT = "/dev/ttyS0"


class EcPgClient:
  """
  EC client for Pigweed RPC.
  """
  def __init__(self, dev):
    self.ec_serial = serial.Serial(dev, 115200, timeout=0.01)
    callback_client_impl = pw_hdlc.rpc.callback_client.Impl(
      default_unary_timeout_s=1.0,
      default_stream_timeout_s=1.0,
    )
    self.ec_client = pw_hdlc.rpc.HdlcRpcClient(
      read = lambda: self.ec_serial.read(4096),
      paths_or_modules = [EC_PROTO],
      channels = pw_hdlc.rpc.default_channels(self.ec_serial.write),
      client_impl = callback_client_impl,
    )
    self.videomux_service = self.ec_client.rpcs()["videomux_service"]

  def videomux_off(self):
    status, _ = self.videomux_service.all_off()
    if not status.ok():
      raise pw_rpc.callback_client.errors.RpcError(self.videomux_service.all_off, status)

  def videomux_set(self, port, direction):
    status, resp = self.videomux_service.set(**{port: direction})
    if not status.ok():
      raise pw_rpc.callback_client.errors.RpcError(self.videomux_service.set, status)
    return resp


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--off", action='store_true',
                      help="Disable all ports before connecting any")
  parser.add_argument("--port", type=str.lower, choices=['dp1', 'dp2', 'hdmi1', 'hdmi2'],
                      help="Port to connect")
  parser.add_argument("--dir", type=str.lower, choices=['fpga', 'ite'],
                      help="Direction to connect the port")
  options = parser.parse_args()

  if (options.port is None) != (options.dir is None):
    print("If used, both the port and the dir arguments are required")
    sys.exit(128)

  try:
    ec = EcPgClient(EC_SERIAL_PORT)

    if options.off:
      ec.videomux_off()

    if options.port and options.dir:
      dest_enum = EC_PROTO.videomux_set_request.videomux_dest
      direction = dest_enum.RX if options.dir == 'ite' else dest_enum.FPGA
      ec.videomux_set(options.port, direction)

  except Exception as e:
    print("---------------------")
    print("Failed to connect to EC serial. Is chameleond disabled?")
    print("---------------------")
    raise e
