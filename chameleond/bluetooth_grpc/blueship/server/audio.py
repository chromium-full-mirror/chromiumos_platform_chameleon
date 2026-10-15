# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Audio grpc interface."""

import asyncio
import logging
from typing import AsyncGenerator

from blueship import audio_grpc_aio
from blueship import audio_pb2
from chameleond.bluetooth_grpc.blueship.server.utils import check_server_ready
from google.protobuf import empty_pb2
import grpc


# Delta of each volume change
VOLUME_DELTA = 5


class AudioService(audio_grpc_aio.AudioServicer):
    """Service to trigger Chameleon Audio procedures."""

    def __init__(self, shared_context):
        """Initialize the struct

        Args:
            shared_context: context that is shared by all service
        """
        self.ctx = shared_context

    @property
    def is_wbs(self):
        return self.ctx.hfp_codec == "mSBC"

    @check_server_ready
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
        if request.profile == audio_pb2.AUDIO_PROFILE_A2DP:
            audio_profile = "a2dp"
            # Audio test data for a2dp
            test_data["rate"] = 48000
            test_data["channels"] = 2
        elif request.profile == audio_pb2.AUDIO_PROFILE_HFP:
            if self.is_wbs:
                audio_profile = "hfp_wbs"
                test_data["rate"] = 16000
                test_data["channels"] = 1
            else:
                audio_profile = "hfp_nbs"
                test_data["rate"] = 8000
                test_data["channels"] = 1

        if not self.ctx.btd.StartRecordingAudioSubprocess(
            audio_profile, test_data
        ):
            context.abort(grpc.StatusCode.INTERNAL, "Failed to start recording")
        return empty_pb2.Empty()

    @check_server_ready
    async def StopRecordAudio(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        if not self.ctx.btd.StopRecordingingAudioSubprocess():
            context.abort(grpc.StatusCode.INTERNAL, "Failed to stop recording")
        return empty_pb2.Empty()

    @check_server_ready
    async def StartPlayAudio(
        self,
        request: audio_pb2.StartPlayAudioRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        if self.is_wbs:
            audio_profile = "hfp_wbs"
            test_data = {
                "rate": 16000,
                "channels": 1,
                "device_file": request.path,
                "format": "S16_LE",
            }
        else:
            audio_profile = "hfp_nbs"
            test_data = {
                "rate": 8000,
                "channels": 1,
                "device_file": request.path,
                "format": "S16_LE",
            }

        if not self.ctx.btd.StartPlayingAudioSubprocess(
            audio_profile, test_data
        ):
            context.abort(grpc.StatusCode.INTERNAL, "Failed to start playing")
        return empty_pb2.Empty()

    @check_server_ready
    async def StopPlayAudio(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> empty_pb2.Empty:
        if not self.ctx.btd.StopPlayingAudioSubprocess():
            context.abort(grpc.StatusCode.INTERNAL, "Failed to stop playing")
        return empty_pb2.Empty()

    @check_server_ready
    async def SendAvrcpCmd(
        self,
        request: audio_pb2.SendAvrcpCmdRequest,
        context: grpc.ServicerContext,
    ) -> empty_pb2.Empty:
        if request.cmd == audio_pb2.AUDIO_PLAYER_VOL_UP:
            self.ctx.btd.SetVolumeDelta(VOLUME_DELTA)
            return empty_pb2.Empty()
        elif request.cmd == audio_pb2.AUDIO_PLAYER_VOL_DOWN:
            self.ctx.btd.SetVolumeDelta(-VOLUME_DELTA)
            return empty_pb2.Empty()
        elif request.cmd == audio_pb2.AUDIO_PLAYER_PLAY:
            cmd = "play"
        elif request.cmd == audio_pb2.AUDIO_PLAYER_PAUSE:
            cmd = "pause"
        elif request.cmd == audio_pb2.AUDIO_PLAYER_STOP:
            cmd = "stop"
        elif request.cmd == audio_pb2.AUDIO_PLAYER_NEXT:
            cmd = "next"
        elif request.cmd == audio_pb2.AUDIO_PLAYER_PREV:
            cmd = "previous"
        else:
            logging.error("Unrecognized command %s", request.cmd)
            return empty_pb2.Empty()

        self.ctx.btd.SendMediaPlayerCommand(cmd)
        return empty_pb2.Empty()

    @check_server_ready
    async def OnMediaInfoChanged(
        self, request: empty_pb2.Empty, context: grpc.ServicerContext
    ) -> AsyncGenerator[audio_pb2.MediaInfo, None]:
        def _to_media_info_message(info_dict):
            """Helper function to convert media info from dict to message"""
            try:
                # playerctl only supports Stopped, Playing and Paused
                if info_dict["status"] == "Stopped":
                    status = audio_pb2.PLAYER_STATUS_STOPPED
                elif info_dict["status"] == "Playing":
                    status = audio_pb2.PLAYER_STATUS_PLAYING
                elif info_dict["status"] == "Paused":
                    status = audio_pb2.PLAYER_STATUS_PAUSED
                else:
                    logging.error(
                        "Player status %s is not recognized",
                        info_dict["status"],
                    )

                return audio_pb2.MediaInfo(
                    artist=info_dict["artist"],
                    title=info_dict["title"],
                    album=info_dict["album"],
                    length=int(info_dict["length"]),
                    status=status,
                )
            except Exception as e:
                logging.warn("error in generating media info: %s", str(e))
                return None

        info_msg = None
        # Playerctl does provide DBus signal allows clients to get updates.
        # There seems no strong needs to do, so implement it by a simple loop.
        while True:
            new_info_msg = _to_media_info_message(
                self.ctx.btd.GetMediaPlayerMediaInfo()
            )

            if new_info_msg is not None and info_msg != new_info_msg:
                info_msg = new_info_msg
                yield new_info_msg

            await asyncio.sleep(1)
