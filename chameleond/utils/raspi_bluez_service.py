# Lint as: python2, python3
# -*- coding: utf-8 -*-
# pylint: disable=import-error

# Copyright 2019 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Bluez Service Classes (for Bluetooth Classic HID and RFCOMM)"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import logging
import os
import socket
import time

from bluetooth import BluetoothSocket
from bluetooth import L2CAP
import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib
from six.moves import range

from .bluez_service_consts import BLUEZ_HID_PERIPHERAL_PROFILE_PATH
from .bluez_service_consts import BLUEZ_HID_SERVICE_NAME
from .bluez_service_consts import BLUEZ_HID_SERVICE_PATH
from .bluez_service_consts import BLUEZ_RFCOMM_ECHO_PROFILE_PATH
from .bluez_service_consts import BLUEZ_RFCOMM_SERVICE_NAME
from .bluez_service_consts import BLUEZ_RFCOMM_SERVICE_PATH
from .bluez_service_consts import PERIPHERAL_PROFILE_UUID
from .bluez_service_consts import SERVICE_PROFILE_SDP_PATH


P_CTRL = 17
P_INTR = 19

MAX_DBUS_RETRY_ATTEMPTS = 3
MAX_CONNECT_RETRY_ATTEMPTS = 3

ECHO_SERVICE_CHANNEL = 30


class BluezServiceException(Exception):
    """Exception class for BluezPeripheral class."""

    def __init__(self, message):
        super(BluezServiceException, self).__init__()
        self.message = message


class BluezServiceProfile(dbus.service.Object):
    """Implementation of org.bluez.Profile1 interface for a HID device."""

    fd = -1

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="", out_signature=""
    )
    def Release(self):
        print("Release")

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="", out_signature=""
    )
    def Cancel(self):
        print("Cancel")

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="oha{sv}", out_signature=""
    )
    def NewConnection(self, path, fd, properties):
        self.fd = fd.take()
        print("NewConnection(%s, %d)" % (path, self.fd))
        for key in list(properties.keys()):
            if key == "Version" or key == "Features":
                print("  %s = 0x%04x" % (key, properties[key]))
            else:
                print("  %s = %s" % (key, properties[key]))

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="o", out_signature=""
    )
    def RequestDisconnection(self, path):
        print("RequestDisconnection(%s)" % (path))

        if self.fd > 0:
            os.close(self.fd)
            self.fd = -1

    def __init__(self, bus, path):
        dbus.service.Object.__init__(self, bus, path)

    def cleanup(self):
        logging.info("BluezServiceProfile: cleanup")
        self.remove_from_connection()


class EchoProfile(dbus.service.Object):
    def __init__(self, bus, path):
        dbus.service.Object.__init__(self, bus, path)
        self.fd = None
        self.path = path

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="", out_signature=""
    )
    def Release(self):
        logging.info("EchoProfile: Release")
        if self.fd:
            self.fd.close()
            self.fd = None

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="oha{sv}", out_signature=""
    )
    def NewConnection(self, path, fd, properties):
        logging.info(
            "EchoProfile: New Connection from {} {} {}".format(
                properties, path, fd
            )
        )
        self.fd = os.fdopen(fd.take(), "r+b", 0)
        try:
            while True:
                data = self.fd.read(1024)
                if not data:
                    time.sleep(0.1)
                    continue
                self.fd.write(data)  # Echo back the received data
        except OSError as e:
            logging.warn(f"EchoProfile: Connection closed or error: {e}")
        finally:
            logging.info(
                "EchoProfile: Closing Connection from {} {} {}".format(
                    properties, path, fd
                )
            )
            self.fd.close()
            self.fd = None

    @dbus.service.method(
        "org.bluez.Profile1", in_signature="", out_signature=""
    )
    def RequestDisconnection(self):
        logging.info("EchoProfile: Request Disconnection")
        if self.fd:
            self.fd.close()
            self.fd = None

    def cleanup(self):
        logging.info("EchoProfile: cleanup")
        self.remove_from_connection()


class BluezHIDService(dbus.service.Object):
    """Bluez Service implementation for HID."""

    def __init__(self, device_type, adapter_address):
        self._profile = None

        self._cinterrupt = None
        self._ccontrol = None
        self._connected = False

        self._scontrol = None
        self._sinterrupt = None
        self._scch_watch_id = None
        self._sich_watch_id = None

        self._bus = dbus.SystemBus()
        self._bus_name = dbus.service.BusName(
            BLUEZ_HID_SERVICE_NAME,
            bus=self._bus,
            replace_existing=True,
            allow_replacement=True,
        )
        super(BluezHIDService, self).__init__(
            self._bus_name, BLUEZ_HID_SERVICE_PATH
        )

        self._address = adapter_address
        self._device_type = device_type

        # Init profile only if one is declared for this device type
        profile_uuid = PERIPHERAL_PROFILE_UUID.get(self._device_type, None)
        if profile_uuid:
            self._InitBluezProfile(
                SERVICE_PROFILE_SDP_PATH.get(self._device_type, None),
                BLUEZ_HID_PERIPHERAL_PROFILE_PATH,
                profile_uuid,
            )

        self._Listen(self._address)

        # Add a handler for changes in state, specifically requesting caller's
        # device_path in the callback
        self.property_changed_match = self._bus.add_signal_receiver(
            self.PropertyChanged,
            signal_name="PropertiesChanged",
            bus_name="org.bluez",
            path_keyword="device_path",
        )

    def cleanup(self):
        logging.info("BluezHIDService: cleanup")

        if self._profile:
            self._profile.cleanup()
            self._profile = None

        if self._scontrol:
            self._scontrol.shutdown(socket.SHUT_RDWR)
            self._scontrol.close()
            self._scontrol = None
        if self._sinterrupt:
            self._sinterrupt.shutdown(socket.SHUT_RDWR)
            self._sinterrupt.close()
            self._sinterrupt = None

        if self._scch_watch_id:
            GLib.source_remove(self._scch_watch_id)
            self._scch_watch_id = None
        if self._sich_watch_id:
            GLib.source_remove(self._sich_watch_id)
            self._sich_watch_id = None

        if self.property_changed_match:
            self.property_changed_match.remove()
            self.property_changed_match = None

        self.remove_from_connection()

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

        if "Device1" in caller:
            if dbus.String("Connected") in prop_dict:
                remote_addr = str(caller_details["device_path"]).split("dev_")[
                    -1
                ]
                connection_status = bool(prop_dict[dbus.String("Connected")])

                info_msg = "Connection change to {}: {}".format(
                    remote_addr, connection_status
                )
                logging.info(info_msg)

                # Handle disconnection
                if not connection_status:
                    self.OnDisconnect(remote_addr)

        elif "Adapter1" in caller:
            if dbus.String("Discoverable") in prop_dict:
                discoverable_status = bool(
                    prop_dict[dbus.String("Discoverable")]
                )
                info_msg = "Discovery status changed: {}".format(
                    discoverable_status
                )
                logging.info(info_msg)

        else:
            logging.debug("Unknown d-bus signal caller: %s", caller)

    def OnDisconnect(self, remote_addr):
        """Called when disconnection occurs"""

        logging.info("Bluez service disconnected")

        if self._ccontrol is not None and self._ccontrol.fileno() > 0:
            try:
                peer_addr, _ = self._ccontrol.getpeername()[0]
                if peer_addr == remote_addr:
                    self._ccontrol.close()
            except:
                # getpeername throw an exception when it is not connected.
                logging.info("Control socket is already disconnected")

        if self._cinterrupt is not None and self._cinterrupt.fileno() > 0:
            try:
                peer_addr, _ = self._cinterrupt.getpeername()[0]
                if peer_addr == remote_addr:
                    self._cinterrupt.close()
            except:
                # getpeername throw an exception when it is not connected.
                logging.info("Interrupt socket is already disconnected")

        self._connected = False
        self._Listen(self._address)

    def _InitBluezProfile(
        self, profile_sdp_path, profile_dbus_path, profile_uuid
    ):
        """Register a Bluetooth profile with bluez.

        Args:
          profile_sdp_path: Relative path of XML file for profile SDP
          profile_uuid:     Service Class/ Profile UUID
          www.bluetooth.com/specifications/assigned-numbers/service-discovery/

        Raises:
          BluezServiceException: If there is an I/O error or an unknown error
        """

        logging.debug(
            "Configuring Bluez Profile from %s",
            SERVICE_PROFILE_SDP_PATH[self._device_type],
        )

        try:
            with open(profile_sdp_path, "r") as prfd:
                prf_content = prfd.read()
        except IOError as e:
            raise BluezServiceException(
                "I/O error ({0}): {1}".format(e.errno, e.strerror)
            )
        except:
            raise BluezServiceException("Unknown error in _InitBluezProfile()")
        else:
            opts = {
                "ServiceRecord": prf_content,
                "Role": "server",
                "RequireAuthentication": False,
                "RequireAuthorization": False,
            }

            self._profile = BluezServiceProfile(
                dbus.SystemBus(), profile_dbus_path
            )
            manager = dbus.Interface(
                dbus.SystemBus().get_object("org.bluez", "/org/bluez"),
                "org.bluez.ProfileManager1",
            )

            # Occasionally d-bus manager interface won't be ready in time, so we
            # delay in retry in case of a d-bus failure
            for _ in range(MAX_DBUS_RETRY_ATTEMPTS):
                try:
                    manager.RegisterProfile(
                        profile_dbus_path, profile_uuid, opts
                    )
                    break
                except (dbus.DBusException, TypeError) as e:
                    logging.info("Registering profile again... %s", str(e))
                    time.sleep(0.1)

    def _Listen(self, dev_addr):
        logging.info("start listening HID socket")

        if self._scch_watch_id:
            GLib.source_remove(self._scch_watch_id)
        if self._sich_watch_id:
            GLib.source_remove(self._sich_watch_id)
        if self._scontrol:
            self._scontrol.shutdown(socket.SHUT_RDWR)
            self._scontrol.close()
        if self._sinterrupt:
            self._sinterrupt.shutdown(socket.SHUT_RDWR)
            self._sinterrupt.close()

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
        self._scch_watch_id = GLib.io_add_watch(
            self._scch, GLib.IO_IN, self.OnConnect
        )
        self._sich_watch_id = GLib.io_add_watch(
            self._sich, GLib.IO_IN, self.OnConnect
        )

    @dbus.service.method("org.chromium.autotest.btkbservice", in_signature="s")
    def Connect(self, addr):
        """Initiates connection to remote host"""

        # Close sockets in case they are still open (a closed socket has fileno -1)
        if self._ccontrol is not None and self._ccontrol.fileno() > 0:
            self._ccontrol.close()
            self._cinterrupt.close()

        # Connect can fail if host isn't ready yet. Try a couple times to be safe
        for _ in range(0, MAX_CONNECT_RETRY_ATTEMPTS):
            try:
                self._ccontrol = BluetoothSocket(L2CAP)
                self._cinterrupt = BluetoothSocket(L2CAP)

                self._ccontrol.connect((str(addr), P_CTRL))
                self._cinterrupt.connect((str(addr), P_INTR))

                self._connected = True
                break

            except Exception as e:
                logging.warn("\tConnect failed, retrying: %s", str(e))

                time.sleep(0.5)

    def OnConnect(self, fd, _):
        if fd == self._scch:
            self._ccontrol, _ = self._scontrol.accept()
        elif fd == self._sich:
            self._cinterrupt, _ = self._sinterrupt.accept()
            self.Connected()

            logging.info("Bluez %s service connected", self._device_type)

    @dbus.service.method(
        "org.chromium.autotest.btkbservice", in_signature="yay"
    )
    def SendKeys(self, modifier, keys):
        # Avoid sending HID report when the Bluetooth socket has not yet accepted a
        # connection.

        logging.debug("Checking Bluez service is connected")
        self.wait_for_connected()
        report = bytes([0xA1, 0x01, modifier, 0x00])
        report += bytes(keys[:6])
        logging.debug(f"Sending HID report {report}")
        self._cinterrupt.send(report)

    @dbus.service.method("org.chromium.autotest.btkbservice", in_signature="ay")
    def SendHIDReport(self, report):
        """Sends HID report across socket"""
        # Avoid sending HID report when the Bluetooth socket has not yet accepted a
        # connection.
        self.wait_for_connected()

        # Convert from dbus to native type for socket send
        native_report = bytes(report)
        try:
            self._cinterrupt.send(native_report)
        except Exception as e:
            logging.info("Unknown Error %s", e)
            raise

    @dbus.service.signal("org.chromium.autotest.btkbservice", signature="")
    def Connected(self):
        self._connected = True
        pass

    def wait_for_connected(self):
        end_time = time.time() + 30
        next_log_time = time.time()
        sleep_interval = 1
        log_interval = 5

        while time.time() <= end_time:
            if self._connected:
                return
            else:
                if time.time() >= next_log_time:
                    logging.info("Bluez service may not be connected yet")
                    next_log_time = time.time() + log_interval
                time.sleep(sleep_interval)

        raise BluezServiceException(
            "Bluetooth Socket connection is not established yet"
        )


class BluezRfcommEchoService(dbus.service.Object):
    """Bluez Service implementation for RFCOMM Echo Service."""

    def __init__(self, device_type, adapter_address):
        self._profile = None
        self._bus = dbus.SystemBus()
        self._bus_name = dbus.service.BusName(
            BLUEZ_RFCOMM_SERVICE_NAME,
            bus=self._bus,
            replace_existing=True,
            allow_replacement=True,
        )
        super(BluezRfcommEchoService, self).__init__(
            self._bus_name, BLUEZ_RFCOMM_SERVICE_PATH
        )

        # Init profile only if one is declared for this device type
        profile_uuid = PERIPHERAL_PROFILE_UUID.get(device_type, None)
        if profile_uuid:
            self._InitBluezProfile(
                SERVICE_PROFILE_SDP_PATH.get(device_type, None),
                BLUEZ_RFCOMM_ECHO_PROFILE_PATH,
                profile_uuid,
            )

    def cleanup(self):
        logging.info("BluezRfcommEchoService: cleanup")

        if self._profile:
            self._profile.cleanup()
            self._profile = None

        self.remove_from_connection()

    def _InitBluezProfile(
        self, profile_sdp_path, profile_dbus_path, profile_uuid
    ):
        """Register a Bluetooth profile with bluez.

        Args:
          profile_sdp_path: Relative path of XML file for profile SDP
          profile_uuid:     Service Class/ Profile UUID
          www.bluetooth.com/specifications/assigned-numbers/service-discovery/

        Raises:
          BluezServiceException: If there is an I/O error or an unknown error
        """

        logging.debug(
            "Configuring Bluez Profile from %s",
            profile_sdp_path,
        )

        try:
            with open(profile_sdp_path, "r") as prfd:
                prf_content = prfd.read()
        except IOError as e:
            raise BluezServiceException(
                "I/O error ({0}): {1}".format(e.errno, e.strerror)
            )
        except:
            raise BluezServiceException("Unknown error in _InitBluezProfile()")
        else:
            opts = {
                "ServiceRecord": prf_content,
                "Role": "server",
                "RequireAuthentication": False,
                "RequireAuthorization": False,
                "Channel": dbus.UInt16(ECHO_SERVICE_CHANNEL),
            }

            self._profile = EchoProfile(dbus.SystemBus(), profile_dbus_path)

            manager = dbus.Interface(
                dbus.SystemBus().get_object("org.bluez", "/org/bluez"),
                "org.bluez.ProfileManager1",
            )

            # Occasionally d-bus manager interface won't be ready in time, so we
            # delay in retry in case of a d-bus failure
            for _ in range(MAX_DBUS_RETRY_ATTEMPTS):
                try:
                    manager.RegisterProfile(
                        profile_dbus_path, profile_uuid, opts
                    )
                    break
                except (dbus.DBusException, TypeError) as e:
                    logging.info("Registering profile again... %s", str(e))
                    time.sleep(0.1)
