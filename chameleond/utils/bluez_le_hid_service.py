# -*- coding: utf-8 -*-

# Copyright 2019 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""This module implements HID over GATT service on bluez"""

import logging

import dbus
import dbus.service


try:
    from gi.repository import GObject
except ImportError:
    import gobject as GObject

from .bluez_service_consts import BLUEZ_HID_SERVICE_NAME
from .bluez_service_consts import BLUEZ_HID_SERVICE_PATH
from .example_gatt_server import Characteristic
from .example_gatt_server import DBUS_OM_IFACE
from .example_gatt_server import Descriptor
from .example_gatt_server import GATT_CHRC_IFACE
from .example_gatt_server import Service


class LEApplication(dbus.service.Object):
    """LE Application Object"""

    def __init__(self, bus):
        self.path = "/"
        self.services = []
        dbus.service.Object.__init__(self, bus, self.path)

    def cleanup(self):
        logging.info("LEApplication: cleanup")
        for service in self.services:
            service.cleanup()

        self.remove_from_connection()

    def GetPath(self):
        return dbus.ObjectPath(self.path)

    def AddService(self, service):
        self.services.append(service)

    @dbus.service.method(DBUS_OM_IFACE, out_signature="a{oa{sa{sv}}}")
    def GetManagedObjects(self):
        response = {}

        for service in self.services:
            response[service.get_path()] = service.get_properties()
            chrcs = service.get_characteristics()
            for chrc in chrcs:
                response[chrc.get_path()] = chrc.get_properties()
                descs = chrc.get_descriptors()
                for desc in descs:
                    response[desc.get_path()] = desc.get_properties()

        return response


class HIDApplication(LEApplication):
    """Top-level HID application"""

    def __init__(self, bus, device_type):
        LEApplication.__init__(self, bus)

        # As described in HoG spec, HID application requires HID, Battery, and
        # Device info primary services
        self.AddService(HIDService(bus, 0, device_type))
        self.AddService(BatteryService(bus, 1))
        self.AddService(DevInfoService(bus, 2))


class HIDService(Service):
    """HID service"""

    HID_UUID = "0x1812"

    # Refer to https://www.bluetooth.com/specifications/gatt/services/
    # to see what characteristics are mandatory for HID services
    def __init__(self, bus, index, device_type):
        Service.__init__(self, bus, index, self.HID_UUID, True)
        self.add_characteristic(HIDReportChrc(bus, 0, self, device_type))
        self.add_characteristic(HIDReportMapChrc(bus, 1, self, device_type))
        self.add_characteristic(HIDInformationChrc(bus, 2, self))
        self.add_characteristic(HIDControlPointChrc(bus, 3, self))


class ReportListener(dbus.service.Object):
    """Listens for HID reports and forwards them to the registered handler."""

    def __init__(self, handle):
        self._bus = dbus.SystemBus()
        self._bus_name = dbus.service.BusName(
            BLUEZ_HID_SERVICE_NAME,
            bus=self._bus,
            replace_existing=True,
            allow_replacement=True,
        )
        super(ReportListener, self).__init__(
            self._bus_name, BLUEZ_HID_SERVICE_PATH
        )

        self._handle = handle

    def cleanup(self):
        self.remove_from_connection()

    @dbus.service.method(BLUEZ_HID_SERVICE_NAME, in_signature="ay")
    def SendHIDReport(self, report):
        """Sends HID report across socket"""

        # We chop the first two elements of the hid report (Report start, and hid
        # device type), as with gatt these are provided by report map characteristic
        self._handle(report[2:])

    @dbus.service.method(BLUEZ_HID_SERVICE_NAME, in_signature="yay")
    def SendKeys(self, modifier, keys):
        """Sends keys across socket."""

        report = [0xA1, 0x01, modifier, 0x00] + keys[:6]

        # We chop the first two elements of the hid report (Report start, and hid
        # device type), as with gatt these are provided by report map characteristic
        self._handle(report[2:])


class HIDReportChrc(Characteristic):
    """Characteristic that transports HID data"""

    HID_REPORT_UUID = "0x2a4d"

    def __init__(self, bus, index, service, device_type):
        Characteristic.__init__(
            self, bus, index, self.HID_REPORT_UUID, ["read", "notify"], service
        )

        self.device_type = device_type

        # Instantiate a listener to let us know when new reports come in
        self._service = ReportListener(self.UpdateReport)

        self.add_descriptor(
            ReportReferenceDescriptor(bus, 0, self, self.device_type)
        )

        if "MOUSE" in self.device_type:
            self._report = [1, 0, 0, 0]  # Left click  # x  # y  # wheel

        elif "KEYBOARD" in self.device_type:
            self._report = [
                0x00,  # Modifier byte
                0x00,  # Reserved for vendor use
                0x00,  # Remaining 6 bytes for key presses
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
            ]

    def cleanup(self):
        super().cleanup()
        self._service.cleanup()

    def UpdateReport(self, report):
        """Called by listener when new report is available

        Stores the updated report and propagates it to anybody subscribed to notify
        """

        self._report = report
        self.PropertiesChanged(
            GATT_CHRC_IFACE, {"Value": [dbus.Byte(b) for b in report]}, []
        )

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        return [dbus.Byte(b) for b in self._report]

    def StartNotify(self):
        """Called by dbus - requests notifications"""

        logging.debug("Starting notify of HID report!")

    def StopNotify(self):
        """Called by dbus - requests stop to notifications"""

        logging.debug("Stopping notify of HID report!")


class ReportReferenceDescriptor(Descriptor):
    """Report reference descriptor

    Denotes which report type to use (denoted by 0x85 in report map) and
    report type (input/output/feature)
    """

    REPORT_REF_DESC_UUID = "0x2908"

    def __init__(self, bus, index, characteristic, device_type):
        Descriptor.__init__(
            self,
            bus,
            index,
            self.REPORT_REF_DESC_UUID,
            ["read"],
            characteristic,
        )

        self.device_type = device_type

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        # First byte is report id, second says we are input report
        if "MOUSE" in self.device_type:
            # Mouse report map has report id 2, so we treat it specially
            return [dbus.Byte(0x02), dbus.Byte(0x01)]

        return [dbus.Byte(0x01), dbus.Byte(0x01)]


class HIDReportMapChrc(Characteristic):
    """HID report map characteristic

    Direct from USB hid spec, tells how hid device formats its reports
    """

    HID_REPORT_MAP_UUID = "0x2a4b"

    def __init__(self, bus, index, service, device_type):
        Characteristic.__init__(
            self, bus, index, self.HID_REPORT_MAP_UUID, ["read"], service
        )

        self.device_type = device_type

        # HID mouse report map. We borrowed these from other physical devices we
        # have to play with, but the format for the hid reports are defined in the
        # HID spec: https://www.usb.org/hid
        if "MOUSE" in self.device_type:
            self._report_map = (
                "05010902A1010901A10085020509190129031500250195037"
                "501810295017505810305010930093109381581257F750895"
                "038106C0C0"
            )

        elif "KEYBOARD" in self.device_type:
            self._report_map = (
                "05010906a101850175019508050719e029e71500250181029"
                "5017508810395057501050819012905910295017503910395"
                "067508150026ff000507190029ff8100c0050c0901a101850"
                "3150025017501950b0a23020a21020ab10109b809b609cd09"
                "b509e209ea09e9093081029501750d8103c0"
            )

    def _GetReport(self):
        """Converts string repr into dbus data"""

        # Grab hex from string, and convert to array of dbus.Byte as required
        hex_vals = bytearray.fromhex(self._report_map)
        return [dbus.Byte(b) for b in hex_vals]

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        rm = self._GetReport()
        return rm


class HIDInformationChrc(Characteristic):
    """HID information characteristic

    Required, says what hid spec we support, country of origin, and features
    """

    HID_INFO_UUID = "0x2a4a"

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.HID_INFO_UUID, ["read"], service
        )

        # HID device description
        # First two bytes denote hid spec # (copied from working HoG device)
        # third is country of origin, 0x0 says we are not localized
        # fourth is flags, 0x3 says we can be remote wake source and that we
        # are normally connectable
        self._capabilities = [0x11, 0x01, 0x00, 0x03]

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        return [dbus.Byte(b) for b in self._capabilities]


class HIDControlPointChrc(Characteristic):
    """HID Control Point characteristic

    Writeable, allows client to tell gatt server to go into suspend
    """

    HID_CTRL_PT_UUID = "0x2a4c"

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self,
            bus,
            index,
            self.HID_CTRL_PT_UUID,
            ["write-without-response"],
            service,
        )

    def WriteValue(self, value, options):
        """Called by dbus - requests write to characteristic"""

        msg = "HID CTRL point WriteValue called with options {}".format(options)
        logging.debug(msg)


class BatteryService(Service):
    """Fake Battery service that emulates a draining battery."""

    BATTERY_SERVICE_UUID = "0x180f"

    def __init__(self, bus, index):
        Service.__init__(self, bus, index, self.BATTERY_SERVICE_UUID, True)
        self.add_characteristic(BatteryLevelCharacteristic(bus, 0, self))


class BatteryLevelCharacteristic(Characteristic):
    """Fake Battery Level characteristic that slowly drains"""

    BATTERY_LVL_UUID = "0x2a19"

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.BATTERY_LVL_UUID, ["read", "notify"], service
        )
        self.notifying = False
        self.battery_lvl = 100
        self.drain_battery_event = None

    def notify_battery_level(self):
        """Notifies of new battery level"""

        if not self.notifying:
            return

        self.PropertiesChanged(
            GATT_CHRC_IFACE, {"Value": [dbus.Byte(self.battery_lvl)]}, []
        )

    def drain_battery(self):
        """Drains the battery"""

        if not self.notifying:
            return True
        if self.battery_lvl > 0:
            self.battery_lvl -= 1
            if self.battery_lvl < 0:
                self.battery_lvl = 0

        logging.debug("Battery Level drained: %s", repr(self.battery_lvl))
        self.notify_battery_level()
        return True

    def set_battery_level(self, level):
        """Sets the device battery level"""
        logging.info("Set battery to level %s", level)

        self.battery_lvl = max(level, 0)
        if self.notifying:
            self.notify_battery_level()

    def start_drain_battery(self):
        """Start to drain the device battery."""
        logging.info("Start to drain the device battery")
        self.drain_battery_event = GObject.timeout_add(
            10000, self.drain_battery
        )

    def stop_drain_battery(self):
        """ "Stops to drain the device battery."""
        logging.info("Stio to drain the device battery")
        if self.drain_battery_event:
            GObject.source_remove(self.drain_battery_event)
            self.drain_battery_event = None

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        logging.debug("Battery Level read: %s", repr(self.battery_lvl))
        return [dbus.Byte(self.battery_lvl)]

    def StartNotify(self):
        """Called by dbus - requests notifications"""

        logging.info("BatteryLevelChar: StartNotify")

        if self.notifying:
            return

        self.notifying = True
        self.notify_battery_level()

    def StopNotify(self):
        """Called by dbus - requests stop to notifications"""

        if not self.notifying:
            return

        self.notifying = False


class DevInfoService(Service):
    """Device information service

    Provides basic info of device such as name, model, etc
    """

    DEV_INFO_UUID = "0x180A"

    def __init__(self, bus, index):
        Service.__init__(self, bus, index, self.DEV_INFO_UUID, True)

        self.add_characteristic(ManufacturerNameCharacteristic(bus, 0, self))
        self.add_characteristic(PnPCharacteristic(bus, 1, self))


class ManufacturerNameCharacteristic(Characteristic):
    """DevInfo characteristic to provide manufacturer's name"""

    MANUFACTURER_NAME_UUID = "0x2a29"
    MANUFACTURER_NAME = "RASPI"

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.MANUFACTURER_NAME_UUID, ["read"], service
        )

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        return [dbus.Byte(b) for b in self.MANUFACTURER_NAME]


class PnPCharacteristic(Characteristic):
    """DevInfo characteristic to provide manufacturer's name"""

    PNP_UUID = "0x2a50"

    # Current value picked to match MX Anywhere 2S device, but the byte
    # 0x1A is changed to 0x55 to not clash with the list of devices which
    # looks like a keyboard but it isn't (b/330731210).
    PNP = [0x02, 0x6D, 0x04, 0x55, 0xB0, 0x03, 0x00]

    def __init__(self, bus, index, service):
        Characteristic.__init__(
            self, bus, index, self.PNP_UUID, ["read"], service
        )

    def ReadValue(self, options):
        """Called by dbus - Reads current value of characteristic"""

        return [dbus.Byte(b) for b in self.PNP]
