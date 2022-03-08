# -*- coding: utf-8 -*-
# Lint as: python3
# pylint: disable=import-error,logging-not-lazy

# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""This module implements gatt server functionality on bluez"""

from __future__ import print_function

import sys

import logging
import dbus
import dbus.mainloop.glib

try:
  from gi.repository import GObject
except ImportError:
  import gobject as GObject

from .bluez_le_hid_service import HIDApplication
from .bluez_le_better_together_service import PhoneLEBetterTogetherApplication
from .bluez_le_fast_pair_service import FastPairLEApplication
from .bluetooth_peripheral_kit import PeripheralKit
from .example_gatt_server import Application, BLUEZ_SERVICE_NAME, \
    DBUS_OM_IFACE, GATT_MANAGER_IFACE
from .bluez_service_consts import PERIPHERAL_DEVICE_APPEARANCE, \
    PERIPHERAL_DEVICE_NAME
from .hci_cmd import HciCommands, HciTool

mainloop = None


class GATTServer(object):
  """Bluez gatt server implementation"""

  def __init__(self, device=None):
    bus = dbus.SystemBus()

    adapter = self._FindAdapter(bus)
    if not adapter:
      logging.error('GattManager1 interface not found')
      return

    service_manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, adapter), GATT_MANAGER_IFACE)

    self.device_type = 'generic' if not device else device.device_type
    self.peripheral_type = None
    if 'MOUSE' in self.device_type:
      self.peripheral_type = PeripheralKit.MOUSE
    elif 'KEYBOARD' in self.device_type:
      self.peripheral_type = PeripheralKit.KEYBOARD
    elif 'PHONE' in self.device_type:
      self.peripheral_type = PeripheralKit.PHONE
    elif 'FAST_PAIR' in self.device_type:
      self.peripheral_type = PeripheralKit.FAST_PAIR

    # Choose application using args
    if 'MOUSE' in self.device_type or 'KEYBOARD' in self.device_type:
      self.app = HIDApplication(bus, self.device_type)
      logging.info('HID %s application starting...', self.device_type)
    elif 'PHONE' in self.device_type:
      self.app = PhoneLEBetterTogetherApplication(bus, self.device_type)
      logging.info('%s LE application starting...', self.device_type)
    elif 'FAST_PAIR' in self.device_type:
      self.app = FastPairLEApplication(bus, device)
      logging.info('Fast Pair application starting...')

    else:
      # Default to generic application provided in example
      self.app = Application(bus)
      logging.info('Generic application starting...')

    # We register application with empty callbacks to run it async
    service_manager.RegisterApplication(
        self.app.GetPath(), {},
        reply_handler=self._RegisterAppCB,
        error_handler=self._RegisterAppErrCB)

    # Start with discoverable enabled
    self._discoverable = True
    self._ConfigureAdvertisements()

    # Add a handler for changes in state, specifically requesting caller's
    # device_path in the callback
    bus.add_signal_receiver(
        self._PropertyChanged,
        signal_name='PropertiesChanged',
        bus_name='org.bluez',
        path_keyword='device_path')

  def _RegisterAppCB(self):
    """Callback for app registration"""

    pass

  def _RegisterAppErrCB(self, error):
    """Callback for app registration error"""
    logging.error('Failed to register application: ' + str(error))
    mainloop.quit()

  def _FindAdapter(self, bus):
    """Finds adapter within dbus tree"""

    remote_om = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, '/'), DBUS_OM_IFACE)

    # TODO b:142131418 occasionally this stalls and times out, causing 25s delay
    objects = remote_om.GetManagedObjects()

    for o, props in list(objects.items()):
      if GATT_MANAGER_IFACE in list(props.keys()):
        return o

    return None

  def _FormatDataField(self, attr_id, data):
    """Puts each data block into the correct structure

    Returns:
      data in structure [attr len, attr id, attr data]
    """

    formatted_data = [len(data) + 1, attr_id]
    formatted_data.extend(data)

    return formatted_data

  def _ConfigureAdvertisements(self):
    """Configures and registers LE advertisement"""

    FULL_LOCAL_NAME_ID = 0x09
    FLAGS_ID = 0x01
    APPEARANCE_ID = 0x19
    ADV_SERVICE_ID = 0x03
    ADV_SERVICE_DATA_ID = 0x16

    # Assign local name based on peripheral type
    local_name = PERIPHERAL_DEVICE_NAME[self.peripheral_type]
    local_name_data = [ord(ch) for ch in local_name]

    # LE only, general discoverable
    flag_data = [0x06]

    # Appearance - based on peripheral
    appearance_data = PERIPHERAL_DEVICE_APPEARANCE[self.peripheral_type]

    # Data structure is as follows
    # total len | attr 1 len, attr 1 id, attr 1 data | attr2 ...

    # Create data structure
    data = []

    if 'FAST_PAIR' in self.device_type:
      data.extend(self._FormatDataField(FLAGS_ID, flag_data))
      data.extend(
          self._FormatDataField(ADV_SERVICE_DATA_ID,
                                [0x2c, 0xfe] + self.app.GetServiceData()))
    else:
      data.extend(self._FormatDataField(FULL_LOCAL_NAME_ID, local_name_data))
      data.extend(self._FormatDataField(FLAGS_ID, flag_data))
      data.extend(self._FormatDataField(APPEARANCE_ID, appearance_data))
      data.extend(self._FormatDataField(ADV_SERVICE_ID, [0x12, 0x18]))


    # Pad the packet with zeros to make bluez happy
    data.extend([0] * (31 - len(data)))

    # hci commands can be found in Version 5.1 | Vol 2, Part E Sec 7.8
    # Advertisement structure
    set_adv_data_cmd = HciCommands.le_set_advertising_data(
        data_length=len(data), data=data)

    # (TODO b/158217517) we have found that a race condition exists in two-peer
    # tests where the adv and scan response of a peer is interrupted, which
    # causes the dev info to be incorrect on the DUT. We make the scan response
    # data identical to adv data as a work-around to ameliorate these failures
    # while the underlying issue is fixed

    # Also apply adv data to scan response
    set_adv_resp_cmd = HciCommands.le_set_scan_response_data(
        data_length=len(data), data=data)

    # Stop advertising
    stop_adv = HciCommands.le_set_advertising_enable(enable=False)
    # Start advertising
    start_adv = HciCommands.le_set_advertising_enable(enable=True)

    # Advertise with low duty-cycle (30-35ms) to make discovery faster
    rapid_adv = HciCommands.le_set_advertising_params(
        interval_min=0x30, interval_max=0x38)

    cmds = [stop_adv, set_adv_data_cmd, set_adv_resp_cmd, rapid_adv, start_adv
           ] if self._discoverable else [stop_adv]

    # Add commands and run them via hcitool
    tool = HciTool(sudo=True, wait_time=0.1)

    for cmd in cmds:
      tool.add_command(cmd)

    tool.run_commands()

  def SetDiscoverable(self, discoverable):
    """Change whether device is discoverable and configure advertisements.

    Only configures advertisements if the discoverable value has changed.

    Args:
      discoverable: Whether the device should advertise.
    """
    prev_discoverable = self._discoverable
    self._discoverable = discoverable

    if discoverable != prev_discoverable:
      self._ConfigureAdvertisements()

  def _PropertyChanged(self, *args, **kwargs):
    """Called when a property changes on the bluez d-bus interface

    Useful for tracking the peer's connection and discovery status

    Args:
      args: list of form [caller, property_dict]
      kwargs: dict containing keyword arguments requested in the
      add_signal_receiver call i.e. device_path of calling object
    """

    # Renaming to be more human readable while satisfying pylint
    changed_prop = args
    caller_info = kwargs

    caller = str(changed_prop[0])
    prop_dict = changed_prop[1]

    if 'Device1' in caller:
      if dbus.String('Connected') in prop_dict:
        remote_addr = str(caller_info['device_path']).split('dev_')[-1]
        conn_status = bool(prop_dict[dbus.String('Connected')])

        info_msg = 'Connection change to {}: {}'.format(remote_addr,
                                                        conn_status)
        logging.info(info_msg)

        # Re-enable advertising on disconnect so server can continue
        if not conn_status:
          self._ConfigureAdvertisements()

    if 'Adapter1' in caller:
      if dbus.String('Powered') in prop_dict:
        power_status = bool(prop_dict[dbus.String('Powered')])

        # Re-enable advertising on power up so server can continue
        if power_status:
          self._ConfigureAdvertisements()


def main():
  # Allow logging to work like print when server is run standalone
  logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

  global mainloop # pylint: disable=global-statement

  # Set up main loop for incoming activity on the bus
  dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
  mainloop = GObject.MainLoop()

  # Establish and run server with example HoG application
  server = GATTServer('MOUSE')  # pylint: disable=unused-variable

  mainloop.run()


if __name__ == '__main__':
  main()
