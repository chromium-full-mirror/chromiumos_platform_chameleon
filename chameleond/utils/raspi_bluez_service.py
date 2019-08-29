# -*- coding: utf-8 -*-

# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez Service Classes (for Bluetooth/BLE HID)"""

from __future__ import print_function

import logging
import os
import time

import dbus
import dbus.mainloop.glib
import dbus.service

# Libraries needed on raspberry pi. ImportError on
# Fizz can be ignored.
try:
  from bluetooth import BluetoothSocket, L2CAP
except ImportError:
  pass

try:
  from gi.repository import GLib
except ImportError:
  pass

from bluez_service_consts import BLUEZ_KEYBOARD_SERVICE_NAME, \
    BLUEZ_KEYBOARD_SERVICE_PATH, BLUEZ_KEYBOARD_PROFILE_PATH


KEYBOARD_PROFILE_SDP_PATH = (os.path.dirname(os.path.abspath(__file__)) +
                             '/keyboard_sdp_record.xml')
KEYBOARD_SERVICE_UUID = '00001124-0000-1000-8000-00805f9b34fb'
P_CTRL = 17
P_INTR = 19

MAX_DBUS_RETRY_ATTEMPTS = 3


class BluezServiceException(Exception):
  """Exception class for BluezPeripheral class."""
  def __init__(self, message):
    super(BluezServiceException, self).__init__()
    self.message = message


class BluezKeyboardProfile(dbus.service.Object):
  """Implementation of org.bluez.Profile1 interface for a keyboard."""

  fd = -1
  @dbus.service.method('org.bluez.Profile1',
                       in_signature='', out_signature='')
  def Release(self):
    print('Release')


  @dbus.service.method('org.bluez.Profile1',
                       in_signature='', out_signature='')
  def Cancel(self):
    print('Cancel')


  @dbus.service.method('org.bluez.Profile1',
                       in_signature='oha{sv}', out_signature='')
  def NewConnection(self, path, fd, properties):
    self.fd = fd.take()
    print('NewConnection(%s, %d)' % (path, self.fd))
    for key in properties.keys():
      if key == 'Version' or key == 'Features':
        print('  %s = 0x%04x' % (key, properties[key]))
      else:
        print('  %s = %s' % (key, properties[key]))

  @dbus.service.method('org.bluez.Profile1',
                       in_signature='o', out_signature='')
  def RequestDisconnection(self, path):
    print('RequestDisconnection(%s)' % (path))

    if self.fd > 0:
      os.close(self.fd)
      self.fd = -1

  def __init__(self, bus, path):
    dbus.service.Object.__init__(self, bus, path)


class BluezKeyboardService(dbus.service.Object):
  """Bluez Keyboard Service implementation."""

  def __init__(self, adapter_address):
    self._cinterrupt = None
    self._ccontrol = None

    self._bus = dbus.SystemBus()
    self._bus_name = dbus.service.BusName(BLUEZ_KEYBOARD_SERVICE_NAME,
                                          bus=self._bus)
    super(BluezKeyboardService, self).__init__(self._bus_name,
                                               BLUEZ_KEYBOARD_SERVICE_PATH)

    self._address = adapter_address
    # Init keyboard profile
    self._InitBluezProfile(KEYBOARD_PROFILE_SDP_PATH,
                           BLUEZ_KEYBOARD_PROFILE_PATH,
                           KEYBOARD_SERVICE_UUID)

    self._Listen(self._address)

    # Add a handler for changes in state, specifically requesting caller's
    # device_path in the callback
    self._bus.add_signal_receiver(self.PropertyChanged,
                                  signal_name='PropertiesChanged',
                                  bus_name='org.bluez',
                                  path_keyword='device_path')


  def PropertyChanged(self, *args, **kwargs):
    """Called when a property changes on the bluez d-bus interface

    Useful for tracking the peer's connection and discovery status

    Args:
      args: list of form [caller, property_dict]
      kwargs: dict containing keyword arguments requested in the
      add_signal_receiver call i.e. device_path of calling object
    """

    # Renaming to be more human readable while satisfying pylint
    changed_prop = args
    caller_details = kwargs

    caller = str(changed_prop[0])
    prop_dict = changed_prop[1]

    if 'Device1' in caller:
      if dbus.String('Connected') in prop_dict:
        remote_addr = str(caller_details['device_path']).split('dev_')[-1]
        connection_status = bool(prop_dict[dbus.String('Connected')])

        info_msg = 'Connection change to {}: {}'.format(remote_addr,
                                                        connection_status)
        logging.info(info_msg)

        # Handle disconnection
        if not connection_status:
          self.OnDisconnect()

    elif 'Adapter1' in caller:
      if dbus.String('Discoverable') in prop_dict:
        discoverable_status = bool(prop_dict[dbus.String('Discoverable')])
        info_msg = 'Discovery status changed: {}'.format(discoverable_status)
        logging.info(info_msg)

    else:
      logging.debug('Unknown d-bus signal caller: %s', caller)


  def OnDisconnect(self):
    """Called when disconnection occurs"""

    logging.debug('Bluez keyboard service disconnected')


  def _InitBluezProfile(self, profile_sdp_path,
                        profile_dbus_path,
                        profile_uuid):
    """Register a Bluetooth profile with bluez.

    profile_sdp_path: Relative path of XML file for profile SDP
    profile_uuid:     Service Class/ Profile UUID
    www.bluetooth.com/specifications/assigned-numbers/service-discovery/
    """
    logging.debug('Configuring Bluez Profile from %s',
                  KEYBOARD_PROFILE_SDP_PATH)
    try:
      with open(profile_sdp_path, 'r') as prfd:
        prf_content = prfd.read()
    except IOError as e:
      raise BluezServiceException('I/O error ({0}): {1}'.format(e.errno,
                                                                e.strerror))
    except:
      raise BluezServiceException('Unknown error in _InitBluezProfile()')
    else:
      opts = {
          'ServiceRecord':prf_content,
          'Role':'server',
          'RequireAuthentication':False,
          'RequireAuthorization':False
      }
      self._profile = BluezKeyboardProfile(dbus.SystemBus(), profile_dbus_path)
      manager = dbus.Interface(dbus.SystemBus().get_object('org.bluez',
                                                           '/org/bluez'),
                               'org.bluez.ProfileManager1')

      # Occasionally d-bus manager interface won't be ready in time, so we
      # delay in retry in case of a d-bus failure
      for _ in range(MAX_DBUS_RETRY_ATTEMPTS):
        try:
          manager.RegisterProfile(profile_dbus_path, profile_uuid, opts)
          break
        except dbus.DBusException, e:
          logging.info('Registering profile again... %s', str(e))
          time.sleep(.1)


  def _Listen(self, dev_addr):
    self._scontrol = BluetoothSocket(L2CAP)
    self._sinterrupt = BluetoothSocket(L2CAP)
    self._scch = GLib.IOChannel(self._scontrol.fileno())
    self._sich = GLib.IOChannel(self._sinterrupt.fileno())

    self._scontrol.bind((dev_addr, P_CTRL))
    self._sinterrupt.bind((dev_addr, P_INTR))

    # Start listening on server sockets. Add watch to process connection
    # asynchronously.
    self._scontrol.listen(1)
    self._sinterrupt.listen(1)
    GLib.io_add_watch(self._scch, GLib.IO_IN, self.OnConnect)
    GLib.io_add_watch(self._sich, GLib.IO_IN, self.OnConnect)


  def OnConnect(self, fd, _):
    if fd == self._scch:
      self._ccontrol, _ = self._scontrol.accept()
    elif fd == self._sich:
      self._cinterrupt, _ = self._sinterrupt.accept()
      self.Connected()
      logging.debug('Bluez keyboard service connected')


  @dbus.service.method('org.chromium.autotest.btkbservice', in_signature='yay')
  def SendKeys(self, modifier, keys):
    report = ''
    report += chr(0xA1)
    report += chr(0x01)
    report += chr(modifier)
    report += chr(0x00)
    count = 0
    for key_code in keys:
      if count < 6:
        report += chr(key_code)
        count += 1
    self._cinterrupt.send(report)


  @dbus.service.signal('org.chromium.autotest.btkbservice', signature='')
  def Connected(self):
    pass
