#!/usr/bin/env python3
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Really simple chameleon client example."""

import argparse
import sys
import pprint
import xmlrpc.client

from screenshot import read_edid, capture_to_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--host", type=str, default="localhost",
                    help="host address of Chameleond")
parser.add_argument("--port", type=int, default=9992,
                    help="port number of Chameleond")
args = parser.parse_args()

p = xmlrpc.client.ServerProxy(f"http://{args.host}:{args.port}")
print(f"Chameleon can be accessed via p = {p!r}")
print(f" MAC Address {p.GetMacAddress()!r}")
pprint.pprint(p.GetVersions(), sort_dicts=False)

def print_ports():
  print("Ports:")
  ports = p.GetSupportedPorts()
  for port_id in ports:
    def iter_port_capabilities(port_id):
      if p.HasVideoSupport(port_id):
        global video_port_id
        video_port_id = port_id
        yield "video"
      if p.HasAudioSupport(port_id):
        yield "audio"

      yield p.GetConnectorType(port_id)

      if p.IsPhysicalPlugged(port_id):
        yield "detected"
      if p.IsPlugged(port_id):
        yield "plugged"

    print(f"  {port_id=}: ", end="")
    for capability in iter_port_capabilities(port_id):
      print(capability, end=" ", flush=True)
    print()

video_port_id = None
print_ports()
if sys.flags.interactive:
  print("Interactive examples:")
  if video_port_id:
    print(f"  p.Plug({video_port_id})")
    print(f'  p.ApplyEdid({video_port_id},\n    p.CreateEdid(read_edid("edids/whatever.txt"))\n  )')
    print(f"  capture_to_file(p, {video_port_id})")
    print(f"  p.Unplug({video_port_id})")
else:
  print(f"You probably want to run this with `python3 -i {sys.argv[0]}`")
