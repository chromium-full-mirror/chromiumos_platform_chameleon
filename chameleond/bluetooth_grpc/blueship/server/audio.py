# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Audio grpc interface."""

import asyncio
from typing import AsyncGenerator

from blueship import audio_grpc_aio
from blueship import audio_pb2
from chameleond.bluetooth_grpc.pandora.server import utils
from google.protobuf import empty_pb2
import grpc


class AudioService(audio_grpc_aio.AudioServicer):
    """Service to trigger Chameleon Audio procedures."""

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context

    async def StartRecordAudio(
        self,
        request: audio_pb2.StartRecordAudioRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        test_data = {
            "rate": None,
            "channels": 2,
            "recorded_by_peer": request.path,
            "format": "S16_LE",
        }
        if request.profile == audio_pb2.Audio_Profile_A2DP:
            audio_profile = "A2DP"
            # Audio test data for a2dp
            test_data["rate"] = 48000
            test_data["channels"] = 2
        elif request.profile == audio_pb2.Audio_Profile_HFP:
            # This is assuming that WBS is in used.
            # TODO: Get the selected codec from configuration
            audio_profile = "hfp_wbs"
            test_data["rate"] = 16000
            test_data["channels"] = 1

        self.ctx.btd.StartRecordingAudioSubprocess(audio_profile, test_data)
        return empty_pb2.Empty()

    async def StopRecordAudio(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        self.ctx.btd.StopRecordingingAudioSubprocess()
        return empty_pb2.Empty()

    async def StartPlayAudio(
        self,
        request: audio_pb2.StartPlayAudioRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        # This is assuming that WBS is in used.
        # TODO: Get the selected codec from configuration
        test_data = {
            "rate": 16000,
            "channels": 1,
            "device_file": request.path,
            "format": "S16_LE",
        }

        self.ctx.btd.StartPlayingAudioSubprocess("hfp_wbs", test_data)
        return empty_pb2.Empty()

    async def StopPlayAudio(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        self.ctx.btd.StopPlayingAudioSubprocess()
        return empty_pb2.Empty()
