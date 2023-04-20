#!/usr/bin/env python3
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Chameleond main entry point."""

import argparse
import logging
import xmlrpc.server

class ChameleonXMLRPCRequestHandler(xmlrpc.server.SimpleXMLRPCRequestHandler):
  def address_string(self):
    # Disable the default reverse DNS resolving as we don't want logging
    # lines to block if there's no DNS available.
    return self.client_address[0]

  def end_headers(self):
    # Allow CORS requests from any origin, useful for UI
    self.send_header("Access-Control-Allow-Headers",
                      "Origin, X-Requested-With, Content-Type, Accept")
    self.send_header("Access-Control-Allow-Origin", "*")
    super().end_headers()

  def do_OPTIONS(self):
    # CORS checks happen using an OPTIONS request, so we must support them too
    self.send_response(200)
    self.end_headers()

def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--driver', type=str, default='v3',
                      help='driver of Chameleond')
  parser.add_argument('--host', type=str, default='0.0.0.0',
                      help='host address of RPC server')
  parser.add_argument('--port', type=int, default=9992,
                      help='port number of RPC server')
  args = parser.parse_args()

  logging.basicConfig(
    level=logging.INFO,
    datefmt="%S", # just seconds as the rest is already tracked by journalctl
    format=':%(asctime)s.%(msecs)ds %(levelname)s %(filename)s:%(lineno)d %(message)s',
  )

  logging.info(f"Importing {args.driver!r}...")
  driver = __import__(args.driver).ChameleondDriver()

  server = xmlrpc.server.SimpleXMLRPCServer(
    (args.host, args.port),
    requestHandler=ChameleonXMLRPCRequestHandler,
    logRequests=True,
    allow_none=True,
  )
  server.register_instance(driver, allow_dotted_names=True)

  logging.info(f"Listening on {server.server_address}...")
  server.serve_forever()

if __name__=="__main__":
  main()
