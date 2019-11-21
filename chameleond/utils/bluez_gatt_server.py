# -*- coding: utf-8 -*-

# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module implements gatt server functionality on bluez"""

import logging
import os
from subprocess import call
import sys
import time

import dbus
import dbus.mainloop.glib

try:
  from gi.repository import GObject
except ImportError:
  import gobject as GObject

from bluez_le_hid_service import HIDApplication
from bluetooth_peripheral_kit import PeripheralKit
from example_gatt_server import Application, BLUEZ_SERVICE_NAME, \
    DBUS_OM_IFACE, GATT_MANAGER_IFACE
from bluez_service_consts import PERIPHERAL_DEVICE_APPEARANCE, \
    PERIPHERAL_DEVICE_NAME

mainloop = None


class GATTServer(object):
  """Bluez gatt server implementation"""

  def __init__(self, device_type='generic'):
    bus = dbus.SystemBus()

    adapter = self._FindAdapter(bus)
    if not adapter:
      logging.error('GattManager1 interface not found')
      return

    service_manager = dbus.Interface(
        bus.get_object(BLUEZ_SERVICE_NAME, adapter),
        GATT_MANAGER_IFACE)

    self.device_type = device_type
    self.peripheral_type = None
    if 'MOUSE' in self.device_type:
      self.peripheral_type = PeripheralKit.MOUSE
    if 'KEYBOARD' in self.device_type:
      self.peripheral_type = PeripheralKit.KEYBOARD

    # Choose application using args
    if 'MOUSE' in self.device_type or 'KEYBOARD' in self.device_type:
      self.app = HIDApplication(bus, self.device_type)
      logging.info('HID %s application starting...', self.device_type)

    else:
      # Default to generic application provided in example
      self.app = Application(bus)
      logging.info('Generic application starting...')

    # We register application with empty callbacks to run it async
    service_manager.RegisterApplication(self.app.GetPath(), {},
                                        reply_handler=self._RegisterAppCB,
                                        error_handler=self._RegisterAppErrCB)

    # With application running, call for advertisements to start
    self._ConfigureAdvertisements()

    # Add a handler for changes in state, specifically requesting caller's
    # device_path in the callback
    bus.add_signal_receiver(self._PropertyChanged,
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

    remote_om = dbus.Interface(bus.get_object(BLUEZ_SERVICE_NAME, '/'),
                               DBUS_OM_IFACE)

    # TODO b:142131418 occasionally this stalls and times out, causing 25s delay
    objects = remote_om.GetManagedObjects()

    for o, props in objects.items():
      if GATT_MANAGER_IFACE in props.keys():
        return o

    return None


  def _FormatDataField(self, attr_id, data):
    """Puts each data block into the correct structure

    Returns:
      data in structure [attr len, attr id, attr data]
    """

    formatted_data = [len(data)+1, attr_id]
    formatted_data.extend(data)

    return formatted_data


  def _ConfigureAdvertisements(self):
    """Configures and registers LE advertisement"""

    FULL_LOCAL_NAME_ID = 0x09
    FLAGS_ID = 0x01
    APPEARANCE_ID = 0x19
    ADV_SERVICE_ID = 0x03

    # Assign local name based on peripheral type
    local_name = PERIPHERAL_DEVICE_NAME[self.peripheral_type]
    local_name_data = [ord(ch) for ch in local_name]

    # Assign local name
    os.system("sudo hciconfig hci0 name \'{}\'".format(local_name))

    # LE only, general discoverable
    flag_data = [0x06]

    # Appearance - based on peripheral
    appearance_data = PERIPHERAL_DEVICE_APPEARANCE[self.peripheral_type]

    # Service UUIDs - advertise HID service
    service_uuid_data = [0x12, 0x18]

    # Data structure is as follows
    # total len | attr 1 len, attr 1 id, attr 1 data | attr2 ...

    # Create data structure
    data = []
    data.extend(self._FormatDataField(FULL_LOCAL_NAME_ID, local_name_data))
    data.extend(self._FormatDataField(FLAGS_ID, flag_data))
    data.extend(self._FormatDataField(APPEARANCE_ID, appearance_data))
    data.extend(self._FormatDataField(ADV_SERVICE_ID, service_uuid_data))

    # Pad the packet with zeros to make bluez happy
    data.extend([0] * (31-len(data)))

    # Add total length of data to front of data, followed by data
    dat = '{:02x} {}'.format(len(data), ' '.join(['{:02x}'.format(val)
                                                  for val in data]))

    # hci commands can be found in Version 5.1 | Vol 2, Part E Sec 7.8
    # Advertisement structure
    adv_cmd = 'sudo hcitool -i hci0 cmd 0x08 0x0008 {}'.format(dat)
    # Stop advertising
    stop_adv = 'sudo hcitool -i hci0 cmd 0x08 0x000a 00'
    # Start advertising
    start_adv = 'sudo hcitool -i hci0 cmd 0x08 0x000a 01'
    # Advertise with low duty-cycle (100ms) to make discovery faster
    rapid_adv = ('sudo hcitool -i hci0 cmd 0x08 0x0006 A0 00'
                 ' A0 00 00 00 00 00 00 00 00 00 00 07 00')

    # Run commands sequentially
    for cmd in [stop_adv, adv_cmd, rapid_adv, start_adv]:
      call(cmd, shell=True, stdout=open(os.devnull, 'w'))
      time.sleep(.1)


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

  # Set up main loop for incoming activity on the bus
  global mainloop
  dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
  mainloop = GObject.MainLoop()

  # Establish and run server with example HoG application
  server = GATTServer('MOUSE')

  mainloop.run()

if __name__ == '__main__':
  main()
