# -*- coding: utf-8 -*-

# Copyright 2020 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module implements Better Together over GATT service on bluez"""

try:
  from gi.repository import GObject
except ImportError:
  import gobject as GObject

from example_gatt_server import Characteristic, GATT_CHRC_IFACE, Service
from bluez_le_hid_service import LEApplication, BatteryService, DevInfoService

class PhoneLEBetterTogetherApplication(LEApplication):
  """Fake Better together application"""

  def __init__(self, bus, device_type):
    LEApplication.__init__(self, bus)

    # Add ProximityAuth, Battery, and Device info primary services
    self.AddService(ProximityAuthService(bus, 0))
    self.AddService(BatteryService(bus, 1))
    self.AddService(DevInfoService(bus, 2))

class ProximityAuthService(Service):
  """ProximityAuth service"""
  SERVICE_UUID = 'b3b7e28e-a000-3e17-bd86-6e97b9e28c11'

  def __init__(self, bus, index):
    Service.__init__(self, bus, index, self.SERVICE_UUID, True)
    tx_chrc = MessageTXChrc(bus, 0, self)
    self.add_characteristic(tx_chrc)
    self.add_characteristic(MessageRXChrc(bus, 1, self, tx_chrc))

class MessageTXChrc(Characteristic):
  """Characteristic that transports the ProximityAuth message"""

  CHRC_UUID = '00000100-0004-1000-8000-001A11000102'

  def __init__(self, bus, index, service):
    Characteristic.__init__(
        self, bus, index,
        self.CHRC_UUID,
        ['read', 'write', 'indicate', 'notify'],
        service)
    self.notifying = False

  def StartNotify(self):
    """Called by dbus - requests notifications"""

    if self.notifying:
      return

    self.notifying = True


  def StopNotify(self):
    """Called by dbus - requests stop to notifications"""

    if not self.notifying:
      return

    self.notifying = False


  def SendMessage(self, message):
    """Send message"""
    if self.notifying:
      self.PropertiesChanged(
          GATT_CHRC_IFACE,
          {'Value': message}, [])


class MessageRXChrc(Characteristic):
  """Characteristic that received the ProximityAuth messages"""

  CHRC_UUID = '00000100-0004-1000-8000-001A11000101'


  def __init__(self, bus, index, service, tx_chrc):
    Characteristic.__init__(
        self, bus, index,
        self.CHRC_UUID,
        ['write', 'notify'],
        service)
    self.tx_chrc = tx_chrc


  def WriteValue(self, value, options):
    """Called by dbus - requests write to characteristic"""
    # Better Together needs to send some message back as the response to the
    # message received.
    self.tx_chrc.SendMessage(value)
