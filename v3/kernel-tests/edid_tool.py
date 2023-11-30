#!/usr/bin/env python3
# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""
Tool to set EDID
"""

import argparse
from linuxpy.video.device import Device


EDID_3840x2160 = bytes.fromhex("""
00FFFFFFFFFFFF0022F01A3200000000
2E180104B54728783A87D5A8554D9F25
0E5054210800D1C0A9C081C0D100B300
9500A94081804DD000A0F0703E803020
3500C48F2100001A000000FD00183C1E
873C000A202020202020000000FC0048
502053706563747265203332000000FF
00434E43393430303030310A2020018F
020318F14B101F041303120211010514
2309070783010000A36600A0F0701F80
30203500C48F2100001A565E00A0A0A0
295030203500C48F2100001AEF5100A0
F070198030203500C48F2100001AB339
00A080381F4030203A00C48F2100001A
283C80A070B0234030203600C48F2100
001A00000000000000000000000000C4
""".replace("\n", ""))


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--dev", type=str, required=True,
                      help="Device to which set the EDID")
  parser.add_argument("--clear", action='store_true',
                      help="Clear an EDID from the device")
  options = parser.parse_args()

  with Device(options.dev) as dev:
    if options.clear:
      dev.clear_edid()
    else:
      dev.set_edid(EDID_3840x2160)
