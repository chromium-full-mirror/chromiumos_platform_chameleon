# -*- coding: utf-8 -*-
# Lint as: python3
# pylint: disable=dangerous-default-value,cros-logging-import,logging-format-interpolation

# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""Helper functions for invoking hcitool cmd
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import logging
import subprocess
import time

from six.moves import range

def _number_to_le_hex(value, octets=1):
  """Convert number to little endian hex (no 0x prefix)

  Args:
    value: Value to convert to LE hex.
    octets: Number of octets to generate. If size exceeds it, it truncates.
  """
  le = []
  if not value:
    le = ['00'] * octets
  else:
    # Loop while value is not zero and we have remaining octets to print
    while value and octets:
      le.append('{:02x}'.format(value % 256))
      value = value // 256
      octets = octets - 1

    # If we generated less octets than expected, zero pad it
    if octets:
      le.extend(['00'] * octets)

  return le


# Opcode groups
LE_OGF = '0x08'


class HciCommands(object):
  """Wrapper for generating hci commands."""

  @staticmethod
  def le_set_advertising_enable(enable=False):
    """LE Set Advertising Enable

    Args:
      enable: [1 octet] Enable advertising
    """
    return [LE_OGF, '0x000a', '01' if enable else '00']

  @staticmethod
  def le_set_advertising_params(interval_min=0x800,
                                interval_max=0x800,
                                advertising_type=0x0,
                                own_address_type=0x0,
                                peer_address_type=0x0,
                                peer_address=[0, 0, 0, 0, 0, 0],
                                advertising_channel_map=0x7,
                                advertising_filter_policy=0x0):
    """LE Set Advertising Params

    Intervals should be between 0x20 and 0x4000. Time = N x 0.625ms

    Args:
      interval_min: [2 octets] Minimum advertising interval
      interval_max: [2 octets] Maximum advertising interval
      advertising_type: [1 octet] ADV_IND, ADV_DIRECT_IND, ADV_SCAN_IND,
                                  ADV_NONCONN_IND, ADV_DIRECT_IND low duty
      own_address_type: [1 octet] Range 0x0 - 0x3
      peer_address_type: [1 octet] 0x0 = Public, 0x1 = Random
      peer_address: [6 octet] Peer address
      advertising_channel_map: [1 octet] Channel used bits. 37, 38, 39.
      advertising_filter_policy: [1 octet] Range 0x0 - 0x3
    """
    cmd = [LE_OGF, '0x0006']

    peer_address.reverse()

    cmd.extend(_number_to_le_hex(interval_min, octets=2))
    cmd.extend(_number_to_le_hex(interval_max, octets=2))
    cmd.extend(_number_to_le_hex(advertising_type, octets=1))
    cmd.extend(_number_to_le_hex(own_address_type, octets=1))
    cmd.extend(_number_to_le_hex(peer_address_type, octets=1))
    cmd.extend(['{:02x}'.format(x) for x in peer_address])
    cmd.extend(_number_to_le_hex(advertising_channel_map, octets=1))
    cmd.extend(_number_to_le_hex(advertising_filter_policy, octets=1))

    return cmd

  @staticmethod
  def le_set_advertising_data(data_length=0, data=[0] * 31):
    """LE Set Advertising Data

    Args:
      data_length: [1 octet] Number of significant octets in data.
      data: [31 octets] Advertising data
    """
    cmd = [LE_OGF, '0x0008']

    cmd.extend(_number_to_le_hex(data_length, octets=1))
    cmd.extend(['{:02x}'.format(x) for x in data])

    return cmd

  @staticmethod
  def le_set_scan_response_data(data_length=0, data=[0] * 31):
    """LE Set Scan Response Data

    Args:
      data_length: [1 octet] Number of significant octets in data.
      data: [31 octets] Scan response data
    """
    cmd = [LE_OGF, '0x0009']

    cmd.extend(_number_to_le_hex(data_length, octets=1))
    cmd.extend(['{:02x}'.format(x) for x in data])

    return cmd

  @staticmethod
  def le_set_scan_params(le_scan_type=0x01,
                         le_scan_interval=0x0010,
                         le_scan_window=0x0010,
                         own_address_type=0x0,
                         scanning_filter_policy=0x0):
    """LE Set Scan Params

    Args:
      le_scan_type: [1 octets] 0x0 = passive, 0x1 = public
      le_scan_interval: [2 octets] Scan interval
      le_scan_window: [2 octet] Scan window
      own_address_type: [1 octet] Range 0x0 - 0x3
      scanning_filter_policy: [1 octet] Range 0x0 - 0x3
    """
    cmd = [LE_OGF, '0x000b']

    cmd.extend(_number_to_le_hex(le_scan_type, octets=1))
    cmd.extend(_number_to_le_hex(le_scan_interval, octets=2))
    cmd.extend(_number_to_le_hex(le_scan_window, octets=2))
    cmd.extend(_number_to_le_hex(own_address_type, octets=1))
    cmd.extend(_number_to_le_hex(scanning_filter_policy, octets=1))

    return cmd

  @staticmethod
  def le_set_scan_enable(enable=False, filter_duplicates=False):
    """LE Set Scan Enable

    Args:
      enable: [1 octet] Enable scanning
      filter_duplicates: [1 octet] Filter duplicates
    """
    cmd = [LE_OGF, '0x000c']

    cmd.extend(_number_to_le_hex(int(enable), octets=1))
    cmd.extend(_number_to_le_hex(int(filter_duplicates), octets=1))

    return cmd


class HciTool(object):
  """Wrapper for executing hcitool."""

  CMD_PREFIX = 'hcitool -i hci0 cmd '

  def __init__(self, sudo=True, wait_time=0.1):
    """Wrapper for executing hcitool.

    Args:
      sudo: Run hcitool with sudo
      wait_time: Time to wait between commands
    """
    self.sudo = sudo
    self.wait_time = wait_time
    self.commands = []

  def add_command(self, cmd):
    """Add a command generated by HciCommands.

    Args:
      cmd: [OGF, OCF, <bytes with command data>]
    """
    fmt = 'sudo {} {}' if self.sudo else '{} {}'
    self.commands.append(fmt.format(self.CMD_PREFIX, ' '.join(cmd)))

  def run_commands(self):
    """Run all commands added."""
    for cmd in self.commands:
      try:
        subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT)
      except subprocess.CalledProcessError as cpe:
        logging.error('Error executing [{}]. Result {}: {}'.format(
            cpe.cmd, cpe.returncode, cpe.output))
      time.sleep(self.wait_time)


# If invoked as a script, run tests
if __name__ == '__main__':

  def compare_array(a, b):
    result = len(a) == len(b) and all([a[i] == b[i] for i in range(len(a))])
    print('{}:   {} vs {}'.format('PASS' if result else 'FAIL', a, b))

  # Check some hci commands
  compare_array(
      HciCommands.le_set_advertising_enable(enable=True),
      ['0x08', '0x000a', '01'])

  compare_array(HciCommands.le_set_advertising_params(),
                ['0x08', '0x0006', '00', '08', '00', '08'] + ['00'] * 9 +
                ['07', '00'])

  # number to le hex tests
  compare_array(_number_to_le_hex(16, octets=1), ['10'])
  compare_array(_number_to_le_hex(0, octets=1), ['00'])
  compare_array(_number_to_le_hex(0, octets=3), ['00', '00', '00'])
  compare_array(_number_to_le_hex(0x400, octets=2), ['00', '04'])
  compare_array(_number_to_le_hex(0x400, octets=4), ['00', '04', '00', '00'])
