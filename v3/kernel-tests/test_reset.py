# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import pytest
import random
import subprocess
import time


class TestResets:
  @pytest.fixture
  def replug(self, ssh_cmd, videomux_cmd, request):
    try:
      dp_port = pytest.dp_port
    except AttributeError:
      pytest.skip("Unknown port to replug")

    videomux_cmd_off = f'{videomux_cmd} --off'
    subprocess.check_output(ssh_cmd + [videomux_cmd_off])
    time.sleep(1 + random.random() * 2)
    videomux_cmd_plug = f'{videomux_cmd} --dir FPGA --port {dp_port}'
    subprocess.check_output(ssh_cmd + [videomux_cmd_plug])

  @pytest.fixture(autouse=True)
  def wait_for_video_on_dprx(self, replug, wait_for_video_on_dprx):
    # Override fixture, so replug is executed before wait_for_video_on_dprx
    pass


  @pytest.mark.parametrize("try_id", pytest.reset_tries)
  def test_cable_replug(self, try_id, ssh_cmd, toolbox_cmd_str):
    timeout = 60
    while timeout > 0:
      start = time.clock_gettime(time.CLOCK_MONOTONIC)
      try:
        # Try to get 10 frames
        out = subprocess.check_output(ssh_cmd + [f'{toolbox_cmd_str} -c 10'],
                                      encoding="utf-8", timeout=timeout)
        assert out == ''
      except subprocess.CalledProcessError as e:
        # Some intermediate problems may occure as resolution changes so try again
        timeout -= time.clock_gettime(time.CLOCK_MONOTONIC) - start
        continue
      except subprocess.TimeoutExpired as e:
        pytest.fail("Didn't get 10 frames")
      break
    else:
      pytest.fail("Didn't get 10 frames")
