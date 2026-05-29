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
        self._service_data_callback_mgr = CallbackManager(
            name="ServiceData Changed"
        )
        self._device_found_callback_mgr = CallbackManager(name="Device Found")
        self._disconnected_callback_mgr = CallbackManager(
            name="Device Disconnected"
        )

        # Register callback on PropertiesChanged signal
        self._property_changed_receiver = sys_dbus.add_signal_receiver(
            self._on_property_changed,
            signal_name="PropertiesChanged",
            bus_name="org.bluez",
            path_keyword="device_path",
        )
        # Register callback on InterfacesAdded signal
        self._interfaces_added_receiver = sys_dbus.add_signal_receiver(
            self._on_interfaces_added,
            signal_name="InterfacesAdded",
            bus_name="org.bluez",
            dbus_interface="org.freedesktop.DBus.ObjectManager",
        )

    def cleanup(self):
        if self._property_changed_receiver:
            self._property_changed_receiver.remove()
        if self._interfaces_added_receiver:
            self._interfaces_added_receiver.remove()

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

    def RegisterServiceDataChangedCallback(self, callback):
        """Register the callback on service data changed.

        Args:
          callback: The callback function to register
        """
        return self._service_data_callback_mgr.RegisterCallback(callback)

    def UnregisterServiceDataChangedCallback(self, handle):
        """Unregister the callback on service data changed.

        Args:
          handle: the handle of the callback.
        """
        self._service_data_callback_mgr.UnregisterCallback(handle)

    def RegisterDeviceFoundCallback(self, callback):
        """Register the callback on device found.

        Args:
          callback: The callback function to register
        """
        return self._device_found_callback_mgr.RegisterCallback(callback)

    def UnregisterDeviceFoundCallback(self, handle):
        """Unregister the callback on device found.

        Args:
          handle: the handle of the callback.
        """
        self._device_found_callback_mgr.UnregisterCallback(handle)

    def RegisterDeviceDisconnectedCallback(self, callback):
        """Register the callback on device disconnected.

        Args:
          callback: The callback function to register
        """
        return self._disconnected_callback_mgr.RegisterCallback(callback)

    def UnregisterDeviceDisconnectedCallback(self, handle):
        """Unregister the callback on device disconnected.

        Args:
          handle: the handle of the callback.
        """
        self._disconnected_callback_mgr.UnregisterCallback(handle)

    def _service_data_from_dbus(self, service_data_dbus):
        """Helper function to convert ServiceData to built-in type.

        Args:
          service_data_dbus: The ServiceData in D-Bus type (a{sv})
        Returns:
          Service data in dict (string: array of int)
        """
        service_data = {}
        for uuid_dbus, byte_array_variant in service_data_dbus.items():
            uuid = str(uuid_dbus)
            byte_array = [int(byte) for byte in byte_array_variant]
            service_data[uuid] = byte_array
        return service_data

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

            if dbus.String("Connected") in prop_dict:
                if not bool(prop_dict[dbus.String("Connected")]):
                    self._disconnected_callback_mgr.CallAll(address)

            if dbus.String("ServiceData") in prop_dict:
                service_data_dbus = prop_dict[dbus.String("ServiceData")]
                service_data = self._service_data_from_dbus(service_data_dbus)

                self._service_data_callback_mgr.CallAll(address, service_data)

    def _on_interfaces_added(self, device_path, interfaces_and_properties):
        device_intf = interfaces_and_properties.get("org.bluez.Device1", None)
        if device_intf:
            address = device_intf.get("Address", None)
            if address:
                logging.info("Found device: %s", address)

                # Convert properties from D-Bus to built-in types
                props = {}

                service_data_dbus = device_intf.get("ServiceData", None)

                if service_data_dbus is not None:
                    props["ServiceData"] = self._service_data_from_dbus(
                        service_data_dbus
                    )

                self._device_found_callback_mgr.CallAll(address, props)
