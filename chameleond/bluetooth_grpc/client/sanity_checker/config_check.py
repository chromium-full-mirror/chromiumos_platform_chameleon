# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

import time
import unittest

from blueship import audio_pb2
from blueship import manager_pb2
from blueship.manager_grpc import Manager
import grpc


PANDORA_SERVER_PORT = 8999


class ConfigGrpcTests(unittest.TestCase):
    """Class to perform sanity check on ConfigService via unittest framework"""

    DEFAULT_API_VERSION = "0.0"
    DEFAULT_IO_CAPABILITY = manager_pb2.IO_CAPABILITY_NO_INPUT_NO_OUTPUT
    DEFAULT_DEVICE_CATEGORY = manager_pb2.DEVICE_CATEGORY_KEYBOARD
    DEFAULT_SUPPORT_CLASSIC = False
    DEFAULT_SUPPORT_LE = True
    DEFAULT_PIN = "0000"
    DEFAULT_CODEC_LIST = [manager_pb2.CODEC_CVSD]
    DEFAULT_AUDIO_PLAYER_LIST = [
        audio_pb2.AUDIO_PLAYER_PLAY,
        audio_pb2.AUDIO_PLAYER_PAUSE,
        audio_pb2.AUDIO_PLAYER_STOP,
        audio_pb2.AUDIO_PLAYER_NEXT,
        audio_pb2.AUDIO_PLAYER_PREV,
    ]

    def setUp(self):
        """Setup the testing environment"""
        # TODO: Start gRPC server before the tests
        self.connect_to_server()
        self.manager_proxy = Manager(self.proxy)

    def tearDown(self):
        """Clear the testing environment"""
        self.connect_to_server()

    def connect_to_server(self):
        self.proxy = grpc.insecure_channel(f"localhost:{PANDORA_SERVER_PORT}")
        try:
            # Wait for the channel to become ready, with a timeout
            channel_ready_future = grpc.channel_ready_future(self.proxy)
            channel_ready_future.result(timeout=60)  # Adjust timeout as needed
        except grpc.FutureTimeoutError:
            print("Connection timed out.")
        except grpc.RpcError as e:
            print(f"Error connecting to server: {e}")

    def test_read_api(self):
        """Test Support API Version can be read"""
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.api.support_api_version.string_value,
            self.DEFAULT_API_VERSION,
        )

    def test_write_api(self):
        """Test Support API Version can not be written on chameleon"""
        write_config = manager_pb2.Configuration()
        write_config.api.support_api_version.string_value = "0.2"
        resp = self.manager_proxy.RestartServer(write_config)

        # Wait for the server to be restarted
        self.connect_to_server()

        # API version should not be changed.
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.api.support_api_version.string_value,
            self.DEFAULT_API_VERSION,
        )

    def test_read_io_capability(self):
        """Test IO Capability can be read"""
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.device.io_capability.io_capability,
            self.DEFAULT_IO_CAPABILITY,
        )

    def test_write_io_capability(self):
        """Test IO Capability can be written"""
        write_config = manager_pb2.Configuration()
        write_config.device.io_capability.io_capability = (
            manager_pb2.IO_CAPABILITY_KEYBOARD_DISPLAY
        )
        resp = self.manager_proxy.RestartServer(write_config)

        # Wait for the server to be restarted
        self.connect_to_server()

        # IO Capability should be changed.
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.device.io_capability.io_capability,
            manager_pb2.IO_CAPABILITY_KEYBOARD_DISPLAY,
        )

    def test_read_device_category(self):
        """Test device category can be read"""
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.device.category.device_category,
            self.DEFAULT_DEVICE_CATEGORY,
        )

    def test_write_device_category(self):
        """Test device category can be written"""
        write_config = manager_pb2.Configuration()
        write_config.device.category.device_category = (
            manager_pb2.DEVICE_CATEGORY_MOUSE
        )
        resp = self.manager_proxy.RestartServer(write_config)

        # Wait for the server to be restarted
        self.connect_to_server()

        # IO Capability should be changed.
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.device.category.device_category,
            manager_pb2.DEVICE_CATEGORY_MOUSE,
        )

    def test_read_controller(self):
        """Test controller can be read"""
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.controller.support_classic.bool_value,
            self.DEFAULT_SUPPORT_CLASSIC,
        )
        self.assertEqual(
            resp.config.controller.support_le.bool_value,
            self.DEFAULT_SUPPORT_LE,
        )

    def test_write_controller(self):
        """Test device category can be written"""
        write_config = manager_pb2.Configuration()
        write_config.controller.support_classic.bool_value = True
        write_config.controller.support_le.bool_value = False
        resp = self.manager_proxy.RestartServer(write_config)

        # Wait for the server to be restarted
        self.connect_to_server()

        # Controller should be changed.
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.controller.support_classic.bool_value, True
        )
        self.assertEqual(resp.config.controller.support_le.bool_value, False)

    def test_read_security(self):
        """Test security can be read"""
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.security.pin.string_value,
            self.DEFAULT_PIN,
        )

    def test_write_security(self):
        """Test security can be written"""
        write_config = manager_pb2.Configuration()
        write_config.security.pin.string_value = "1234"
        resp = self.manager_proxy.RestartServer(write_config)

        # Wait for the server to be restarted
        self.connect_to_server()

        # PIN should be changed.
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(resp.config.security.pin.string_value, "1234")

    def test_read_audio(self):
        """Test audio can be read"""
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.audio.supported_codecs.codec_list.codec_list,
            self.DEFAULT_CODEC_LIST,
        )
        self.assertEqual(
            resp.config.audio.supported_player_commands.player_cmd_list.player_cmd_list,
            self.DEFAULT_AUDIO_PLAYER_LIST,
        )

    def test_write_audio_codec(self):
        """Test audio codec can be written"""
        write_config = manager_pb2.Configuration(
            audio=manager_pb2.AudioConfig(
                supported_codecs=manager_pb2.ConfigVariant(
                    codec_list=manager_pb2.RepeatedCodec(
                        codec_list=[manager_pb2.CODEC_MSBC]
                    )
                )
            )
        )
        resp = self.manager_proxy.RestartServer(write_config)

        # Wait for the server to be restarted
        self.connect_to_server()

        # Codec should be changed.
        resp = self.manager_proxy.ReadConfig()
        self.assertEqual(
            resp.config.audio.supported_codecs.codec_list.codec_list,
            [manager_pb2.CODEC_MSBC],
        )

    def test_write_audio_codec_fail(self):
        """Test AAC codec is not supported"""
        write_config = manager_pb2.Configuration(
            audio=manager_pb2.AudioConfig(
                supported_codecs=manager_pb2.ConfigVariant(
                    codec_list=manager_pb2.RepeatedCodec(
                        codec_list=[manager_pb2.CODEC_AAC]
                    )
                )
            )
        )
        resp = self.manager_proxy.IsConfigOK(write_config)
        self.assertEqual(resp.ok, False)

    def test_write_audio_supported_player_commands_fail(self):
        """Test audio supported player commands can't be written"""
        write_config = manager_pb2.Configuration(
            audio=manager_pb2.AudioConfig(
                supported_player_commands=manager_pb2.ConfigVariant(
                    player_cmd_list=manager_pb2.RepeatedPlayerCommands(
                        player_cmd_list=self.DEFAULT_AUDIO_PLAYER_LIST
                        + [audio_pb2.AUDIO_PLAYER_VOL_UP]
                    )
                ),
            )
        )
        resp = self.manager_proxy.IsConfigOK(write_config)
        self.assertEqual(resp.ok, False)


if __name__ == "__main__":
    unittest.main()
