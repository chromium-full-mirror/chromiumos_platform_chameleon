# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Manager grpc interface."""

import asyncio
import logging

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

        logging.info("Request config: %s", req_config_dict)

        for section_name, section_dict in req_config_dict.items():
            for entry_name, entry_variant in section_dict.items():
                cur_entry = cur_config_dict[section_name][entry_name]
                # Remove the writable field as we don't update it.
                entry_variant.pop("writable", None)
                # The entry must have another field, this is secured by proto definition
                (req_entry_value_type, req_entry_value) = list(
                    entry_variant.items()
                )[0]

                if req_entry_value_type not in cur_entry:
                    success = False
                    break

                if cur_entry[req_entry_value_type] == req_entry_value:
                    continue

                # Needs to update the current config
                if not cur_entry.get("writable", False):
                    success = False
                    break

                cur_entry[req_entry_value_type] = req_entry_value

        # Check if the entry value is supported on chameleon
        try:
            unsupported_codec = [
                "CODEC_AAC",
                "CODEC_APTX",
                "CODEC_LDAC",
                "CODEC_LC3",
            ]
            for codec in unsupported_codec:
                if (
                    codec
                    in req_config_dict["audio"]["supportedCodecs"]["codecList"][
                        "codecList"
                    ]
                ):
                    success = False
                    break
        except KeyError:
            # The entries checking above might not be included in the request.
            # Ignore the key error for easier implementation.
            pass
        except Exception as e:
            logging.error("Exception on getting supported codec: %s", str(e))

        if success:
            ParseDict(cur_config_dict, self.ctx.config)
            # Stop the server and rely on the |start_bluetooth_test_server|
            # to restart.
            asyncio.create_task(self.server.stop(None))

        return manager_pb2.RestartServerResponse(success=success)

    async def ReadConfig(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> manager_pb2.ReadConfigResponse:
        return manager_pb2.ReadConfigResponse(config=self.ctx.config)
