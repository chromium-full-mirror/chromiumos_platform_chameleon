# -*- coding: utf-8 -*-

# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""The control interface of Bluetooth flow for Raspi devices."""

from chameleond.devices import chameleon_device
from chameleond.utils.bluetooth_raspi import BluezPeripheral
from chameleond.utils.bluetooth_peripheral_kit import PeripheralKit


class RaspiFlow(chameleon_device.Flow):
  """The control interface of a Raspi bluetooth (Bluez-based) device."""

  # Should be BluezPeripheral for builtin bluetooth peripheral. May be different
  # for other subclasses (e.g. Intel ThP2 solution).

  def __init__(self, device_address):
    """Initializes a Raspi flow object."""
    super(RaspiFlow, self).__init__()
    self._dev_addr = device_address

  def IsDetected(self):
    """Returns true if BT adapter is detected."""
    return self._dev_addr is not None

  def InitDevice(self):
    return

  def Reset(self):
    return

  def Select(self):
    return

  def GetConnectorType(self):
    return None

  def IsPhysicalPlugged(self):
    return True

  def IsPlugged(self):
    return True

  def Plug(self):
    return

  def Unplug(self):
    return

  def DoFSM(self):
    return


class RaspiHIDKeyboard(RaspiFlow, BluezPeripheral):
  """This is the class loaded from fpga_tio.

  We inherit from both Flow and PeripheralKit, as fpga_tio's interface needs
  access to methods in both of them
  """

  def __init__(self):
    # Instantiate bluez and raspi flow
    BluezPeripheral.__init__(self, PeripheralKit.KEYBOARD)
    RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())
