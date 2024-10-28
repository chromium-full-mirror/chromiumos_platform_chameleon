# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Manager grpc interface."""

import asyncio

from blueship import manager_grpc_aio
from blueship import manager_pb2
from google.protobuf import empty_pb2
from google.protobuf.json_format import MessageToDict
from google.protobuf.json_format import ParseDict
import grpc


class ManagerService(manager_grpc_aio.ManagerServicer):
    """Service to trigger Chameleon Manager procedures."""

    def __init__(self, shared_context, server):
        self.ctx = shared_context
        self.server = server

    async def ResetServer(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.ctx.config.CopyFrom(self.ctx.default_config)
        asyncio.create_task(self.server.stop(None))
        return empty_pb2.Empty()

    async def RestartServer(
        self,
        request: manager_pb2.RestartServerRequest,
        context: grpc.ServicerContext,
    ) -> manager_pb2.RestartServerResponse:
        success = True

        req_config_dict = MessageToDict(request.next_config)
        cur_config_dict = MessageToDict(self.ctx.config)

        for section_name, section_dict in req_config_dict.items():
            for entry_name, entry_variant in section_dict.items():
                cur_entry = cur_config_dict[section_name][entry_name]
                if not cur_entry.get("writable", False):
                    continue
                # Remove the writable field as we don't update it.
                entry_variant.pop("writable", None)
                # The entry must have another field, this is secured by proto definition
                (req_entry_value_type, req_entry_value) = list(
                    entry_variant.items()
                )[0]

                if req_entry_value_type not in cur_entry:
                    success = False
                    continue

                if cur_entry[req_entry_value_type] == req_entry_value:
                    continue

                cur_entry[req_entry_value_type] = req_entry_value

        if success:
            ParseDict(cur_config_dict, self.ctx.config)
            # Stop the server and rely on the |start_bluetooth_test_server|
            # to restart.
            asyncio.create_task(self.server.stop(None))

        return empty_pb2.Empty()

    async def ReadConfig(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> manager_pb2.ReadConfigResponse:
        return manager_pb2.ReadConfigResponse(config=self.ctx.config)
