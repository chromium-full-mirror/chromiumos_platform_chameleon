# -*- coding: utf-8 -*-

# Copyright 2019 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module implements the PeripheralKit instance for a bluez peripheral
   on Raspberry Pi.
"""

import logging
import os
import sys
import threading
import time

import dbus
import dbus.mainloop.glib
import dbus.service

# Libraries needed on raspberry pi. ImportError on
# Fizz can be ignored.
try:
  from gi.repository import GLib
except ImportError:
  pass

from chameleond.utils.raspi_bluez_service import BluezService
from bluetooth_peripheral_kit import PeripheralKit
from bluetooth_peripheral_kit import PeripheralKitException
from bluez_service_consts import PERIPHERAL_DEVICE_CLASS, \
    PERIPHERAL_DEVICE_NAME, BLUEZ_SERVICE_NAME, BLUEZ_SERVICE_PATH
from bluez_gatt_server import GATTServer

DBUS_BLUEZ_SERVICE_IFACE = 'org.bluez'
DBUS_BLUEZ_ADAPTER_IFACE = DBUS_BLUEZ_SERVICE_IFACE + '.Adapter1'
DBUS_BLUEZ_DEVICE_IFACE = DBUS_BLUEZ_SERVICE_IFACE + '.Device1'

MAX_DBUS_RETRY_ATTEMPTS = 3
CONNECTION_WAIT_TIME = 5

# Definitions of mouse button HID encodings
RAW_HID_BUTTONS_RELEASED = 0x0
RAW_HID_LEFT_BUTTON = 0x01
RAW_HID_RIGHT_BUTTON = 0x02

# UART input modes
# raw mode
UART_INPUT_RAW_MODE = 0xFD
RAW_REPORT_START = 0xA1
# Length of report format for keyboard
RAW_REPORT_FORMAT_KEYBOARD_LENGTH = 9
RAW_REPORT_FORMAT_KEYBOARD_DESCRIPTOR = 1
RAW_REPORT_FORMAT_KEYBOARD_LEN_SCAN_CODES = 6

# shorthand mode
UART_INPUT_SHORTHAND_MODE = 0xFE
SHORTHAND_REPORT_FORMAT_KEYBOARD_MAX_LEN_SCAN_CODES = 6
# Length of report format for mouse
RAW_REPORT_FORMAT_MOUSE_LENGTH = 5
RAW_REPORT_FORMAT_MOUSE_DESCRIPTOR = 2


class BluezPeripheralException(PeripheralKitException):
  """A dummy exception class for Bluez class."""
  pass


class BluezPeripheral(PeripheralKit):
  """This is an abstraction of a Bluez peripheral."""


  def __init__(self):
    super(BluezPeripheral, self).__init__()
    self._settings = {}
    self._setup_dbus_loop()

    self.remote_address = None
    self._bluez_service = None
    self._service = None
    self._device_type = None

    # Bluez DBus constants - npnext
    self._service_iface = None
    self._dbus_system_bus = dbus.SystemBus()
    self._dbus_hci_adapter_path = '/org/bluez/hci0'
    self._dbus_hci_props = dbus.Interface(self._dbus_system_bus.get_object(\
                                                            'org.bluez',\
                                                            '/org/bluez/hci0'),\
                                          'org.freedesktop.DBus.Properties')

    # Power on the device - this should only need to happen once
    # Occasionally the resource isn't up in time, so we retry
    self._set_hci_prop('org.bluez.Adapter1', 'Powered', dbus.Boolean(1))

    logging.debug('Bluetooth peripheral powered and waiting for bind to device')


  def _setup_dbus_loop(self):
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    self._loop = GLib.MainLoop()
    self._thread = threading.Thread(target=self._loop.run)
    self._thread.start()


  def _set_hci_prop(self, iface_name, prop_name, prop_val):
    """Handles HCI property set

    Sometimes resource isn't ready, so this utility will repeat commands
    multiple times to allow more reliable operation

    Returns:
      True if set succeeds, False otherwise
    """

    for _ in range(MAX_DBUS_RETRY_ATTEMPTS):
      try:
        self._dbus_hci_props.Set(iface_name, prop_name, prop_val)

        # Ensure property was successfully set
        if self._dbus_hci_props.Get(iface_name, prop_name) == prop_val:
          return True

        else:
          error_msg = 'Prop set but stale... try again'
          logging.error(error_msg)
          time.sleep(.1)

      except dbus.exceptions.DBusException:
        error_msg = 'Setting {} to {} again'.format(prop_name, prop_val)
        logging.error(error_msg)
        time.sleep(.1)

    return False


  def GetCapabilities(self):
    """What can this kit do/not do that tests need to adjust for?

    Returns:
      A dictionary from PeripheralKit.CAP_* strings to an appropriate value.
      See PeripheralKit for details.
    """
    capabilities = {PeripheralKit.CAP_TRANSPORTS:
                    [PeripheralKit.TRANSPORT_BREDR, PeripheralKit.TRANSPORT_LE],
                    PeripheralKit.CAP_HAS_PIN: True,
                    PeripheralKit.CAP_INIT_CONNECT: True}

    return capabilities


  def EnableBLE(self, use_ble):
    """Put device into either LE or Classic mode

    The raspi is a dual device, supporting both LE and Classic BT. If we are
    testing LE connections, I don't want the DUT to successfully be able to
    make a classic connection, for instance, so the unwanted one is disabled
    """

    if use_ble:
      state_change_cmds = ['sudo btmgmt power off',
                           'sudo btmgmt le on',
                           'sudo btmgmt privacy on',
                           'sudo btmgmt bredr off',
                           'sudo btmgmt ssp on',
                           'sudo btmgmt power on']

    else:
      state_change_cmds = ['sudo btmgmt power off',
                           'sudo btmgmt bredr on',
                           'sudo btmgmt le off',
                           'sudo btmgmt ssp on',
                           'sudo btmgmt power on']

    for cmd in state_change_cmds:
      os.system(cmd)

      # I add a slight delay so there is adequate time for the change to be done
      time.sleep(.1)


  def GetBaseDeviceType(self, device_type):
    """Returns the base device type of a peripheral, i.e. BLE_MOUSE -> MOUSE"""

    if 'BLE_' in device_type:
      device_type = device_type.replace('BLE_', '')

    return device_type


  def SpecifyDeviceType(self, device_type):
    """Instantiates one of our supported devices

    The raspi stack is designed to emulate a single device at a time. This
    function is called by autotest and defines which device must be emulated
    for the current test

    Args:
      device_type: String device type, e.g. "MOUSE"
    """

    # Do nothing if we were already bound to this device
    if self._device_type == device_type:
      return True

    if self._device_type is not None:
      error = 'Peripheral already bound to device: {}'.format(self._device_type)
      logging.error(error)
      raise BluezPeripheralException(error)

    self._device_type = device_type

    if 'BLE' in device_type:
      logging.info('Binding to BLE device!')

      # Enable le only, to make sure our test device isn't connecting
      # via BT classic
      self.EnableBLE(True)

      # Establish and run gatt server
      server = GATTServer(device_type)

    else:
      logging.info('Binding to Classic device!')

      # Enable bt classic only, to make sure our test device isn't connecting
      # via LE
      self.EnableBLE(False)

      # Set device type and initiate service based on it
      self._bluez_service = BluezService(self._device_type,
                                         self.GetLocalBluetoothAddress())

      self.Init()


    self.SetAdvertisedName(PERIPHERAL_DEVICE_NAME[self.GetBaseDeviceType(\
                                                  self._device_type)])

    logging.info('Bluetooth peripheral now bound to %s', device_type)

    # Give the service a moment to initialize
    time.sleep(1)

    return True


  def ResetStack(self):
    """Restores BT stack to pristine state by restarting running services"""
    reset_cmds = ['service bluetooth restart',
                  '/etc/init.d/chameleond restart']

    # Disable power
    self._set_hci_prop('org.bluez.Adapter1', 'Powered', dbus.Boolean(0))

    # Restart chameleon and bluetooth service
    os.system(' && '.join(reset_cmds))


  # Power cycle the device
  def PowerCycle(self):
    return self.Reboot()


  # Override BluetoothHID's implementation of init
  def Init(self, factory_reset=True):
    """Ensures our chip is in the correct state for the tests to be run"""

    # Make sure device is powered up and discoverable
    self._set_hci_prop('org.bluez.Adapter1', 'Discoverable', dbus.Boolean(1))

    # Set class based on device we're emulating
    if self._device_type and 'BLE' not in self._device_type:
      self.SetClassOfService(PERIPHERAL_DEVICE_CLASS[self._device_type])

    return True


  def CreateSerialDevice(self):
    """Device setup and recovery

        In the current test framework, CreateSerialDevice is called for
        device initialization or to try and correct an error. While we
        don't have a serial connection, this function is used in the same
        way - device setup and recovery
    """

    return self.Init()


  # Check the serial device we aren't using
  def CheckSerialConnection(self):
    return True


  # Close the serial device we aren't using
  def Close(self):
    return True


  def EnterCommandMode(self):
    return True


  def GetPort(self):
    return '/dev/fakedev'


  def Reboot(self):
    logging.info('REBOOTING')

    # Turn it off
    self._set_hci_prop('org.bluez.Adapter1', 'Powered', dbus.Boolean(0))

    # Turn it back on again
    self._set_hci_prop('org.bluez.Adapter1', 'Powered', dbus.Boolean(1))

    # Put ourselves back into correct state for discovery
    return self.Init()


  def SetAdvertisedName(self, name):
    self._set_hci_prop('org.bluez.Adapter1', 'Alias', dbus.String(name))


  def GetAuthenticationMode(self):
    return PeripheralKit.OPEN_MODE


  def GetPinCode(self):
    return '0000'


  def GetLocalBluetoothAddress(self):
    """Get the builtin Bluetooth MAC address.

    If the HCI device doesn't exist, Get() will throw an exception
    (dbus.exceptions.DBus.Error.UnknownObject)
    """
    try:
      addr = str(self._dbus_hci_props.Get('org.bluez.Adapter1', 'Address'))
    except dbus.exceptions.DBusException:
      addr = None
    return addr


  def GetConnectionStatus(self):
    """Determine whether the device has an active connection

    Returns:
      True if a connection is active, False otherwise
    """

    # If we can't find a connected object, no active connections
    if self.GetRemoteConnectedBluetoothAddress() is not None:
      return True

    return False


  def _GetDeviceWithAddress(self, addr):
    manager = dbus.Interface(self._dbus_system_bus.get_object('org.bluez', '/'),
                             'org.freedesktop.DBus.ObjectManager')

    objects = manager.GetManagedObjects()

    # Go through each object in org.bluez.Device1 until
    # we find the one that matches our desired address
    for path, ifaces in objects.items():
      device = ifaces.get(DBUS_BLUEZ_DEVICE_IFACE)

      if device is not None and device['Address'] == addr:
        obj = self._dbus_system_bus.get_object('org.bluez', path)
        return dbus.Interface(obj, DBUS_BLUEZ_DEVICE_IFACE)


  def GetRemoteConnectedBluetoothAddress(self):
    """Get the address of the current connected device, if applicable

    Returns:
      None if no connection can be found
      Mac address of connected device i
    """

    # Grab ObjectManager and its objects
    manager = dbus.Interface(self._dbus_system_bus.get_object('org.bluez', '/'),
                             'org.freedesktop.DBus.ObjectManager')

    objects = manager.GetManagedObjects()

    # Go through each obj in org.bluez.Device1 and check "Connected" attribute
    for _, ifaces in objects.items():
      device = ifaces.get(DBUS_BLUEZ_DEVICE_IFACE)
      if device is None:
        continue
      if device['Address'] is not None and device['Connected']:
        return device['Address']

    return None


  def SetClassOfService(self, class_of_service):
    # Class is a read-only DBus property, so needs to be set using system calls.
    cmd = 'sudo hciconfig hci0 class {}'.format(hex(class_of_service))
    os.system(cmd)


  def SetRemoteAddress(self, remote_address):
    """Sets address later used for connect

    Args:
      remote_address: string denoting remote address
    """
    self.remote_address = remote_address
    return True


  def Connect(self):
    """Attempts to connect to the address specified with SetRemoteAddress()"""

    if self.remote_address is None:
      logging.error('Connect called with no remote address supplied')
      return False

    logging.debug('Attempting to connect to %s', self.remote_address)

    # Establish link to service if we don't have it already
    if not self._service_iface:
      self._service = self._dbus_system_bus.get_object(BLUEZ_SERVICE_NAME,
                                                       BLUEZ_SERVICE_PATH)
      self._service_iface = dbus.Interface(self._service, BLUEZ_SERVICE_NAME)

    # Request Bluez service to connect to address
    self._service_iface.Connect(self.remote_address,
                                reply_handler=self.ConnectDoneHandler,
                                error_handler=self.ConnectErrorHandler)

    # Autotest currently doesn't account for the time it takes for connection
    # to succeed, so we put a small wait here. TODO b:145628709
    time.sleep(CONNECTION_WAIT_TIME)

    return True


  def ConnectDoneHandler(self):
    """Called when connect completes"""
    pass


  def ConnectErrorHandler(self, err):
    """Called in case of error on connect"""
    logging.error('ConnectErrorHandler: %s', err)


  def Disconnect(self):
    """Requests a disconnect from the remote device

    Returns:
      True if connected device exists, False otherwise
    """

    logging.debug('Disconnecting from adapter')

    # Can't do anything if we're not connected
    if not self.GetConnectionStatus():
      return False

    device = self._GetDeviceWithAddress(self.remote_address)
    device.Disconnect()

    return True


  def SendHIDReport(self, report):
    """Sends a hid report to our bluez service

    Args:
      report: scan code representing state of HID device
    """

    if not self._service_iface:
      self._service = self._dbus_system_bus.get_object(BLUEZ_SERVICE_NAME,
                                                       BLUEZ_SERVICE_PATH)
      self._service_iface = dbus.Interface(self._service, BLUEZ_SERVICE_NAME)

    # Passing with empty handlers allows operation to run async
    self._service_iface.SendHIDReport(report,
                                      reply_handler=self.KeysSentHandler,
                                      error_handler=self.KeysErrorHandler)


  def KeysSentHandler(self):
    """Called when hid report send completes"""
    pass


  def KeysErrorHandler(self, err):
    """Called in case of error on hid report send"""
    logging.error('KeysErrorHandler: %s', err)


  def _CheckValidModifiers(self, modifiers):
    invalid_modifiers = [m for m in modifiers if m not in self.MODIFIERS]
    if invalid_modifiers:
      logging.error('Modifiers not valid: "%s".', str(invalid_modifiers))
      return False
    return True


  def _IsValidScanCode(self, code):
    """Check if the code is a valid scan code.

    Args:
      code: the code to check

    Returns:
      True: if the code is a valid scan code.
    """
    return (self.SCAN_NO_EVENT <= code <= self.SCAN_PAUSE or
            self.SCAN_SYSTEM_POWER <= code <= self.SCAN_SYSTEM_WAKE)


  def _CheckValidScanCodes(self, keys):
    invalid_keys = [k for k in keys if not self._IsValidScanCode(k)]
    if invalid_keys:
      logging.error('Keys not valid: "%s".', str(invalid_keys))
      return False
    return True


  def RawKeyCodes(self, modifiers=None, keys=None):
    """Generate the codes in raw keyboard report format.

    This method sends data in the raw report mode. The first start
    byte chr(UART_INPUT_RAW_MODE) is stripped and the following bytes
    are sent without interpretation.

    For example, generate the codes of 'shift-alt-i' by
      codes = RawKeyCodes(modifiers=[RasPi.LEFT_SHIFT, RasPi.LEFT_ALT],
                          keys=[RasPi.SCAN_I])

    Args:
      modifiers: a list of modifiers
      keys: a list of scan codes of keys

    Returns:
      a raw code string if both modifiers and keys are valid, or
      None otherwise.
    """
    modifiers = modifiers or []
    keys = keys or []

    if not (self._CheckValidModifiers(modifiers) and
            self._CheckValidScanCodes(keys)):
      return None

    real_scan_codes = [chr(key) for key in keys]
    padding_0s = (chr(0) * (RAW_REPORT_FORMAT_KEYBOARD_LEN_SCAN_CODES -
                            len(real_scan_codes)))

    return (chr(UART_INPUT_RAW_MODE) +
            chr(RAW_REPORT_FORMAT_KEYBOARD_LENGTH) +
            chr(RAW_REPORT_FORMAT_KEYBOARD_DESCRIPTOR) +
            chr(sum(modifiers)) +
            chr(0x0) +
            ''.join(real_scan_codes) +
            padding_0s)


  def _MouseButtonsRawHidValues(self):
    """Gives the raw HID values for whatever buttons are pressed."""
    currently_pressed = 0x0
    for button in self._buttons_pressed:
      if button == PeripheralKit.MOUSE_BUTTON_LEFT:
        currently_pressed |= RAW_HID_LEFT_BUTTON
      elif button == PeripheralKit.MOUSE_BUTTON_RIGHT:
        currently_pressed |= RAW_HID_RIGHT_BUTTON
      else:
        error = 'Unknown mouse button in state: %s' % button
        logging.error(error)
        raise BluezPeripheralException(error)
    return currently_pressed


  def MouseMove(self, delta_x, delta_y):
    """Move the mouse (delta_x, delta_y) steps.

    If buttons are being pressed, they will stay pressed during this operation.
    This move is relative to the current position by the HID standard.
    Valid step values must be in the range [-127,127].

    Args:
      delta_x: The number of steps to move horizontally.
               Negative values move left, positive values move right.
      delta_y: The number of steps to move vertically.
               Negative values move up, positive values move down.
    """
    raw_buttons = self._MouseButtonsRawHidValues()
    if delta_x or delta_y:
      mouse_codes = self._RawMouseCodes(buttons=raw_buttons, x_stop=delta_x,
                                        y_stop=delta_y)
      self.SendHIDReport(mouse_codes)


  def MouseScroll(self, steps):
    """Scroll the mouse wheel steps number of steps.

    Buttons currently pressed will stay pressed during this operation.
    Valid step values must be in the range [-127,127].

    Args:
      steps: The number of steps to scroll the wheel.
             With traditional scrolling:
               Negative values scroll down, positive values scroll up.
             With reversed (formerly "Australian") scrolling this is reversed.
    """
    raw_buttons = self._MouseButtonsRawHidValues()
    if steps:
      mouse_codes = self._RawMouseCodes(buttons=raw_buttons, wheel=steps)
      self.SendHIDReport(mouse_codes)


  def MousePressButtons(self, buttons):
    """Press the specified mouse buttons.

    The kit will continue to press these buttons until otherwise instructed, or
    until its state has been reset.

    Args:
      buttons: A set of buttons, as PeripheralKit MOUSE_BUTTON_* values, that
               will be pressed (and held down).
    """
    self._MouseButtonStateUnion(buttons)
    raw_buttons = self._MouseButtonsRawHidValues()
    if raw_buttons:
      mouse_codes = self._RawMouseCodes(buttons=raw_buttons)
      self.SendHIDReport(mouse_codes)


  def MouseReleaseAllButtons(self):
    """Release all mouse buttons."""
    self._MouseButtonStateClear()
    mouse_codes = self._RawMouseCodes(buttons=RAW_HID_BUTTONS_RELEASED)
    self.SendHIDReport(mouse_codes)


  def _RawMouseCodes(self, buttons=0, x_stop=0, y_stop=0, wheel=0):
    """Generate the codes in mouse raw report format.

    This method sends data in the raw report mode. The first start
    byte chr(UART_INPUT_RAW_MODE) is stripped and the following bytes
    are sent without interpretation.

    For example, generate the codes of moving cursor 100 pixels left
    and 50 pixels down:
      codes = _RawMouseCodes(x_stop=-100, y_stop=50)

    Args:
      buttons: the buttons to press and release
      x_stop: the pixels to move horizontally
      y_stop: the pixels to move vertically
      wheel: the steps to scroll

    Returns:
      a raw code string.
    """
    def SignedChar(value):
      """Converted the value to a legitimate signed character value.

      Given value must be in [-127,127], or odd things will happen.

      Args:
        value: a signed integer

      Returns:
        a signed character value
      """
      if value < 0:
        # Perform two's complement.
        return value + 256
      return value

    return (chr(RAW_REPORT_START) +
            chr(RAW_REPORT_FORMAT_MOUSE_DESCRIPTOR) +
            chr(SignedChar(buttons)) +
            chr(SignedChar(x_stop)) +
            chr(SignedChar(y_stop)) +
            chr(SignedChar(wheel)))


  def PressShorthandCodes(self, modifiers=None, keys=None):
    """Generate key press codes in shorthand report format.

    Only key press is sent. The shorthand mode is useful in separating the
    key press and key release events.

    For example, generate the codes of 'shift-alt-i' by
      codes = PressShorthandCodes(modifiers=[RasPi.LEFT_SHIFT, RasPi.LEFT_ALT],
                                  keys=[RasPi_I])

    Args:
      modifiers: a list of modifiers
      keys: a list of scan codes of keys

    Returns:
      a shorthand code string if both modifiers and keys are valid, or
      None otherwise.
    """
    modifiers = modifiers or []
    keys = keys or []

    if not (self._CheckValidModifiers(modifiers) and
            self._CheckValidScanCodes(keys)):
      return None

    if len(keys) > SHORTHAND_REPORT_FORMAT_KEYBOARD_MAX_LEN_SCAN_CODES:
      return None

    return (chr(UART_INPUT_SHORTHAND_MODE) +
            chr(len(keys) + 1) +
            chr(sum(modifiers)) +
            ''.join([chr(key) for key in keys]))


  def ReleaseShorthandCodes(self):
    """Generate the shorthand report format code for key release.

    Key release is sent.

    Returns:
      a special shorthand code string to release any pressed keys.
    """
    return chr(UART_INPUT_SHORTHAND_MODE) + chr(0x0)


  def GetKitInfo(self):
    """A simple demo of getting kit information."""
    logging.info('advertised name: %s', self.GetAdvertisedName())
    logging.info('local bluetooth address: %s', self.GetLocalBluetoothAddress())
    class_of_service = self.GetClassOfService()
    try:
      class_of_service = hex(class_of_service)
    except TypeError:
      pass
    logging.info('Class of service: %s', class_of_service)
    class_of_device = self.GetClassOfDevice()
    try:
      class_of_device = hex(class_of_device)
    except TypeError:
      pass
    logging.info('Class of device: %s', class_of_device)


if __name__ == '__main__':
  # To allow basic printing when run from command line
  logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

  kit_instance = BluezPeripheral()
  kit_instance.GetKitInfo()
