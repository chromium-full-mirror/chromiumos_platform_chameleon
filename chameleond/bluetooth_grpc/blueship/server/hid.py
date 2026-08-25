# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""HID grpc interface."""

import time

from blueship import hid_grpc_aio
from blueship import hid_pb2
from chameleond.bluetooth_grpc.blueship.server.utils import check_server_ready
from google.protobuf import empty_pb2
import grpc


class HIDService(hid_grpc_aio.HIDServicer):
    """Service to trigger Chameleon HID procedures."""

    # Delay after each keyboard traffic in seconds
    KEYBOARD_DELAY = 0.01

    # Delay after each mouse traffic in seconds
    MOUSE_DELAY = 0.01

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context

    @check_server_ready
    async def PressKey(
        self,
        request: hid_pb2.KeyPressRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.KeyboardPressSingleKey(request.key)
        # A shortcut solution to ensure the event is sent
        time.sleep(self.KEYBOARD_DELAY)
        return empty_pb2.Empty()

    @check_server_ready
    async def ReleaseKey(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.KeyboardReleaseAllKey()
        # A shortcut solution to ensure the event is sent
        time.sleep(self.KEYBOARD_DELAY)
        return empty_pb2.Empty()

    @check_server_ready
    async def MouseMove(
        self,
        request: hid_pb2.MouseMoveRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.Move(
            request.delta_x, request.delta_y, delay=self.MOUSE_DELAY
        )
        return empty_pb2.Empty()

    @check_server_ready
    async def MouseScroll(
        self,
        request: hid_pb2.MouseScrollRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.btd.Scroll(
            request.steps
        )
        return empty_pb2.Empty()

