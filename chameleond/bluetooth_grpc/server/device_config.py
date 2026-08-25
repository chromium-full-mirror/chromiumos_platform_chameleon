# Copyright 2024 The ChromiumOS Authors
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

from blueship import audio_pb2
from blueship import manager_pb2


DEFAULT_CHAMELEON_CONFIG = manager_pb2.Configuration(
    api=manager_pb2.APIConfig(
        support_api_version=manager_pb2.ConfigVariant(
            writable=False, string_value="0.2"
        ),
    ),
    device=manager_pb2.DeviceInfoConfig(
        name=manager_pb2.ConfigVariant(
            writable=True,
            string_value="",
        ),
        io_capability=manager_pb2.ConfigVariant(
            writable=True,
            io_capability=manager_pb2.IO_CAPABILITY_NO_INPUT_NO_OUTPUT,
        ),
        category=manager_pb2.ConfigVariant(
            writable=True,
            device_category=manager_pb2.DEVICE_CATEGORY_NOT_CONFIGURED,
        ),
    ),
    controller=manager_pb2.ControllerConfig(
        support_classic=manager_pb2.ConfigVariant(
            writable=True,
            bool_value=False,
        ),
        support_le=manager_pb2.ConfigVariant(
            writable=True,
            bool_value=True,
        ),
        # CYW43455 doesn't support BLE Extended scan.
        # Reference: https://community.infineon.com/t5/AIROC-Wi-Fi-and-Wi-Fi-Bluetooth/CYW43455-Bluetooth-LE-Extended-Scan-Support/td-p/340045
        support_le_ext_scan=manager_pb2.ConfigVariant(
            writable=False,
            bool_value=False,
        ),
    ),
    security=manager_pb2.SecurityConfig(
        pin=manager_pb2.ConfigVariant(writable=True, string_value="0000"),
        secure_connections=manager_pb2.ConfigVariant(
            writable=True,
            secure_connections=manager_pb2.SECURE_CONNECTIONS_OFF,
        ),
        secure_simple_pairing=manager_pb2.ConfigVariant(
            writable=True,
            bool_value=True,
        ),
        link_mode=manager_pb2.ConfigVariant(
            writable=True,
            # Set the link mode to prefer peripheral role.
            link_mode=manager_pb2.LINK_MODE_ACCEPT,
        ),
        privacy=manager_pb2.ConfigVariant(
            writable=True,
            bool_value=False,
        ),
    ),
    audio=manager_pb2.AudioConfig(
        supported_codecs=manager_pb2.ConfigVariant(
            writable=True,
            codec_list=manager_pb2.RepeatedCodec(
                codec_list=[manager_pb2.CODEC_CVSD]
            ),
        ),
        supported_player_commands=manager_pb2.ConfigVariant(
            writable=True,
            player_cmd_list=manager_pb2.RepeatedPlayerCommands(
                player_cmd_list=[
                    audio_pb2.AUDIO_PLAYER_PLAY,
                    audio_pb2.AUDIO_PLAYER_PAUSE,
                    audio_pb2.AUDIO_PLAYER_STOP,
                    audio_pb2.AUDIO_PLAYER_NEXT,
                    audio_pb2.AUDIO_PLAYER_PREV,
                ]
            ),
        ),
    ),
    devkit=manager_pb2.DevKitConfig(
        rfcomm_services=manager_pb2.ConfigVariant(
            writable=True,
            service_list=manager_pb2.RepeatedRfcommService(
                service_list=[manager_pb2.ECHO_SERVICE]
            ),
        ),
    ),
)
