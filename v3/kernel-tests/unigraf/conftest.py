# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from __future__ import annotations

import pytest
import subprocess
import time
import zlib

from PIL import Image

try:
  import tsi
except Exception:
  tsi = None


def pytest_configure(config):
  if tsi is None:
    return

  # Note that device was plugged before starting UCD, otherwise some glitches may happen

  # Initialize UCD and timings list in pytest_configure, not in the fixture, because we need timings
  # list in the collection phase, where fixtures are not available yet.

  # Initialize TSI library
  ltsi = tsi.TsiLib()
  dev = ltsi.open(config.getoption("--ucdsn"))

  # Choose DP
  pytest.ucd_role = dev.select_role(tsi.dev.UCD323.DPSource)

  # Collect timings from UCD
  timing_manager = pytest.ucd_role.dptx.pg.timing_manager
  timings_list = ([timing_manager.get_cta(i) for i in range(0, 256)] +
                  [timing_manager.get_dmt(i) for i in range(0, 128)] +
                  [timing_manager.get_cvt(i) for i in range(0, 1)])
  # Filter timings we can actually use
  pytest.timings_list = list(filter(lambda timing: timing is not None and timing.is_valid(),
                                    timings_list))


@pytest.fixture(scope="session")
def reference_image(request):
  # Prepare image data
  image = Image.open(request.config.getoption("--image"))
  dimensions = image.size
  image = image.convert('RGB')
  return {'img': image, 'dim': dimensions}


@pytest.fixture(scope="session")
def color_mode():
  # Create color mode
  color_mode = tsi.ColorInfo()
  color_mode.color_format = tsi.ColorInfo.ColorFormat.CF_RGB
  color_mode.bpc = 8
  color_mode.colorimetry = tsi.ColorInfo.Colorimetry.CM_sRGB

  return color_mode


@pytest.fixture
def timing(request):
  return request.param


@pytest.fixture
def video_mode(color_mode, timing):
  return tsi.VideoMode(timing=timing, color_info=color_mode)


@pytest.fixture
def crc_data(reference_image, video_mode):
  # Get required image size
  target_size = (video_mode.timing.hactive, video_mode.timing.vactive)

  try:
    cache = crc_data.cache
  except AttributeError:
    # Create cache for the first time
    crc_data.cache = {}
    cache = crc_data.cache

  try:
    # Check if we already have image with required size
    return cache[target_size]
  except KeyError:
    # Create the image with required size
    pass

  l = list(reference_image['img'].getdata())
  org_size = reference_image['dim']
  data = bytearray()
  for v in range(0, target_size[1]):
    # Get line of pixels
    line = l[v * org_size[0]:(v + 1) * org_size[0]]
    # Make sure that line is long enough for target resolution
    line = line * (1 + target_size[0] // len(line))
    # Append line
    data += bytearray([x for sets in line[:target_size[0]] for x in sets])
  crc = zlib.crc32(data)
  cache[target_size] = {'data': data, 'crc': crc}
  return cache[target_size]


@pytest.fixture
def pattern_generator(video_mode, pg_content, pattern_params):
  # Some patterns can generate few minutes
  pg_timeout = 60 * 5
  pg_try_interval = 0.5
  pytest.ucd_role.dptx.pg.setup(stream=0, vm=video_mode, content_type=pg_content,
                                pattern_params=pattern_params)
  if not pytest.ucd_role.dptx.pg.apply():
    pytest.skip("Pattern not applied")
  for i in range(int(pg_timeout // pg_try_interval)):
    if not pytest.ucd_role.dptx.pg.status(0).is_video_produced:
      break
    time.sleep(pg_try_interval)
  else:
    pytest.skip("Pattern not produced")
