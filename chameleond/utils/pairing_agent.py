# -*- coding: utf-8 -*-
# Copyright 2020 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module provides the functionality of a bluez pairing agent."""

from __future__ import print_function

import logging
import threading

import dbus  # pylint: disable=import-error
import dbus.mainloop.glib  # pylint: disable=import-error
import dbus.service  # pylint: disable=import-error


try:
    from gi.repository import GObject
except ImportError:
    import gobject as GObject


BUS_NAME = "org.bluez"
AGENT_INTERFACE = "org.bluez.Agent1"
AGENT_MANAGER_INTERFACE = "org.bluez.AgentManager1"
DEVICE_INTERFACE = "org.bluez.Device1"
PROP_INTERFACE = "org.freedesktop.DBus.Properties"

BLUEZ_OBJECT_PATH = dbus.ObjectPath("/org/bluez")
AGENT_PATH = dbus.ObjectPath("/test/agent")

# To minimize extensive code modifications, maintain the pairing agent variable
# as a global variable. This approach eliminates the need to alter code that
# utilizes the functions within the module.
_unique_pairing_agent = None


class Agent(dbus.service.Object):
    """A Pairing Agent"""

    PASSKEY = dbus.UInt32(123456)
    PIN = dbus.String("0000")
    PASSKEY_TIMEOUT_SEC = 5

    _passkey_event = threading.Event()

    def __init__(self, bus, path, main_loop):
        super(Agent, self).__init__(bus, path)
        self.bus = bus
        self.loop = main_loop
        self.passkey = None
        self._pin = None

    def wait_for_passkey(self):
        logging.info(
            "Waiting for passkey for %d seconds", self.PASSKEY_TIMEOUT_SEC
        )
        event_set = self._passkey_event.wait(self.PASSKEY_TIMEOUT_SEC)
        if not event_set:
            logging.warning("Never received passkey")

    def SetPin(self, pin):
        self._pin = dbus.String(pin)

    def SetPasskey(self, passkey):
        logging.info("Setting passkey to %d", passkey)
        self.passkey = dbus.UInt32(passkey)
        self._passkey_event.set()

    def DoesPasskeyMatch(self, other_passkey):
        return self.passkey is not None and self.passkey == other_passkey

    def SetTrusted(self, path):
        props = dbus.Interface(
            self.bus.get_object(BUS_NAME, path), PROP_INTERFACE
        )
        props.Set(DEVICE_INTERFACE, "Trusted", True)

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Release(self):
        """Release the agent.

        It is called when Bluetooth stack is closed. However, we'd like to
        centralize the clean-up of the agent in StopAgent(). Hence this is nop
        for now.
        """
        logging.info("Release")

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        logging.info("AuthorizeService (%s, %s)", device, uuid)

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        logging.info("RequestPinCode (%s)", device)
        self.SetTrusted(device)
        return self._pin or self.PIN

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        logging.info("RequestPasskey (%s)", device)

        if not self._passkey_event.is_set():
            thread = threading.Thread(target=self.wait_for_passkey)
            thread.start()
            thread.join()
        self._passkey_event.clear()

        self.SetTrusted(device)
        return self.passkey or self.PASSKEY

    @dbus.service.method(AGENT_INTERFACE, in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        logging.info(
            "DisplayPasskey (%s, %06u entered %u)", device, passkey, entered
        )

    @dbus.service.method(AGENT_INTERFACE, in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        logging.info("DisplayPinCode (%s, %s)", device, pincode)

    @dbus.service.method(AGENT_INTERFACE, in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        logging.info("RequestConfirmation (%s, %06d)", device, passkey)
        self.SetTrusted(device)
        self.SetPasskey(passkey)

    @dbus.service.method(AGENT_INTERFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        logging.info("RequestAuthorization (%s)", device)

    @dbus.service.method(AGENT_INTERFACE, in_signature="", out_signature="")
    def Cancel(self):
        logging.info("Cancel")


def SetupAgent(capability, agent_registered_event):
    """Sets up a pairing agent and runs it.

    It sets up and registers the pairing agent, and runs the main loop. It is a
    blocking call.

    Args:
      capability: the capability of the device. The capability parameter can
                  have the values: DisplayOnly, DisplayYesNo, KeyboardOnly,
                  NoInputNoOutput and KeyboardDisplay.
      agent_registered_event: A threading.Event to signal after the pairing
                              agent is registered.
    """
    global _unique_pairing_agent  # pylint: disable=global-statement

    if _unique_pairing_agent is not None:
        logging.error(
            "Cannot call SetupAgent while another pairing agent is active."
        )
        return

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    bus = dbus.SystemBus()
    main_loop = GObject.MainLoop()
    _unique_pairing_agent = Agent(bus, AGENT_PATH, main_loop)

    bluez_obj = bus.get_object(BUS_NAME, BLUEZ_OBJECT_PATH)
    agent_manager = dbus.Interface(bluez_obj, AGENT_MANAGER_INTERFACE)
    agent_manager.RegisterAgent(AGENT_PATH, dbus.String(capability))
    agent_manager.RequestDefaultAgent(AGENT_PATH)

    agent_registered_event.set()

    main_loop.run()


def StopAgent():
    """Stops the pairing agent.

    Stops and unregisters the pairing agent from the D-Bus main loop.
    """
    global _unique_pairing_agent  # pylint: disable=global-statement

    if _unique_pairing_agent:
        bluez_obj = _unique_pairing_agent.bus.get_object(
            BUS_NAME, BLUEZ_OBJECT_PATH
        )
        agent_manager = dbus.Interface(bluez_obj, AGENT_MANAGER_INTERFACE)
        agent_manager.UnregisterAgent(AGENT_PATH)

        _unique_pairing_agent.remove_from_connection()

        _unique_pairing_agent.loop.quit()
        _unique_pairing_agent = None
        logging.info("Agent unregistered")


if __name__ == "__main__":
    SetupAgent("NoInputNoOutput")
