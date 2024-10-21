# -*- coding: utf-8 -*-

# Copyright 2019 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""The control interface of Bluetooth flow for Raspi devices."""

import logging
import time

from chameleond.devices import chameleon_device
from chameleond.utils import pairing_agent
from chameleond.utils.bluetooth_audio import BluetoothAudio
from chameleond.utils.bluetooth_peripheral_kit import PeripheralKit
from chameleond.utils.bluetooth_raspi import BluezPeripheral
from chameleond.utils.bluez_service_consts import CLASS_OF_DEVICE_MASK
from chameleond.utils.bluez_service_consts import CLASS_OF_SERVICE_MASK
from chameleond.utils.bluez_service_consts import PERIPHERAL_DEVICE_CLASS
from chameleond.utils.bluez_service_consts import PERIPHERAL_DEVICE_NAME
from chameleond.utils.raspi_bluez_client import BluezKeyboardClient


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


class BluetoothHIDException(Exception):
    """A dummpy exception class for Bluetooth HID class."""

    pass


class RaspiHIDKeyboard(RaspiFlow, BluezPeripheral):
    """This is the class loaded from fpga_tio.

    We inherit from both Flow and PeripheralKit, as fpga_tio's interface needs
    access to methods in both of them
    """

    def __init__(self):
        # Instantiate bluez and raspi flow
        BluezPeripheral.__init__(self)
        RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())

        self._client = None

    def GetDeviceType(self):
        """Get the peer device type

        Returns:
          The type of device emulated
        """

        return PeripheralKit.KEYBOARD

    def GetAdvertisedName(self):
        """Get the name advertised by the kit.

        Returns:
          The name that the kit advertises to other Bluetooth devices.
        """

        return PERIPHERAL_DEVICE_NAME[PeripheralKit.KEYBOARD]

    def GetClassOfDevice(self):
        """Get the class of device

        Returns:
          Class of device that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.KEYBOARD]
            & CLASS_OF_DEVICE_MASK
        )

    def GetClassOfService(self):
        """Get the class of service

        Returns:
          Class of service that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.KEYBOARD]
            & CLASS_OF_SERVICE_MASK
        )

    def KeyboardSendTrace(self, input_scan_codes):
        """Sends scan codes from a data trace over the BT link

        Args:
          input_scan_codes: List object of scan codes representing keyboard state
        """

        for scan_code in input_scan_codes:
            time.sleep(0.1)

            self.SendHIDReport(bytearray(scan_code))

    def KeyboardSendString(self, string_to_send, delay):
        """Sends characters one-by-one over the BT link.

        Args:
          string_to_send: String object that will be sent over the link.
          delay: Time in seconds between sending each character.
        """

        if self._client is None:
            self._client = BluezKeyboardClient()

        self._client.send_string(string_to_send, delay)


class RaspiHIDMouse(RaspiFlow, BluezPeripheral):
    """This is the class loaded from fpga_tio.

    We inherit from both Flow and PeripheralKit, as fpga_tio's interface needs
    access to methods in both of them
    """

    SEND_DELAY_SECS = 0.2

    HID_MAX_REPORT_VALUE = 127
    HID_MIN_REPORT_VALUE = -127

    def __init__(self, send_delay=SEND_DELAY_SECS):
        # Instantiate bluez and raspi flow
        BluezPeripheral.__init__(self)
        RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())

        self.send_delay = send_delay

    def GetDeviceType(self):
        """Get the peer device type

        Returns:
          The type of device emulated
        """

        return PeripheralKit.MOUSE

    def GetAdvertisedName(self):
        """Get the name advertised by the kit.

        Returns:
          The name that the kit advertises to other Bluetooth devices.
        """

        return PERIPHERAL_DEVICE_NAME[PeripheralKit.MOUSE]

    def GetClassOfDevice(self):
        """Get the class of device

        Returns:
          Class of device that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.MOUSE] & CLASS_OF_DEVICE_MASK
        )

    def GetClassOfService(self):
        """Get the class of service

        Returns:
          Class of service that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.MOUSE] & CLASS_OF_SERVICE_MASK
        )

    def _EnsureHIDValueInRange(self, value):
        """Ensures given value is in the range [-127,127] (inclusive).

        Args:
          value: The value that should be checked.

        Raises:
          BluetoothHIDException if value is outside of the acceptable range.
        """

        if (
            value < self.HID_MIN_REPORT_VALUE
            or value > self.HID_MAX_REPORT_VALUE
        ):
            error = (
                "Value %s is outside of acceptable range [-127,127]." % value
            )
            logging.error(error)
            raise BluetoothHIDException(error)

    def Move(self, delta_x=0, delta_y=0):
        """Move the mouse (delta_x, delta_y) steps.

        If buttons are being pressed, they will stay pressed during this operation.
        This move is relative to the current position by the HID standard.
        Valid step values must be in the range [-127,127].

        Args:
          delta_x: The number of steps to move horizontally.
                   Negative values move left, positive values move right.
          delta_y: The number of steps to move vertically.
                   Negative values move up, positive values move down.

        Raises:
          BluetoothHIDException if a given delta is not in [-127,127].
        """

        self._EnsureHIDValueInRange(delta_x)
        self._EnsureHIDValueInRange(delta_y)
        self.MouseMove(delta_x, delta_y)
        time.sleep(self.send_delay)

    def _PressLeftButton(self):
        """Press the left button"""

        self.MousePressButtons({PeripheralKit.MOUSE_BUTTON_LEFT})
        time.sleep(self.send_delay)

    def _PressRightButton(self):
        """Press the right button"""

        self.MousePressButtons({PeripheralKit.MOUSE_BUTTON_RIGHT})
        time.sleep(self.send_delay)

    def _ReleaseAllButtons(self):
        """Release all pressed buttons"""

        self.MouseReleaseAllButtons()
        time.sleep(self.send_delay)

    def LeftClick(self):
        """Make a left click."""

        self._PressLeftButton()
        self._ReleaseAllButtons()

    def RightClick(self):
        """Make a right click."""

        self._PressRightButton()
        self._ReleaseAllButtons()

    def ClickAndDrag(self, delta_x=0, delta_y=0):
        """Left click, drag (delta_x, delta_y) steps, and release.

        This move is relative to the current position by the HID standard.
        Valid step values must be in the range [-127,127].

        Args:
          delta_x: The number of steps to move horizontally.
                   Negative values move left, positive values move right.
          delta_y: The number of steps to move vertically.
                   Negative values move up, positive values move down.

        Raises:
          BluetoothHIDException if a given delta is not in [-127,127].
        """

        self._EnsureHIDValueInRange(delta_x)
        self._EnsureHIDValueInRange(delta_y)
        self._PressLeftButton()
        self.Move(delta_x, delta_y)
        self._ReleaseAllButtons()

    def Scroll(self, steps):
        """Scroll the mouse wheel steps number of steps.

        Buttons currently pressed will stay pressed during this operation.
        Valid step values must be in the range [-127,127].

        Args:
          steps: The number of steps to scroll the wheel.
                 With traditional scrolling:
                   Negative values scroll down, positive values scroll up.
                 With reversed (formerly "Australian") scrolling this is reversed.
        """

        self._EnsureHIDValueInRange(steps)
        self.MouseScroll(steps)
        time.sleep(self.send_delay)

    def _ProcessAction(self, action_type, action_args):
        """Processes a mouse action based on the action type.

        Args:
          action_type: Type of mouse action.
          action_args: Arguments for the mouse action.

        Raises:
          BluetoothHIDException if a given delta is not in [-127,127].
        """
        if action_type == "MouseMove":
            delta_x, delta_y = action_args
            self._EnsureHIDValueInRange(delta_x)
            self._EnsureHIDValueInRange(delta_y)
            self.MouseMove(delta_x, delta_y)
        elif action_type == "PressLeftButton":
            self.MousePressButtons({PeripheralKit.MOUSE_BUTTON_LEFT})
        elif action_type == "PressRightButton":
            self.MousePressButtons({PeripheralKit.MOUSE_BUTTON_RIGHT})
        elif action_type == "ReleaseAllButtons":
            self.MouseReleaseAllButtons()

    def BulkActions(self, action_list, interval=0.2):
        """Executes a sequence of mouse actions with specified delays.

        Args:
          action_list: List of tuples (action_type, action_aargs) representing
                       mouse actions.
          interval: Time in seconds between actions.

        Raises:
          BluetoothHIDException if a given delta is not in [-127,127].
        """
        for action_type, action_args in action_list:
            self._ProcessAction(action_type, action_args)
            time.sleep(interval)


class RaspiHIDGamepad(RaspiFlow, BluezPeripheral):
    """This is the class loaded from fpga_tio.

    We inherit from both Flow and PeripheralKit, as fpga_tio's interface needs
    access to methods in both of them.
    """

    SEND_DELAY_SECS = 0.2

    HID_MIN_REPORT_VALUE = 0
    HID_MIN_STICK_REPORT_VALUE = 4095
    HID_MAX_STICK_REPORT_VALUE = 65535
    HID_MAX_TRIGGER_REPORT_VALUE = 1023

    def __init__(self, send_delay=SEND_DELAY_SECS):
        # Instantiate bluez and raspi flow.
        BluezPeripheral.__init__(self)
        RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())

        self._client = None
        self.send_delay = send_delay

    def GetDeviceType(self):
        """Gets the peer device type.

        @return: The type of device emulated.
        """
        return PeripheralKit.GAMEPAD

    def GetAdvertisedName(self):
        """Gets the name advertised by the kit.

        @return: The name that the kit advertises to other Bluetooth devices.
        """
        return PERIPHERAL_DEVICE_NAME[PeripheralKit.GAMEPAD]

    def GetClassOfDevice(self):
        """Gets the class of device.

        @return: Class of device that is emulated by this peripheral.
        """
        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.GAMEPAD]
            & CLASS_OF_DEVICE_MASK
        )

    def GetClassOfService(self):
        """Gets the class of service.

        @return: Class of service that is emulated by this peripheral.
        """
        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.GAMEPAD]
            & CLASS_OF_SERVICE_MASK
        )

    def _ReleaseAllButtons(self):
        """Releases all pressed buttons."""

        self.GamepadReleaseAllButtons()
        time.sleep(self.send_delay)

    def _EnsureTiggerHIDValueInRange(self, value):
        """Ensures given value is in the range [0, 1023] (inclusive).

        Args:
          value: The value that should be checked.

        Raises:
          BluetoothHIDException if value is outside the acceptable range.
        """

        if (
            value < self.HID_MIN_REPORT_VALUE
            or value > self.HID_MAX_TRIGGER_REPORT_VALUE
        ):
            error = "Value %s is outside of acceptable range [0,1023]." % value
            logging.error(error)
            raise BluetoothHIDException(error)

    def _EnsureStickHIDValueInRange(self, value):
        """Ensures given value is in the range [4095,65535] (inclusive).
        Flat 4095 defines a dead zone around the center of the axis where any
        movement less than 4095 will be considered zero and then no event will be
        triggered.

        Args:
          value: The value that should be checked.

        Raises:
          BluetoothHIDException if value is outside the acceptable range.
        """

        if (
            value < self.HID_MIN_STICK_REPORT_VALUE
            or value > self.HID_MAX_STICK_REPORT_VALUE
        ):
            error = (
                "Value %s is outside of acceptable range [4095,65535]." % value
            )
            logging.error(error)
            raise BluetoothHIDException(error)

    def MoveLeftThumbstick(self, delta_x=4095, delta_y=4095):
        """Moves the left gamepad thumbstick.

        Valid step values must be in the range [4095,65535].

        Args:
          delta_x: A value between 4095-65535 to move the thumbstick horizontally.
          delta_y: A value between 4095-65535 to move the thumbstick vertically.

        Raises:
          BluetoothHIDException if a given delta is not in [4095,65535].
        """

        self._EnsureStickHIDValueInRange(delta_x)
        self._EnsureStickHIDValueInRange(delta_y)
        self.GamepadThumbstickMove(
            PeripheralKit.GAMEPAD_LEFT_THUMBSTICK, delta_x, delta_y
        )
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def MoveRightThumbstick(self, delta_x=4095, delta_y=4095):
        """Moves the right gamepad thumbstick.

        Valid step values must be in the range [4095,65535].

        Args:
         delta_x: A value between 4095-65535 to move the thumbstick horizontally.
         delta_y: A value between 4095-65535 to move the thumbstick vertically.

        Raises:
          BluetoothHIDException if a given delta is not in [0,65535].
        """

        self._EnsureStickHIDValueInRange(delta_x)
        self._EnsureStickHIDValueInRange(delta_y)
        self.GamepadThumbstickMove(
            PeripheralKit.GAMEPAD_RIGHT_THUMBSTICK, delta_x, delta_y
        )
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressLeftBumper(self):
        """Presses the left gamepad bumper (LB)."""

        self.GamepadPressButtons(PeripheralKit.GAMEPAD_BUTTON_LEFT_BUMPER)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressRightBumper(self):
        """Presses the right gamepad bumper (RB)."""

        self.GamepadPressButtons(PeripheralKit.GAMEPAD_BUTTON_RIGHT_BUMPER)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressLeftTrigger(self, value):
        """Presses the left gamepad trigger (LT) by the provided value.

        Args:
          value: The value to press the trigger with.

        Raises:
          BluetoothHIDException if a given delta is not in [0,1023].
        """

        self._EnsureTiggerHIDValueInRange(value)
        self.GamepadTriggerButtonsPress(
            PeripheralKit.GAMEPAD_BUTTON_LEFT_TRIGGER, value
        )
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressRightTrigger(self, value):
        """Presses the right gamepad trigger (RT) by the provided value.

        Args:
          value: The value to press the trigger with.

        Raises:
          BluetoothHIDException if a given delta is not in [0,1023].
        """

        self._EnsureTiggerHIDValueInRange(value)
        self.GamepadTriggerButtonsPress(
            PeripheralKit.GAMEPAD_BUTTON_RIGHT_TRIGGER, value
        )
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressLeftThumbstick(self):
        """Presses the left thumbstick."""

        self.GamepadPressButtons(PeripheralKit.GAMEPAD_LEFT_THUMBSTICK)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressRightThumbstick(self):
        """Presses the right thumbstick."""

        self.GamepadPressButtons(PeripheralKit.GAMEPAD_RIGHT_THUMBSTICK)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressDPadButton(self, button):
        """Presses one of the D-Pad buttons (up, down, left, right).

        Args:
          button: A D-Pad button, as GAMEPAD_BUTTON_* value, that will be pressed.
        """

        self.GamepadPressButtons(button)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressActionButton(self, button):
        """Presses one of the action buttons (A, B, X and Y).

        Args:
          button: Action button, as GAMEPAD_BUTTON_* value, that will be pressed.
        """

        self.GamepadPressButtons(button)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def PressStartButton(self):
        """Presses the start button."""

        self.GamepadPressButtons(PeripheralKit.GAMEPAD_BUTTON_START)
        time.sleep(self.send_delay)
        self._ReleaseAllButtons()

    def _ProcessAction(self, action_type, action_args):
        """Processes a gamepad action based on the action type.

        Args:
          action_type: Type of gamepad action.
          action_args: Arguments for the gamepad action.

        Raises:
          BluetoothHIDException if a given delta is not in [4095,65535].
        """
        if action_type in ("MoveLeftThumbstick", "MoveRightThumbstick"):
            stick, delta_x, delta_y = action_args
            self._EnsureStickHIDValueInRange(delta_x)
            self._EnsureStickHIDValueInRange(delta_y)
            self.GamepadThumbstickMove(stick, delta_x, delta_y)
        elif action_type == "GamepadPressButtons":
            button = action_args
            self.GamepadPressButtons(button)
        elif action_type == "ReleaseAllButtons":
            self.GamepadReleaseAllButtons()
        else:
            logging.error("Invalid action type: %s", action_type)

    def BulkActions(self, action_list, interval=0.2):
        """Executes a sequence of gamepad actions with specified delays.

        Args:
          action_list: List of tuples (action_type, action_args) representing
                       gamepad actions.
          interval: Time in seconds between actions.

        Raises:
          BluetoothHIDException if a given delta is not in [4095,65535].
        """
        for action_type, action_args in action_list:
            self._ProcessAction(action_type, action_args)
            time.sleep(interval)


class RaspiBLEPhone(RaspiFlow, BluezPeripheral):
    """This is the class loaded from fpga_tio.

    We inherit from both Flow and PeripheralKit, as fpga_tio's interface needs
    access to methods in both of them
    """

    def __init__(self):
        # Instantiate bluez and raspi flow
        BluezPeripheral.__init__(self)
        RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())

        self._client = None

    def GetDeviceType(self):
        """Get the peer device type

        Returns:
          The type of device emulated
        """

        return PeripheralKit.PHONE

    def GetAdvertisedName(self):
        """Get the name advertised by the kit.

        Returns:
          The name that the kit advertises to other Bluetooth devices.
        """

        return PERIPHERAL_DEVICE_NAME[PeripheralKit.PHONE]

    def GetClassOfDevice(self):
        """Get the class of device

        Returns:
          Class of device that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.PHONE] & CLASS_OF_DEVICE_MASK
        )

    def GetClassOfService(self):
        """Get the class of service

        Returns:
          Class of service that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.PHONE] & CLASS_OF_SERVICE_MASK
        )


class RaspiBluetoothAudioFlow(RaspiFlow, BluetoothAudio):
    """This is the class loaded from fpga_tio.

    It inherits from both Flow and BluetoothAudio, as fpga_tio's interface needs
    access to methods in both of them.
    """

    def __init__(self):
        # Instantiate bluez and raspi flow
        BluetoothAudio.__init__(self)
        RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())
        self._client = None


class RaspiBLEFastPair(RaspiFlow, BluezPeripheral):
    """This is the class loaded from fpga_tio.

    It inhertis from both Flow and BluezPeripheral, as fpga_tio's interface needs
    access to methods in both of them.
    """

    def __init__(self):
        # Instantiate bluez and raspi flow
        BluezPeripheral.__init__(self)
        RaspiFlow.__init__(self, self.GetLocalBluetoothAddress())

        self._client = None

    def GetAdvertisedName(self):
        """Get the name advertised by the kit.

        Returns:
          The name that the kit advertises to other Bluetooth devices.
        """

        return PERIPHERAL_DEVICE_NAME[PeripheralKit.FAST_PAIR]

    def GetDeviceType(self):
        """Get the peer device type

        Returns:
          The type of device emulated
        """

        return PeripheralKit.FAST_PAIR

    def GetClassOfDevice(self):
        """Get the class of device

        Returns:
          Class of device that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.FAST_PAIR]
            & CLASS_OF_DEVICE_MASK
        )

    def GetClassOfService(self):
        """Get the class of service

        Returns:
          Class of service that is emulated by this peripheral
        """

        return (
            PERIPHERAL_DEVICE_CLASS[PeripheralKit.FAST_PAIR]
            & CLASS_OF_SERVICE_MASK
        )

    def SetAntispoofingKeyPem(self, key_pem):
        """Set the anti-spoofing key for the Fast Pair serivce"""

        if self._gatt_server is None or self._gatt_server.app is None:
            logging.warn(
                "Failed to set anti-spoofing key. Service doesn't exist."
            )
            return

        self._gatt_server.app.SetAntiSpoofingKeyPem(key_pem)

    def AddAccountKey(self, account_key):
        """Adds an account key to the Fast Pair GATT service"""

        if self._gatt_server is None or self._gatt_server.app is None:
            logging.warn("Failed to add account key. Service doesn't exist.")
            return

        self._gatt_server.app.AddAccountKey(account_key)

    def SetAdvertiseNameAndHID(self, enabled):
        """Adds name and HID UUID to device advertisement"""
        if self._gatt_server is None:
            logging.warn("Failed to set advertising name and HID UUID.")
            return

        self._gatt_server.SetAdvertiseNameAndHID(enabled)

    def SetPasskey(self, passkey):
        """Sets the passkey for this device's pairing agent"""
        if self._agent is None:
            logging.warn("Failed to set passkey.")
            return

        pairing_agent.agent.SetPasskey(passkey)
