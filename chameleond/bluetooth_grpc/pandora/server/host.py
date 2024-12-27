# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Host grpc interface."""

import asyncio
import logging
from typing import AsyncGenerator

from chameleond.bluetooth_grpc.pandora.server import utils
import dbus
from google.protobuf import empty_pb2
import grpc
from pandora import host_grpc_aio
from pandora import host_pb2


class HostService(host_grpc_aio.HostServicer):
    """Service to trigger Bluetooth Host procedures."""

    def __init__(self, server, shared_context, security):
        """Initialize the struct

        Args:
            server: the gRPC server instance
            shared_context: context that is shared by all service
            security: instance of SecurityService
        """
        self.server = server
        self.ctx = shared_context
        self.security = security

        # Context for Scan
        self.scan_async_loop = None
        self.scan_rsp_queue = None
        self.service_data_callback_handle = (
            self.ctx.btd.bluez_observer.RegisterServiceDataChangedCallback(
                self._service_data_callback
            )
        )

        self.on_device_found_callback_handle = (
            self.ctx.btd.bluez_observer.RegisterDeviceFoundCallback(
                self._on_device_found_callback
            )
        )

    def _service_data_callback(self, *args):
        address, service_data = args

        if self.scan_rsp_queue is not None and self.scan_async_loop is not None:
            asyncio.run_coroutine_threadsafe(
                self.scan_rsp_queue.put(
                    host_pb2.ScanningResponse(
                        public=utils.address_to(address),
                        data=host_pb2.DataTypes(
                            service_data_uuid128=utils.service_data_to(
                                service_data
                            )
                        ),
                    )
                ),
                self.scan_async_loop,
            )

    def _on_device_found_callback(self, *args):
        address, props = args

        if self.scan_rsp_queue is not None and self.scan_async_loop is not None:
            scan_rsp = host_pb2.ScanningResponse(
                public=utils.address_to(address)
            )
            service_data = props.get("ServiceData", None)

            if service_data:
                scan_rsp.data.service_data_uuid128.update(
                    utils.service_data_to(service_data)
                )
            asyncio.run_coroutine_threadsafe(
                self.scan_rsp_queue.put(scan_rsp),
                self.scan_async_loop,
            )

    async def FactoryReset(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        # Restart the grpc server
        logging.info("FactoryReset")
        asyncio.create_task(self.server.stop(None))
        return empty_pb2.Empty()

    async def Reset(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        # Side effect: the device will be set to discoverable.
        self.ctx.btd.Reboot()
        return empty_pb2.Empty()

    async def ReadLocalAddress(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> host_pb2.ReadLocalAddressResponse:
        address = self.ctx.btd.GetLocalBluetoothAddress()
        return host_pb2.ReadLocalAddressResponse(
            address=utils.address_to(address)
        )

    async def Connect(
        self, request: host_pb2.ConnectRequest, context: grpc.ServicerContext
    ) -> host_pb2.ConnectResponse:
        # TODO(johnlai): Checks controller config before initiating the
        # connection.
        address = utils.address_from(request.address)
        self.ctx.btd.SetRemoteAddress(address)
        connected = self.ctx.btd.Connect()

        if not connected:
            await context.abort(
                grpc.StatusCode.UNKNOWN, f"Failed to connect to the {address}."
            )

        return host_pb2.ConnectResponse(
            connection=utils.connection_to(
                utils.Connection(address, utils.BtTransport.BREDR)
            )
        )

    async def WaitConnection(
        self,
        request: host_pb2.WaitConnectionRequest,
        context: grpc.ServicerContext,
    ) -> host_pb2.WaitConnectionResponse:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

    async def ConnectLE(
        self, request: host_pb2.ConnectLERequest, context: grpc.ServicerContext
    ) -> host_pb2.ConnectLEResponse:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

    async def WaitConnectionUpdate(
        self,
        request: host_pb2.WaitConnectionUpdateRequest,
        context: grpc.ServicerContext,
    ) -> host_pb2.WaitConnectionUpdateResponse:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

    async def GetConnectionParameters(
        self,
        request: host_pb2.GetConnectionParametersRequest,
        context: grpc.ServicerContext,
    ) -> host_pb2.GetConnectionParametersResponse:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

    async def Disconnect(
        self, request: host_pb2.DisconnectRequest, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        address = utils.address_from(request.address)
        self.ctx.btd.SetRemoteAddress(address)
        connected = self.ctx.btd.get_device_property(address, "Connected")

        if connected:
            logging.info("Disconnect: device is already disconnected.")
        else:
            self.ctx.btd.Disconnect()

        return empty_pb2.Empty()

    async def WaitDisconnection(
        self,
        request: host_pb2.WaitDisconnectionRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

    async def Advertise(
        self, request: host_pb2.AdvertiseRequest, context: grpc.ServicerContext
    ) -> AsyncGenerator[host_pb2.AdvertiseResponse, None]:
        # TODO(johnlai): Checks controller config before starting the
        # advertising.

        # Chameleon can only advertise one advertising set, disables
        # current advertising firstly.
        self.ctx.btd.SetDiscoverable(False)

        # TODO(johnlai): Configure advertisement data.

        connections = None
        properties_changed_receiver = None
        default_gatt_server_removed = False
        if request.connectable:
            connections = asyncio.Queue()
            loop = asyncio.get_running_loop()

            # Register callback to be called when a device is connected.
            def on_property_changed(*args, **kwargs):
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
                    f"on_property_changed: changed_prop: {changed_prop} caller_info: {caller_info}"
                )

                if "Device1" in caller:
                    address = utils.address_from_bluez_device_path(
                        str(caller_info["device_path"])
                    )
                    paired = False
                    connected = False

                    # Based on the experiment, pairing and connecting with
                    # another device only results in a 'Paired' property change.
                    if dbus.String("Connected") in prop_dict:
                        connected = bool(prop_dict[dbus.String("Connected")])
                        logging.info(
                            f"Connection change to {address}: {connected}"
                        )
                    elif dbus.String("Paired") in prop_dict:
                        paired = bool(prop_dict[dbus.String("Paired")])
                        logging.info(
                            f"Pairing state change to {paired}: {paired}"
                        )

                    # According to the Pandora interface definition, restarting
                    # advertising again after any incoming connection has been
                    # established.
                    if paired or connected:
                        loop.call_soon_threadsafe(
                            self.ctx.btd.SetDiscoverable, False
                        )
                        loop.call_soon_threadsafe(
                            self.ctx.btd.SetDiscoverable, True
                        )

                        # Puts new connection into the queue.
                        asyncio.run_coroutine_threadsafe(
                            connections.put(address), loop
                        )
                elif "Adapter1" in caller:
                    if dbus.String("Powered") in prop_dict:
                        powered = bool(prop_dict[dbus.String("Powered")])

                        if powered:
                            loop.call_soon_threadsafe(
                                self.ctx.btd.SetDiscoverable, False
                            )
                            loop.call_soon_threadsafe(
                                self.ctx.btd.SetDiscoverable, True
                            )

            bus = dbus.SystemBus()
            if self.ctx.btd._gatt_server.receiver:
                self.ctx.btd._gatt_server.receiver.remove()
                self.ctx.btd._gatt_server.receiver = None
                default_gatt_server_removed = True

            properties_changed_receiver = bus.add_signal_receiver(
                on_property_changed,
                signal_name="PropertiesChanged",
                bus_name="org.bluez",
                path_keyword="device_path",
            )

        # Starts advertising.
        self.ctx.btd.SetDiscoverable(True)

        try:
            while True:
                if request.connectable:
                    logging.info("Advertise: Wait for LE connection...")
                    address = await connections.get()
                    logging.info("Advertise: Connected to %s", address)

                    yield host_pb2.AdvertiseResponse(
                        connection=utils.connection_to(
                            utils.Connection(address, utils.BtTransport.LE)
                        )
                    )

                await asyncio.sleep(1)
        finally:
            self.ctx.btd.SetDiscoverable(False)

            if properties_changed_receiver:
                properties_changed_receiver.remove()

            if (
                not self.ctx.btd._gatt_server.receiver
                and default_gatt_server_removed
            ):
                bus = dbus.SystemBus()

                self.ctx.btd._gatt_server.receiver = bus.add_signal_receiver(
                    self.ctx.btd._gatt_server.OnPropertyChanged,
                    signal_name="PropertiesChanged",
                    bus_name="org.bluez",
                    path_keyword="device_path",
                )

    async def Scan(
        self, request: host_pb2.ScanRequest, context: grpc.ServicerContext
    ) -> AsyncGenerator[host_pb2.ScanningResponse, None]:
        properties_changed_receiver = None
        interfaces_added_receiver = None

        try:
            self.scan_rsp_queue = asyncio.Queue()
            self.scan_async_loop = asyncio.get_running_loop()

            discovery_filter = {"Transport": "le"}
            self.ctx.btd.SetDiscoveryFilter(discovery_filter)
            self.ctx.btd.StartDiscovery()

            while True:
                # TODO(johnlai) This address will always be resolved address.
                # Fix this once we know how to differentiate bluez address type.
                yield await self.scan_rsp_queue.get()

        finally:
            self.ctx.btd.SetDiscoveryFilter({})
            self.ctx.btd.StopDiscovery()
            self.scan_rsp_queue = None
            self.scan_async_loop = None

    async def Inquiry(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> AsyncGenerator[host_pb2.InquiryResponse, None]:
        receiver = None
        try:
            discovered_devices = asyncio.Queue()
            loop = asyncio.get_running_loop()

            def on_device_found(*args, **kwargs):
                changed_prop = args
                caller_details = kwargs
                caller = str(changed_prop[0])

                if "Device1" in caller:
                    device_path = caller_details.get("device_path")
                    address = utils.address_from_bluez_device_path(device_path)
                    asyncio.run_coroutine_threadsafe(
                        discovered_devices.put(address), loop
                    )

            discovery_filter = {"Transport": "bredr"}
            self.ctx.btd.SetDiscoveryFilter(discovery_filter)

            bus = dbus.SystemBus()
            receiver = bus.add_signal_receiver(
                on_device_found,
                signal_name="PropertiesChanged",
                bus_name="org.bluez",
                path_keyword="device_path",
            )

            self.ctx.btd.StartDiscovery()

            while True:
                address = await discovered_devices.get()
                yield host_pb2.InquiryResponse(
                    address=utils.address_to(address)
                )
        finally:
            if receiver:
                receiver.remove()
            self.ctx.btd.SetDiscoveryFilter({})
            self.ctx.btd.StopDiscovery()

    async def SetDiscoverabilityMode(
        self,
        request: host_pb2.SetDiscoverabilityModeRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        mode = request.mode
        if mode == host_pb2.DISCOVERABLE_LIMITED:
            await context.abort(
                grpc.StatusCode.UNIMPLEMENTED,
                "SetDiscoverabilityMode: limited discoverable mode is not supported",
            )
        elif mode == host_pb2.NOT_DISCOVERABLE:
            self.ctx.btd.SetDiscoverableNoConfigAdv(False)
        elif mode == host_pb2.DISCOVERABLE_GENERAL:
            self.ctx.btd.SetDiscoverableNoConfigAdv(True)
        return empty_pb2.Empty()

    async def SetConnectabilityMode(
        self,
        request: host_pb2.SetConnectabilityModeRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")
