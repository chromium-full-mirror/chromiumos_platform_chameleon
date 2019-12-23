# -*- coding: utf-8 -*-
# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module provides emulation of bluetooth HID devices."""

from __future__ import print_function

import chameleon_common  # pylint: disable=W0611
from bluetooth_peripheral_kit import PeripheralKit


class BluetoothVirtualDeviceException(Exception):
  """A dummpy exception class for Bluetooth Virtual Device class."""
  pass


class BluetoothVirtualDevice(object):
  """A bluetooth Virtual Device."""

  def __init__(self, device_type):
    """Initialization of BluetoothHID

    Args:
      device_type: the device type for emulation
    """
    self._device_type = device_type
    self._device_name = 'Bluetooth Virtual Device'
    self._bluetooth_address = '00:11:22:33:44:55'
    self._pin = '0000'
    self._class_of_service = 0
    self._class_of_device = 0
    self._authentication_mode = 'none'
    self._port = 'none'
    self._hid_type = 'none'

  def Init(self):
    return True

  def GetCapabilities(self):
    return {PeripheralKit.CAP_TRANSPORTS: [PeripheralKit.TRANSPORT_BREDR],
            PeripheralKit.CAP_HAS_PIN: False,
            PeripheralKit.CAP_INIT_CONNECT: False}

  def EnterCommandMode(self):
    return True

  def LeaveCommandMode(self, force=False):  # pylint: disable=W0613
    return True

  def Reboot(self):
    return True

  def FactoryReset(self):
    return True

  def GetAdvertisedName(self):
    return self._device_name

  def GetLocalBluetoothAddress(self):
    return self._bluetooth_address

  def GetPinCode(self):
    return self._pin

  def GetClassOfService(self):
    return self._class_of_service

  def GetClassOfDevice(self):
    return self._class_of_device

  def GetHIDDeviceType(self):
    return self._hid_type

  def GetAuthenticationMode(self):
    return self._authentication_mode

  def GetPort(self):
    return self._port

  def CheckSerialConnection(self):
    return True

  def Close(self):
    return True

  def PowerCycle(self):
    return self.Reboot()
