# -*- coding: utf-8 -*-
# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""The control interface of Bluetooth base flow module driver."""

from __future__ import print_function

# TODO: to port chromite.lib.cros_logging to replace legacy logging
import logging  # pylint: disable=cros-logging-import
import os

import chameleon_common  # pylint: disable=W0611
from chameleond.devices import chameleon_device
from chameleond.utils import bluetooth_virtual_device
from chameleond.utils import system_tools


class Servod(object):
  """A simple object that performs Servod operations."""

  CONFIG_PATH = '/usr/local/lib/python2.7/dist-packages/servo/data/'

  # TODO: We had better figure out a way to auto detect the config path to use.
  CONFIG = {
      'kukui': 'krane_rev1.xml',
  }

  def __init__(self):
    """Initializes a Servod object."""
    self._board = ''
    self._config = ''
    self._start_servod_cmd = ''
    self._start_servod_cmd_list = []
    self._servod = None
    self._measure_power_cmd_list = ['dut-control', 'pp3300_wlan_mw', '-t', '3']

  def SetBoard(self, board):
    self._board = board
    self._config = os.path.join(self.CONFIG_PATH, self.CONFIG.get(board, ''))

    if not os.path.isfile(self._config):
      logging.error('The servod config path does not exist: %s', self._config)
      return False
    return True

  def GetStartCmd(self):
    if self._start_servod_cmd_list == []:
      if bool(self._board) and bool(self._config):
        cmd = 'servod -b %s -c %s' % (self._board, self._config)
        self._start_servod_cmd_list = cmd.split()
      else:
        logging.error('GetStartCmd failed.')

    return self._start_servod_cmd_list

  def GetBoard(self):
    return self._board

  def Start(self):
    if self._servod:
      logging.error('Trying to start Servod when it is still running.')
      return False

    cmd_list = self.GetStartCmd()
    logging.info('cmd_list: %s', str(cmd_list))
    if bool(cmd_list):
      cmd_name = cmd_list[0]
      cmd_args = cmd_list[1:]
      self._servod = system_tools.SystemTools.RunInSubprocess(
          cmd_name, *cmd_args)

      logging.info('Servod is started.')
      return True

    return False

  def MeasurePowerConsumption(self):
    """Measure the power consumption.

    The output format looks like

      @@             NAME  COUNT  AVERAGE  STDDEV    MAX   MIN
      @@   pp3300_wlan_mw    415     2.61    1.97  10.00  0.00

    We would like to return the AVERAGE value which is 2.61 in the example.
    """
    proc = system_tools.SystemTools.RunInSubprocess(
        *self._measure_power_cmd_list)

    (return_code, out, err) = system_tools.SystemTools.GetSubprocessOutput(proc)
    if return_code:
      logging.error('measureing power return %d, error: %s', return_code, err)
      return None

    for line in out.splitlines():
      if '@@' in line and 'pp3300_wlan_mw' in line:
        items = line.split()
        if len(items) < 3:
          logging.error('power number format errors: %s', line)
          continue
        avg_power = items[3]
        logging.debug('avg_power: %s', str(avg_power))
        return avg_power
    return None

  def Stop(self):
    if self._servod is None:
      logging.error('Stop Servod before starting it.')
      return False

    if self._servod.poll() is None:
      self._servod.terminate()
      logging.info('Servod is terminated.')
      self._servod = None
      return True

    return False


class BluetoothBaseFlow(chameleon_device.VirtualFlow,
                        bluetooth_virtual_device.BluetoothVirtualDevice):
  """A flow object that simply acts as a XMLRPC server."""

  DEVICE_TYPE = 'BLUETOOTH_BASE'

  def __init__(self, port_id, usb_ctrl):
    """Initializes a BluetoothBaseFlow object.

    Args:
      port_id: the port id that represents the type of port used.
      usb_ctrl: a USBController object that BluetoothHIDFlow references to.
    """
    self._port_id = port_id
    self._usb_ctrl = usb_ctrl
    self.servod = None

    chameleon_device.VirtualFlow.__init__(self)
    bluetooth_virtual_device.BluetoothVirtualDevice.__init__(
        self, self.DEVICE_TYPE)

  def EnableServod(self, board):
    servod = Servod()
    if servod.SetBoard(board):
      self.servod = servod
      return True
    return False
