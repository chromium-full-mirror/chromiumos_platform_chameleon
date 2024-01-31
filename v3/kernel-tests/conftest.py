# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import pytest
import subprocess
import time


def ucd_addoption(parser):
  ucd_group = parser.getgroup("Tests using UCD options")
  ucd_group.addoption("--motion", type=int, default=0,
                      help=("Number of frames to generate if motion pattern is tested."
                            " If 0, number of frames equals to width in pixels + 100."))
  ucd_group.addoption("--random", type=int, default=500,
                      help="Number of random pixels to check in motion pattern")
  ucd_group.addoption("--image", type=str, default="./unigraf/reference.png",
                      help="Path for image to load on CRC test")
  ucd_group.addoption("--ucdsn", type=str, default="2237C506",
                      help="Unigraf UCD serial number")


def reset_addoption(parser):
  reset_group = parser.getgroup("Reset tests")
  reset_group.addoption("--try_count", type=int, default=10,
                        help="Number of retries of the test")


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
  parser.addoption("--noplug", action='store_true',
                   help="Do not disable chameleond and do not try to plug the port")
  ucd_addoption(parser)
  reset_addoption(parser)


def get_ssh_cmd(config):
  # Arguments to start SSH to chameleon
  return ["ssh", "-i", config.getoption("--ssh_key"),
          f'cros@{config.getoption("--host")}']


def get_test_tools_dir(config):
  return "/home/cros/chameleon/v3/kernel-tests/"


def get_videomux_cmd(config):
  return f'python3 {get_test_tools_dir(config)}videomux_tool.py'


def get_edid_tool_cmd(config):
  return f'python3 {get_test_tools_dir(config)}edid_tool.py'


def handle_plug(config):
  """
  Handle optional port plug and chameleond suspend
  """

  ssh_cmd = get_ssh_cmd(config)

  pytest.plug = not config.getoption("--noplug")
  videodev = config.getoption("--dev")
  if pytest.plug:
    video_dev_config = {'/dev/v4l/by-path/platform-c0060a00.video-video-index0':
                        {'dp_port': 'dp1', 'dp_mgmt': 'dp_mgmt_sst', 'dp_vbid': 'dprx0_vbid'},
                        '/dev/v4l/by-path/platform-c0060600.video-video-index0':
                        {'dp_port': 'dp2', 'dp_mgmt': 'dp_mgmt_mst', 'dp_vbid': 'dprx0_vbid'},
                       }
    for dev in video_dev_config:
      try:
        out = subprocess.check_output(ssh_cmd + [f'test {dev} -ef {videodev}'])
        # Test is satisfied, so both files point at the same device
        pytest.dp_port = video_dev_config[dev]['dp_port']
        pytest.dp_mgmt = video_dev_config[dev]['dp_mgmt']
        pytest.dp_vbid = video_dev_config[dev]['dp_vbid']
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
  edid_tool_cmd = f'{get_edid_tool_cmd(config)} --dev {pytest.videodev}'
  subprocess.check_output(ssh_cmd + [edid_tool_cmd])
  # Connect videomux port
  videomux_cmd = f'{get_videomux_cmd(config)} --off --dir FPGA --port {pytest.dp_port}'
  subprocess.check_output(ssh_cmd + [videomux_cmd])


def handle_unplug(config):
  """
  Handle optional port unplug and chameleond restart
  """
  if not pytest.plug:
    return

  ssh_cmd = get_ssh_cmd(config)
  test_tools_dir = get_test_tools_dir(config)

  videomux_cmd = f'{get_videomux_cmd(config)} --off'
  subprocess.check_output(ssh_cmd + [videomux_cmd])

  edid_tool_cmd = f'{get_edid_tool_cmd(config)} --clear --dev {pytest.videodev}'
  subprocess.check_output(ssh_cmd + [edid_tool_cmd])

  if pytest.chameleond_active:
    subprocess.check_output(ssh_cmd + ["sudo systemctl start chameleond"])


def handle_reset_test_arguments(config):
  # Handle argument now so it can be used to parametrize reset test
  pytest.reset_tries = list(range(config.getoption("--try_count")))


def pytest_configure(config):
  handle_plug(config)
  handle_reset_test_arguments(config)


def pytest_unconfigure(config):
  handle_unplug(config)


@pytest.fixture(scope="session")
def ssh_cmd(request):
  return get_ssh_cmd(request.config)


@pytest.fixture(scope="session")
def test_tools_dir(request):
  return get_test_tools_dir(request.config)


@pytest.fixture(scope="session")
def videomux_cmd(request):
  return get_videomux_cmd(request.config)


@pytest.fixture(scope="session")
def toolbox_cmd_str(test_tools_dir, request):
  # Common part of command that starts v4l-test-toolbox. It includes device and format options.
  return (f'{test_tools_dir}v4l-test-toolbox -d {request.config.getoption("--dev")} '
          f'-f {request.config.getoption("--format")}')


@pytest.fixture(autouse=True)
def wait_for_video_on_dprx(ssh_cmd, test_tools_dir, request):
  # By default if it is known which register to check, wait for video on DPRX as we are not testing
  # this part.
  if 'nodprxcheck' in request.keywords:
    # Skip the check for tests that has mark that it is not necessary "@pytest.mark.nodprxcheck"
    return

  try:
    dp_mgmt = pytest.dp_mgmt
    dp_vbid = pytest.dp_vbid
  except AttributeError:
    return

  dprx_timeout = 10
  dprx_try_interval = 0.5
  for i in range(int(dprx_timeout // dprx_try_interval)):
    out = subprocess.check_output(ssh_cmd + [f'sudo {test_tools_dir}regmap {dp_mgmt} {dp_vbid}'],
                                  encoding="utf-8")
    out = out.split()
    vbid = int(out[2], 16)
    if vbid & 0xc0 == 0xc0:
        break
    time.sleep(dprx_try_interval)
  else:
    pytest.skip("No video from source on dprx")
