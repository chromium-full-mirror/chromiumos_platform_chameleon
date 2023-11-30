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


def pytest_addoption(parser):
  parser.addoption("--host", type=str, default="localhost",
                   help="host address of chameleon")
  parser.addoption("--ssh_key", type=str, default="~/.ssh/testing_rsa",
                   help="SSH key to access chameleon")
  parser.addoption("--dev", type=str,
                   default="/dev/v4l/by-path/platform-c0060600.video-video-index0",
                   help="video device to use on chameleon")
  parser.addoption("--format", type=str, default="RGB3",
                   help="Pixel format of video stream")
  parser.addoption("--motion", type=int, default=0,
                   help=("Number of frames to generate if motion pattern is tested."
                         " If 0, number of frames equals to width in pixels + 100."))
  parser.addoption("--random", type=int, default=500,
                   help="Number of random pixels to check in motion pattern")
  parser.addoption("--image", type=str, default="./reference.png",
                   help="Path for image to load on CRC test")
  parser.addoption("--ucdsn", type=str, default="2237C506",
                   help="Unigraf UCD serial number")
  parser.addoption("--noplug", action='store_true',
                   help="Do not disable chameleond and do not try to plug the port")


def get_ssh_cmd(config):
  # Arguments to start SSH to chameleon
  return ["ssh", "-i", config.getoption("--ssh_key"),
          f'cros@{config.getoption("--host")}']


def get_test_tools_dir(config):
  return "/home/cros/chameleon/v3/kernel-tests/"


def handle_plug(config):
  """
  Handle optional port plug and chameleond suspend
  """

  ssh_cmd = get_ssh_cmd(config)

  pytest.plug = not config.getoption("--noplug")
  videodev = config.getoption("--dev")
  if pytest.plug:
    video_dev_config = {'/dev/v4l/by-path/platform-c0060a00.video-video-index0':
                        {'dp_port': 'dp1'},
                        '/dev/v4l/by-path/platform-c0060600.video-video-index0':
                        {'dp_port': 'dp2'},
                       }
    for dev in video_dev_config:
      try:
        out = subprocess.check_output(ssh_cmd + [f'test {dev} -ef {videodev}'])
        # Test is satisfied, so both files point at the same device
        dp_port = video_dev_config[dev]['dp_port']
        break
      except subprocess.CalledProcessError as e:
        if e.returncode == 1:
          # Different V4L devices, try next one
          continue
        else:
          raise e from None
    else:
      # No matching V4L device found
      # TODO: Extend automatic plug to other ports
      pytest.plug = False
      return
  else:
    return

  pytest.videodev = videodev

  test_tools_dir = get_test_tools_dir(config)
  try:
    out = subprocess.check_output(ssh_cmd + ["sudo systemctl is-active chameleond"])
    pytest.chameleond_active = out.startswith(b'active')
  except subprocess.CalledProcessError as e:
    if e.returncode == 3:
      pytest.chameleond_active = False
    else:
      raise e from None
  if pytest.chameleond_active:
    subprocess.check_output(ssh_cmd + ["sudo systemctl stop chameleond"])

  # Set any edid to trigger HPD
  edid_tool_path = f'python3 {test_tools_dir}edid_tool.py'
  edid_tool_cmd = f'{edid_tool_path} --dev {pytest.videodev}'
  subprocess.check_output(ssh_cmd + [edid_tool_cmd])
  # Connect videomux port
  videomux_path = f'python3 {test_tools_dir}videomux_tool.py'
  videomux_cmd = f'{videomux_path} --off --dir FPGA --port {dp_port}'
  subprocess.check_output(ssh_cmd + [videomux_cmd])


def handle_unplug(config):
  """
  Handle optional port unplug and chameleond restart
  """
  if not pytest.plug:
    return

  ssh_cmd = get_ssh_cmd(config)
  test_tools_dir = get_test_tools_dir(config)

  videomux_path = f'python3 {test_tools_dir}videomux_tool.py'
  videomux_cmd = f'{videomux_path} --off'
  subprocess.check_output(ssh_cmd + [videomux_cmd])

  edid_tool_path = f'python3 {test_tools_dir}edid_tool.py'
  edid_tool_cmd = f'{edid_tool_path} --clear --dev {pytest.videodev}'
  subprocess.check_output(ssh_cmd + [edid_tool_cmd])

  if pytest.chameleond_active:
    subprocess.check_output(ssh_cmd + ["sudo systemctl start chameleond"])


def pytest_configure(config):
  if tsi is None:
    return

  # Need to be plugged before starting UCD, otherwise some glitches may happen
  handle_plug(config)

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


def pytest_unconfigure(config):
  handle_unplug(config)


@pytest.fixture(scope="session")
def ssh_cmd(request):
  return get_ssh_cmd(request.config)


@pytest.fixture(scope="session")
def test_tools_dir(request):
  return get_test_tools_dir(request.config)


@pytest.fixture(scope="session")
def toolbox_cmd_str(test_tools_dir, request):
  # Common part of command that starts v4l-test-toolbox. It includes device and format options.
  return (f'{test_tools_dir}v4l-test-toolbox -d {request.config.getoption("--dev")} '
          f'-f {request.config.getoption("--format")}')


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
