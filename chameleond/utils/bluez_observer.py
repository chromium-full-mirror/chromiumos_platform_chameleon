# Copyright 2025 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import logging

import dbus


class CallbackManager:
    """Manages and invokes registered callback functions.

    This class provides a mechanism to register, unregister, and call
    multiple callback functions. Each callback is assigned a unique handle
    for management.
    """

    def __init__(self, name):
        # Stores all the registered callbacks for device paired.
        # key: handle (int)
        # value: callback function
        self.callbacks = dict()
        self.next_handle = 0
        self.name = name

    def RegisterCallback(self, func) -> int:
        """Registers a callback function.

        Args:
          func: the callback function

        Returns: the handle of the registered callback
        """
        handle = self.next_handle
        self.callbacks[handle] = func
        self.next_handle += 1
        return handle

    def UnregisterCallback(self, handle: int):
        """Unregisters a callback function.

        Args:
          handle: the handle of the callback to unregister
        """
        if handle in self.callbacks:
            del self.callbacks[handle]

    def CallAll(self, *args):
        """Calls all registered callbacks.

        Args:
          args: list of arguments to pass through to the callbacks
        """
        for handle, cb in self.callbacks.items():
            logging.debug(
                "CallbackManager: Calling %s callback %d", self.name, handle
            )
            cb(*args)


class BlueZObserver:
    """Class to observe BlueZ states and manage callbacks"""

    def __init__(self, sys_dbus):
        self._paired_callback_mgr = CallbackManager(name="Device Paired")
        # Register callback on PropertiesChanged signal
        self._property_changed_receiver = sys_dbus.add_signal_receiver(
            self._on_property_changed,
            signal_name="PropertiesChanged",
            bus_name="org.bluez",
            path_keyword="device_path",
        )

    def cleanup(self):
        if self._property_changed_receiver:
            self._property_changed_receiver.remove()

    def RegisterDevicePairedCallback(self, callback):
        """Register the callback on device paired.

        Args:
          callback: The callback function to register
        """
        return self._paired_callback_mgr.RegisterCallback(callback)

    def UnregisterDevicePairedCallback(self, handle):
        """Unregister the callback on device paired.

        Args:
          handle: the handle of the callback.
        """
        self._paired_callback_mgr.UnregisterCallback(handle)

    def _on_property_changed(self, *args, **kwargs):
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

        logging.debug(
            "on_property_changed: changed_prop: %s caller_info: %s",
            changed_prop,
            caller_info,
        )

        if "Device1" in caller:
            device_path = str(caller_info["device_path"])
            address = device_path[-17:].replace("_", ":")

            if dbus.String("Paired") in prop_dict:
                if bool(prop_dict[dbus.String("Paired")]):
                    self._paired_callback_mgr.CallAll(address)
