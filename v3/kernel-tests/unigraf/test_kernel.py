# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from __future__ import annotations

import pytest
import subprocess

tsi = pytest.importorskip("tsi")

def id_from_timing(timing):
  return str(timing)


class TestMotionPattern:
  @pytest.fixture
  def random_opt(self, request):
    random = request.config.getoption("--random")
    if random > 0:
      return f'-R {random}'

    return ""

  @pytest.fixture
  def frames_count(self, video_mode, request):
    # Get number of frames to generate
    motion = request.config.getoption("--motion")
    if motion == 0:
      return video_mode.timing.hactive + 100

    return motion

  @pytest.fixture
  def pg_content(self):
    # Required for pattern_generator fixture
    return 'Motion pattern'

  @pytest.fixture
  def pattern_params(self, frames_count):
    # Required for pattern_generator fixture
    return tsi.MotionParams(frames_count=frames_count)

  @pytest.mark.parametrize("timing", pytest.timings_list, indirect=True, ids=id_from_timing)
  def test_motion_pattern(self, ssh_cmd, toolbox_cmd_str, random_opt, frames_count,
                          pattern_generator):
    try:
      out = subprocess.check_output(ssh_cmd +
                                    [f'{toolbox_cmd_str} -M {random_opt} -c {frames_count * 2 + 100}'],
                                    encoding="utf-8")
      assert out == ''
    except subprocess.CalledProcessError as e:
      if e.returncode == 1:
        # The most common reason, is that frame buffer doesn't receive any data
        pytest.fail(f"Error on v4l-test-toolbox. No data on FB? {e}")
      else:
        pytest.fail(f"Error on v4l-test-toolbox. {e}")


class TestCrc:
  @pytest.fixture
  def pg_content(self, crc_data):
    # Required for pattern_generator fixture
    return crc_data['data']

  @pytest.fixture
  def pattern_params(self):
    # Required for pattern_generator fixture
    return None

  @pytest.mark.parametrize("timing", pytest.timings_list, indirect=True, ids=id_from_timing)
  def test_crc(self, ssh_cmd, toolbox_cmd_str, crc_data, pattern_generator):
    crc = crc_data['crc']
    try:
      out = subprocess.check_output(ssh_cmd + [f'{toolbox_cmd_str} --crc -c 5'],
                                    encoding="utf-8")
      assert out != '', "Didn't get CRC"
    except subprocess.CalledProcessError as e:
      if e.returncode == 1:
        # The most common reason, is that frame buffer doesn't receive any data
        pytest.fail(f"Error on v4l-test-toolbox. No data on FB? {e}")
      else:
        pytest.fail(f"Error on v4l-test-toolbox. {e}")

    res = out.split()
    assert len(res) == res.count(res[0]), f"""Got different CRCs for some framse: {res}
                                          expected CRC: {hex(crc)}"""

    assert int(res[0], 16) == crc, f"Got CRC: {res[0]}, expected: {hex(crc)}"
