#!/usr/bin/env python3
# Copyright 2023 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Connect to Chameleond and capture screenshot."""

import argparse
import codecs
import subprocess
import sys
import tempfile
import xmlrpc.client

def read_edid(filename):
  """Read a text-format EDID and turn it into a binary string

  The EDIDs are stored in text files as ASCII hex digits with
  no intervening spaces, e.g.

    00ffffffffffff0022f06c2801010101
    0c170104b5402878e28d85ad4f35b125
    ...

  This function reads the text from the file, decodes it from hex
  into bytes, and then pads out to 256 bytes because the Chameleon
  wants the EDIDs to always be 256 bytes long.

  Args:
    filename: EDID file, with directory if needed to access it
  """
  edid = b""
  for line in open(filename).readlines():
    edid += codecs.decode(line.strip(), "hex")
  return edid.ljust(256, b'\0')

def capture_to_file(chameleon, port_id, filename="image.png"):
  """Writes an image to a file, uses `convert`

  Args:
    chameleon: the xmlrpc.client.ServerProxy
    port_id: int, port to be captured
    filename: output file
  """
  width, height = chameleon.DetectResolution(port_id)
  print('Detected screen size %dx%d' % (width, height))
  size_str = '%dx%d' % (width, height)

  print('Capturing the screen size %s...' % size_str)
  pixels = chameleon.DumpPixels(port_id).data

  print('Got pixel size %d' % len(pixels))
  with tempfile.NamedTemporaryFile(suffix='.rgb') as f:
    print('Temporarily write to file:', f.name)
    f.write(pixels)
    f.flush()
    command = ['convert', '-size', size_str, '-depth', '8']
    command += [f.name, options.output]
    subprocess.check_call(command)
    print('Outputted to file:', options.output)

def screenshot(chameleon, options):
  """Main entry point of the tool, takes a screenshot.

  Args:
    chameleon: the xmlrpc.client.ServerProxy
    options: cmdline options from parser.parse_args()
  """

  port_id = options.port_id
  if port_id is None:
    # get the first one that's probable
    port_id = chameleon.ProbeInputs()[0]
    print("Port was not given, picked the first one that probed.")

  was_plugged = chameleon.IsPlugged(port_id)

  print(f"Screenshotting port_id={port_id}, "
        f"type {chameleon.GetConnectorType(port_id)}, "
        f"detected={chameleon.IsPhysicalPlugged(port_id)}, "
        f"plugged={was_plugged}"
  )
  assert chameleon.HasVideoSupport(port_id)

  try:
    if was_plugged and (options.replug or options.edid_file):
      print('Unplugging...')
      chameleon.Unplug(port_id)

    if options.edid_file:
      print('Reading EDID from %s...' % options.edid_file)
      edid = read_edid(options.edid_file)
      print('Applying EDID...')
      edid_id = chameleon.CreateEdid(xmlrpc.client.Binary(edid))
      chameleon.ApplyEdid(port_id, edid_id)
      chameleon.DestroyEdid(edid_id)

    if not chameleon.IsPlugged(port_id):
      print('Plugging... ', end="", flush=True)
      chameleon.Plug(port_id)

      print('Wait for input stable', end="", flush=True)
      MAX_WAIT_TIMEOUT = 30
      WAIT_INTERVAL = 5
      for attempts in range(MAX_WAIT_TIMEOUT // WAIT_INTERVAL):
        print('.', end="", flush=True)
        if chameleon.WaitVideoInputStable(port_id, WAIT_INTERVAL):
          print(' stable!')
          break
      else:
        raise Exception("Timeout while WaitVideoInputStable()")

    capture_to_file(chameleon, port_id, filename=options.output)

    if options.open:
      print(f"Opening {options.output!r}...")
      subprocess.call(["xdg-open", options.output])

  except xmlrpc.client.Fault as e:
    if "already connected, don't want to disconnect it." in e.faultString:
      print(f"\n{e.faultString}")
      print("Calling chameleon.Reset() to fix ^ for next screenshot attempt... Perhaps try again.")
      chameleon.Reset()
      sys.exit(1)
    raise

  finally:
    if not was_plugged:
      print('Unplugging to the original state...')
      chameleon.Unplug(port_id)

if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--host", type=str, default="localhost",
                      help="host address of chameleond")
  parser.add_argument("--port", type=int, default=9992,
                      help="port number of chameleond")
  parser.add_argument("--port_id", type=int, default=None,
                      help="video port number on the chameleon to use as a source")
  parser.add_argument("--replug", action="store_true",
                      help="unplug and plug before capturing screen")
  parser.add_argument("--edid", type=str, dest="edid_file", default=None,
                      help="filename of the edid to apply")
  parser.add_argument("--output", type=str, default="image.png",
                      help="output file name of screenshot")
  parser.add_argument("--open", action="store_true",
                      help="xdg-open the output in a GUI picture viewer")
  options = parser.parse_args()

  chameleon = xmlrpc.client.ServerProxy(f"http://{options.host}:{options.port}")
  screenshot(chameleon, options)
