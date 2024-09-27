# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Host grpc interface."""

import asyncio
from typing import AsyncGenerator

from chameleond.bluetooth.pandora.server import utils
from google.protobuf import empty_pb2
import grpc
from pandora import host_grpc_aio
from pandora import host_pb2


class HostService(host_grpc_aio.HostServicer):
    """Service to trigger Bluetooth Host procedures."""

    def __init__(self, server, bluetooth, security):
        self.server = server
        self.bluetooth = bluetooth
        self.security = security

    async def FactoryReset(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        self.bluetooth.ResetStack()
        asyncio.create_task(self.server.stop(None))
        return empty_pb2.Empty()

    async def Reset(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        # Side effect: the device will be set to discoverable.
        self.bluetooth.Reboot()
        return empty_pb2.Empty()

    async def ReadLocalAddress(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> host_pb2.ReadLocalAddressResponse:
        address = self.bluetooth.GetLocalBluetoothAddress()
        return host_pb2.ReadLocalAddressResponse(
            address=utils.address_to(address)
        )

    async def Connect(
        self, request: host_pb2.ConnectRequest, context: grpc.ServicerContext
    ) -> host_pb2.ConnectResponse:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

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
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")

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
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")
        yield host_pb2.AdvertiseResponse()

    async def Scan(
        self, request: host_pb2.ScanRequest, context: grpc.ServicerContext
    ) -> AsyncGenerator[host_pb2.ScanningResponse, None]:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")
        yield host_pb2.ScanningResponse()

    async def Inquiry(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> AsyncGenerator[host_pb2.InquiryResponse, None]:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")
        yield host_pb2.InquiryResponse()

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
            self.bluetooth.SetDiscoverableNoConfigAdv(False)
        elif mode == host_pb2.DISCOVERABLE_GENERAL:
            self.bluetooth.SetDiscoverableNoConfigAdv(True)
        return empty_pb2.Empty()

    async def SetConnectabilityMode(
        self,
        request: host_pb2.SetConnectabilityModeRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        context.set_code(grpc.StatusCode.UNIMPLEMENTED)
        context.set_details("Method not implemented!")
        raise NotImplementedError("Method not implemented!")
