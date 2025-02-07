# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Power grpc interface."""

import logging
import time

from blueship import power_grpc_aio
from blueship import power_pb2
from google.protobuf import empty_pb2
import grpc


class PowerService(power_grpc_aio.PowerServicer):
    """Service to trigger Chameleon power procedures."""

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context
        self.connected_device = None
        self.bredr_only = not self.ctx.support_le and self.ctx.support_classic

    async def PowerOn(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.AdapterPowerOn()
        self.ctx.btd.Init()

        # Wait until power on procedure completes.
        time.sleep(1)

        if self.bredr_only and self.connected_device is not None:
            self.ctx.btd.SetRemoteAddress(self.connected_device)
            logging.info("Reconnect to %s", self.connected_device)
            self.ctx.btd.Connect()

            # If it's classic HID, it's expected the peripheral to connect the
            # HID profile.
            if self.ctx.device_type in ["KEYBOARD", "MOUSE"]:
                logging.info("Reconnect to HID")
                self.ctx.btd.ConnectHID()

        return empty_pb2.Empty()

    async def PowerOff(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        if self.bredr_only:
            # Record the connected device before powering off. It is expected to
            # have only one connected device.
            self.connected_device = (
                self.ctx.btd.GetRemoteConnectedBluetoothAddress()
            )

        self.ctx.btd.AdapterPowerOff()

        # Wait until power off procedure completes
        time.sleep(1)

        return empty_pb2.Empty()

    async def SetBatteryLevel(
        self,
        request: power_pb2.SetBatteryLevelRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.SetBatteryLevel(request.battery_level)

        return empty_pb2.Empty()
