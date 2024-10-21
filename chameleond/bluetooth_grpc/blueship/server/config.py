# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Config grpc interface."""

from blueship import config_grpc_aio
from blueship import config_pb2
from google.protobuf import empty_pb2
from google.protobuf.json_format import MessageToDict
from google.protobuf.json_format import ParseDict
import grpc


class ConfigService(config_grpc_aio.ConfigServicer):
    """Service to trigger Chameleon Config procedures."""

    def __init__(self, device_config):
        self.device_config = device_config
        self.default_config = config_pb2.Configuration()
        self.default_config.CopyFrom(device_config)

    async def ClearConfig(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        self.device_config.CopyFrom(self.default_config)
        return empty_pb2.Empty()

    async def WriteConfig(
        self,
        request: config_pb2.WriteConfigRequest,
        context: grpc.ServicerContext,
    ) -> config_pb2.WriteConfigResponse:
        success = True

        req_config_dict = MessageToDict(request.config)
        cur_config_dict = MessageToDict(self.device_config)

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

                cur_entry[req_entry_value_type] = req_entry_value

        if success:
            ParseDict(cur_config_dict, self.device_config)

        resp = config_pb2.WriteConfigResponse()
        resp.success = success
        return resp

    async def ReadConfig(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> config_pb2.ReadConfigResponse:
        return config_pb2.ReadConfigResponse(config=self.device_config)
