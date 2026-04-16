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

    async def IsServerReady(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> manager_pb2.IsServerReadyResponse:
        return manager_pb2.IsServerReadyResponse(value=self.ctx.is_server_ready)

    async def GetApiVersion(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> manager_pb2.GetApiVersionResponse:
        version = self.ctx.config.api.support_api_version.string_value
        return manager_pb2.GetApiVersionResponse(version=version)

    async def ResetServer(
        self,
        request: empty_pb2.Empty,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        raise NotImplementedError("Method not implemented!")

    async def RestartServer(
        self,
        request: manager_pb2.RestartServerRequest,
        context: grpc.ServicerContext,
    ) -> manager_pb2.RestartServerResponse:
        raise NotImplementedError("Method not implemented!")

    async def ApplyConfig(
        self,
        request: manager_pb2.ApplyConfigRequest,
        context: grpc.ServicerContext,
    ) -> manager_pb2.ApplyConfigResponse:
        if self.ctx.is_configured:
            logging.warning("ApplyConfig: Already configured, ignoring.")
            return manager_pb2.ApplyConfigResponse(success=False)

        config_dict = self._to_config_dict_or_none(request.next_config)
        success = config_dict is not None

        if success:
            logging.info("ApplyConfig: Applying config.")
            self.ctx.is_server_ready = False
            ParseDict(config_dict, self.ctx.config)
            asyncio.create_task(self.ctx.initialize_device())

        return manager_pb2.ApplyConfigResponse(success=success)

    async def ReadConfig(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> manager_pb2.ReadConfigResponse:
        return manager_pb2.ReadConfigResponse(config=self.ctx.config)

    async def IsConfigOK(
        self,
        request: manager_pb2.IsConfigOKRequest,
        context: grpc.ServicerContext,
    ) -> manager_pb2.IsConfigOKResonse:
        return manager_pb2.IsConfigOKResonse(
            ok=self._to_config_dict_or_none(request.config) is not None
        )

    def _to_config_dict_or_none(self, config):
        req_config_dict = MessageToDict(config)
        res_config_dict = MessageToDict(self.ctx.default_config)

        logging.info("Request config: %s", req_config_dict)

        for section_name, section_dict in req_config_dict.items():
            for entry_name, entry_variant in section_dict.items():
                res_entry = res_config_dict[section_name][entry_name]
                # Remove the writable field as we don't update it.
                entry_variant.pop("writable", None)
                # The entry must have another field, this is secured by proto definition
                (req_entry_value_type, req_entry_value) = list(
                    entry_variant.items()
                )[0]

                if req_entry_value_type not in res_entry:
                    return None

                if res_entry[req_entry_value_type] == req_entry_value:
                    continue

                # Needs to update the current config
                if not res_entry.get("writable", False):
                    return None

                res_entry[req_entry_value_type] = req_entry_value

        def _check_codec_supported():
            UNSUPPORTERD_CODEC = [
                "CODEC_AAC",
                "CODEC_APTX",
                "CODEC_LDAC",
                "CODEC_LC3",
            ]
            for codec in UNSUPPORTERD_CODEC:
                if (
                    codec
                    in req_config_dict["audio"]["supportedCodecs"]["codecList"][
                        "codecList"
                    ]
                ):
                    logging.warning("codec %s is not supported.", codec)
                    return False

            return True

        check_funcs = [
            _check_codec_supported,
        ]

        for func in check_funcs:
            try:
                if not func():
                    return None
            except KeyError:
                # The entries checking above might not be included in the
                # request. Ignore the key error for easier implementation.
                pass
            except Exception as e:
                logging.error("Exception: %s", str(e))

        return res_config_dict
