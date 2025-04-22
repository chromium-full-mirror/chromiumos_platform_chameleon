# Lint as: python2, python3
# -*- coding: utf-8 -*-

# Copyright 2019 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module implements the PeripheralKit instance for a bluez peripheral
on Raspberry Pi.
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import logging
import os
import re
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


from chameleond.utils import pairing_agent
from chameleond.utils import system_tools
from chameleond.utils.bluez_observer import BlueZObserver
from chameleond.utils.raspi_bluez_service import BluezHIDService
from chameleond.utils.raspi_bluez_service import BluezRfcommEchoService
from six.moves import range

from . import bluetooth_socket
from .bluetooth_peripheral_kit import PeripheralKit
from .bluetooth_peripheral_kit import PeripheralKitException
from .bluez_gatt_server import GATTServer
from .bluez_gatt_server import PUBLIC_DEVICE_ADDRESS
from .bluez_gatt_server import RANDOM_DEVICE_ADDRESS
from .bluez_service_consts import BLUEZ_HID_SERVICE_NAME
from .bluez_service_consts import BLUEZ_HID_SERVICE_PATH
from .bluez_service_consts import BTD_CONF_FILE
from .bluez_service_consts import PERIPHERAL_BTD_FLAGS
from .bluez_service_consts import PERIPHERAL_DEVICE_CLASS
from .bluez_service_consts import PERIPHERAL_DEVICE_NAME
from .hci_cmd import HciCommands
from .hci_cmd import HciTool


DBUS_BLUEZ_SERVICE_IFACE = "org.bluez"
DBUS_BLUEZ_ADAPTER_IFACE = DBUS_BLUEZ_SERVICE_IFACE + ".Adapter1"
DBUS_BLUEZ_DEVICE_IFACE = DBUS_BLUEZ_SERVICE_IFACE + ".Device1"
DBUS_PROP_IFACE = "org.freedesktop.DBus.Properties"
DBUS_OBJECT_MANAGER_INTERFACE = "org.freedesktop.DBus.ObjectManager"

# Time to wait for bluetoothd to start
BLUETOOTHD_WAIT_TIME = 30
MAX_DBUS_RETRY_ATTEMPTS = 3
CONNECTION_WAIT_TIME = 10

# Definitions of mouse button HID encodings
RAW_HID_BUTTONS_RELEASED = 0x0
RAW_HID_LEFT_BUTTON = 0x01
RAW_HID_RIGHT_BUTTON = 0x02

# Definitions of gamepad button HID encodings
RAW_HID_GAMEPAD_BTN_START = 0x08
RAW_HID_GAMEPAD_BTN_A = 0x01
RAW_HID_GAMEPAD_BTN_B = 0x02
RAW_HID_GAMEPAD_BTN_X = 0x08
RAW_HID_GAMEPAD_BTN_Y = 0x10
RAW_HID_GAMEPAD_BTN_LEFT = 0x07
RAW_HID_GAMEPAD_BTN_RIGHT = 0x03
RAW_HID_GAMEPAD_BTN_UP = 0x01
RAW_HID_GAMEPAD_BTN_DOWN = 0x05
RAW_HID_GAMEPAD_LB = 0x40
RAW_HID_GAMEPAD_RB = 0x80
RAW_HID_GAMEPAD_LS = 0x20
RAW_HID_GAMEPAD_RS = 0x40

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

# Length of report format for gamepad
RAW_REPORT_FORMAT_GAMEPAD_LENGTH = 1
RAW_REPORT_FORMAT_GAMEPAD_DESCRIPTOR = 4

# Time to wait about the pairing agent to exit.
AGENT_EXIT_TIMEOUT_SECS = 5

GAMEPAD_BUTTONS_MAP = {
    PeripheralKit.GAMEPAD_BUTTON_START: RAW_HID_GAMEPAD_BTN_START,
    PeripheralKit.GAMEPAD_BUTTON_A: RAW_HID_GAMEPAD_BTN_A,
    PeripheralKit.GAMEPAD_BUTTON_B: RAW_HID_GAMEPAD_BTN_B,
    PeripheralKit.GAMEPAD_BUTTON_X: RAW_HID_GAMEPAD_BTN_X,
    PeripheralKit.GAMEPAD_BUTTON_Y: RAW_HID_GAMEPAD_BTN_Y,
    PeripheralKit.GAMEPAD_BUTTON_LEFT: RAW_HID_GAMEPAD_BTN_LEFT,
    PeripheralKit.GAMEPAD_BUTTON_RIGHT: RAW_HID_GAMEPAD_BTN_RIGHT,
    PeripheralKit.GAMEPAD_BUTTON_UP: RAW_HID_GAMEPAD_BTN_UP,
    PeripheralKit.GAMEPAD_BUTTON_DOWN: RAW_HID_GAMEPAD_BTN_DOWN,
    PeripheralKit.GAMEPAD_BUTTON_LEFT_BUMPER: RAW_HID_GAMEPAD_LB,
    PeripheralKit.GAMEPAD_BUTTON_RIGHT_BUMPER: RAW_HID_GAMEPAD_RB,
    PeripheralKit.GAMEPAD_LEFT_THUMBSTICK: RAW_HID_GAMEPAD_LS,
    PeripheralKit.GAMEPAD_RIGHT_THUMBSTICK: RAW_HID_GAMEPAD_RS,
}

GAMEPAD_BUTTONS_REPORT_INDEX = {
    "LEFT_STICK": 0,
    "RIGHT_STICK": 4,
    "LEFT_TRIGGER": 8,
    "RIGHT_TRIGGER": 10,
    "GAMEPAD_BUTTON_LEFT": 12,
    "GAMEPAD_BUTTON_RIGHT": 12,
    "GAMEPAD_BUTTON_UP": 12,
    "GAMEPAD_BUTTON_DOWN": 12,
    "GAMEPAD_BUTTON_A": 13,
    "GAMEPAD_BUTTON_B": 13,
    "GAMEPAD_BUTTON_X": 13,
    "GAMEPAD_BUTTON_Y": 13,
    "GAMEPAD_BUTTON_LEFT_BUMPER": 13,
    "GAMEPAD_BUTTON_RIGHT_BUMPER": 13,
    "GAMEPAD_LEFT_THUMBSTICK": 14,
    "GAMEPAD_RIGHT_THUMBSTICK": 14,
    "GAMEPAD_BUTTON_START": 14,
}


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
        self.device_type = None
        self._address = None
        self._bluez_service = None
        self._service = None
        self._gatt_server = None

        # Bluez DBus constants - npnext
        self._service_iface = None
        self._adapter_iface = None
        self._dbus_system_bus = dbus.SystemBus()
        self._dbus_hci_adapter_path = "/org/bluez/hci0"
        self._dbus_hci_props = None

        # Make sure adapter is powered for tests. _set_hci_prop will connect
        # self._dbus_hci_props, and even start bluetoothd if necessary
        self._set_hci_prop("org.bluez.Adapter1", "Powered", dbus.Boolean(1))

        self._agent = None
        # 16 is the length of gamepad report bytes that changed according to
        # pressed buttons.
        self.gamepad_report = [0x00] * 16

        self.bluez_observer = BlueZObserver(self._dbus_system_bus)

        logging.debug(
            "Bluetooth peripheral powered and waiting for bind to device"
        )

    def __del__(self):
        """Quit the mainloop when done."""
        self._loop.quit()

    def cleanup(self):
        logging.info("BluezPeripheral: cleanup")
        if self._gatt_server:
            self._gatt_server.cleanup()
            self._gatt_server = None

        if self._bluez_service:
            self._bluez_service.cleanup()
            self._bluez_service = None

        if self._agent:
            self.StopPairingAgent()

        if self.bluez_observer:
            self.bluez_observer.cleanup()

        self._loop.quit()

    def get_service_iface(self):
        if not self._service_iface:
            self._service = self._dbus_system_bus.get_object(
                BLUEZ_HID_SERVICE_NAME, BLUEZ_HID_SERVICE_PATH
            )
            self._service_iface = dbus.Interface(
                self._service, BLUEZ_HID_SERVICE_NAME
            )

        return self._service_iface

    def StartPairingAgent(self, capability):
        """Start a pairing agent with the specified capability.

        Args:
          capability: the capability of the device.
                      The capability parameter can have the values:
                      DisplayOnly, DisplayYesNo, KeyboardOnly, NoInputNoOutput
                      and KeyboardDisplay.
                      Refer to bluez/doc/agent-api.txt for more details.
        """
        if self._agent:
            self.StopPairingAgent()

        agent_registered_event = threading.Event()

        self._agent = threading.Thread(
            target=pairing_agent.SetupAgent,
            args=(capability, agent_registered_event),
        )
        self._agent.start()
        agent_registered_event.wait()
        logging.info(
            "The pairing agent is started with capability %s", capability
        )

    def StopPairingAgent(self):
        """Stop the pairing agent."""
        logging.info("Stop the pairing agent")
        if self._agent:
            pairing_agent.StopAgent()
            self._agent.join(AGENT_EXIT_TIMEOUT_SECS)
            logging.info("agent exited and joined")
            self._agent = None

    def _setup_dbus_loop(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self._loop = GLib.MainLoop()
        self._thread = threading.Thread(target=self._loop.run)
        self._thread.start()

    def _kill_bluetoothd(self):
        """Calls for bluetoothd to be killed, in case it is in a bad state"""

        os.system("killall -9 bluetoothd")

    def _start_bluetoothd(self):
        """Calls for bluetoothd to be started, if not started already"""

        os.system("sudo service bluetooth start")

    def unpack_if_variant(self, value):
        """If given value is GLib.Variant, unpack it to the actual type."""
        if isinstance(value, GLib.Variant):
            return value.unpack()
        return value

    def _check_prop_handle(self, handle):
        """Checks if bluetoothd is running by accessing an adapter object"""

        try:
            handle.Get("org.bluez.Adapter1", "Powered")
            return True

        except Exception as e:
            logging.info(
                "Failed to retrieve bluez adapter property: %s", str(e)
            )
            return False

    def _create_prop_handle(self):
        """Establish dbus link to bluetoothd for hci properties

        Returns: dbus interface to bluetoothd properties
        """

        return dbus.Interface(
            self._dbus_system_bus.get_object("org.bluez", "/org/bluez/hci0"),
            "org.freedesktop.DBus.Properties",
        )

    def _refresh_hci_prop_handle(self):
        """Initializes a dbus handle to hci properties"""

        # If we already have a link to bluetoothd, just return it
        if self._dbus_hci_props is not None:
            return

        # Next step, try to link to already-running bluetoothd
        handle = self._create_prop_handle()

        if self._check_prop_handle(handle):
            self._dbus_hci_props = handle
            return

        # A pgrep return of 0 indicates that a process was found. If bluetoothd is
        # running and we can't reach it, kill and restart to get it out of bad state
        if os.system("pgrep bluetoothd") == 0:
            logging.error("Could not reach bluetoothd, killing")
            self._kill_bluetoothd()

        logging.info("Starting bluetooth service")
        self._start_bluetoothd()

        # Since bluetoothd can be delayed by system conditions outside our control,
        # we wait and refresh our link to its dbus properties until it is ready
        for _ in range(0, BLUETOOTHD_WAIT_TIME):
            handle = self._create_prop_handle()
            if self._check_prop_handle(handle):
                logging.info("Bluetooth ready, returning link")
                self._dbus_hci_props = handle
                return

            time.sleep(1)

    def _set_hci_prop(self, iface_name, prop_name, prop_val):
        """Handles HCI property set

        Sometimes resource isn't ready, so this utility will repeat commands
        multiple times to allow more reliable operation

        Returns:
          True if set succeeds, False otherwise
        """

        # Make sure we have a working handle to bluetoothd
        self._refresh_hci_prop_handle()

        for _ in range(MAX_DBUS_RETRY_ATTEMPTS):
            try:
                initial_value = self._dbus_hci_props.Get(iface_name, prop_name)

                # Return if property has value we want already
                if initial_value == prop_val:
                    return True

                # Set property to the value we want
                logging.info(
                    "{}: {} -> {}".format(prop_name, initial_value, prop_val)
                )
                self._dbus_hci_props.Set(iface_name, prop_name, prop_val)

                time.sleep(0.1)

            except dbus.exceptions.DBusException as e:
                error_msg = "Setting {} to {} again: {}".format(
                    prop_name, prop_val, str(e)
                )
                logging.error(error_msg)
                time.sleep(0.1)

        return False

    def _get_hci_prop(self, iface_name, prop_name):
        """Handles HCI property get

        Args: iface_name: Dbus interface to be queried
        Args: prop_name: Property name to be queried

        Returns: property value, or None on error
        """

        # Make sure we have a working handle to bluetoothd
        self._refresh_hci_prop_handle()

        for _ in range(MAX_DBUS_RETRY_ATTEMPTS):
            try:
                return self._dbus_hci_props.Get(iface_name, prop_name)

            except dbus.exceptions.DBusException as e:
                error_msg = "Will try to get {} again: {}".format(
                    prop_name, str(e)
                )
                logging.error(error_msg)
                time.sleep(0.1)

        return None

    def get_device_property(self, address, prop_name):
        """Reads a property of remote bluetooth device.

        Args:
            address: string address of remote bluetooth device.

        Returns:
            prop_name: property to be queried.
        """
        device = self.GetDeviceWithAddress(address)
        prop_val = None

        if device:
            prop_val = self.unpack_if_variant(
                device[DBUS_PROP_IFACE].Get(DBUS_BLUEZ_DEVICE_IFACE, prop_name)
            )
        else:
            logging.error(
                f"get_device_property: Failed to get device with the address {address}"
            )
        return prop_val

    def SetTrustedByRemoteAddress(self, remote_address, trusted=True):
        device = self.GetDeviceWithAddress(remote_address)
        if device is None:
            logging.error(
                "Failed to get device with the address %s", remote_address
            )
            return False

        try:
            properties = dbus.Interface(device, DBUS_PROP_IFACE)
            properties.Set(
                DBUS_BLUEZ_DEVICE_IFACE,
                "Trusted",
                dbus.Boolean(trusted, variant_level=1),
            )
            return True
        except Exception as e:
            logging.error("SetTrustedByRemoteAddress: %s", e)
        except:
            logging.error("SetTrustedByRemoteAddress: unexpected error")
        return False

    def GetCapabilities(self):
        """What can this kit do/not do that tests need to adjust for?

        Returns:
          A dictionary from PeripheralKit.CAP_* strings to an appropriate value.
          See PeripheralKit for details.
        """
        capabilities = {
            PeripheralKit.CAP_TRANSPORTS: [
                PeripheralKit.TRANSPORT_BREDR,
                PeripheralKit.TRANSPORT_LE,
            ],
            PeripheralKit.CAP_HAS_PIN: True,
            PeripheralKit.CAP_INIT_CONNECT: True,
        }

        return capabilities

    def EnableBLE(self, use_ble):
        """Put device into either LE or Classic mode

        The raspi is a dual device, supporting both LE and Classic BT. If we are
        testing LE connections, I don't want the DUT to successfully be able to
        make a classic connection, for instance, so the unwanted one is disabled
        """

        if use_ble:
            state_change_cmds = [
                "sudo btmgmt power off",
                "sudo btmgmt le on",
                "sudo btmgmt bredr off",
                "sudo btmgmt sc on",
                "sudo btmgmt power on",
            ]

        else:
            state_change_cmds = [
                "sudo btmgmt power off",
                "sudo btmgmt bredr on",
                "sudo btmgmt le off",
                "sudo btmgmt ssp on",
                "sudo btmgmt power on",
            ]

        for cmd in state_change_cmds:
            os.system(cmd)

            # I add a slight delay so there is adequate time for the change to be done
            time.sleep(0.1)

    def GetBaseDeviceType(self, device_type):
        """Returns the base device type of a peripheral, i.e. BLE_MOUSE -> MOUSE"""

        if "BLE_" in device_type:
            device_type = device_type.replace("BLE_", "")

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
        if self.device_type == device_type:
            return True

        if self.device_type is not None:
            error = "Peripheral already bound to device: {}".format(
                self.device_type
            )
            logging.error(error)
            raise BluezPeripheralException(error)

        self.device_type = device_type

        if "BLE" in device_type:
            logging.info("Binding to BLE device!")

            # Enable le only, to make sure our test device isn't connecting
            # via BT classic
            self.EnableBLE(True)

            # Establish and run gatt server
            self._gatt_server = GATTServer(self)

        else:
            logging.info("Binding to Classic device!")

            # Enable bt classic only, to make sure our test device isn't connecting
            # via LE
            self.EnableBLE(False)

            # Set device type and initiate service based on it
            if "DEV_KIT" in device_type:
                self._bluez_service = BluezRfcommEchoService(
                    self.device_type, self.GetLocalBluetoothAddress()
                )
            else:
                self._bluez_service = BluezHIDService(
                    self.device_type, self.GetLocalBluetoothAddress()
                )

            self.Init()

        self.SetAdapterAlias(
            PERIPHERAL_DEVICE_NAME[self.GetBaseDeviceType(self.device_type)]
        )

        logging.info("Bluetooth peripheral now bound to %s", device_type)

        # Give the service a moment to initialize
        time.sleep(1)

        return True

    def SetBtdFlags(self, device_type):
        """Allows us to set bluetoothd config execution flags

        In some cases, we wish to apply specific bluetoothd execution flags
        depending on the device type we are emulating. This function sets the
        bluetoothd flags, and is intended to be run before the service is restarted

        @param device_type: String device type, e.g. "MOUSE"
        """
        # Define regex to separate executable from flags. Example contents:
        # ExecStart=/usr/libexec/bluetooth/bluetoothd -d -P input
        PLUGIN_RE = re.compile(
            r"^(?P<prefix>\s*ExecStart=.*?)"
            r"(?P<flags>\s*-.*)?$"  # pre-flags
        )  # optional flags block

        desired_btd_flags = PERIPHERAL_BTD_FLAGS[
            self.GetBaseDeviceType(device_type)
        ]

        file_contents = []
        with open(BTD_CONF_FILE, "r") as mf:
            file_contents = mf.readlines()

        exec_line = 0
        m = None
        for idx, line in enumerate(file_contents):
            m = PLUGIN_RE.search(line)
            if m:
                exec_line = idx
                break

        if not m:
            logging.warn(
                "Failed to locate ExecStart block in bluetoothd config"
            )
            return

        # Update the exec line with desired bluetoothd flags
        old_line = file_contents[exec_line]
        file_contents[exec_line] = "{} {}\n".format(
            m.group("prefix"), desired_btd_flags
        )

        # Store the original as a comment above the new one, if it doesn't exist yet
        if m.group("prefix") not in file_contents[exec_line - 1]:
            file_contents.insert(exec_line, "# {}".format(old_line))

        logging.info("Applying bluetoothd flags: %s", desired_btd_flags)

        # Write new contents back to the file
        with open(BTD_CONF_FILE, "w") as mf:
            mf.write("".join(file_contents))

    def ResetStack(self, next_device_type=None, restart_chameleond=True):
        """Restores BT stack to pristine state by restarting running services"""

        logging.info("ResetStack")
        reset_cmds = [
            "systemctl daemon-reload",
            "service bluetooth restart",
        ]

        if restart_chameleond:
            reset_cmds.append("service chameleond restart")

        # If we know what device type is used next, we can specify which plugins
        # bluetoothd should be loaded with before the service is restarted
        if next_device_type:
            self.SetBtdFlags(next_device_type)

        self.CleanCachedFiles()
        self.AdapterPowerOff()

        # Since bluetoothd is going to be restarted, clean up the dbus proxy to
        # enforce we create a new one once restarted.
        self._dbus_hci_props = None

        # Stop Bluetooth audio related daemons which may interfere
        # with HID tests.
        # Since these commands may return non zero value if they are not
        # running, we should not put them in the reset_cmds below.
        os.system("sudo killall pulseaudio")
        os.system("sudo service ofono stop")

        # Restart chameleon and bluetooth service
        os.system(" && ".join(reset_cmds))

    # Power cycle the device
    def PowerCycle(self):
        return self.Reboot()

    # Override BluetoothHID's implementation of init
    def Init(self, factory_reset=True):
        """Ensures our chip is in the correct state for the tests to be run"""

        # Make sure device is powered up and discoverable
        if not self._get_hci_prop("org.bluez.Adapter1", "Powered"):
            logging.info("Init: Adapter not powered")
            return False
        self.SetDiscoverable(True)

        # Set class based on device we're emulating
        if self.device_type and "BLE" not in self.device_type:
            self.SetClassOfService(PERIPHERAL_DEVICE_CLASS[self.device_type])

        return True

    def CleanCachedFiles(self):
        """Clean up files that bluetoothd loads when starts.

        This enforce bluetoothd to be in a clean state by cleanning up files in
        /var/lib/bluetooth.
        """

        bluez_storage_path = "/var/lib/bluetooth/"
        adapter_storage_paths = []
        cache_storage_paths = []
        peer_storage_paths = []

        cleanup_syscmds = []

        for dirpath, dirlist, filelist in os.walk(bluez_storage_path):
            if dirpath == bluez_storage_path:
                adapter_storage_paths = [
                    os.path.join(dirpath, adapter) for adapter in dirlist
                ]
            elif dirpath in adapter_storage_paths:
                if "settings" in filelist:
                    # Empty adapter persistent settings. e.g. Alias, Powered
                    cleanup_syscmds.append(
                        "truncate -s 0 " + os.path.join(dirpath, "settings")
                    )

                for dirname in dirlist:
                    if dirname == "cache":
                        cache_storage_paths.append(
                            os.path.join(dirpath, "cache")
                        )
                    else:
                        peer_storage_paths.append(
                            os.path.join(dirpath, dirname)
                        )
            elif dirpath in cache_storage_paths:
                for cached_dev in filelist:
                    cleanup_syscmds.append(
                        "rm " + os.path.join(dirpath, cached_dev)
                    )
            elif dirpath in peer_storage_paths:
                for info in filelist:
                    cleanup_syscmds.append("rm " + os.path.join(dirpath, info))
                cleanup_syscmds.append("rmdir " + dirpath)

        for cmd in cleanup_syscmds:
            logging.info('Executing command "%s" for cleanup', cmd)
            os.system(cmd)

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
        return "/dev/fakedev"

    def AdapterPowerOff(self):
        return self._set_hci_prop(
            "org.bluez.Adapter1", "Powered", dbus.Boolean(0)
        )

    def AdapterPowerOn(self):
        return self._set_hci_prop(
            "org.bluez.Adapter1", "Powered", dbus.Boolean(1)
        )

    def Reboot(self):
        logging.info("REBOOTING")

        self.AdapterPowerOff()
        self.AdapterPowerOn()

        # Put ourselves back into correct state for discovery
        return self.Init()

    def SetAdapterAlias(self, name):
        self._set_hci_prop("org.bluez.Adapter1", "Alias", dbus.String(name))

    def SetBatteryLevel(self, level):
        """Sets device battery level."""
        logging.info("bluetooth_raspi.SetBatteryLevel")
        if self._gatt_server:
            self._gatt_server.SetBatteryLevel(level)

    def SetDiscoverable(self, discoverable):
        self._set_hci_prop(
            "org.bluez.Adapter1", "Discoverable", dbus.Boolean(discoverable)
        )

        # Set discoverable timeout to 0 so that it won't expire.
        if discoverable:
            self._set_hci_prop(
                "org.bluez.Adapter1", "DiscoverableTimeout", dbus.UInt32(0)
            )
        # Also set discoverable in gatt server if relevant
        if self._gatt_server:
            self._gatt_server.SetDiscoverable(discoverable)

    def SetDiscoverableNoConfigAdv(self, discoverable):
        """Set discoverable without configuring advertisements."""
        self._set_hci_prop(
            "org.bluez.Adapter1", "Discoverable", dbus.Boolean(discoverable)
        )

        # Set discoverable timeout to 0 so that it won't expire.
        if discoverable:
            self._set_hci_prop(
                "org.bluez.Adapter1", "DiscoverableTimeout", dbus.UInt32(0)
            )
        # Also set discoverable in gatt server if relevant
        if self._gatt_server:
            self._gatt_server.SetDiscoverableNoConfigAdv(discoverable)

    def GetAuthenticationMode(self):
        return PeripheralKit.OPEN_MODE

    def GetPinCode(self):
        return "0000"

    def AdvertiseWithNamesAndAddresses(self, name_and_addr, duration):
        """Advertises local names and addresses for duration time one by one.

        After this function returned, the local name and address will be reset back
        to default and discoverable will be turned off.

        Args:
          name_and_addr: A list of (name, addr). Each tuple describes the local name
            and the address for the device to advertise.
          duration: The time (in seconds) for a (name, addr) to be advertised.
        """

        def set_addr(addr):
            tool = HciTool(sudo=True)
            cmd = HciCommands.set_local_bluetooth_address(addr)
            if cmd is None:
                raise ValueError("invalid BT address: {}".format(addr))
            tool.add_command(cmd)
            tool.run_commands()

        old_name = self._gatt_server.GetAdvLocalName()
        old_addr = self.GetLocalBluetoothAddress()
        self.SetDiscoverable(False)

        try:
            for name, addr in name_and_addr:
                self._gatt_server.SetAdvLocalName(name)
                set_addr(addr)

                self.SetDiscoverable(True)
                time.sleep(duration)
                self.SetDiscoverable(False)
        finally:
            self._gatt_server.SetAdvLocalName(old_name)
            set_addr(old_addr)
            self.SetDiscoverable(False)

    def GetLocalBluetoothAddress(self):
        """Get the builtin Bluetooth MAC address.

        If the HCI device doesn't exist, Get() will throw an exception
        (dbus.exceptions.DBus.Error.UnknownObject)
        """

        # Return stored value if we have one
        if self._address is not None:
            return self._address

        try:
            addr = str(self._get_hci_prop("org.bluez.Adapter1", "Address"))
            self._address = addr
        except Exception as e:
            logging.error("Failed to get local addr: {}".format(e))
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

    def _GetAddressFromPath(self, device_path):
        manager = dbus.Interface(
            self._dbus_system_bus.get_object(DBUS_BLUEZ_SERVICE_IFACE, "/"),
            DBUS_OBJECT_MANAGER_INTERFACE,
        )

        objects = manager.GetManagedObjects()

        # Go through each object until we find the one that matches
        # our device path
        for path, ifaces in list(objects.items()):
            if path == device_path:
                device = ifaces.get(DBUS_BLUEZ_DEVICE_IFACE)
                if device is not None:
                    return device["Address"]
        return None

    def GetDeviceWithAddress(self, addr):
        manager = dbus.Interface(
            self._dbus_system_bus.get_object(DBUS_BLUEZ_SERVICE_IFACE, "/"),
            DBUS_OBJECT_MANAGER_INTERFACE,
        )

        objects = manager.GetManagedObjects()

        # Go through each object in org.bluez.Device1 until
        # we find the one that matches our desired address
        for path, ifaces in list(objects.items()):
            device = ifaces.get(DBUS_BLUEZ_DEVICE_IFACE)

            if device is not None and device["Address"] == addr:
                obj = self._dbus_system_bus.get_object(
                    DBUS_BLUEZ_SERVICE_IFACE, path
                )
                return dbus.Interface(obj, DBUS_BLUEZ_DEVICE_IFACE)
        return None

    def GetRandomAddress(self):
        """Read the random address of BT

        @return: random address of BT or empty string when failed
        """
        cmd = "cat /sys/kernel/debug/bluetooth/hci0/random_address"
        address = os.popen(cmd).read().strip().upper()
        return address

    def SetPrivacy(self, enable):
        """Set the LE privacy state to ON/OFF

        @param enable: Whether to set LE privacy to True/False.

        @return: True if able to set privacy
        """
        _control = bluetooth_socket.BluetoothControlSocket()
        if not self.AdapterPowerOff():
            logging.error("Unable to power off adapter")
            return False
        if not _control.set_privacy(0, enable):
            logging.error("Unable to set privacy state")
            return False
        if not self.AdapterPowerOn():
            logging.error("Unable to power on adapter")
            return False

        if self._gatt_server:
            self._gatt_server.SetOwnAddressType(
                RANDOM_DEVICE_ADDRESS if enable else PUBLIC_DEVICE_ADDRESS
            )

        return True

    def SetAdvertising(self, enable):
        """Set LE advertising to OFF/ON and configure advertisement
        parameters if LE advertising is enabled.

        @param enable: Whether controller should advertise via LE.

        @return: True if new setting success
        """
        _control = bluetooth_socket.BluetoothControlSocket()
        if not _control.set_advertising(0, enable):
            logging.error("Unable to set LE advertising {}".format(enable))
            return False
        if enable and self._gatt_server:
            self._gatt_server._ConfigureAdvertisements()
        return True

    def SetIOCapability(self, io_capability):
        """Set IO Capability in kernel

        @param index: Controller index.
        @param io_capability: IO Capability in one of
            Possible values for the parameter:
                'DisplayOnly'
                'DisplayYesNo'
                'KeyboardOnly'
                'NoInputNoOutput'
                'KeyboardDisplay'

        @return True on success,
                False on failure.
        """
        logging.info("Setting IO Capability to %s", io_capability)
        _control = bluetooth_socket.BluetoothControlSocket()
        if not _control.set_io_capability(0, io_capability):
            logging.error("Failed to set IO Capability")
            return False
        return True

    def SetSecureConnections(self, secure_conn):
        """Sets whether a controller supports secure connections.

        @param secure_conn: "off" or "on" or "only".

        @return True on success, False otherwise.
        """
        logging.info("Setting Secure Connection to %s", secure_conn)
        _control = bluetooth_socket.BluetoothControlSocket()
        if not _control.set_secure_connections(0, secure_conn):
            logging.error("Failed to set Secure Connection")
            return False
        return True

    def SetSecureSimplePairing(self, enable):
        """Sets Secure Simple Pairing to enable / disable.

        @param enable: Whether controller should support SSP.

        @return True on success, False otherwise.
        """
        logging.info("Setting Secure Simple Pairing to %s", enable)
        _control = bluetooth_socket.BluetoothControlSocket()
        if _control.set_ssp(0, enable) is None:
            logging.error("Failed to set Secure Connection")
            return False
        return True

    def SetRPATimeout(self, timeout):
        """Set the timeout value for random private address

        @param timeout: Number of seconds after which
                        BT random private address will change

        @return: True if new timeout success
        """
        if not str(timeout).isdigit():
            logging.error("Timeout must be a number")
            return False
        if int(timeout) < 30 or int(timeout) > 3600:
            logging.error("Timeout must be in range [30, 3600]s")
            return False

        cmd = "echo {} > /sys/kernel/debug/bluetooth/hci0/rpa_timeout".format(
            timeout
        )
        err = os.system(cmd)
        if err != 0:
            logging.error("Unable to update RPA timeout. Err {}".format(err))
            return False
        return True

    def GetRPATimeout(self):
        """Read the timeout value for random private address

        @return: timeout value as integer
        """
        cmd = "cat /sys/kernel/debug/bluetooth/hci0/rpa_timeout"
        timeout = os.popen(cmd).read()
        if timeout == "":
            logging.error("Fail not exist or timeout not defined.")
            return 0
        return int(timeout)

    def GetRemoteConnectedBluetoothAddress(self):
        """Get the address of the current connected device, if applicable

        Returns:
          None if no connection can be found
          Mac address of connected device
        """

        # Grab ObjectManager and its objects
        manager = dbus.Interface(
            self._dbus_system_bus.get_object("org.bluez", "/"),
            DBUS_OBJECT_MANAGER_INTERFACE,
        )

        objects = manager.GetManagedObjects()

        # Go through each obj in org.bluez.Device1 and check "Connected" attribute
        for _, ifaces in list(objects.items()):
            device = ifaces.get(DBUS_BLUEZ_DEVICE_IFACE)
            if device is None:
                continue
            if device["Address"] is not None and device["Connected"]:
                return device["Address"]

        return None

    def SetClassOfService(self, class_of_service):
        # Class is a read-only DBus property, so needs to be set using system calls.
        cmd = "sudo hciconfig hci0 class {}".format(hex(class_of_service))
        os.system(cmd)

    def SetLinkMode(self, mode):
        """Sets controller to the specified link mode.

        Args:
          mode: string in 'NONE', 'ACCEPT', 'MASTER', 'AUTH', 'ENCRYPT',
                'TRUSTED', 'RELIABLE', 'SECURE'.
        """

        cmds = []
        link_mode_cmd = "sudo hciconfig hci0 lm {}".format(mode)

        # link mode only allowed to change when bredr is enabled.
        if "BLE" in self.device_type:
            cmds.extend(
                [
                    "sudo btmgmt power off",
                    "sudo btmgmt bredr on",
                    link_mode_cmd,
                    "sudo btmgmt bredr off",
                    "sudo btmgmt power on",
                ]
            )
        else:
            cmds.append(link_mode_cmd)

        for cmd in cmds:
            os.system(cmd)
            time.sleep(0.1)

    def SetRemoteAddress(self, remote_address):
        """Sets address later used for connect

        Args:
          remote_address: string denoting remote address
        """
        self.remote_address = remote_address
        return True

    def _PairSuccessHandler(self):
        """Called when pairing request completes"""

    def _PairErrorHandler(self, err):
        """Called in case of error on pairing request"""
        logging.error("Failed to pair: %s", err)

    def Pair(self):
        """Attempts to pair to the address specified with SetRemoteAddress()

        Returns:
          True if success to issue the pairing request, False otherwise
        """
        if self.remote_address is None:
            logging.error("Pair called with no remote address supplied")
            return False

        device = self.GetDeviceWithAddress(self.remote_address)
        device_iface = dbus.Interface(device, DBUS_PROP_IFACE)
        is_paired = bool(device_iface.Get(DBUS_BLUEZ_DEVICE_IFACE, "Paired"))

        if not device:
            logging.error(
                "Device %s is None, can not pair", self.remote_address
            )
            return False

        if is_paired:
            logging.warning(
                "Device %s has already paired. Skip to pair",
                self.remote_address,
            )
            return False

        logging.info("Attempting to pair to %s", self.remote_address)

        device.Pair(
            reply_handler=self._PairSuccessHandler,
            error_handler=self._PairErrorHandler,
        )
        return True

    def Connect(self):
        """Attempts to connect to the address specified with SetRemoteAddress()

        Returns:
          True if connection to remote address succeeds, False otherwise
        """

        if self.remote_address is None:
            logging.error("Connect called with no remote address supplied")
            return False

        device = self.GetDeviceWithAddress(self.remote_address)
        device_iface = dbus.Interface(device, DBUS_PROP_IFACE)
        is_connected = bool(
            device_iface.Get(DBUS_BLUEZ_DEVICE_IFACE, "Connected")
        )

        if is_connected:
            logging.warn(
                "Device %s has already connected. Skip to connect",
                self.remote_address,
            )
            return True

        logging.info("Attempting to connect to %s", self.remote_address)

        if self.device_type in (
            "MOUSE",
            "KEYBOARD",
            "GAMEPAD",
        ):
            self.ConnectHID()
        else:
            # Call connect directly through bluez device object
            if not device:
                logging.error(
                    "Device {} is None, can not connect".format(
                        self.remote_address
                    )
                )
                return False

            try:
                device.Connect()
            except Exception as e:
                logging.error(
                    "Failed to connect to {}: {}".format(self.remote_address, e)
                )
                return False

        start_time = time.time()

        while not is_connected:
            if time.time() > start_time + CONNECTION_WAIT_TIME:
                break

            time.sleep(1)
            is_connected = bool(
                device_iface.Get(DBUS_BLUEZ_DEVICE_IFACE, "Connected")
            )

        return is_connected

    def ConnectHIDDoneHandler(self):
        """Called when connect HID completes"""
        logging.info("Connect HID succeeded")

    def ConnectHIDErrorHandler(self, err):
        """Called in case of error on connect HID"""
        logging.error("Connect HID failed: %s", err)

    def ConnectHID(self):
        """Attempt to connect to HID to the remote address."""

        self.get_service_iface().Connect(
            self.remote_address,
            reply_handler=self.ConnectHIDDoneHandler,
            error_handler=self.ConnectHIDErrorHandler,
        )

    def _GetAdapterIface(self):
        """Returns handle to bluez adapter interface

        Returns:
          Handle to bluez adapter interface
        """

        if self._adapter_iface is None:
            self._adapter_iface = dbus.Interface(
                self._dbus_system_bus.get_object(
                    DBUS_BLUEZ_SERVICE_IFACE, self._dbus_hci_adapter_path
                ),
                DBUS_BLUEZ_ADAPTER_IFACE,
            )

        return self._adapter_iface

    def RemoveDevice(self, remote_address):
        """Removes a remote device from bluez

        Args:
          remote_address: string address of BT device
        """

        try:
            logging.info("Trying to remove {}".format(remote_address))
            device = self.GetDeviceWithAddress(remote_address)

            if device:
                self._GetAdapterIface().RemoveDevice(device)

        except Exception as e:
            logging.info(
                "Failed to remove device {}: {}".format(remote_address, e)
            )

    def SetDiscoveryFilter(self, discovery_filter):
        """Sets the discovery filter.

        Returns:
            True if the request was sent without error, False otherwise.
        """
        try:
            self._GetAdapterIface().SetDiscoveryFilter(discovery_filter)
        except Exception as e:
            logging.error("Failed to set discovery filter: %s", e)
            return False
        return True

    def StartDiscovery(self):
        """Tries to start discovery on the adapter

        Returns:
          True if discovery started without error, False otherwise
        """

        try:
            self._GetAdapterIface().StartDiscovery()

        except Exception as e:
            logging.error("Failed to start discovery: {}".format(e))

            return False

        return True

    def StopDiscovery(self):
        """Tries to stop discovery on the adapter

        Returns:
          True if discovery stopped without error, False otherwise
        """

        try:
            self._GetAdapterIface().StopDiscovery()

        except Exception as e:
            logging.error("Failed to stop discovery: {}".format(e))

            return False

        return True

    def StartUnfilteredDiscovery(self):
        """Starts unfiltered discovery session for DUT advertisement testing

        Since there is no way to initiate an LE scan through bluez without
        filtering enabled, submit request directly over HCI layer. This is useful
        for LE advertising tests, as we will discover advertisements much faster.
        """

        # Submit LE Set Scan Enable command with filter_duplicates disabled
        cmds = [
            HciCommands.le_set_scan_params(),
            HciCommands.le_set_scan_enable(
                enable=True, filter_duplicates=False
            ),
        ]

        tool = HciTool(sudo=True, wait_time=0.1)

        for cmd in cmds:
            tool.add_command(cmd)

        tool.run_commands()

        return True

    def StopUnfilteredDiscovery(self):
        """Stops unfiltered discovery session for DUT advertisement testing

        Disables a scan started via self.StartUnfilteredDiscovery()
        """

        tool = HciTool(sudo=True, wait_time=0.1)

        # Submit LE Set Scan Enable command with LE_Scan_enable set to false
        tool.add_command(HciCommands.le_set_scan_enable(enable=False))

        tool.run_commands()

        return True

    def FindAdvertisementWithAttributes(self, attrs=[], timeout=10):
        """Locate an advertisement containing the requested attributes from btmon

        Args:
          attrs: List of strings to be located within an advertising event
          timeout: Seconds to discover before returning failure

        Returns:
          String containing matching advertising event if found, None otherwise
        """

        def _IsMatchedEvent(ev):
            """Determines whether an event matches the requested criteria

            Args:
              ev: String containing btmon event

            Returns: True if event matches criteria, False otherwise
            """
            content = "".join(ev)

            if "LE Advertising Report" not in content:
                return False

            # Search for all requested attributes. Only return true if all are found
            for attr in attrs:
                if attr not in content:
                    return False

            return True

        current_event = []

        # Start searching for devices
        if not self.StartUnfilteredDiscovery():
            return None

        end_time = time.time() + timeout
        process = system_tools.SystemTools.RunInSubprocess("btmon")

        # If no btmon traffic is occurring, the readline call will block forever.
        # Here, configure a timer to terminate the process after our selected
        # timeout.
        timer = threading.Timer(timeout, process.terminate)
        timer.start()

        desired_event = None
        while time.time() < end_time:
            output = process.stdout.readline().decode("utf8")
            if output == "" and process.poll() is not None:
                break

            # output will contain a single line of btmon, i.e.
            # '> HCI Event: LE Meta Event (0x3e) plen 43'
            if output:
                # Event headers are labeled with their data length. If we encounter a
                # header, we check the last event to see if it matches our search
                if " plen " in output:
                    if current_event and _IsMatchedEvent(current_event):
                        desired_event = "".join(current_event)
                        break

                    # If we found an event header and the previous wasn't a match, start
                    # recording this event
                    current_event = []

                # Don't add header to this event, as the header timestamp has a non-zero
                # chance to match a numeric search attribute
                else:
                    current_event.append(output)

        # Terminate listening process and stop discovery
        process.terminate()
        timer.cancel()
        self.StopUnfilteredDiscovery()
        return desired_event

    def _DiscoverDevice(
        self, remote_address, wait_time=10, allow_early_discovery_by_path=False
    ):
        """This method determines if a device has been discovered via dbus path

        Here, we perform the same operation as test_discover_device in autotest,
        where we consider a remote device "discovered" when bluez creates a dbus
        object for it. This allows us to avoid installing and importing extra
        libraries for scanning, particularly for LE.

        Args:
          remote_address: string address of desired BT device
          wait_time: seconds we should wait before returning failure to discover
          allow_early_discovery_by_path: boolean denoting whether we can return
            immediately if we already have a dbus object for this address.
            Otherwise, a fresh advertisement is required for a device to be
            discovered

        Returns:
          True if device is found, False otherwise
        """

        if allow_early_discovery_by_path:
            # Return early if we already have this device
            if self.GetDeviceWithAddress(remote_address):
                logging.info(
                    "Device {} found without discovery".format(remote_address)
                )
                return True

        self.discovered_devices = []
        # Register callback on PropertiesChanged signal
        # TODO: Replace with CallbackManager
        receiver = self._dbus_system_bus.add_signal_receiver(
            self._DeviceFound,
            signal_name="PropertiesChanged",
            bus_name="org.bluez",
            path_keyword="device_path",
        )

        # Start searching for devices
        self.StartDiscovery()

        # Wait until our device has been added to discovered_devices by listening
        # thread, or timeout
        start_time = time.time()
        while remote_address not in self.discovered_devices:
            if time.time() > start_time + wait_time:
                break

            time.sleep(1)

        # Clean up
        receiver.remove()
        self.StopDiscovery()

        return remote_address in self.discovered_devices

    def _DeviceFound(self, *args, **kwargs):
        """Called when a property changes on the bluez d-bus interface

        Useful for tracking reception of advertisements, as they update the bluez
        device

        Args:
          args: list of form [caller, property_dict]
          kwargs: dict containing keyword arguments requested in the
            add_signal_receiver call i.e. device_path of calling object
        """

        # Renaming to be more human readable while satisfying pylint
        changed_prop = args
        caller_details = kwargs

        caller = str(changed_prop[0])

        if "Device1" in caller:
            device_path = caller_details.get("device_path")
            device_address = device_path[-17:].replace("_", ":")

            # Store new devices. list append is thread safe
            if device_address not in self.discovered_devices:
                logging.info("New device %s found", device_address)
                self.discovered_devices.append(device_address)
                resolved_address = self._GetAddressFromPath(device_path)
                if (
                    resolved_address is not None
                    and resolved_address not in self.discovered_devices
                ):
                    logging.info(
                        "New device with resolved address %s found",
                        resolved_address,
                    )
                    self.discovered_devices.append(resolved_address)

    def Discover(self, remote_address):
        """Try to discover the remote device

        Returns:
          True if remote address is discovered.
        """

        return self._DiscoverDevice(remote_address)

    def Disconnect(self):
        """Requests a disconnect from the remote device

        Returns:
          True if connected device exists, False otherwise
        """

        logging.debug("Disconnecting from adapter")

        # Can't do anything if we're not connected
        if not self.GetConnectionStatus():
            return False

        device = self.GetDeviceWithAddress(self.remote_address)
        if device is None:
            logging.error(
                "Failed to get device with the address %s", self.remote_address
            )
            return False

        device.Disconnect()

        return True

    def SendHIDReport(self, report):
        """Sends a hid report to our bluez service

        Args:
          report: scan code representing state of HID device
        """
        # Passing with empty handlers allows operation to run async
        self.get_service_iface().SendHIDReport(
            report,
            reply_handler=self.KeysSentHandler,
            error_handler=self.KeysErrorHandler,
        )

    def KeysSentHandler(self):
        """Called when hid report send completes"""
        pass

    def KeysErrorHandler(self, err):
        """Called in case of error on hid report send"""
        logging.error("KeysErrorHandler: %s", err)

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
        return (
            self.SCAN_NO_EVENT <= code <= self.SCAN_PAUSE
            or self.SCAN_SYSTEM_POWER <= code <= self.SCAN_SYSTEM_WAKE
        )

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

        if not (
            self._CheckValidModifiers(modifiers)
            and self._CheckValidScanCodes(keys)
        ):
            return None

        real_scan_codes = [key for key in keys]
        padding_0s = (0) * (
            RAW_REPORT_FORMAT_KEYBOARD_LEN_SCAN_CODES - len(real_scan_codes)
        )

        return bytearray(
            (
                UART_INPUT_RAW_MODE,
                RAW_REPORT_FORMAT_KEYBOARD_LENGTH,
                RAW_REPORT_FORMAT_KEYBOARD_DESCRIPTOR,
                sum(modifiers),
                0x0,
            )
            + tuple(keys)
            + padding_0s
        )

    def _MouseButtonsRawHidValues(self):
        """Gives the raw HID values for whatever buttons are pressed."""
        currently_pressed = 0x0
        for button in self._buttons_pressed:
            if button == PeripheralKit.MOUSE_BUTTON_LEFT:
                currently_pressed |= RAW_HID_LEFT_BUTTON
            elif button == PeripheralKit.MOUSE_BUTTON_RIGHT:
                currently_pressed |= RAW_HID_RIGHT_BUTTON
            else:
                error = "Unknown mouse button in state: %s" % button
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
            mouse_codes = self._RawMouseCodes(
                buttons=raw_buttons, x_stop=delta_x, y_stop=delta_y
            )
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

        return bytearray(
            (
                RAW_REPORT_START,
                RAW_REPORT_FORMAT_MOUSE_DESCRIPTOR,
                SignedChar(buttons),
                SignedChar(x_stop),
                SignedChar(y_stop),
                SignedChar(wheel),
            )
        )

    def SendGamepadHIDReport(self):
        """Sends gamepad HID report."""
        gamepad_codes = self._RawGamepadCodes(self.gamepad_report)
        self.SendHIDReport(gamepad_codes)

    def GamepadTriggerButtonsPress(self, trigger, value):
        """Presses gamepad trigger buttons (LT, RT).

        Args:
          trigger: A trigger button, as GAMEPAD_BUTTON_LEFT_TRIGGER or
                   GAMEPAD_BUTTON_RIGHT_TRIGGER value, that will be pressed.
          value: A value between 0-1023 to press the trigger.
        """
        if value:
            hex_value = value.to_bytes(2, byteorder="little")
            if trigger == PeripheralKit.GAMEPAD_BUTTON_LEFT_TRIGGER:
                index = GAMEPAD_BUTTONS_REPORT_INDEX["LEFT_TRIGGER"]
                self.gamepad_report[index : index + 1] = bytearray(hex_value)
            elif trigger == PeripheralKit.GAMEPAD_BUTTON_RIGHT_TRIGGER:
                index = GAMEPAD_BUTTONS_REPORT_INDEX["RIGHT_TRIGGER"]
                self.gamepad_report[index : index + 1] = bytearray(hex_value)
        self.SendGamepadHIDReport()

    def GamepadThumbstickMove(self, stick, delta_x=4095, delta_y=4095):
        """Moves the gamepad thumbstick.

        Args:
          stick: The thumbstick type, left or right as PeripheralKit
                 GAMEPAD_LEFT_THUMBSTICK or GAMEPAD_RIGHT_THUMBSTICK value.
          delta_x: A value between 4095-65535 to move the thumbstick horizontally.
          delta_y: A value between 4095-65535 to move the thumbstick vertically.
        """
        x_hex_value = delta_x.to_bytes(2, byteorder="little")
        y_hex_value = delta_y.to_bytes(2, byteorder="little")
        if stick == PeripheralKit.GAMEPAD_LEFT_THUMBSTICK:
            index = GAMEPAD_BUTTONS_REPORT_INDEX["LEFT_STICK"]
            self.gamepad_report[index : index + 2] = bytearray(x_hex_value)
            self.gamepad_report[index + 2 : index + 4] = bytearray(y_hex_value)
        elif stick == PeripheralKit.GAMEPAD_RIGHT_THUMBSTICK:
            index = GAMEPAD_BUTTONS_REPORT_INDEX["RIGHT_STICK"]
            self.gamepad_report[index : index + 2] = bytearray(x_hex_value)
            self.gamepad_report[index + 2 : index + 4] = bytearray(y_hex_value)
        self.SendGamepadHIDReport()

    def GamepadPressButtons(self, button):
        """Presses the provided gamepad button.

        Args:
          button: A gamepad button, as GAMEPAD_BUTTON_* value, that will be
                  pressed.
        """
        button_index = GAMEPAD_BUTTONS_REPORT_INDEX[button]
        self.gamepad_report[button_index] = GAMEPAD_BUTTONS_MAP.get(button)
        self.SendGamepadHIDReport()

    def GamepadReleaseAllButtons(self):
        """Releases all gamepad buttons."""
        self.gamepad_report[:] = [0x00] * len(self.gamepad_report)
        self.SendGamepadHIDReport()

    def _RawGamepadCodes(self, gamepad_report):
        """Generates the codes in gamepad raw report format.

        Args:
          gamepad_report: Gamepad report to send with HID report.

        Returns:
          a raw code string.
        """
        return bytearray(
            (
                RAW_REPORT_START,
                RAW_REPORT_FORMAT_GAMEPAD_LENGTH,
                *gamepad_report,
            )
        )

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

        if not (
            self._CheckValidModifiers(modifiers)
            and self._CheckValidScanCodes(keys)
        ):
            return None

        if len(keys) > SHORTHAND_REPORT_FORMAT_KEYBOARD_MAX_LEN_SCAN_CODES:
            return None

        return (
            chr(UART_INPUT_SHORTHAND_MODE)
            + chr(len(keys) + 1)
            + chr(sum(modifiers))
            + "".join([chr(key) for key in keys])
        )

    def ReleaseShorthandCodes(self):
        """Generate the shorthand report format code for key release.

        Key release is sent.

        Returns:
          a special shorthand code string to release any pressed keys.
        """
        return chr(UART_INPUT_SHORTHAND_MODE) + chr(0x0)

    def GetKitInfo(self):
        """A simple demo of getting kit information."""
        logging.info("advertised name: %s", self.GetAdvertisedName())
        logging.info(
            "local bluetooth address: %s", self.GetLocalBluetoothAddress()
        )
        class_of_service = self.GetClassOfService()
        try:
            class_of_service = hex(class_of_service)
        except TypeError:
            pass
        logging.info("Class of service: %s", class_of_service)
        class_of_device = self.GetClassOfDevice()
        try:
            class_of_device = hex(class_of_device)
        except TypeError:
            pass
        logging.info("Class of device: %s", class_of_device)


if __name__ == "__main__":
    # To allow basic printing when run from command line
    logging.basicConfig(stream=sys.stdout, level=logging.DEBUG)

    kit_instance = BluezPeripheral()
    kit_instance.GetKitInfo()
