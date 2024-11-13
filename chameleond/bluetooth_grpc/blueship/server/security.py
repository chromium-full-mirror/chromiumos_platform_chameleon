# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Security grpc interface."""

import asyncio
from typing import AsyncGenerator

from blueship import security_grpc_aio
from blueship import security_pb2
from chameleond.bluetooth_grpc.pandora.server import utils
from google.protobuf import empty_pb2
import grpc


class SecurityService(security_grpc_aio.SecurityServicer):
    """Service to trigger Chameleon Security procedures."""

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context

    async def Pair(
        self,
        request: security_pb2.PairRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        address = utils.address_from(request.address)
        self.ctx.btd.SetRemoteAddress(address)
        self.ctx.btd.Pair()
        return empty_pb2.Empty()
